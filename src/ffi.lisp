(in-package :bliss)

;;; The foreign-memory primitives, as MACROS.
;;;
;;; TORCL-FFI:MEM-SET and friends are one-line DEFUNs over TORCL::%FOREIGN-MEMORY,
;;; and on a phone that DEFUN costs far more than the work it wraps. JNI-ARGS
;;; calls MEM-SET once per argument, so a four-argument JNI call paid it four
;;; times -- measured warmed on a Pixel 10 Pro XL, one JNI call through these
;;; helpers cost 271us against 3.6us for the underlying %FFI-CALL.
;;;
;;; Macros rather than inlined functions because TorCL has no INLINE: a macro
;;; expands to the builtin call at the call site and there is no call left to
;;; pay for. The argument order matches the TORCL-FFI functions exactly, so
;;; these are a drop-in rename.
(defmacro ffi-alloc (bytes) `(torcl::%foreign-memory :alloc ,bytes))
(defmacro ffi-free (pointer) `(torcl::%foreign-memory :free ,pointer))
(defmacro ffi-set (value pointer type &optional (offset 0))
  `(torcl::%foreign-memory :set ,pointer ,type ,offset ,value))
(defmacro ffi-ref (pointer type &optional (offset 0))
  `(torcl::%foreign-memory :ref ,pointer ,type ,offset))
