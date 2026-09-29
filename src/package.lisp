;;;; Bliss — a UI framework for TorCL, written as Lisp data.
(defpackage :bliss
  (:use :cl)
  (:export
   ;; geometry
   :rect :rect-x :rect-y :rect-width :rect-height :rect-right :rect-bottom :rect-union
   ;; paint
   :rgb :rgba :colour-red :colour-green :colour-blue :colour-alpha
   :+black+ :+white+ :+transparent+ :mix-colours :blend
   ;; the view tree
   :view-kind :view-props :view-children :view-prop
   ;; layout
   :measure :layout :laid-out :laid-out-view :laid-out-frame :laid-out-children
   :constraints :unbounded :tight :*measure-calls* :*measure-misses* :forget-layout
   ;; display list
   :render :flatten-to-rects :colour :measure-kind :render-kind :round-rect-spans
   :parse-svg-path :svg-path-strings
   :shadow-rects :shadow-op :*shadow-colour* :stroke-spans :*border-colour* :path-spans :flatten-path
   :record-placement :placement-overlap :display-damage :op-bounds
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
   :semantics :semantic-p :merges-p :describe-node :+roles+
   :announce :announce-node :accessibility-enabled-p :exploring-by-touch-p :describe-screen
   :window-insets
   :hit-test :dispatch :node-prop :scale-point :scroll-by :*drag-slop*
   :hit-path :node-path :scrolling-ancestor :needed-scroll :drag-scroll :bring-into-view
   :fling-step :flinging-p :drag-velocity :*fling-friction* :*fling-minimum*
   :laid-out-content
   ;; widgets
   :*theme* :theme :theme-value :button :toggle :spacer :text
   :vstack :hstack :progress :switch :labelled :scroll :virtual-list :visible-range :image
   :text-field :card :divider :list-item :app-bar :scaffold :chip
   :checkbox :radio :snackbar :dialog :tabs :slider
   :*schemes* :*type-scale* :*spacing* :use-scheme :type-size :space
   :icon :icon-button :icon-names :*icons* :thick-line :circle-path
   ;; which field the keyboard is bound to
   :paragraph :wrap-text :wrapped-extent
   ;; a REPL into the running application
   :start-live-repl :stop-live-repl :live-repl-poll :*live-log* :*slynk-port*
   ;; taps
   :tap-step :tap-handler :tappable-p :*long-press-time* :*double-press-time*
   :*text-input* :focus-text-field :blur-text-field :pump-text-input :text-focus-id
   ;; state that outlives the process
   :*state-store* :save-state :restore-state
   ;; a real platform View inside the tree
   :platform-view :platform-view-rects :sync-platform-views :make-platform-view :platform-view-call
   ;; JNI, and the Canvas backend over Android's own Skia
   :jni-start :jni-check :jni-find-class :jni-method :jni-string
   :jni-text :jni-call-boolean :jni-call-int :jni-field :jni-int-field :jni-call-static-int :jni-release :jni-delete-global :with-local-refs :*jni-calls*
   ;; the on-screen keyboard
   :show-keyboard :hide-keyboard :toggle-keyboard :keyboard-shown-p :key-character
   :attach-editor :editor-text :set-editor-text :start-text-input :accepting-text-p
   ;; the Android host: window, touch mapping and the frame loop
   :*pressed* :*dirty* :*touch-events* :invalidate :android-host :open-android-host :run-android-app
   :host-width :host-height :host-placed :host-backend :host-drag-samples
   :host-insets :refresh-insets :host-drag-chain
   :with-frame-clock :host-started :host-last-frame
   :canvas-open :canvas-draw :canvas-pixels :canvas-release-pixels
   :*measure-text* :bitmap-text-extent :text-extent
   :canvas-width :canvas-height)
  (:documentation
   "A view tree is Lisp data. LAYOUT turns it into placed frames, RENDER turns
those into a flat display list, and a backend executes that list. The framework
above the display list knows nothing about GL, Android, or pixels, which is what
lets it run and be tested anywhere."))
