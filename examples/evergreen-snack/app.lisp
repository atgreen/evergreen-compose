;;;; SPDX-FileCopyrightText: Copyright 2020 The Android Open Source Project
;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Evergreen Snack: a local shopping sample adapted from Jetsnack (see NOTICE).

(unless (find-package :evergreen-compose) (load "evergreen-compose.lisp"))
(defpackage :evergreen-snack (:use :cl) (:import-from :evergreen-compose #:ui)
  (:export #:view #:reset))
(in-package :evergreen-snack)
(load (merge-pathnames "data.lisp" *load-truename*))

(defvar *page* :home)
(defvar *detail* nil)
(defvar *quantity* 1)
(defvar *cart* nil)
(defvar *favorites* nil)
(defvar *query* "")
(defvar *category* :all)
(defvar *under-five* nil)
(defvar *alphabetical* nil)
(defvar *overlay* nil)
(defvar *address* "123 Evergreen Lane")
(defvar *address-draft* "")
(defvar *dark* nil)
(defun reset ()
  (setf *page* :home *detail* nil *quantity* 1 *favorites* nil *query* ""
        *category* :all *under-five* nil *alphabetical* nil *overlay* nil
        *address* "123 Evergreen Lane" *address-draft* "" *dark* nil
        *cart* (copy-tree '((5 . 2) (7 . 3) (9 . 1)))))
(reset)
(defun snack (id) (find id *snacks* :key (lambda (s) (getf s :id))))
(defun money (cents) (format nil "$~D.~2,'0D" (floor cents 100) (mod cents 100)))
(defun cart-total () (loop for (id . count) in *cart* sum (* count (getf (snack id) :price))))
(defun set-count (id count)
  (let ((line (assoc id *cart*)))
    (cond ((not (plusp count)) (setf *cart* (remove id *cart* :key #'car)))
          (line (setf (cdr line) (min 99 count)))
          (t (setf *cart* (append *cart* (list (cons id (min 99 count)))))))))
(defun add-to-cart ()
  (set-count *detail* (+ *quantity* (or (cdr (assoc *detail* *cart*)) 0)))
  (setf *overlay* :added))
(defun back ()
  (cond (*overlay* (setf *overlay* nil)) (*detail* (setf *detail* nil)) (t (setf *page* :home))))
(defun category-of (id)
  (cond ((member id '(17 24)) :drinks) ((member id '(21 22 26 27 28)) :fruit)
        ((member id '(15 16 18 19 20 23)) :savory) (t :sweet)))
(defun filtered-snacks ()
  (let ((items (remove-if-not
                (lambda (s) (and (search *query* (getf s :name) :test #'char-equal)
                                 (or (eq *category* :all) (eq *category* (category-of (getf s :id))))
                                 (or (not *under-five*) (< (getf s :price) 500)))) *snacks*)))
    (if *alphabetical* (sort items #'string-lessp :key (lambda (s) (getf s :name))) items)))
(defun favorite-p (id) (not (null (member id *favorites*))))
(defun toggle-favorite (id)
  (setf *favorites* (if (favorite-p id) (remove id *favorites*) (cons id *favorites*))))
(defun open-snack (id) (setf *detail* id *quantity* 1))
(defun action (id icon label callback &rest properties)
  (apply #'ui :icon-button :id id :icon icon :description label :on-click callback properties))

(defun snack-card (s section)
  (let ((id (getf s :id)))
    (ui :card :id (format nil "open-~A-~D" section id) :width 176
        :on-click (lambda () (open-snack id)) :children
      (list (ui :image :asset (getf s :image) :description (getf s :name) :height 136 :fill-width t :scale :crop)
            (ui :column :padding 12 :spacing 6 :children
              (list (ui :text :text (getf s :name) :font-weight :bold :max-lines 1)
                    (ui :text :text (money (getf s :price)) :color :primary)))))))
(defun collection-row (title ids key)
  (ui :column :spacing 12 :children
    (list (ui :text :text title :style :title :padding-horizontal 16)
          (ui :lazy-row :height 272 :spacing 12 :content-padding 16 :children
            (mapcar (lambda (id) (snack-card (snack id) key)) ids)))))
(defun home ()
  (ui :lazy-column :id "snack-home" :fill t :spacing 16 :content-padding 8 :children
    (list (ui :text :text "Something good for your next REPL break." :style :headline :padding 16)
          (collection-row "Evergreen picks" '(1 2 3 4 5 6) "picks")
          (collection-row "Popular on Evergreen Snack" '(15 16 17 18 19) "popular")
          (collection-row "Work from home favourites" '(21 24 26 27 28) "wfh")
          (collection-row "A little treat" '(7 8 9 10 11 12 13 14) "treats"))))
(defun result-row (s)
  (let ((id (getf s :id)))
    (ui :row :id (format nil "result-~D" id) :fill-width t :spacing 12 :padding 8 :children
      (list (ui :image :asset (getf s :image) :width 76 :height 76 :radius 12 :scale :crop :description (getf s :name))
            (ui :column :id (format nil "open-result-~D" id) :weight 1 :spacing 4
                :on-click (lambda () (open-snack id)) :children
              (list (ui :text :text (getf s :name) :style :title)
                    (ui :text :text (money (getf s :price)) :color :primary)))
            (action (format nil "favorite-~D" id) :favorite "Toggle favourite"
                    (lambda () (toggle-favorite id)) :color (if (favorite-p id) :primary :muted))))))
(defun search-view ()
  (ui :column :fill t :spacing 8 :children
    (list (ui :text-field :id "query" :value *query* :label "Find a snack" :fill-width t :padding-horizontal 16
              :on-change (lambda (s) (setf *query* s)))
          (ui :lazy-row :height 56 :content-padding 8 :spacing 8 :children
            (loop for (category label) on '(:all "All" :sweet "Sweet" :savory "Savory" :fruit "Fruit" :drinks "Drinks") by #'cddr collect
              (let ((chosen category))
                (ui :chip :id (format nil "category-~(~A~)" category) :text label :selected (eq category *category*)
                    :on-click (lambda () (setf *category* chosen))))))
          (ui :row :padding-horizontal 16 :spacing 8 :children
            (list (ui :chip :id "under-five" :text "Under $5" :selected *under-five* :on-click (lambda () (setf *under-five* (not *under-five*))))
                  (ui :chip :id "sort" :text "A–Z" :selected *alphabetical* :on-click (lambda () (setf *alphabetical* (not *alphabetical*))))))
          (ui :lazy-column :weight 1 :fill-width t :content-padding 12 :spacing 8 :children
            (let ((results (filtered-snacks)))
              (if results (mapcar #'result-row results) (list (ui :text :text "No snacks found. Try another search." :padding 24))))))))
(defun details ()
  (let ((s (snack *detail*)))
    (ui :lazy-column :id (format nil "snack-detail-~D" *detail*) :fill t :content-padding 20 :spacing 16 :children
      (list (ui :image :asset (getf s :image) :height 270 :fill-width t :scale :crop :radius 24 :description (getf s :name))
            (ui :text :text (getf s :name) :style :headline :font-weight :bold)
            (ui :text :text (money (getf s :price)) :style :title :color :primary)
            (ui :text :text "A snack for your next coding break. Explore the sample menu, choose a quantity, and add it to your basket.")
            (ui :text :text "Sample product · ingredients and availability are not provided." :style :label :color :muted)
            (ui :row :spacing 12 :children
              (list (ui :number-stepper :id "quantity" :value *quantity* :min 1 :max 20 :on-change (lambda (n) (setf *quantity* n)))
                    (action "favorite" :favorite "Toggle favourite" (lambda () (toggle-favorite *detail*))
                            :color (if (favorite-p *detail*) :primary :muted))))
            (ui :button :id "add-cart" :text (format nil "Add to basket · ~A" (money (* *quantity* (getf s :price))))
                :fill-width t :on-click #'add-to-cart)))))
(defun cart-row (line)
  (let* ((id (car line)) (s (snack id)))
    (ui :column :id (format nil "line-~D" id) :spacing 8 :children
      (list (result-row s)
            (ui :row :spacing 12 :children
              (list (ui :number-stepper :id (format nil "cart-~D" id) :value (cdr line) :min 1 :max 99
                        :on-change (lambda (n) (set-count id n)))
                    (ui :text :text (money (* (cdr line) (getf s :price))) :weight 1)
                    (action (format nil "remove-~D" id) :delete "Remove from basket" (lambda () (set-count id 0)))))
            (ui :divider)))))
(defun cart-view ()
  (ui :lazy-column :id "snack-cart" :fill t :content-padding 16 :spacing 16 :children
    (append (list (ui :text :text "Your basket" :style :headline))
            (if *cart* (mapcar #'cart-row *cart*) (list (ui :text :text "Your basket is empty. Find something tasty on Home." :padding 16)))
            (list (ui :text :text (format nil "Subtotal  ~A" (money (cart-total))) :style :title)
                  (ui :text :text "Sample prices. Delivery and tax are not calculated." :style :label :color :muted)
                  (ui :button :id "checkout" :text "Try checkout" :enabled (not (null *cart*)) :fill-width t
                      :on-click (lambda () (when *cart* (setf *overlay* :checkout))))))))
(defun profile-view ()
  (ui :lazy-column :id "snack-profile" :fill t :content-padding 20 :spacing 16 :children
    (append
      (list (ui :text :text "Your snack shelf" :style :headline)
            (ui :list-item :text "Delivery address" :supporting *address* :icon :home)
            (ui :outlined-button :id "edit-address" :text "Edit address"
                :on-click (lambda () (setf *address-draft* *address* *overlay* :address)))
            (ui :text :text "Favourites" :style :title))
      (if *favorites* (mapcar (lambda (id) (result-row (snack id))) *favorites*)
          (list (ui :text :text "Tap a heart to keep a snack here."))))))
(defun overlay ()
  (case *overlay*
    (:added (ui :alert-dialog :id "added" :title "Added to basket" :text "Your basket has been updated."
                :confirm-label "Keep browsing" :on-confirm (lambda () (setf *overlay* nil)) :on-dismiss (lambda () (setf *overlay* nil))))
    (:checkout (ui :alert-dialog :id "checkout-result" :title "Sample checkout"
                   :text (format nil "Basket total: ~A. No order was placed and no payment was taken." (money (cart-total)))
                   :on-confirm (lambda () (setf *overlay* nil)) :on-dismiss (lambda () (setf *overlay* nil))))
    (:address (ui :dialog :id "address" :on-dismiss (lambda () (setf *overlay* nil)) :children
                (list (ui :text :text "Delivery address" :style :title)
                      (ui :text-field :id "address-field" :value *address-draft* :label "Address" :fill-width t
                          :on-change (lambda (s) (setf *address-draft* s)))
                      (ui :button :id "save-address" :text "Save" :on-click
                          (lambda () (unless (zerop (length (string-trim " " *address-draft*)))
                                       (setf *address* *address-draft* *overlay* nil)))))))))
(defun view ()
  (ui :theme :id "screen" :dark *dark* :primary (if *dark* "#edc18b" "#805600")
      :on-back #'back :back-enabled (not (null (or *detail* *overlay* (not (eq *page* :home))))) :children
    (append
      (list (ui :scaffold :fill t :children
              (append
                (list (ui :top-bar :slot :top :text "Evergreen Snack" :children
                        (append (when *detail* (list (action "back" :back "Back" #'back :slot :navigation)))
                                (list (action "theme" :settings "Toggle theme" (lambda () (setf *dark* (not *dark*))))))))
                (unless *detail*
                  (list (ui :bottom-bar :slot :bottom :children
                          (loop for (page label icon) on '(:home "Home" :home :search "Search" :search :cart "Basket" :more :profile "You" :person) by #'cdddr collect
                            (let ((selected page))
                              (ui :nav-item :id (format nil "nav-~(~A~)" page) :text label :icon icon :selected (eq page *page*)
                                  :on-click (lambda () (setf *page* selected))))))))
                (list (if *detail* (details) (ecase *page* (:home (home)) (:search (search-view)) (:cart (cart-view)) (:profile (profile-view))))))))
      (when *overlay* (list (overlay))))))

(defparameter *saved-variables*
  '(*cart* *favorites* *address* *dark* *category* *under-five* *alphabetical*))

(in-package :cl-user)
(defun android-main (window)
  (declare (ignore window))
  (evergreen-compose:run-compose-app #'evergreen-snack:view :state evergreen-snack::*saved-variables*))
