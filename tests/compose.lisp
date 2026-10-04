;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)
(defun test-compose-catalog ()
  (let ((*package* (find-package :cl-user)))
    (with-open-file (in (merge-pathnames "../examples/catalog/app.lisp" *tests-directory*))
      (read in)
      (loop for form = (read in nil :eof) until (eq form :eof) do (eval form))))
  (let ((session (make-compose-session)) (seen nil) (package (find-package :evergreen-compose-catalog)))
    (labels ((set-value (name value) (setf (symbol-value (intern name package)) value))
             (publish ()
               (compose-snapshot session (funcall (symbol-function (intern "VIEW" package))))
               (maphash (lambda (id record) (declare (ignore id)) (pushnew (first record) seen))
                        (compose-session-nodes session))))
      (dolist (section (symbol-value (intern "*SECTIONS*" package)))
        (set-value "*SECTION*" section) (publish))
      (dolist (overlay '(:date :date-range :time :dialog :alert :sheet))
        (set-value "*OVERLAY*" overlay) (publish))
      (set-value "*OVERLAY*" nil)
      (dolist (type *compose-controls*)
        (check-true (format nil "Shipped catalog demonstrates ~A" type) (member type seen)))
      (set-value "*SECTION*" "Actions") (publish)
      (compose-dispatch session '(1 "tab/Selection" "click" ""))
      (publish)
      (check-true "Gallery tabs replace content" (gethash "slider" (compose-session-nodes session)))
      (compose-dispatch session '(2 "slider" "change" "70"))
      (check "Gallery slider callback changes Lisp state" 70
             (gethash "slider" (symbol-value (intern "*VALUES*" package)))))))

(defun test-compose-controls ()
  (let ((session (make-compose-session)) (received :unset) (sequence 0))
    (dolist (case '((:slider "42" 42) (:range-slider "20,80" (20 80))
                    (:date-picker "1791072000000" 1791072000000)
                    (:date-picker "" nil) (:date-range-picker "1791072000000," (1791072000000 nil))
                    (:time-picker "14,35" (14 35)) (:horizontal-pager "2" 2)
                    (:vertical-pager "3" 3) (:option "true" t) (:accordion "false" nil) (:icon-toggle-button "true" t)
                    (:search-bar "tea" "tea")))
      (destructuring-bind (type wire expected) case
        (handler-case
            (progn (compose-snapshot session (ui type :id "control" :on-change
                                                 (lambda (value) (setf received value))))
                   (compose-dispatch session (list (incf sequence) "control" "change" wire))
                   (check (format nil "~A delivers typed values" type) expected received))
          (error () (check (format nil "~A is supported" type) t nil)))))
    (check-true "All seventy-six catalog controls are available"
      (and (boundp '*compose-controls*) (= 76 (length (symbol-value '*compose-controls*)))
           (= 76 (length (remove-duplicates (symbol-value '*compose-controls*))))))
    (dolist (wire '("abc" "1.5" "1,2" "#.(delete-file \"anything\")"))
      (handler-case
          (progn (compose-snapshot session (ui :slider :id "control" :on-change (lambda (v) (declare (ignore v)))))
                 (check-true "Malformed numeric events are rejected"
                   (handler-case (progn (compose-dispatch session (list (incf sequence) "control" "change" wire)) nil)
                     (error () t))))
        (error () (check "Slider can be constructed" t nil))))))

(defun test-compose ()
  (let ((session (make-compose-session)) (clicked 0) (edited nil))
    (let ((json (compose-snapshot session
                   (ui :column :children
                       (list (ui :button :id "add" :text "A\"B" :on-click (lambda () (incf clicked)))
                             (ui :text-field :id "name" :value "" :on-change (lambda (s) (setf edited s))))))))
      (check-true "Compose escapes JSON strings" (search "A\\\"B" json))
      (check-true "Compose sends protocol version" (search "\"protocol\":1" json)))
    (compose-dispatch session '(1 "add" "click" ""))
    (check "Compose routes semantic click" 1 clicked)
    (compose-dispatch session '(2 "name" "change" "héllo 🌱"))
    (check "Compose preserves Unicode text" "héllo 🌱" edited)
    (compose-dispatch session '(2 "add" "click" ""))
    (check "Compose ignores replayed events" 1 clicked)
    (compose-snapshot session (ui :text :text "removed"))
    (compose-dispatch session '(3 "add" "click" ""))
    (check "Removed Compose controls cannot fire" 1 clicked)
    (check "Removed events still acknowledge edits" 3 (compose-session-ack session))
    (check-true "Compose rejects duplicate IDs"
      (handler-case (progn (compose-snapshot session (ui :column :children
                           (list (ui :text :id "x") (ui :text :id "x")))) nil) (error () t)))
    (check-true "Compose requires stable callback IDs"
      (handler-case (progn (compose-snapshot session (ui :button :on-click (lambda ()))) nil) (error () t)))
    (check-true "Compose rejects unknown widgets"
      (handler-case (progn (compose-snapshot session (ui :typo)) nil) (error () t)))))

(defun test-compose-deltas ()
  (let ((session (make-compose-session)))
    (labels ((view (label)
               (ui :column :children
                   (cons (ui :button :id "counter" :text label :on-click (lambda ()))
                         (loop for i below 1000 collect
                           (ui :text :id (format nil "row-~D" i) :text (format nil "Number ~D" i)))))))
      (let ((first (compose-snapshot session (view "Zero")))
            (changed (compose-snapshot session (view "One")))
            (same (compose-snapshot session (view "One"))))
        (check-true "Initial Compose model includes all rows" (> (length first) 50000))
        (check-true "One button update does not resend 1000 rows" (< (length changed) 250))
        (check-true "Unchanged Compose trees send no node records" (search "\"nodes\":[]" same))))))

(defun test-compose-hello ()
  (let* ((package (or (find-package :compose-hello-test)
                      (make-package :compose-hello-test :use '(:cl))))
         (*package* package) (session (make-compose-session)))
    (with-open-file (in (merge-pathnames "../examples/hello/app.lisp" *tests-directory*))
      (read in)
      (loop for form = (read in nil :eof) until (eq form :eof) do (eval form)))
    (let ((view (symbol-function (intern "GREETING" package))))
      (compose-snapshot session (funcall view))
      (compose-dispatch session '(1 "count" "click" ""))
      (let ((delta (compose-snapshot session (funcall view))))
        (check-true "Shipped Hello counter changes its label" (search "Count: 1" delta))
        (check-true "Shipped Hello counter retains its 1000 rows" (< (length delta) 250)))
      (compose-dispatch session '(2 "name" "change" "Ada 🌱"))
      (compose-snapshot session (funcall view))
      (check "Shipped Hello editor updates Lisp state" "Ada 🌱" (symbol-value (intern "*NAME*" package))))))

(defun test-expanded-controls ()
  (dolist (type '(:combo-box :multi-select :pull-to-refresh :reorderable-list :swipe-reveal
                 :accordion :async-image :markdown :photo-picker :document-picker
                 :number-stepper :otp-field :list-detail :section-list :carousel
                 :zoom-image :calendar :chart :data-table :rating :rich-text-editor
                 :map :media-player :camera :web-view))
    (check-true (format nil "Expanded control ~A is available" type)
      (handler-case (progn (compose-snapshot (make-compose-session) (ui type)) t) (error () nil))))
  (dolist (case '((:number-stepper "3" 3) (:rating "4" 4) (:carousel "2" 2)
                 (:calendar "1791072000000" 1791072000000) (:otp-field "0123" "0123")))
    (destructuring-bind (type wire expected) case
      (check (format nil "~A change contract" type) expected (compose-change-value type wire))))
  (let ((session (make-compose-session)) (received nil))
    (handler-case
        (progn (compose-snapshot session (ui :reorderable-list :id "order" :on-move
                                             (lambda (from to) (setf received (list from to)))))
               (compose-dispatch session '(1 "order" "move" "2,0"))
               (check "Reorder event delivers indices" '(2 0) received))
      (error () (check "Reorder event supported" t nil)))))

(defun test-compose-only ()
  (check "Public package is Evergreen Compose" "EVERGREEN-COMPOSE" (package-name (find-package :evergreen-compose)))
  (check "Retired layout API is absent" nil (find-symbol "LAYOUT" :evergreen-compose))
  (let ((order (with-open-file (in (merge-pathnames "../load-order.sexp" *tests-directory*)) (read in))))
    (check "Portable load path contains only Compose support"
           '("package" "ffi" "state" "live" "utf8" "compose" "services") (getf order :host))
    (check "Android load path contains only shared bridge services"
           '("jni" "java" "android-services" "compose-host") (getf order :target))))
