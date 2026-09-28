;;;; Bliss — a UI framework for TorCL, written as Lisp data.
(defpackage :bliss
  (:use :cl)
  (:export
   ;; geometry
   :rect :rect-x :rect-y :rect-width :rect-height :rect-right :rect-bottom
   ;; paint
   :rgb :rgba :colour-red :colour-green :colour-blue :colour-alpha
   :+black+ :+white+ :+transparent+ :mix-colours :blend
   ;; the view tree
   :view-kind :view-props :view-children :view-prop
   ;; layout
   :measure :layout :laid-out :laid-out-view :laid-out-frame :laid-out-children
   :constraints :unbounded :tight
   ;; display list
   :render :flatten-to-rects :colour :measure-kind :render-kind :round-rect-spans
   ;; backends
   :surface :make-surface :surface-width :surface-height :surface-pixels
   :draw :clear :pixel-at :write-ppm :ascii-art :draw-image :surface-rect
   :native-pixel :colour-from-native
   ;; GLES backend (Android)
   :gles-init :gles-surface-size :gles-draw
   ;; the backend protocol
   :backend :present :backend-size :backend-text-metrics :use-backend :draw-frame
   :software-backend :make-software-backend :canvas-backend :make-canvas-backend
   ;; the frame clock
   :now :frame-delta :animating :approach :ease :*frame-time* :*frame-delta*
   ;; input and dispatch
   :hit-test :dispatch :node-prop :scale-point :scroll-by :*drag-slop*
   :laid-out-content
   ;; widgets
   :*theme* :theme :theme-value :button :toggle :spacer :text
   :vstack :hstack :progress :switch :labelled :scroll :virtual-list :visible-range :image
   ;; JNI, and the Canvas backend over Android's own Skia
   :jni-start :jni-check :jni-find-class :jni-method :jni-string
   ;; the Android host: window, touch mapping and the frame loop
   :*pressed* :*dirty* :invalidate :android-host :open-android-host :run-android-app
   :host-width :host-height :host-placed :host-backend
   :canvas-open :canvas-draw :canvas-pixels :canvas-release-pixels
   :*measure-text* :bitmap-text-extent :text-extent
   :canvas-width :canvas-height)
  (:documentation
   "A view tree is Lisp data. LAYOUT turns it into placed frames, RENDER turns
those into a flat display list, and a backend executes that list. The framework
above the display list knows nothing about GL, Android, or pixels, which is what
lets it run and be tested anywhere."))
