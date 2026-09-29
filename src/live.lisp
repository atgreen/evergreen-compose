(in-package :bliss)

;;;; A REPL into the running application.
;;;;
;;;; Editing a screen otherwise costs a sync, a build, an install, a force-stop
;;;; and a relaunch -- about forty seconds, and every scrap of application state
;;;; is lost. With this, a redefinition takes effect on the next frame.
;;;;
;;;; slynk is the SLIME protocol server SLY and icl speak. It normally owns the
;;;; thread: SETUP-SERVER blocks in an accept loop, and each connection blocks in
;;;; a message loop. Neither is available here, because one interpreter runs one
;;;; Activity on one thread and that thread is drawing frames.
;;;;
;;;; So this drives slynk from the OUTSIDE, a slice per frame: poll the listener,
;;;; poll the connection, and let slynk process whatever has actually arrived.
;;;; Everything it needs already exists -- PROCESS-REQUESTS takes a timeout, and
;;;; T means "scan and return" rather than "wait" -- so no part of slynk is
;;;; reimplemented here.
;;;;
;;;; On a phone the laptop reaches this through `adb forward tcp:4005 tcp:4005`,
;;;; which makes the phone's port look local; nothing here knows the difference.

(defvar *slynk-listener* nil "The listening socket id, or NIL when not serving.")
(defvar *slynk-connection* nil "The connected slynk connection, or NIL.")
(defvar *slynk-port* nil)

(defvar *live-log* (lambda (message) (format t "~&; ~A~%" message))
  "Where this file reports. A function of one string.

A hook rather than a call, because SRC/ANDROID.LISP is not loaded on a desktop
and ANDROID:LOG is therefore not always a function that exists. The Android host
points this at logcat when it loads.")

(defun live-log (message) (funcall *live-log* message))

(defparameter +slynk-files+
  '("slynk-match" "slynk-backend" "backend-torcl" "torcl-prelude"
    "slynk-rpc" "slynk" "slynk-completion" "slynk-apropos" "torcl-slynk-patch")
  "Load order, and it matters. The backend is defined against SLYNK-BACKEND's
DEFINTERFACE machinery so it follows that; the patch overrides slynk's own
SERVE-REQUESTS so it must come last. Names are the FLATTENED ones -- APK assets
are a single directory, so backend/torcl.lisp ships as backend-torcl.lisp.")

(defun %define-repl-history ()
  "Define the CL REPL history variables.

icl's eval wrapper opens with (setf *** ** ** * ...) before it evaluates
anything, so without these the FIRST thing a client sends kills the interpreter
outright -- \"unbound variable: **\" -- and the client reports only that it could
not connect, which points at the socket and not at the evaluator. Defining * does
not disturb the multiply function: the value cell and the function cell are
separate."
  (dolist (name '("*" "**" "***" "+" "++" "+++" "/" "//" "///" "-"))
    (eval (list 'defparameter (intern name "COMMON-LISP-USER") nil))))

(defun start-live-repl (&key (port 4005) (prefix "slynk-"))
  "Load slynk and listen on PORT. Returns the port actually bound.

PREFIX is what the flattened slynk assets are called; a project that ships them
under another name says so. Loading costs a few seconds and a few megabytes, so
this is called deliberately and never by default."
  (unless (find-package "SLYNK")
    (dolist (name +slynk-files+)
      (load (concatenate 'string prefix name ".lisp"))))
  (%define-repl-history)
  (funcall (find-symbol "INIT" "SLYNK"))
  (setf *slynk-listener* (torcl::%socket-listen "127.0.0.1" port 5)
        *slynk-port* (torcl::%socket-local-port *slynk-listener*))
  *slynk-port*)

(defun stop-live-repl ()
  (when *slynk-connection*
    (ignore-errors (funcall (find-symbol "CLOSE-CONNECTION" "SLYNK")
                            *slynk-connection* nil nil))
    (setf *slynk-connection* nil))
  (when *slynk-listener*
    (torcl::%socket-close *slynk-listener*)
    (setf *slynk-listener* nil *slynk-port* nil))
  nil)

(defun slynk-socket-stream ()
  "The stream under the current connection."
  (funcall (find-symbol "CONNECTION-SOCKET-IO" "SLYNK") *slynk-connection*))

(defun live-repl-poll ()
  "Give slynk one slice. Call once a frame. True if anything was served.

Two polls with a zero timeout, so a frame with nobody connected costs two
poll(2) calls and nothing else. A REDEFINITION ARRIVES AS AN ORDINARY REQUEST,
so the caller should treat a true return as a reason to redraw -- the function
that builds the view may be a different function now."
  (when *slynk-listener*
    (let ((served nil))
      ;; Accept only when somebody is actually waiting: %SOCKET-ACCEPT blocks,
      ;; and blocking here would freeze the interface until a client connected.
      (unless *slynk-connection*
        (when (torcl::%socket-listener-ready-p *slynk-listener* 0)
          (let ((client (torcl::%socket-accept *slynk-listener*)))
            (setf *slynk-connection*
                  (funcall (find-symbol "MAKE-CONNECTION" "SLYNK")
                           *slynk-listener* client nil))
            (setf served t))))
      (when *slynk-connection*
        ;; Ask the socket first, so a frame with an idle client costs one poll
        ;; rather than a walk through slynk's event machinery. HANDLE-REQUESTS
        ;; would be safe to call unconditionally -- its T timeout means "scan, do
        ;; not wait" -- but it cannot say whether anything actually arrived, and
        ;; the caller needs that to know whether to redraw.
        (handler-case
            (when (torcl::%socket-wait-for-input (slynk-socket-stream) 0)
              (funcall (find-symbol "HANDLE-REQUESTS" "SLYNK") *slynk-connection* t)
              (setf served t))
          (error (e)
            ;; A client that disappears surfaces as an ordinary error rather
            ;; than as a condition worth naming, so drop the connection and
            ;; leave the listener up for the next one.
            (live-log (format nil "live repl: connection lost: ~A" e))
            (setf *slynk-connection* nil))))
      served)))
