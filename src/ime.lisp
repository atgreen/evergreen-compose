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
;;;; cannot, which is why this lives in Bliss and not in the TorCL runtime.
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

(defparameter +activity-class+ "android/app/NativeActivity")
(defparameter +view-class+ "android/view/View")
(defparameter +imm-class+ "android/view/inputmethod/InputMethodManager")

(defun java-activity ()
  "The Java NativeActivity object: the fourth pointer of the ANativeActivity."
  (let ((native (android:activity)))
    (when (torcl-ffi:null-pointer-p native)
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
  (setf *keyboard-shown*
        (jni-call-boolean (input-method-manager)
                          (java-method +imm-class+ "showSoftInput" "(Landroid/view/View;I)Z")
                          (jni-args (list :object (decor-view)) (list :int 0)))))

(defun hide-keyboard ()
  "Put the on-screen keyboard away. True if the system accepted the request."
  (setf *keyboard-shown* nil)
  (jni-call-boolean (input-method-manager)
                    (java-method +imm-class+ "hideSoftInputFromWindow" "(Landroid/os/IBinder;I)Z")
                    (jni-args (list :object (jni-call-object
                                             (decor-view)
                                             (java-method +view-class+ "getWindowToken"
                                                          "()Landroid/os/IBinder;")
                                             (jni-args)))
                              (list :int 0))))

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
