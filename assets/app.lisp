;;;; The entry the EGCL Android runtime loads: it LOADs android.lisp, then this.
;;;;
;;;; One line names the demo. Every examples/android-*.lisp is in the APK and
;;;; each one loads bliss.lisp and defines CL-USER::ANDROID-MAIN, which is what
;;;; the runtime calls once it has a window, so switching demos is this line.
(load "android-kitchen-sink.lisp")
