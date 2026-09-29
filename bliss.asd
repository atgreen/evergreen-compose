(asdf:defsystem "bliss"
  :description "A UI framework for TorCL: view trees are Lisp data."
  :license "MIT OR Apache-2.0"
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "geometry")
                             (:file "paint")
                             (:file "font")
                             (:file "view")
                             (:file "layout")
                             (:file "clock")
                             (:file "input")
                             (:file "text-input")
                             (:file "widgets")
                             (:file "icons-material")
                             (:file "path")
                             (:file "svg")
                             (:file "display")
                             (:file "backend")
                             (:file "utf8")
                             (:module "backend"
                              :components ((:file "software")))))))
