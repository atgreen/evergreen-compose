(in-package :bliss)

;;;; The on-screen keyboard.
;;;;
;;;; This file exists because the obvious route does not work and the reason is
;;;; not discoverable from the symptom. Measured on a Pixel 10 Pro XL, Android 16:
;;;;
;;;;   * ANativeActivity_showSoftInput -- the NDK's own call, the one the
;;;;     documentation points at -- leaves mInputShown false and raises nothing.
;;;;     It returns VOID, so there is no failure to observe: it looks like
;;;;     success and is not.
;;;;   * InputMethodManager.showSoftInput(decorView, 0), the same request made
;;;;     through JNI, returns TRUE and the keyboard comes up. From a plain
;;;;     NativeActivity, with no Java class of our own and no DEX.
;;;;
;;;; So a framework with a JNI layer can have a keyboard and one without one
;;;; cannot, which is why this lives in Bliss and not in the EGCL runtime.
;;;;
;;;; What comes back is the part to be careful about. The window has focus but
;;;; no VIEW does (getCurrentFocus is null), so there is no InputConnection --
;;;; isAcceptingText is false -- and the IME is bound to a fallback
;;;; BaseInputConnection. That fallback dispatches KeyEvents, which land in the
;;;; same AInputQueue as hardware keys, which is why typing works at all here.
;;;;
;;;; It is a fallback and not a contract. Android says not to rely on a soft
;;;; keyboard sending key events, and it is right: gesture typing, autocorrect,
;;;; suggestion bars, emoji and every non-Latin input method commit TEXT through
;;;; an InputConnection and send no keys. Getting one of those needs a focused
;;;; editor View, and attaching a View needs the main thread --
;;;;
;;;;   CalledFromWrongThreadException: Only the original thread that created a
;;;;   view hierarchy can touch its views. Expected: main Calling: Thread-2
;;;;
;;;; -- which the worker this Lisp runs on is not. That is the whole of what
;;;; stands between here and real text input: thread affinity, not DEX, not a
;;;; class we are unable to define.

(defvar *java* (make-hash-table :test #'equal)
  "Resolved classes and method IDs, which cost ~35us each to look up and never
change. Keyed by name so the call sites read as the Java they are.")

(defun java-class (name)
  (or (gethash name *java*)
      (setf (gethash name *java*) (jni-find-class name))))

(defun java-method (class-name name signature &key static)
  (let ((key (list class-name name signature)))
    (or (gethash key *java*)
        (setf (gethash key *java*)
              (jni-method (java-class class-name) name signature :static static)))))

(defun java-field (class-name name signature)
  "A field ID, cached like a method. Reading the four public ints of an Insets
looked each of them up again every time -- two C strings and a crossing apiece,
on every pass of the frame loop."
  (let ((key (list class-name name signature :field)))
    (or (gethash key *java*)
        (setf (gethash key *java*)
              (jni-field (java-class class-name) name signature)))))

(defparameter +activity-class+ "android/app/NativeActivity")
(defparameter +view-class+ "android/view/View")
(defparameter +imm-class+ "android/view/inputmethod/InputMethodManager")

(defun java-activity ()
  "The Java NativeActivity object: the fourth pointer of the ANativeActivity."
  (let ((native (android:activity)))
    (when (egcl-ffi:null-pointer-p native)
      (error "There is no ANativeActivity yet"))
    (word-at native 3)))

(defun decor-view ()
  "The window's decor view -- the one View that certainly exists and is served.

Fetched rather than cached: it belongs to the Window, and an application that
outlives a window recreation would otherwise be holding a dead one."
  (jni-call-object
   (jni-call-object (java-activity)
                    (java-method +activity-class+ "getWindow" "()Landroid/view/Window;")
                    (jni-args))
   (java-method "android/view/Window" "getDecorView" "()Landroid/view/View;")
   (jni-args)))

(defun input-method-manager ()
  (jni-call-object (java-activity)
                   (java-method +activity-class+ "getSystemService"
                                "(Ljava/lang/String;)Ljava/lang/Object;")
                   (jni-args (list :object (or (gethash :input-method *java*)
                                               (setf (gethash :input-method *java*)
                                                     (jni-string "input_method")))))))

(defvar *keyboard-shown* nil
  "Whether the keyboard was last asked to appear. Our request, not the system's
state: the user can dismiss it with the back gesture and we are not told.")

(defun show-keyboard ()
  "Raise the on-screen keyboard. True if the system accepted the request."
  (with-local-refs ()
    (setf *keyboard-shown*
          (jni-call-boolean (input-method-manager)
                            (java-method +imm-class+ "showSoftInput"
                                         "(Landroid/view/View;I)Z")
                            (jni-args (list :object (decor-view)) (list :int 0))))))

(defun hide-keyboard ()
  "Put the on-screen keyboard away. True if the system accepted the request."
  (setf *keyboard-shown* nil)
  (with-local-refs ()
    (jni-call-boolean (input-method-manager)
                      (java-method +imm-class+ "hideSoftInputFromWindow"
                                   "(Landroid/os/IBinder;I)Z")
                      (jni-args (list :object (jni-call-object
                                               (decor-view)
                                               (java-method +view-class+ "getWindowToken"
                                                            "()Landroid/os/IBinder;")
                                               (jni-args)))
                                (list :int 0)))))

(defun keyboard-shown-p () *keyboard-shown*)

(defun toggle-keyboard ()
  (if *keyboard-shown* (hide-keyboard) (show-keyboard)))

(defun key-character (code meta)
  "The character key CODE produces with META held, or NIL for a key that types
nothing -- shift, the arrows, enter, delete.

Asks Android's own KeyCharacterMap rather than carrying a table, so the layout
and the meta-state rules are the platform's and not a guess. VIRTUAL_KEYBOARD is
the right map for a soft keyboard; a physical one may use another, and this does
not yet know which device an event came from."
  (let* ((map (or (gethash :key-map *java*)
                  (setf (gethash :key-map *java*)
                        (jni-global
                         (jni-call-static-object
                          (java-class "android/view/KeyCharacterMap")
                          (java-method "android/view/KeyCharacterMap" "load"
                                       "(I)Landroid/view/KeyCharacterMap;" :static t)
                          (jni-args (list :int -1)))))))
         (character (jni-call-int map
                                  (java-method "android/view/KeyCharacterMap" "get" "(II)I")
                                  (jni-args (list :int code) (list :int meta)))))
    ;; Zero is "types nothing"; the top bit is COMBINING_ACCENT, a dead key whose
    ;; character is not final until the next one arrives.
    (when (and (plusp character) (<= character #x10FFFF))
      (code-char character))))

;;;; Running JNI on the Android main thread.
;;;;
;;;; Everything above works from the worker thread because none of it touches a
;;;; View. Attaching one does, and Android will not have it:
;;;;
;;;;   CalledFromWrongThreadException: Only the original thread that created a
;;;;   view hierarchy can touch its views. Expected: main Calling: Thread-2
;;;;
;;;; The runtime's ANDROID:CALL-ON-MAIN posts a C call down a pipe registered on
;;;; the main thread's own ALooper and waits for it. It knows nothing about JNI:
;;;; what goes through it is a function pointer out of the table this file is
;;;; already walking, which is why a new call shape needs nothing from the
;;;; runtime.

(defvar *main-env* nil "The MAIN thread's JNIEnv, which is not this thread's.")
(defvar *main-table* nil)

(defun main-env ()
  (or *main-env*
      (let ((env (word-at (android:activity) 2))) ; ANativeActivity.env
        (when (egcl-ffi:null-pointer-p env)
          (error "This Activity has no main-thread JNIEnv"))
        (setf *main-table* (word-at env))
        (setf *main-env* env))))

(defun %main-call (index arguments &key (result :pointer) promote)
  "Call JNI function INDEX on the main thread, with that thread's env first.

PROMOTE asks for the result as a GLOBAL reference, and it is not an option so
much as a correction. The main thread reaches the gate from inside
MessageQueue.nativePollOnce, which is a JNI native method, so every local
reference made there belongs to that frame and is popped the moment the looper
returns to Java. Promoting one on a later call is not an error that can be
handled -- CheckJNI aborts the process:

  JNI DETECTED ERROR IN APPLICATION: jobject is an invalid local reference
  (popped reference at index 11 in a table of size 7) in call to NewGlobalRef

which is how this was found. So it happens inside the same visit, which is what
the runtime's :PROMOTE and :RELEASE are for."
  (let ((env (main-env)))
    (android:call-on-main
     (word-at *main-table* index) (cons env arguments)
     :result result
     :promote (and promote (word-at *main-table* +jni-new-global-ref+))
     :release (and promote (word-at *main-table* +jni-delete-local-ref+)))))

(defun main-check ()
  "Signal if a Java exception is pending ON THE MAIN THREAD, and clear it.

A pending exception is thread state rather than frame state, so it does survive
between visits -- and must not, because CheckJNI aborts on the next call made
while one is pending. Every main-thread call therefore ends here."
  (let ((thrown (%main-call +jni-exception-occurred+ '() :promote t)))
    (unless (egcl-ffi:null-pointer-p thrown)
      (%main-call +jni-exception-clear+ '() :result :void)
      (error "Java on the main thread: ~A"
             (or (jni-text (jni-call-object
                            thrown
                            (java-method "java/lang/Object" "toString"
                                         "()Ljava/lang/String;")
                            (jni-args)))
                 "a throwable that would not describe itself")))))

(defun main-call (index arguments &optional (result :pointer))
  "Call JNI function INDEX on the main thread.

EVERY OBJECT IN ARGUMENTS MUST BE A GLOBAL REFERENCE. A local reference belongs
to the thread that made it and to no other, so handing one across is not merely
unsupported -- CheckJNI aborts the process:

  JNI DETECTED ERROR IN APPLICATION: jobject is an invalid local reference
  (reference outside the table)

which is how this was found, by passing DECOR-VIEW's result straight over. The
fix is either JNI-GLOBAL on the way in, or fetching the object on the main
thread with MAIN-OBJECT, which returns a global already.

This is the mirror of the rule in %MAIN-CALL, and the two are easy to confuse:
a local made THERE dies when the visit ends, and a local made HERE was never
valid there at all."
  (prog1 (%main-call index arguments :result result) (main-check)))

(defun main-object (index arguments)
  "A jobject result from a main-thread call, as a GLOBAL reference."
  (prog1 (%main-call index arguments :promote t) (main-check)))

(defvar *editor* nil
  "The attached android.widget.EditText, as a global reference, or NIL.")

(defun attach-editor ()
  "Attach a real EditText to the window and focus it. Idempotent.

This is what turns the keyboard from something that merely appears into
something with an InputConnection behind it. Without a focused editor the IME
falls back to sending key events, which works for typing Latin letters on the
stock keyboard and for nothing else -- not gesture typing, not autocorrect, not
a suggestion bar, not emoji, and not any input method for a language that is not
composed key by key.

The EditText is Android's own, one pixel square, and never drawn by us: it is
here to hold the input connection, not to be seen. Nothing defines a Java class,
so there is still no DEX in the APK."
  (or *editor*
      (let* ((activity (java-activity))
             (editor (main-object
                      +jni-new-object-a+
                      (list (java-class "android/widget/EditText")
                            (java-method "android/widget/EditText" "<init>"
                                         "(Landroid/content/Context;)V")
                            (jni-args (list :object activity)))))
             (params (main-object
                      +jni-new-object-a+
                      (list (java-class "android/view/ViewGroup$LayoutParams")
                            (java-method "android/view/ViewGroup$LayoutParams" "<init>" "(II)V")
                            (jni-args (list :int 1) (list :int 1))))))
        (main-call +jni-call-void-method-a+
                   (list activity
                         (java-method +activity-class+ "addContentView"
                                      "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V")
                         (jni-args (list :object editor) (list :object params)))
                   :void)
        (main-call +jni-call-void-method-a+
                   (list editor (java-method +view-class+ "setFocusableInTouchMode" "(Z)V")
                         (jni-args (list :int 1)))
                   :void)
        (main-call +jni-call-boolean-method-a+
                   (list editor (java-method +view-class+ "requestFocus" "()Z") (jni-args))
                   :int)
        (setf *editor* editor))))

(defun editor-text ()
  "The editor's current text, or NIL when there is no editor.

Read from THIS thread rather than the main one. getText returns the Editable
field and toString copies it; neither requests a layout, so neither trips the
thread check. What it does race with is the IME committing an edit, and the
worst that race can produce is a string one frame stale."
  (when *editor*
    ;; Read once a frame, so its two references are two per frame: the case a
    ;; local reference table is not built for.
    (with-local-refs ()
      (let ((editable (jni-call-object *editor*
                                       (java-method "android/widget/EditText" "getText"
                                                    "()Landroid/text/Editable;")
                                       (jni-args))))
        (unless (egcl-ffi:null-pointer-p editable)
          (jni-text (jni-call-object editable
                                     (java-method "java/lang/Object" "toString"
                                                  "()Ljava/lang/String;")
                                     (jni-args))))))))

(defun set-editor-text (text)
  "Replace the editor's text, and put the caret after it."
  (when *editor*
    (main-call +jni-call-void-method-a+
               (list *editor*
                     (java-method "android/widget/EditText" "setText"
                                  "(Ljava/lang/CharSequence;)V")
                     (jni-args (list :object (jni-string text))))
               :void)
    (main-call +jni-call-void-method-a+
               (list *editor*
                     (java-method "android/widget/EditText" "setSelection" "(I)V")
                     (jni-args (list :int (length text))))
               :void)))

(defun start-text-input ()
  "Attach the editor if need be, then raise the keyboard against it.

Unlike SHOW-KEYBOARD, which asks on behalf of the decor view and is answered
with a fallback connection, this asks on behalf of a real editor: isAcceptingText
becomes true, and the IME may commit text rather than synthesising keys."
  (let ((editor (attach-editor)))
    (with-local-refs ()
      (setf *keyboard-shown*
            (jni-call-boolean (input-method-manager)
                              (java-method +imm-class+ "showSoftInput"
                                           "(Landroid/view/View;I)Z")
                              (jni-args (list :object editor) (list :int 0)))))))

(defun accepting-text-p ()
  "Whether the IME has a real InputConnection: the question this file exists for."
  (with-local-refs ()
    (jni-call-boolean (input-method-manager)
                      (java-method +imm-class+ "isAcceptingText" "()Z")
                      (jni-args))))

;;; Loading this file IS the installation: it is the Android half of
;;; src/text-input.lisp, and there is nothing else for it to be.
(setf *text-input*
      (list :show (lambda () (start-text-input))
            :hide (lambda () (hide-keyboard))
            :read (lambda () (editor-text))
            ;; Attaching first, because seeding the editor is the point of the
            ;; call and there is nothing to seed until one exists.
            :write (lambda (text) (attach-editor) (set-editor-text text))))
