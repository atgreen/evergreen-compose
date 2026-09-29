(load "bliss.lisp")
(in-package :cl-user)

;;;; A form: two fields, one keyboard.
;;;;
;;;; Two rather than one on purpose. One field cannot show the bug that seeding
;;;; exists to prevent -- tapping the second field while the first holds the
;;;; keyboard, and having the first field's text still sitting in the editor.

(defparameter *name* "")
(defparameter *shelf* 0)
(defparameter *shelf-velocity* 0.0)
(defparameter *tab* 0)
(defparameter *volume* 1/2)
(defparameter *dialog* nil)
(defparameter *city* "")

(defparameter *scheme* :dark)
(defparameter *chrome* nil)
(defparameter *fields* nil)

(defun chrome ()
  "The parts a scroll cannot change: built once, handed back as the SAME LISTS."
  (or *chrome*
      (setf *chrome*
            (list (bliss:app-bar "Bliss"
                                 :leading (bliss:icon :menu :size 20)
                                 :actions (list (bliss:icon :search :size 20)))
                  `(row (:gap ,(bliss:space :small) :padding ,(bliss:space :medium))
                        ,(bliss:chip "Dark" :id :dark :selected (eq *scheme* :dark)
                                     :icon :circle
                                     :on-press (lambda (n) (declare (ignore n)) (toggle-scheme)))
                        ,(bliss:chip "Light" :id :light :selected (eq *scheme* :light)
                                     :icon :ring
                                     :on-press (lambda (n) (declare (ignore n)) (toggle-scheme))))
                  (bliss:card (list (bliss:text "A raised card" :size :title)
                                    ;; Hollow controls ON A CARD, which is the
                                    ;; case a faked border gets wrong: it would
                                    ;; paint a surface-coloured hole here.
                                    `(row (:gap ,(bliss:space :medium) :cross-align :center)
                                       ,(bliss:checkbox nil)
                                       ,(bliss:checkbox t)
                                       ,(bliss:radio nil)
                                       ,(bliss:radio t)
                                       ,(bliss:text "on a card" :size :caption
                                                    :colour (bliss:theme :on-surface-variant)))
                                    (bliss:divider)
                                    (bliss:text "with a shadow under it and a divider across it"
                                                :size :caption
                                                :colour (bliss:theme :on-surface-variant)))
                              :elevation 4 :stretch t)
                  `(column (:padding ,(bliss:space :medium) :gap ,(bliss:space :small))
                     (row (:gap ,(bliss:space :small) :cross-align :center)
                       ,@(loop for name in '(:search :menu :close :check :add :remove
                                             :arrow-back :arrow-forward :settings)
                               collect (bliss:icon name :size 24
                                                   :colour (bliss:theme :primary))))
                     (row (:gap ,(bliss:space :small) :cross-align :center)
                       ,@(loop for name in '(:home :favorite :star :delete :edit :share
                                             :more-vert :info :warning)
                               collect (bliss:icon name :size 24
                                                   :colour (bliss:theme :on-surface-variant)))))
                  (bliss:card (list `(row (:gap ,(bliss:space :medium) :cross-align :center)
                                       ,(bliss:checkbox nil)
                                       ,(bliss:radio nil)
                                       ,(bliss:text "outlined card" :size :caption
                                                    :colour (bliss:theme :on-surface-variant))))
                                    :outlined t :stretch t)
                  (bliss:list-item "Wi-Fi" :supporting "Connected"
                                   :leading (bliss:icon :check :size 18)
                                   :trailing (bliss:icon :chevron-right :size 18))
                  (bliss:list-item "Bluetooth" :supporting "Off"
                                   :leading (bliss:icon :close :size 18)
                                   :trailing (bliss:icon :chevron-right :size 18))))))

(defun fields ()
  "Rebuilt only when what they show changes."
  (let ((key (list *name* *city* (bliss:text-focus-id))))
    (unless (equal key (car *fields*))
      (setf *fields*
            (cons key
                  (list (bliss:text "Name" :size :caption
                                    :colour (bliss:theme :on-surface-variant))
                        (bliss:text-field *name* :id :name :placeholder "Ada Lovelace"
                                          :on-change (lambda (text) (setf *name* text)))
                        (bliss:text "City" :size :caption
                                    :colour (bliss:theme :on-surface-variant))
                        (bliss:text-field *city* :id :city :placeholder "London"
                                          :on-change (lambda (text) (setf *city* text)))
                        (bliss:button "Done" :id :done :size :body
                                      :on-press (lambda (n) (declare (ignore n))
                                                  (bliss:blur-text-field)))))))
    (cdr *fields*)))

(defun toggle-scheme ()
  "Swap light for dark. The cached chrome holds COLOURS, so it has to go."
  (setf *scheme* (if (eq *scheme* :dark) :light :dark))
  (bliss:use-scheme *scheme*)
  (setf *chrome* nil *fields* nil)
  (bliss:invalidate))

(defun shelf (width)
  "The only part a drag actually changes."
  (bliss:virtual-list
   5000
   (lambda (index)
     (bliss:card (list (bliss:text (format nil "~D" index) :size 4))
                 :padding 10 :elevation 2))
   :axis :horizontal :id :shelf :offset *shelf* :viewport (- width 40)
   :item-size 70 :height 70
   :on-drag (lambda (node dx dy)
              (declare (ignore dy))
              (setf *shelf-velocity* 0.0)
              (multiple-value-bind (offset used) (bliss:drag-scroll node *shelf* dx)
                (setf *shelf* offset)
                (bliss:invalidate)
                ;; Horizontal consumed, vertical untouched -- so a vertical drag
                ;; on the shelf scrolls the page behind it.
                (values used 0)))
   ;; The finger lifted while moving. Keep the speed; the frame loop spends it.
   :on-fling (lambda (node vx vy)
               (declare (ignore node vy))
               (setf *shelf-velocity* (- vx))
               (bliss:invalidate))))

(defun controls ()
  "The interactive part, rebuilt every frame because it changes every frame."
  (list (bliss:tabs '("All" "Unread" "Starred") *tab*
                    :on-select (lambda (i) (setf *tab* i) (bliss:invalidate)))
        `(row (:gap ,(bliss:space :medium) :cross-align :center
               :padding ,(bliss:space :medium))
           ,(bliss:icon :remove :size 20 :colour (bliss:theme :on-surface-variant))
           ,(bliss:slider *volume* :id :volume :width 180
                          :on-change (lambda (v) (setf *volume* v) (bliss:invalidate)))
           ,(bliss:icon :add :size 20 :colour (bliss:theme :on-surface-variant)))
        `(column (:padding ,(bliss:space :medium))
           ,(bliss:button "Delete everything" :id :delete
                          :on-press (lambda (n) (declare (ignore n))
                                      (setf *dialog* t) (bliss:invalidate))))
        (bliss:snackbar (format nil "Volume ~D%" (round (* 100 *volume*)))
                        :action "Undo")))

(defparameter *insets* '(0 0 0 0))
(defparameter *page* 0)

(defun ui (width height)
  (let ((screen (screen width height)))
    (if *dialog*
        ;; The dialog goes OVER everything, which is a box stacking two things.
        `(box (:width ,width :height ,height)
           ,screen
           ,(bliss:dialog "Delete everything?"
                          (list (bliss:text "This cannot be undone." :size :body
                                            :colour (bliss:theme :on-surface-variant)))
                          :width width :height height
                          :actions (list (bliss:button "Cancel" :id :cancel
                                                       :on-press (lambda (n) (declare (ignore n))
                                                                   (setf *dialog* nil)
                                                                   (bliss:invalidate)))
                                         (bliss:button "Delete" :id :confirm
                                                       :on-press (lambda (n) (declare (ignore n))
                                                                   (setf *dialog* nil)
                                                                   (bliss:invalidate))))))
        screen)))

(defun screen (width height)
  (bliss:scaffold
   :width width :height (- height (fourth *insets*))
   :top (first (chrome))
   :content (list
             (bliss:scroll
              (append (controls)
                    (list (second (chrome))
                  `(column (:padding ,(bliss:space :medium) :gap ,(bliss:space :medium)
                            :cross-align :stretch)
                     ,(third (chrome))
                     ,(shelf width)
                     ,@(fields))
                  (fourth (chrome))
                  (fifth (chrome))
                  (sixth (chrome))
                  (bliss:divider)
                  (seventh (chrome))))
              :id :page :offset *page* :grow 1
              :on-drag (lambda (node dx dy)
                         (declare (ignore dx))
                         (multiple-value-bind (offset used)
                             (bliss:drag-scroll node *page* dy)
                           (setf *page* offset)
                           (bliss:invalidate)
                           (values 0 used)))))))

;;;; Where the frame goes, measured rather than guessed.

(defparameter *phases* (list :touches 0 :build 0 :layout 0 :render 0 :compare 0 :present 0 :blit 0))
(defparameter *frames* 0)
(defparameter *previous-placement* nil)
(defparameter *matched* 0)
(defparameter *nodes* 0)
(defparameter *damage* 0)
(defparameter *op-damage* 0)
(defparameter *ops* 0)

(defmacro timing (phase &body body)
  `(let ((start (get-internal-real-time)))
     (multiple-value-prog1 (progn ,@body)
       (incf (getf *phases* ,phase) (- (get-internal-real-time) start)))))

(defun draw-timed (host view-function)
  (let* ((view (timing :build (funcall view-function (bliss:host-width host)
                                       (bliss:host-height host))))
         (placed (timing :layout
                          (bliss:layout view 0 0
                                        (bliss:constraints 0 (bliss:host-width host)
                                                           0 (bliss:host-height host)))))
         (display (timing :render (bliss:render placed))))
    (incf *ops* (length display))
    (setf (bliss:host-placed host) placed)
    (multiple-value-bind (matched total damage)
        (bliss:placement-overlap placed *previous-placement*
                                  (bliss:rect 0 0 (bliss:host-width host) (bliss:host-height host)))
      (incf *matched* matched) (incf *nodes* total)
      (incf *damage* (if damage (* (bliss:rect-width damage) (bliss:rect-height damage)) 0)))

    (setf *previous-placement* (bliss:record-placement placed))
    (let* ((last (bliss::host-last-display host))
           (same (timing :compare (equal display last))))
      (unless same
        (let ((damage (when last
                        (bliss:display-damage display last
                                              (bliss:rect 0 0 (bliss:host-width host)
                                                          (bliss:host-height host))))))
          (incf *op-damage* (if damage
                                (* (bliss:rect-width damage) (bliss:rect-height damage))
                                (* (bliss:host-width host) (bliss:host-height host))))
          (setf (bliss::host-last-display host) display)
            (timing :present (bliss:present (bliss:host-backend host) display damage))
          (timing :blit (bliss::host-blit host)))))
    (incf *frames*)
    (when (>= *frames* 10)
      (android:log (format nil "10 frames: touches ~D build ~D layout ~D render ~D compare ~D present ~D blit ~D (ms), ~D measures ~D misses, ~D/~D nodes reusable, ~D% by node, ~D% by op, ~D ops, ~D jni, ~D touches"
                           (getf *phases* :touches) (getf *phases* :build) (getf *phases* :layout)
                           (getf *phases* :render) (getf *phases* :compare)
                           (getf *phases* :present) (getf *phases* :blit)
                           bliss:*measure-calls* bliss:*measure-misses*
                           *matched* *nodes*
                           (round (* 100 *damage*)
                                  (* 10 (bliss:host-width host) (bliss:host-height host)))
                           (round (* 100 *op-damage*)
                                  (* 10 (bliss:host-width host) (bliss:host-height host)))
                           *ops* bliss:*jni-calls* bliss:*touch-events*))
      (setf *matched* 0 *nodes* 0 *damage* 0 *op-damage* 0 *ops* 0 bliss:*jni-calls* 0 bliss:*touch-events* 0
            bliss:*measure-calls* 0 bliss:*measure-misses* 0
            *frames* 0
            *phases* (list :touches 0 :build 0 :layout 0 :render 0 :compare 0 :present 0 :blit 0)))))

(defun a11y-check (host)
  "Prove the plumbing without turning a screen reader on.

The content description can be read back, so that half is verifiable here. That
an announcement is SPOKEN cannot be: it needs TalkBack running, which changes
how the whole phone responds to touch."
  (declare (ignore host))
  (android:log (format nil "a11y enabled=~A exploring=~A"
                       (bliss:accessibility-enabled-p) (bliss:exploring-by-touch-p)))
  (android:log (format nil "a11y announce returned ~A (nil is correct with no reader)"
                       (bliss:announce "Bliss demo ready")))
  (android:log "a11y step: describe-screen")
  (bliss:describe-screen "Bliss demo: a card, a shelf, a form and a settings list")
  (android:log "a11y step: read back")
  (android:log "a11y step: system-bars insets")
  (multiple-value-bind (l t* r b) (bliss:window-insets :system-bars)
    (android:log (format nil "insets system-bars ~D ~D ~D ~D" l t* r b)))
  (multiple-value-bind (l t* r b) (bliss:window-insets :ime)
    (android:log (format nil "insets ime          ~D ~D ~D ~D" l t* r b)))
  ;; Read it back off the view, which is the part that can be checked.
  (android:log (format nil "a11y description reads back as ~S"
                       (bliss::with-local-refs ()
                         (bliss::jni-text
                          (bliss::jni-call-object
                           (bliss::decor-view)
                           (bliss::java-method "android/view/View" "getContentDescription"
                                               "()Ljava/lang/CharSequence;")
                           (bliss::jni-args)))))))

(defun android-main (window)
  (let ((host (bliss:open-android-host window)))
    (a11y-check host)
    (loop while (android:running-p)
          do (when (timing :touches (bliss:host-pump-touches host)) (bliss:invalidate))
             ;; What the system is covering changes when the keyboard opens and
             ;; nothing tells us, so it is asked once a frame.
             (when (bliss:refresh-insets host)
               (setf *insets* (bliss:host-insets host))
               (android:log (format nil "insets now ~A" *insets*)))
             ;; What the input method did, once a frame.
             (bliss:pump-text-input)
             (when bliss:*dirty*
               (setf bliss:*dirty* nil)
               (bliss:with-frame-clock (host)
                 ;; Spend a little of the fling, and ask for another frame while
                 ;; there is any left. ANIMATING is what keeps them coming.
                 (when (bliss:flinging-p *shelf-velocity*)
                   (let ((node (bliss:hit-test (bliss:host-placed host) 0 0
                                               (lambda (n) (eq (bliss:node-prop n :id) :shelf)))))
                     (if node
                         (multiple-value-setq (*shelf* *shelf-velocity*)
                           (bliss:fling-step node *shelf* *shelf-velocity*
                                             (bliss:frame-delta)))
                         (setf *shelf-velocity* 0.0)))
                   (bliss:animating))
                 (draw-timed host #'ui)))
             (sleep 0.008))))
