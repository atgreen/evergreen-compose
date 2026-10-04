;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(load "evergreen-compose.lisp")

(defpackage :evergreen-compose-catalog (:use :cl) (:import-from :evergreen-compose :ui))
(in-package :evergreen-compose-catalog)

(defparameter *sections* '("Actions" "Selection" "Input" "Display" "Collections" "Navigation" "Overlays" "Forms" "Lists" "Content" "Data" "Platform"))
(defvar *section* "Actions")
(defvar *dark* nil)
(defvar *drawer* nil)
(defvar *overlay* nil)
(defvar *status* "Try a control. Its result appears here.")
(defvar *values* (make-hash-table :test #'equal))

(defun value (id &optional default) (gethash id *values* default))
(defun changed (id value)
  (setf (gethash id *values*) value)
  (let ((text (princ-to-string value)))
    (setf *status* (format nil "~A: ~A~A" id (subseq text 0 (min 70 (length text)))
                          (if (> (length text) 70) "…" "")))))
(defun change-handler (id) (lambda (value) (changed id value)))
(defun click-handler (id) (lambda () (changed id (1+ (value id 0)))))
(defun label (text) (ui :text :text text :style :label :color :muted))
(defun sample (title &rest controls)
  (ui :column :id (concatenate 'string "sample/" title) :spacing 8 :padding 8
      :children (cons (label title) controls)))
(defun toggle (type id &rest properties)
  (apply #'ui type :id id :checked (value id) :on-change (change-handler id) properties))
(defun action (type text &rest properties)
  (let ((id (or (getf properties :id) (string-downcase type))))
    (remf properties :id)
    (apply #'ui type :id id :text text :on-click (click-handler id) properties)))
(defun show-overlay (name) (lambda () (setf *overlay* name)))
(defun dismiss-overlay () (setf *overlay* nil))

(defun actions ()
  (list (sample "Buttons"
          (ui :row :spacing 8 :children (list (action :button "Filled") (action :outlined-button "Outlined")))
          (ui :row :spacing 8 :children (list (action :text-button "Text") (action :tonal-button "Tonal"))))
        (sample "Icon buttons"
          (ui :row :spacing 16 :children
            (list (action :icon-button "" :icon :add :description "Add")
                  (toggle :icon-toggle-button "favorite" :icon :favorite :description "Favorite")
                  (action :fab "+" :description "Create"))))
        (sample "Disabled control"
          (ui :button :id "disabled" :text "Unavailable" :enabled nil :on-click (click-handler "disabled")))))

(defun selection ()
  (list (sample "Chips"
          (ui :row :spacing 8 :children
            (list (ui :chip :id "filter" :text "Filter" :selected (value "filter")
                      :on-click (lambda () (changed "filter" (not (value "filter")))))
                  (action :assist-chip "Assist")
                  (ui :input-chip :id "input-chip" :text (if (value "removed") "Restore" "Contact")
                      :selected (not (value "removed"))
                      :on-click (lambda () (changed "removed" nil))
                      :on-dismiss (lambda () (changed "removed" t))))))
        (sample "Checkbox, mixed checkbox, radio, switch"
          (ui :row :spacing 12 :children
            (list (toggle :checkbox "checkbox" :description "Checkbox")
                  (ui :tri-state-checkbox :id "mixed" :state (value "mixed" :mixed) :description "Mixed checkbox"
                      :on-click (lambda () (changed "mixed" (case (value "mixed" :mixed) (:mixed :on) (:on :off) (t :mixed)))))
                  (ui :radio-button :id "radio" :selected (value "radio") :description "Radio option"
                      :on-click (lambda () (changed "radio" (not (value "radio")))))
                  (toggle :switch "switch" :description "Switch"))))
        (sample "Slider — release to update Lisp"
          (ui :slider :id "slider" :value (value "slider" 40) :min 0 :max 100 :steps 9
              :description "Volume" :on-change (change-handler "slider")))
        (sample "Range slider"
          (let ((range (value "range" '(20 80))))
            (ui :range-slider :id "range" :value (first range) :end (second range) :steps 9
                :description "Price range" :on-change (change-handler "range"))))
        (sample "Segmented buttons"
          (ui :segmented-buttons :children
            (loop for name in '("Day" "Week" "Month") collect
              (let ((name name))
                (ui :segment :id (concatenate 'string "segment/" name) :text name
                    :selected (equal name (value "segment" "Week"))
                    :on-click (lambda () (changed "segment" name)))))))))

(defun inputs ()
  (list (sample "Outlined text field"
          (ui :text-field :id "name" :label "Your name" :value (value "name" "")
              :fill-width t :on-change (change-handler "name") :on-submit (change-handler "submitted")))
        (sample "Filled text field"
          (ui :filled-text-field :id "email" :label "Email" :keyboard :email :value (value "email" "")
              :fill-width t :on-change (change-handler "email") :supporting "Native keyboard and selection"))
        (sample "Search"
          (ui :search-bar :id "search" :label "Search examples" :value (value "search" "")
              :on-change (change-handler "search") :on-submit (change-handler "search submitted")
              :children (loop for name in *sections* when (search (value "search" "") name :test #'char-equal)
                              collect (let ((name name))
                                        (ui :list-item :id (concatenate 'string "result/" name) :text name
                                            :on-click (lambda () (setf *section* name)))))))
        (sample "Date and time pickers"
          (ui :button :id "open-date" :text "Choose date" :on-click (show-overlay :date))
          (ui :button :id "open-date-range" :text "Choose date range" :on-click (show-overlay :date-range))
          (ui :button :id "open-time" :text "Choose time" :on-click (show-overlay :time)))))

(defun display-controls ()
  (list (sample "Text and icon"
          (ui :row :spacing 12 :children (list (ui :icon :icon :star :color :primary :description "Star")
                                              (ui :text :text "Native typography" :style :title))))
        (sample "Bundled image" (ui :image :id "sample-image" :asset "sample.png" :height 120 :fill-width t
                                    :scale :crop :description "Blue and green landscape" :on-error (change-handler "image error")))
        (sample "Card and divider"
          (ui :card :fill-width t :padding 12 :children
            (list (ui :text :text "A shared Material surface") (ui :divider) (ui :text :text "Light and dark colors follow the theme."))))
        (sample "Badge" (ui :badge :text "3" :children (list (ui :icon :icon :person :description "Three contacts"))))
        (sample "Progress indicators"
          (ui :linear-progress :value 65 :fill-width t)
          (ui :circular-progress :value 65))
        (sample "List item"
          (ui :list-item :id "list-item" :text "A useful row" :supporting "Tap to see its callback" :icon :info
              :on-click (click-handler "list item") :children (list (ui :icon :icon :next))))
        (sample "Tooltip — press and hold"
          (ui :tooltip :text "Create a new item" :children (list (action :icon-button "" :id "tooltip-add" :icon :add :description "Tooltip example"))))
        (sample "Snackbar"
          (ui :snackbar :id "snackbar" :text (if (value "undo") "Change undone" "Sample saved") :action-label "Undo"
              :on-action (lambda () (changed "undo" t))))))

(defun numbered-cards (prefix count)
  (loop for i below count collect
    (ui :card :id (format nil "~A/~D" prefix i) :width 140 :height 80 :padding 12
        :children (list (ui :text :text (format nil "Item ~D" (1+ i)))))))
(defun collections ()
  (list (sample "Lazy vertical list"
          (ui :lazy-column :id "vertical-list" :height 180 :spacing 8 :children (numbered-cards "vertical" 50)))
        (sample "Lazy horizontal list"
          (ui :lazy-row :id "horizontal-list" :spacing 8 :children (numbered-cards "horizontal" 50)))
        (sample "Lazy grid"
          (ui :lazy-grid :id "grid" :columns 2 :height 200 :spacing 8 :children (numbered-cards "grid" 50)))
        (sample "Horizontal pager"
          (ui :horizontal-pager :id "pages" :page (value "pages" 0) :height 100
              :on-change (change-handler "pages") :children (numbered-cards "page" 5)))
        (sample "Vertical pager"
          (ui :vertical-pager :id "vertical-pages" :page (value "vertical-pages" 0) :height 120
              :on-change (change-handler "vertical-pages") :children (numbered-cards "vertical-page" 5)))
        (sample "Swipe actions"
          (ui :swipe :id "swipe" :on-right (lambda () (changed "swipe" "Completed"))
              :on-left (lambda () (changed "swipe" "Deleted"))
              :children (list (ui :card :fill-width t :height 72 :padding 16 :children
                                 (list (ui :text :text (value "swipe" "Swipe me in either direction")))))))))

(defun destinations (prefix)
  (loop for name in '("Home" "Saved") collect
    (let ((name name))
      (ui :nav-item :id (format nil "~A/~A" prefix name) :text name :icon (if (equal name "Home") :home :star)
          :selected (equal (value prefix "Home") name) :on-click (lambda () (changed prefix name))))))
(defun navigation ()
  (list (sample "Tabs — the gallery tabs change the content above")
        (sample "Top app bar"
          (ui :top-bar :text "Example page" :children
            (list (ui :icon-button :id "top-back" :icon :back :slot :navigation :description "Back"
                      :on-click (click-handler "back")))))
        (sample "Navigation bar"
          (ui :bottom-bar :children (destinations "bar"))
          (ui :text :text (format nil "~A content" (value "bar" "Home"))))
        (sample "Navigation rail"
          (ui :row :children (list (ui :navigation-rail :height 190 :children (destinations "rail"))
                                   (ui :text :text (format nil "~A content" (value "rail" "Home"))))))
        (sample "Navigation drawer"
          (ui :button :id "open-drawer" :text "Open drawer" :on-click (lambda () (setf *drawer* t))))
        (sample "Bottom app bar"
          (ui :bottom-app-bar :children (list (ui :icon-button :id "bottom-add" :icon :add :description "Add"
                                                 :on-click (click-handler "bottom add")))))))

(defun overlays ()
  (list (sample "Dropdown menu"
          (ui :dropdown-menu :id "menu" :expanded (value "menu") :on-dismiss (lambda () (changed "menu" nil))
              :children (list (ui :button :id "open-menu" :slot :anchor :text "Open menu"
                                  :on-click (lambda () (changed "menu" t)))
                              (ui :menu-item :id "menu-copy" :text "Copy" :on-click (lambda () (changed "menu" nil) (changed "menu choice" "Copy")))
                              (ui :menu-item :id "menu-share" :text "Share" :on-click (lambda () (changed "menu" nil) (changed "menu choice" "Share"))))))
        (sample "Dialog" (ui :button :id "open-dialog" :text "Open custom dialog" :on-click (show-overlay :dialog)))
        (sample "Alert dialog" (ui :button :id "open-alert" :text "Confirm an action" :on-click (show-overlay :alert)))
        (sample "Bottom sheet" (ui :button :id "open-sheet" :text "Open bottom sheet" :on-click (show-overlay :sheet)))))

(defun overlay ()
  (when *overlay*
    (if (eq *overlay* :alert)
        (ui :alert-dialog :id "alert" :title "Sample confirmation" :text "This only changes the gallery message."
            :on-dismiss #'dismiss-overlay :on-confirm (lambda () (changed "alert" "Confirmed") (dismiss-overlay)))
        (ui (if (eq *overlay* :sheet) :bottom-sheet :dialog) :id "overlay" :on-dismiss #'dismiss-overlay
            :children
            (list (case *overlay*
                    (:date (ui :date-picker :id "date" :value (value "date") :on-change (change-handler "date")))
                    (:date-range (let ((range (value "date-range" '(nil nil))))
                                   (ui :date-range-picker :id "date-range" :value (first range) :end (second range)
                                       :on-change (change-handler "date-range"))))
                    (:time (let ((time (value "time" '(12 0))))
                             (ui :time-picker :id "time" :hour (first time) :minute (second time) :on-change (change-handler "time"))))
                    (otherwise (ui :text :text (if (eq *overlay* :sheet) "A native modal bottom sheet" "Compose your own dialog content"))))
                  (ui :button :id "close-overlay" :text "Done" :on-click #'dismiss-overlay))))))

(defun options (prefix &optional selectable)
  (loop for name in '("Apple" "Pear" "Peach") collect
    (let ((id (format nil "~A/~A" prefix name)))
      (if selectable
          (ui :option :id id :text name :selected (value id) :on-change (change-handler id))
          (ui :option :id id :text name :value name)))))

(defun forms ()
  (list (sample "Autocomplete"
          (ui :combo-box :id "fruit" :label "Fruit" :value (value "fruit" "")
              :on-change (change-handler "fruit") :on-select (change-handler "fruit") :children (options "fruit")))
        (sample "Multi-select" (ui :multi-select :children (options "selection" t)))
        (sample "Quantity" (ui :number-stepper :id "quantity" :value (value "quantity" 2)
                                :min 0 :max 10 :on-change (change-handler "quantity")))
        (sample "Verification code" (ui :otp-field :id "otp" :length 6 :value (value "otp" "") :on-change (change-handler "otp")))
        (sample "Rating" (ui :rating :id "rating" :value (value "rating" 3) :on-change (change-handler "rating")))
        (sample "Expandable section"
          (ui :accordion :id "accordion" :text "More information" :expanded (value "accordion")
              :on-change (change-handler "accordion") :children (list (ui :text :text "This content expands locally."))))))

(defun advanced-lists ()
  (list (sample "Pull to refresh"
          (ui :pull-to-refresh :id "refresh" :height 160 :on-refresh (lambda () (changed "refreshed" "Updated"))
              :children (list (ui :lazy-column :fill t :children
                                 (list (ui :list-item :text (value "refreshed" "Pull down here to refresh")))))))
        (sample "Reorder — hold the handle and drag"
          (ui :reorderable-list :id "reorder" :height 240 :on-move
              (lambda (from to)
                (let* ((items (copy-list (value "order" '("One" "Two" "Three" "Four"))))
                       (item (nth from items)))
                  (setf items (remove item items :count 1 :test #'equal))
                  (changed "order" (append (subseq items 0 to) (list item) (nthcdr to items)))))
              :children (loop for name in (value "order" '("One" "Two" "Three" "Four")) collect
                              (ui :list-item :id (concatenate 'string "order/" name) :text name))))
        (sample "Swipe to reveal buttons"
          (ui :swipe-reveal :height 80 :children
              (list (ui :button :id "reveal-save" :slot :start :text "Save" :on-click (click-handler "Saved"))
                    (ui :button :id "reveal-delete" :slot :end :text "Delete" :on-click (click-handler "Deleted"))
                    (ui :card :fill-width t :height 80 :padding 16 :children (list (ui :text :text "Swipe left or right"))))))
        (sample "Adaptive list and detail"
          (ui :list-detail :height 130 :show-detail (value "detail") :children
              (list (ui :button :id "select-detail" :slot :list :text "Open detail"
                        :on-click (lambda () (changed "detail" t)))
                    (ui :column :slot :detail :children
                        (list (ui :text :text "On wide screens both panes appear.")
                              (ui :text-button :id "detail-back" :text "Back" :on-click (lambda () (changed "detail" nil))))))))
        (sample "Sticky section headers"
          (ui :section-list :height 210 :children
              (loop for group in '("Today" "Tomorrow" "This week") collect
                (ui :section :id (concatenate 'string "group/" group) :text group :children (numbered-cards group 5)))))
        (sample "Material carousel"
          (ui :carousel :height 140 :item-width 180 :children (numbered-cards "carousel" 8)))))

(defun content-controls ()
  (list (sample "Drawing pad — ink is immediate; Lisp receives completed strokes"
          (ui :drawing-pad :id "ink" :height 220 :fill-width t
              :view-width 600 :view-height 400 :pen-color "#234b38" :pen-width 6
              :on-stroke (lambda (stroke)
                           (changed "ink-strokes" (append (value "ink-strokes") (list stroke))))
              :children
              (loop for (color width points) in (value "ink-strokes") for index from 0
                    collect (ui :ink-stroke :id (format nil "ink-~D" index)
                                :color color :width width
                                :data (with-output-to-string (out)
                                        (format out "M~D,~D" (first (first points)) (second (first points)))
                                        (if (rest points)
                                            (dolist (point (rest points))
                                              (format out "L~D,~D" (first point) (second point)))
                                            (write-string "l0.01,0" out))))))) (sample "Asynchronous image"
          (ui :async-image :id "async" :asset "sample.png" :height 140 :fill-width t
              :on-error (change-handler "image error")))
        (sample "Markdown"
          (ui :markdown :text "# Evergreen Compose
**Native controls**, written in Lisp.

- Shared runtime
- Smooth scrolling
- No app-specific Kotlin"))
        (sample "Pinch to zoom"
          (ui :zoom-image :id "zoom" :asset "sample.png" :height 180 :fill-width t :description "Pinch to zoom landscape"))
        (sample "Rich text — select text, then format"
          (ui :rich-text-editor :id "rich" :value (value "rich" "<p>Edit <b>this text</b></p>") :on-change (change-handler "rich")))))

(defun data-controls ()
  (list (sample "Calendar and agenda"
          (ui :calendar :id "calendar" :value (value "calendar" 1791072000000) :on-change (change-handler "calendar")
              :children (list (ui :text :date "2026-10-04" :text "14:00 — Try Evergreen Compose"))))
        (sample "Chart — tap a bar"
          (ui :chart :id "chart" :on-select (change-handler "chart") :children
              (loop for name in '("Mon" "Tue" "Wed" "Thu" "Fri") for v in '(4 9 6 12 8) collect
                (ui :point :id (concatenate 'string "point/" name) :text name :value v))))
        (sample "Table — sort by tapping a heading"
          (ui :data-table :id "table" :page-size 3 :on-select (change-handler "table") :children
              (append (list (ui :table-column :text "Name") (ui :table-column :text "Score" :numeric t))
                      (loop for name in '("Ada" "Grace" "Barbara" "Margaret" "Frances") for score in '(9 7 10 8 6) collect
                        (ui :table-row :id (concatenate 'string "person/" name) :value name :selected (equal name (value "table"))
                            :children (list (ui :cell :text name) (ui :cell :value score)))))))))

(defun platform-controls ()
  (list (sample "System pickers"
          (ui :photo-picker :id "photo" :on-result (change-handler "photo") :on-error (change-handler "picker error"))
          (ui :document-picker :id "document" :on-result (change-handler "document") :on-error (change-handler "picker error")))
        (sample "Map — pan and zoom"
          (ui :map :id "map" :height 220 :latitude 43653000 :longitude -79383000 :zoom 3
              :on-error (change-handler "map error") :on-select (change-handler "place")
              :children (list (ui :marker :id "toronto" :text "Toronto" :latitude 43653000 :longitude -79383000))))
        (sample "Media player"
          (ui :media-player :id "media" :height 190 :source "asset:///sample.wav" :on-error (change-handler "media error")))
        (sample "Camera — permission requested when opened"
          (ui :camera :id "camera" :on-capture (change-handler "capture") :on-error (change-handler "camera error")))
        (sample "Embedded web content"
          (ui :web-view :id "web" :height 160 :html "<html><body><h2>Evergreen Compose</h2><p>A WebView inside a Lisp app.</p></body></html>"))))

(defun section-content ()
  (cond ((equal *section* "Actions") (actions))
        ((equal *section* "Selection") (selection))
        ((equal *section* "Input") (inputs))
        ((equal *section* "Display") (display-controls))
        ((equal *section* "Collections") (collections))
        ((equal *section* "Navigation") (navigation))
        ((equal *section* "Forms") (forms))
        ((equal *section* "Lists") (advanced-lists))
        ((equal *section* "Content") (content-controls))
        ((equal *section* "Data") (data-controls))
        ((equal *section* "Platform") (platform-controls))
        (t (overlays))))

(defun section-tabs ()
  (ui :tabs :id "sections" :children
    (loop for name in *sections* collect
      (let ((name name))
        (ui :tab :id (concatenate 'string "tab/" name) :text name :selected (equal name *section*)
            :on-click (lambda () (setf *section* name)))))))

(defun catalog-screen ()
  (ui :scaffold :children
    (list (ui :top-bar :slot :top :text "Evergreen Compose" :children
              (list (ui :switch :id "theme" :description "Dark theme" :checked *dark*
                        :on-change (lambda (v) (setf *dark* v)))))
          (ui :text :slot :bottom :text *status* :padding 12 :color :primary)
          (ui :column :fill t :children
              (list (section-tabs)
                    (ui :lazy-column :id (concatenate 'string "section/" *section*)
                        :weight 1 :fill-width t :content-padding 12 :spacing 16
                        :children (section-content)))))))

(defun view ()
  (ui :theme :dark *dark* :children
    (list (ui :navigation-drawer :id "drawer" :open *drawer*
              :on-dismiss (lambda () (setf *drawer* nil)) :children
              (append (loop for name in *sections* collect
                        (let ((name name))
                          (ui :drawer-item :id (concatenate 'string "drawer/" name) :text name
                              :selected (equal name *section*)
                              :on-click (lambda () (setf *section* name *drawer* nil)))))
                      (list (catalog-screen))))
          (overlay))))

(defun cl-user::android-main (window)
  (declare (ignore window))
  (evergreen-compose:run-compose-app #'view :trace t))
