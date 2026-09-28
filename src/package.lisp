;;;; Bliss — a UI framework for TorCL, written as Lisp data.
(defpackage :bliss
  (:use :cl)
  (:export
   ;; geometry
   :rect :rect-x :rect-y :rect-width :rect-height :rect-right :rect-bottom
   ;; paint
   :rgb :rgba :colour-red :colour-green :colour-blue :colour-alpha
   :+black+ :+white+ :+transparent+
   ;; the view tree
   :view-kind :view-props :view-children :view-prop
   ;; layout
   :measure :layout :laid-out :laid-out-view :laid-out-frame :laid-out-children
   :constraints :unbounded :tight
   ;; display list
   :render :flatten-to-rects :colour
   ;; backends
   :surface :make-surface :surface-width :surface-height :surface-pixels
   :draw :clear :pixel-at :write-ppm :ascii-art
   :native-pixel :colour-from-native
   ;; GLES backend (Android)
   :gles-init :gles-surface-size :gles-draw
   ;; the backend protocol
   :backend :present :backend-size :backend-text-metrics :use-backend :draw-frame
   :software-backend :make-software-backend :canvas-backend :make-canvas-backend
   ;; input and dispatch
   :hit-test :dispatch :node-prop :scale-point
   ;; widgets
   :*theme* :theme :button :toggle :spacer :text
   ;; JNI, and the Canvas backend over Android's own Skia
   :jni-start :jni-check :jni-find-class :jni-method :jni-string
   :canvas-open :canvas-draw :canvas-pixels :canvas-release-pixels
   :*measure-text* :bitmap-text-extent :text-extent
   :canvas-width :canvas-height)
  (:documentation
   "A view tree is Lisp data. LAYOUT turns it into placed frames, RENDER turns
those into a flat display list, and a backend executes that list. The framework
above the display list knows nothing about GL, Android, or pixels, which is what
lets it run and be tested anywhere."))
