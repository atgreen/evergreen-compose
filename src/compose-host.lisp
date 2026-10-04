;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)
(defparameter +compose-host-class+ "dev/egcl/compose/ComposeHost")

(defun load-compose-class ()
  ;; FindClass on the native worker cannot see application classes. Resolve
  ;; through the Activity classloader, then retain a process-wide global ref.
  (or (gethash +compose-host-class+ *java*)
      (setf (gethash +compose-host-class+ *java*)
            (jni-global
             (with-local-refs ()
               (let* ((loader (jni-call-object (java-activity)
                                  (java-method "android/content/Context" "getClassLoader" "()Ljava/lang/ClassLoader;")
                                  (jni-args)))
                      (name (jni-string "dev.egcl.compose.ComposeHost")))
                 (unwind-protect
                      (let ((class (jni-call-object loader
                                      (java-method "java/lang/ClassLoader" "loadClass" "(Ljava/lang/String;)Ljava/lang/Class;")
                                      (jni-args (list :object name)))))
                        (jni-check) class)
                   (jni-delete-global name))))))))

(defun compose-call (controller method signature &rest args)
  (prog1 (jni-call-void controller (java-method +compose-host-class+ method signature)
                        (apply #'jni-args args))
    (jni-check)))
(defun compose-text (controller method)
  (with-local-refs ()
    (let ((string (jni-call-object controller
                    (java-method +compose-host-class+ method "()Ljava/lang/String;") (jni-args))))
      (jni-check) (jni-text string))))
(defun compose-publish (controller json)
  (let ((string (jni-string json)))
    (unwind-protect
         (compose-call controller "publish" "(Ljava/lang/String;)V" (list :object string))
      (jni-delete-global string))))

(defun compose-string-call (controller method text)
  (let ((string (jni-string text)))
    (unwind-protect
         (compose-call controller method "(Ljava/lang/String;)V" (list :object string))
      (jni-delete-global string))))

(defun submit-service (controller id url kind)
  (let ((address (jni-string url)) (type (jni-string kind)))
    (unwind-protect
         (compose-call controller "request" "(ILjava/lang/String;Ljava/lang/String;)V"
                       (list :int id) (list :object address) (list :object type))
      (jni-delete-global address) (jni-delete-global type))))

(defun run-compose-app (view &key state on-state on-start trace)
  "Run VIEW, a zero-argument function returning UI data. Callbacks run on the
Lisp worker and trigger a new snapshot. INVALIDATE also requests one (e.g. from
Slynk). STATE lists special variables saved atomically in private storage after
changes and restored before ON-START. ON-STATE runs after changes, including while the Activity is paused."
  (start-live-repl-from-environment)
  (jni-start)
  (load-compose-class)
  (let ((controller
          (jni-global
           (with-local-refs ()
             (let ((object (jni-new (java-class +compose-host-class+)
                              (java-method +compose-host-class+ "<init>" "(Landroid/content/Context;)V")
                              (jni-args (list :object (java-activity))))))
               (jni-check) object))))
        (session (make-compose-session))
        (*service-requests* (make-hash-table))
        (*service-sequence* 0)
        (last-state nil)
        (render-pending t))
    (unwind-protect
         (let ((*service-submit* (lambda (id url kind) (submit-service controller id url kind)))
               (*open-url* (lambda (url) (compose-string-call controller "openUrl" url))))
           (when state
             (setf last-state (compose-text controller "readState"))
             (restore-app-state last-state state))
           (when on-start (funcall on-start))
           (invalidate)
           (loop while (android:running-p)
                 do (let ((failure (compose-text controller "getFailure")))
                      (when failure (error "Compose host: ~A" failure)))
                    (progn
                      (when (live-repl-poll) (invalidate))
                      (loop repeat 8 for result = (compose-text controller "pollService") while result
                            do (let ((*read-eval* nil))
                                 (dispatch-service-result (read-from-string result))))
                      ;; Bound each batch so continuous typing cannot starve publication.
                      (loop repeat 128 for event = (compose-text controller "pollEvent") while event
                            do (let ((*read-eval* nil))
                                 (compose-dispatch session (read-from-string event))))
                      (when *dirty*
                        (setf *dirty* nil render-pending t)
                        ;; Save emitted edits even while the Activity is paused.
                        (when on-state (funcall on-state))
                        (when state
                          (let ((text (encode-app-state state)))
                            (unless (equal text last-state)
                              (compose-string-call controller "writeState" text)
                              (setf last-state text)))))
                      (when (and render-pending (not (android:paused-p)))
                        (setf render-pending nil)
                        (let* ((start (get-internal-real-time))
                               (tree (funcall view))
                               (built (get-internal-real-time))
                               (json (compose-snapshot session tree))
                               (encoded (get-internal-real-time)))
                          (compose-publish controller json)
                          (when trace
                            (let ((sent (get-internal-real-time)))
                              (android:log
                               (format nil "Compose ack=~D bytes=~D view=~Dms encode=~Dms send=~Dms"
                                 (compose-session-ack session) (length json)
                                 (floor (* 1000 (- built start)) internal-time-units-per-second)
                                 (floor (* 1000 (- encoded built)) internal-time-units-per-second)
                                 (floor (* 1000 (- sent encoded)) internal-time-units-per-second))))))))
                    (sleep 0.01)))
      (unwind-protect (compose-call controller "close" "()V")
        (jni-delete-global controller)))))
