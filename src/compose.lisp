;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)

(defvar *dirty* t)
(defun invalidate ()
  "Request a fresh UI snapshot from the application view function."
  (setf *dirty* t))

(defparameter *compose-controls*
  '(:button :outlined-button :text-button :tonal-button :icon-button :icon-toggle-button :fab
    :chip :assist-chip :input-chip :checkbox :tri-state-checkbox :radio-button :switch
    :slider :range-slider :segmented-buttons
    :text-field :filled-text-field :search-bar :date-picker :date-range-picker :time-picker
    :text :icon :image :card :divider :badge :linear-progress :circular-progress
    :list-item :tooltip :snackbar
    :lazy-column :lazy-row :lazy-grid :horizontal-pager :vertical-pager :swipe
    :tabs :bottom-bar :navigation-rail :navigation-drawer :top-bar :bottom-app-bar
    :dropdown-menu :dialog :alert-dialog :bottom-sheet
    :combo-box :multi-select :pull-to-refresh :reorderable-list :swipe-reveal
    :accordion :async-image :markdown :photo-picker :document-picker
    :number-stepper :otp-field :list-detail :section-list :carousel
    :zoom-image :calendar :chart :data-table :rating :rich-text-editor
    :map :media-player :camera :web-view :drawing-pad))
(defparameter *compose-components*
  (append *compose-controls*
          '(:theme :column :row :box :spacer :scaffold :nav-item :tab :menu-item :segment :drawer-item :option :section :point :table-column :table-row :cell :marker :canvas :path :rect :circle :line :ink-stroke)))
(defparameter *compose-events*
  '(:on-click :on-change :on-dismiss :on-right :on-left :on-submit :on-confirm :on-action :on-error :on-move :on-select :on-result :on-refresh :on-load :on-capture :on-back :on-stroke))

(defun ui (type &rest properties)
  "An immutable Compose node. :CHILDREN is a list of UI nodes. Interactive
nodes require a unique string :ID. Click/dismiss/swipe callbacks take no args;
change callbacks receive text, booleans, integers, or pairs of integers;
see docs/COMPOSE-CONTROLS.md for the complete catalog and event contracts."
  (unless (member type *compose-components*) (error "Unknown Compose widget ~S" type))
  (unless (evenp (length properties)) (error "UI properties must be key/value pairs"))
  (list type properties))

(defstruct compose-session
  (callbacks (make-hash-table :test #'equal))
  (ack 0)
  (nodes (make-hash-table :test #'equal))
  (published-p nil))

(defun compose-json-string (text stream)
  (write-char #\" stream)
  (loop for char across text for code = (char-code char)
        do (case char
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (otherwise (if (< code 32) (format stream "\\u~4,'0X" code)
                            (write-char char stream)))))
  (write-char #\" stream))

(defun compose-json-value (value stream)
  (cond ((eq value t) (write-string "true" stream))
        ((null value) (write-string "false" stream))
        ((stringp value) (compose-json-string value stream))
        ((keywordp value) (compose-json-string (string-downcase value) stream))
        ((integerp value) (princ value stream))
        (t (error "Compose property must be a string, integer, keyword or boolean: ~S" value))))

(defun compose-snapshot (session tree)
  "Publish changed node records. Unchanged list contents never cross JNI again."
  (let ((callbacks (make-hash-table :test #'equal))
        (nodes (make-hash-table :test #'equal)) (changes nil))
    (labels ((visit (tree path)
               (destructuring-bind (type properties) tree
                 (unless (member type *compose-components*) (error "Unknown Compose widget ~S" type))
                 (let* ((explicit (getf properties :id)) (id (or explicit path))
                        (props nil) (children nil))
                   (unless (and (stringp id) (plusp (length id))) (error "UI IDs must be nonempty strings"))
                   (when (gethash id nodes) (error "Duplicate Compose ID: ~S" id))
                   (setf (gethash id nodes) :visiting)
                   (loop for (key value) on properties by #'cddr
                         unless (member key '(:id :children))
                           do (unless (keywordp key) (error "UI property names must be keywords"))
                              (when (member key *compose-events*)
                                (unless (and explicit (functionp value))
                                  (error "~S needs an explicit :ID and a callback function" key))
                                (setf (gethash (list id (subseq (string-downcase key) 3)) callbacks)
                                      (cons type value)
                                      value t))
                              (push key props) (push value props))
                   (loop for child in (getf properties :children) for i from 0
                         when child do (push (visit child (or (getf (second child) :id)
                                                              (format nil "~A/~D" id i))) children))
                   (let ((record (list type (nreverse props) (nreverse children))))
                     (setf (gethash id nodes) record)
                     (unless (equal record (gethash id (compose-session-nodes session)))
                       (push (cons id record) changes)))
                   id)))
             (record-json (entry stream)
               (destructuring-bind (id type props children) entry
                 (write-string "{\"id\":" stream) (compose-json-string id stream)
                 (write-string ",\"type\":" stream) (compose-json-value type stream)
                 (write-string ",\"props\":{" stream)
                 (loop for (key value) on props by #'cddr for i from 0
                       do (when (plusp i) (write-char #\, stream))
                          (compose-json-string (string-downcase key) stream) (write-char #\: stream)
                          (compose-json-value value stream))
                 (write-string "},\"children\":[" stream)
                 (loop for id in children for i from 0
                       do (when (plusp i) (write-char #\, stream)) (compose-json-string id stream))
                 (write-string "]}" stream))))
      (let* ((root (visit tree "$"))
             (json (with-output-to-string (stream)
                     (format stream "{\"protocol\":1,\"ack\":~D,\"reset\":~A,\"root\":"
                             (compose-session-ack session) (if (compose-session-published-p session) "false" "true"))
                     (compose-json-string root stream) (write-string ",\"nodes\":[" stream)
                     (loop for entry in changes for i from 0
                           do (when (plusp i) (write-char #\, stream)) (record-json entry stream))
                     (write-string "]}" stream))))
        ;; Commit only after validation/encoding succeeds.
        (setf (compose-session-callbacks session) callbacks
              (compose-session-nodes session) nodes
              (compose-session-published-p session) t)
        json))))

(defun compose-event-integer (text &optional nullable)
  ;; Never use the Lisp reader on widget input. Numeric controls use decimal
  ;; integers (sliders have an application-defined integer scale).
  (if (and nullable (zerop (length text))) nil
      (let ((start (if (and (plusp (length text)) (char= (char text 0) #\-)) 1 0)))
        (unless (and (> (length text) start)
                     (loop for i from start below (length text) always (digit-char-p (char text i))))
          (error "Invalid Compose integer: ~S" text))
        (parse-integer text))))

(defun compose-change-value (type text)
  (case type
    ((:switch :checkbox :icon-toggle-button :accordion :option)
     (cond ((equal text "true") t) ((equal text "false") nil)
           (t (error "Invalid Compose boolean: ~S" text))))
    ((:slider :horizontal-pager :vertical-pager :number-stepper :rating :carousel :calendar) (compose-event-integer text))
    (:date-picker (compose-event-integer text t))
    ((:range-slider :date-range-picker :time-picker)
     (let ((comma (position #\, text)))
       (unless comma (error "Invalid Compose pair: ~S" text))
       (mapcar (lambda (part) (compose-event-integer part (eq type :date-range-picker)))
               (list (subseq text 0 comma) (subseq text (1+ comma))))))
    (otherwise text)))

(defun compose-stroke-value (text)
  "Decode a bounded completed stroke: (color width ((x y) ...))."
  (when (> (length text) 100000) (error "Stroke event is too large"))
  (let* ((*read-eval* nil)
         (stroke (read-from-string text)))
    (unless (and (listp stroke) (= 3 (length stroke))
                 (stringp (first stroke)) (<= 1 (length (first stroke)) 64)
                 (typep (second stroke) '(integer 1 100))
                 (listp (third stroke)) (<= 1 (length (third stroke)) 4096)
                 (every (lambda (point)
                          (and (listp point) (= 2 (length point))
                               (every (lambda (value) (typep value '(integer 0 10000))) point)))
                        (third stroke)))
      (error "Invalid completed stroke"))
    stroke))

(defun compose-dispatch (session event)
  "Dispatch one ordered semantic event. Stale/removed targets are harmless."
  (unless (and (listp event) (= (length event) 4)
               (integerp (first event)) (every #'stringp (rest event)))
    (error "Malformed Compose event: ~S" event))
  (destructuring-bind (sequence id kind value) event
    (when (> sequence (compose-session-ack session))
      (setf (compose-session-ack session) sequence)
      (let ((binding (gethash (list id kind) (compose-session-callbacks session))))
        (when binding
          (cond ((equal kind "move")
                 (let ((pair (compose-change-value :range-slider value)))
                   (apply (cdr binding) pair)))
                ((equal kind "stroke") (funcall (cdr binding) (compose-stroke-value value)))
                ((equal kind "change") (funcall (cdr binding) (compose-change-value (car binding) value)))
                ((member kind '("submit" "error" "select" "result" "capture" "load") :test #'equal) (funcall (cdr binding) value))
                (t (funcall (cdr binding))))))
      (invalidate))))
