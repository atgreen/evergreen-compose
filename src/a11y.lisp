(in-package :bliss)

;;;; Handing the semantics to Android.
;;;;
;;;; What is reachable without a Java class of our own, probed on a Pixel 10 Pro
;;;; XL: the AccessibilityManager and its state, constructing and sending an
;;;; AccessibilityEvent, and setting a content description on the decor view.
;;;;
;;;; What is NOT: explore-by-touch over our widgets. That wants an
;;;; AccessibilityNodeProvider, which arrives through View.AccessibilityDelegate
;;;; -- and both are CLASSES to subclass rather than interfaces to implement, so
;;;; Proxy cannot stand in and there is no way to supply one without DEX. That
;;;; is an inference from the shape of the API rather than something measured,
;;;; and it is the one claim here that deserves testing before it is believed;
;;;; the last time a thing was called impossible on this project (a soft
;;;; keyboard) it turned out to take one JNI call.
;;;;
;;;; So this gives announcements, which are real and are what a reader will
;;;; actually speak, and leaves the tree for the day there is a Java class.

(defparameter +accessibility-class+ "android/view/accessibility/AccessibilityManager")
(defparameter +event-class+ "android/view/accessibility/AccessibilityEvent")
(defparameter +type-announcement+ 16384
  "AccessibilityEvent.TYPE_ANNOUNCEMENT.")

(defun accessibility-manager ()
  (jni-call-object (java-activity)
                   (java-method +activity-class+ "getSystemService"
                                "(Ljava/lang/String;)Ljava/lang/Object;")
                   (jni-args (list :object (or (gethash :accessibility *java*)
                                               (setf (gethash :accessibility *java*)
                                                     (jni-string "accessibility")))))))

(defun accessibility-enabled-p ()
  "Whether anything is listening. Worth asking before building an announcement:
with no reader running the event is discarded, and the string was still built."
  (with-local-refs ()
    (jni-call-boolean (accessibility-manager)
                      (java-method +accessibility-class+ "isEnabled" "()Z")
                      (jni-args))))

(defun exploring-by-touch-p ()
  "Whether a reader is driving touch, which changes what gestures mean."
  (with-local-refs ()
    (jni-call-boolean (accessibility-manager)
                      (java-method +accessibility-class+ "isTouchExplorationEnabled" "()Z")
                      (jni-args))))

(defun announce (text)
  "Say TEXT, if anything is listening. True when it was sent.

An announcement rather than a focus change, because a focus change belongs to a
node in a tree and there is no tree -- see the file header. This is the honest
shape of what can be delivered."
  (when (and text (accessibility-enabled-p))
    (with-local-refs ()
      (let* ((event (jni-call-static-object
                     (java-class +event-class+)
                     (java-method +event-class+ "obtain"
                                  "(I)Landroid/view/accessibility/AccessibilityEvent;"
                                  :static t)
                     (jni-args (list :int +type-announcement+))))
             (words (jni-call-object event
                                     (java-method +event-class+ "getText" "()Ljava/util/List;")
                                     (jni-args))))
        (jni-call-boolean words
                          (java-method "java/util/List" "add" "(Ljava/lang/Object;)Z")
                          (jni-args (list :object (jni-string text))))
        (jni-call-void (accessibility-manager)
                       (java-method +accessibility-class+ "sendAccessibilityEvent"
                                    "(Landroid/view/accessibility/AccessibilityEvent;)V")
                       (jni-args (list :object event)))
        t))))

(defun announce-node (node)
  "Say what NODE is, if it says anything about itself."
  (when (semantic-p node)
    (announce (describe-node (node-prop node :label)
                             (node-prop node :role)
                             (node-prop node :value)))))

(defun describe-screen (text)
  "Give the whole window one description, for a reader that finds nothing else.

Goes through the main thread, and the view is globalised on the way: a local
reference belongs to the thread that made it, and handing DECOR-VIEW's straight
over aborts the process."
  (let ((view (jni-global (decor-view))))
    (main-call +jni-call-void-method-a+
               (list view
                     (java-method +view-class+ "setContentDescription"
                                  "(Ljava/lang/CharSequence;)V")
                     (jni-args (list :object (jni-string text))))
               :void)))

;;;; ── What the system is covering ───────────────────────────────────────
;;;;
;;;; A phone's screen is not all yours. The status bar, the gesture bar, a
;;;; display cutout and above all the keyboard each take a strip of it, and a
;;;; layout that ignores them puts a text field under the keyboard the moment it
;;;; opens -- which is the one place a text field must not be.

(defparameter +insets-class+ "android/graphics/Insets")

(defun window-insets (kind)
  "LEFT TOP RIGHT BOTTOM, in physical pixels, for KIND.

KIND is :SYSTEM-BARS or :IME. Zeroes before the view is attached, which is not
an error: there is no window yet and nothing is covering it.

Insets carries its four numbers as public FIELDS and offers no getters, which is
why JNI-FIELD exists."
  (with-local-refs ()
    (let* ((type-class (java-class "android/view/WindowInsets$Type"))
           (type (jni-call-static-int
                  type-class
                  (java-method "android/view/WindowInsets$Type"
                               (ecase kind (:system-bars "systemBars") (:ime "ime"))
                               "()I" :static t)
                  (jni-args)))
           (insets-source
             (jni-call-object (decor-view)
                              (java-method +view-class+ "getRootWindowInsets"
                                           "()Landroid/view/WindowInsets;")
                              (jni-args))))
      (if (torcl-ffi:null-pointer-p insets-source)
          (values 0 0 0 0)
          (let* ((insets (jni-call-object
                          insets-source
                          (java-method "android/view/WindowInsets" "getInsets"
                                       "(I)Landroid/graphics/Insets;")
                          (jni-args (list :int type))))
                 (class (java-class +insets-class+)))
            (if (torcl-ffi:null-pointer-p insets)
                (values 0 0 0 0)
                (values (jni-int-field insets (jni-field class "left" "I"))
                        (jni-int-field insets (jni-field class "top" "I"))
                        (jni-int-field insets (jni-field class "right" "I"))
                        (jni-int-field insets (jni-field class "bottom" "I")))))))))
