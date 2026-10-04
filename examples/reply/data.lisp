;;;; SPDX-FileCopyrightText: Copyright 2022 The Android Open Source Project
;;;; SPDX-License-Identifier: Apache-2.0

(in-package :evergreen-reply)

;;;; Original Reply mail fixtures; runtime edits stay in a separate copy.

(defparameter *initial-mails*
 '(
  (:id 0 :sender "Google Express" :avatar "avatar_express.png" :subject "Package shipped!"
   :body "Cucumber Mask Facial has shipped.

Keep an eye out for a package to arrive between this Thursday and next Tuesday. If for any reason you don't receive your package before the end of next week, please reach out to us for details on your shipment.

As always, thank you for shopping with us and we hope you love our specially formulated Cucumber Mask!"
   :time "20 mins ago" :mailbox :inbox :starred t
   :attachments ())
  (:id 1 :sender "Ali Connors" :avatar "avatar_5.jpg" :subject "Brunch this weekend?"
   :body "I'll be in your neighborhood doing errands and was hoping to catch you for a coffee this Saturday. If you don't have anything scheduled, it would be great to see you! It feels like its been forever.

If we do get a chance to get together, remind me to tell you about Kim. She stopped over at the house to say hey to the kids and told me all about her trip to Mexico.

Talk to you soon,

Ali"
   :time "40 mins ago" :mailbox :inbox :starred nil
   :attachments ())
  (:id 2 :sender "Allison Trabucco" :avatar "avatar_3.jpg" :subject "Bonjour from Paris"
   :body "Here are some great shots from my trip..."
   :time "1 hour ago" :mailbox :inbox :starred nil
   :attachments (("paris_1.jpg" "Bridge in Paris") ("paris_2.jpg" "Bridge in Paris at night") ("paris_3.jpg" "City street in Paris") ("paris_4.jpg" "Street with bike in Paris")))
  (:id 3 :sender "Kim Alen" :avatar "avatar_7.jpg" :subject "High school reunion?"
   :body "Hi friends,

I was at the grocery store on Sunday night.. when I ran into Genie Williams! I almost didn't recognize her afer 20 years!

Anyway, it turns out she is on the organizing committee for the high school reunion this fall. I don't know if you were planning on going or not, but she could definitely use our help in trying to track down lots of missing alums. If you can make it, we're doing a little phone-tree party at her place next Saturday, hoping that if we can find one person, thee more will..."
   :time "2 hours ago" :mailbox :sent :starred nil
   :attachments ())
  (:id 4 :sender "Trevor Hansen" :avatar "avatar_8.jpg" :subject "Brazil trip"
   :body "Thought we might be able to go over some details about our upcoming vacation.

I've been doing a bit of research and have come across a few paces in Northern Brazil that I think we should check out. One, the north has some of the most predictable wind on the planet. I'd love to get out on the ocean and kitesurf for a couple of days if we're going to be anywhere near or around Taiba. I hear it's beautiful there and if you're up for it, I'd love to go. Other than that, I haven't spent too much time looking into places along our road trip route. I'm assuming we can find places to stay and things to do as we drive and find places we think look interesting. But... I know you're more of a planner, so if you have ideas or places in mind, lets jot some ideas down!

Maybe we can jump on the phone later today if you have a second."
   :time "2 hours ago" :mailbox :inbox :starred t
   :attachments ())
  (:id 5 :sender "Frank Hawkins" :avatar "avatar_4.jpg" :subject "Update to Your Itinerary"
   :body ""
   :time "2 hours ago" :mailbox :inbox :starred nil
   :attachments ())
  (:id 6 :sender "Sandra Adams" :avatar "avatar_2.jpg" :subject "Recipe to try"
   :body "Raspberry Pie: We should make this pie recipe tonight! The filling is very quick to put together."
   :time "2 hours ago" :mailbox :sent :starred nil
   :attachments ())
  (:id 7 :sender "Google Express" :avatar "avatar_express.png" :subject "Delivered"
   :body "Your shoes should be waiting for you at home!"
   :time "2 hours ago" :mailbox :inbox :starred nil
   :attachments ())
  (:id 8 :sender "Frank Hawkins" :avatar "avatar_4.jpg" :subject "Your update on Google Play Store is live!"
   :body "Your update, 0.1.1, is now live on the Play Store and available for your alpha users to start testing.

Your alpha testers will be automatically notified. If you'd rather send them a link directly, go to your Google Play Console and follow the instructions for obtaining an open alpha testing link."
   :time "3 hours ago" :mailbox :trash :starred nil
   :attachments ())
  (:id 9 :sender "Sandra Adams" :avatar "avatar_2.jpg" :subject "(No subject)"
   :body "Hey,

Wanted to email and see what you thought of"
   :time "3 hours ago" :mailbox :drafts :starred nil
   :attachments ())
  (:id 10 :sender "Allison Trabucco" :avatar "avatar_3.jpg" :subject "Try a free TrailGo account"
   :body "Looking for the best hiking trails in your area? TrailGo gets you on the path to the outdoors faster than you can pack a sandwich.

Whether you're an experienced hiker or just looking to get outside for the afternoon, there's a segment that suits you."
   :time "3 hours ago" :mailbox :trash :starred nil
   :attachments ())
  (:id 11 :sender "Allison Trabucco" :avatar "avatar_3.jpg" :subject "Free money"
   :body "You've been selected as a winner in our latest raffle! To claim your prize, click on the link."
   :time "3 hours ago" :mailbox :spam :starred nil
   :attachments ())))
