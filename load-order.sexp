;;;; The one load order, read by everything that loads Bliss.
;;;;
;;;; There were three copies of this list -- load.lisp, bliss.asd and a shell
;;;; script that built an APK's assets -- and a comment in one of them asking
;;;; the reader to keep them in step. They drifted anyway: an APK shipped once
;;;; without src/backend/software.lisp, which left BLISS:MAKE-SURFACE undefined
;;;; on the device -- a crash on the first frame and nothing at all before it.
;;;;
;;;; :HOST is what loads anywhere -- a desktop, the test suite, a machine with
;;;; no Android anything. :TARGET is the rest, and only an APK can load it: JNI,
;;;; the input method, the accessibility bridge and the two Android backends all
;;;; call into a runtime that exists inside the application and nowhere else.
;;;;
;;;; Names are relative to src/ and carry no .lisp. APK assets are one flat
;;;; directory, so on the device "backend/software" is "software.lisp"; that is
;;;; also why the Android host is android-host rather than android, which the
;;;; runtime reserves for its own bindings.
(:host ("package" "ffi" "geometry" "paint" "font" "view" "layout" "clock"
        "input" "semantics" "text-input" "state" "live" "widgets"
        "icons-material" "path" "svg" "display" "platform-view" "backend"
        "backend/software" "utf8")
 :target ("jni" "ime" "a11y" "backend/canvas" "android-host" "backend/gles"))
