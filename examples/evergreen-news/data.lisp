;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Original Common Lisp sample articles for Evergreen News.

(in-package :evergreen-news)

(defparameter *posts*
 '(
  (:id 1 :title "Give your Common Lisp code a home" :subtitle "Packages name your symbols. Systems describe how your source files fit together."
   :author "Evergreen sample editorial" :date "Common Lisp notes" :minutes 1
   :image "post_1.png" :thumb "post_1_thumb.png"
   :paragraphs (
    (:kind :text :text "A small Common Lisp program can begin with one file. As it grows, two different tools help keep it understandable: packages control symbol names, while ASDF systems describe the files and dependencies to load. A package is not a folder, and a system is not a namespace.")
    (:kind :header :text "Start with a clear boundary")
    (:kind :text :text "DEFPACKAGE declares a package and its public symbols. IN-PACKAGE tells the reader which package to use for the forms that follow. Export the operations that callers need, and keep implementation details internal.")
    (:kind :codeblock :text "(defpackage :evergreen-greetings
  (:use :cl)
  (:export #:greet))

(in-package :evergreen-greetings)

(defun greet (name)
  (format nil \"Hello, ~A!\" name))")
    (:kind :text :text "From another package, EVERGREEN-GREETINGS:GREET names the exported function. The single colon is useful documentation: this is part of the public interface.")
    (:kind :header :text "Describe the files separately")
    (:kind :text :text "An ASDF definition can list a package file before the implementation that uses it. With :SERIAL T, components load in the order shown. Put this definition in evergreen-greetings.asd.")
    (:kind :codeblock :text "(asdf:defsystem \"evergreen-greetings\"
  :serial t
  :components ((:file \"package\")
               (:file \"greetings\")))")
    (:kind :quote :text "Give each boundary one job: packages organize names; systems organize loading.")))
  (:id 2 :title "Pass a function, keep the design simple" :subtitle "Closures give small Common Lisp programs a practical way to supply behavior."
   :author "Evergreen sample editorial" :date "Common Lisp notes" :minutes 2
   :image "post_2.png" :thumb "post_2_thumb.png"
   :paragraphs (
    (:kind :text :text "A function can be an argument, a return value, or a value stored in a variable. That gives application code a direct way to accept behavior from its caller. You do not need a framework just to choose how a result is reported.")
    (:kind :header :text "Make the changing part explicit")
    (:kind :codeblock :text "(defun announce (name output)
  (funcall output (format nil \"Hello, ~A!\" name)))

(announce \"Lisper\"
          (lambda (message)
            (format nil \"Notice: ~A\" message)))")
    (:kind :text :text "The example returns \"Notice: Hello, Lisper!\". ANNOUNCE constructs the message, and its caller supplies the destination. A screen could use a callback that updates application state; a test could use one that collects messages.")
    (:kind :header :text "Capture a little state")
    (:kind :codeblock :text "(let ((messages nil))
  (announce \"Ada\"
            (lambda (message)
              (push message messages)))
  (length messages))")
    (:kind :text :text "This returns 1. The anonymous function closes over the lexical variable MESSAGES. It can read and update that binding when called from ANNOUNCE.")
    (:kind :text :text "A closure is convenient for small, local state. When several screens need the same information, give that state a clear owner and lifetime. Passing functions helps express the design; it does not remove the need to decide who owns the data.")))
  (:id 3 :title "Read, evaluate, change, repeat" :subtitle "Use the REPL to ask small questions about your Common Lisp program."
   :author "Evergreen sample editorial" :date "Common Lisp notes" :minutes 2
   :image "post_3.png" :thumb "post_3_thumb.png"
   :paragraphs (
    (:kind :text :text "The read-eval-print loop is a conversation with a running Lisp environment. You enter a form, Lisp evaluates it, and the result gives you something concrete to inspect. Small experiments make a new function easier to understand before it becomes part of an app.")
    (:kind :header :text "Try one transformation")
    (:kind :codeblock :text "(defun story-label (title minutes)
  (format nil \"~A · ~D min read\" title minutes))

(story-label \"Thinking in lists\" 3)")
    (:kind :text :text "The result is a string: \"Thinking in lists · 3 min read\". Change the function, evaluate its definition again, and call it again. Ordinary later calls use the updated definition; already computed values do not rewrite themselves.")
    (:kind :header :text "Keep useful experiments")
    (:kind :codeblock :text "(assert
  (string= (story-label \"Common Lisp\" 2)
           \"Common Lisp · 2 min read\"))")
    (:kind :text :text "An assertion records the behavior you expect. If the condition is false, ASSERT signals an error. Move useful checks from an exploratory session into the project so the next person can repeat them.")
    (:kind :quote :text "The REPL makes a question cheap to ask. A saved check makes its answer repeatable.")
    (:kind :text :text "This news app is bundled as an Android APK. Editing a source file on your computer does not automatically update the installed app: rebuild and install it, or explicitly use a supported live development connection.")))
  (:id 4 :title "Let application state tell the story" :subtitle "Keep the data that matters separate from the widgets that display it."
   :author "Evergreen sample editorial" :date "Common Lisp notes" :minutes 2
   :image "post_4.png" :thumb "post_4_thumb.png"
   :paragraphs (
    (:kind :text :text "A bookmark belongs to the application. The star on a row is one view of that information. Keeping the saved story IDs in one place lets the feed, article page, and saved list agree without asking a widget what it remembers.")
    (:kind :header :text "Model the smallest useful operation")
    (:kind :codeblock :text "(defun toggle-saved-story (id saved-ids)
  (if (member id saved-ids)
      (remove id saved-ids)
      (cons id saved-ids)))

(toggle-saved-story 6 (list 1 3))")
    (:kind :text :text "The call returns (6 1 3). Calling the same function with 6 and that result returns (1 3). The function computes a new list; it does not destructively modify the supplied list.")
    (:kind :header :text "Render from the current value")
    (:kind :text :text "In Evergreen News, callbacks update the saved IDs. The view function reads those IDs to choose the star color and build the saved stories screen. The article and the feed use the same state, so navigating between them preserves the selection.")
    (:kind :text :text "This sample keeps bookmarks and subscriptions in memory. They last for the current running process, not across every app restart. Persistent storage is a separate responsibility with its own loading and saving behavior.")
    (:kind :quote :text "A small state model is easy to inspect, easy to test, and easy to explain.")))
  (:id 5 :title "Thinking in lists and sequences" :subtitle "Transform a collection with MAPCAR, REMOVE-IF-NOT, and REDUCE."
   :author "Evergreen sample editorial" :date "Common Lisp notes" :minutes 1
   :image "post_5.png" :thumb "post_5_thumb.png"
   :paragraphs (
    (:kind :text :text "Common Lisp has lists, vectors, strings, and functions for working with sequences. Start with the shape of the data and the transformation you want. Many tasks become a short pipeline of selection, mapping, and reduction.")
    (:kind :header :text "Keep the stories you want")
    (:kind :codeblock :text "(let* ((minutes (list 2 5 3 8))
       (short-reads
         (remove-if-not (lambda (n) (<= n 3)) minutes)))
  (mapcar (lambda (n) (format nil \"~D min\" n))
          short-reads))")
    (:kind :text :text "The result is (\"2 min\" \"3 min\"). REMOVE-IF-NOT keeps the matching elements. MAPCAR calls its function on each element of a list and collects the returned values in a new list.")
    (:kind :header :text "Combine several values")
    (:kind :codeblock :text "(reduce #'+ (list 2 5 3 8) :initial-value 0)")
    (:kind :text :text "This returns 18. The initial value also makes the empty-input case return 0. Choose an identity value that matches the operation you are performing.")
    (:kind :header :text "Know which collection you have")
    (:kind :text :text "MAPCAR works on lists. MAP works on sequences and takes a result type: (map 'vector #'1+ #(1 2 3)) produces #(2 3 4). Choose the operation deliberately, and check whether a function may modify its input before sharing that input elsewhere.")))
  (:id 6 :title "A small app, written in Common Lisp" :subtitle "Evergreen Compose connects Lisp views and callbacks to native Android controls."
   :author "Evergreen sample editorial" :date "Common Lisp notes" :minutes 2
   :image "post_6.png" :thumb "post_6_thumb.png"
   :paragraphs (
    (:kind :text :text "This screen is an Evergreen Compose sample. Its article data, navigation choices, bookmarks, and subscriptions are written in Common Lisp. A shared Android runtime renders the view descriptions using Compose controls.")
    (:kind :header :text "Describe a view with ordinary functions")
    (:kind :codeblock :text "(evergreen-compose:ui :column :spacing 12
  :children
  (list
    (evergreen-compose:ui :text :text \"Hello, Common Lisp\")
    (evergreen-compose:ui :button :text \"Read a story\"
      :on-click (lambda ()
                  (setf *article* 6)))))")
    (:kind :text :text "The example belongs inside an application that defines *ARTICLE*. UI constructs the description; the callback changes application state when the button is pressed. The app supplies a view function that describes what to display from the current state.")
    (:kind :header :text "Share the Android foundation")
    (:kind :text :text "The native control implementation lives in the Evergreen Compose runtime. Each sample supplies its own Lisp data and behavior, while the runtime handles the shared controls. An app using those packaged controls does not need its own Kotlin implementation.")
    (:kind :header :text "Try the whole interaction")
    (:kind :bullet :text "Open a story and use Back to return to the feed.")
    (:kind :bullet :text "Tap a star, then open Saved stories from the navigation menu.")
    (:kind :bullet :text "Visit Interests and switch between Topics, People, and Publications.")
    (:kind :bullet :text "Use the gear button to switch between light and dark themes.")
    (:kind :text :text "These are original sample articles for the Evergreen adaptation. The app layout is based on the Android Open Source Project JetNews sample; its upstream attribution remains in NOTICE.")))
 ))
