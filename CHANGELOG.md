# Changelog

## 0.0.1 - 2026-10-04

This release establishes the first versioned baseline of Evergreen Compose
(`evergreen-compose`): native Android applications written in Evergreen Common Lisp
(EGCL), using a shared Jetpack Compose and Material 3 runtime. It is experimental;
0.0.1 does not promise API stability or production readiness.

### Application model

- Applications describe immutable UI trees in Lisp with `ui`, and publish them
  with `run-compose-app`. Lisp callbacks own application state; Compose owns
  Android layout, input, scrolling, animation, focus and accessibility.
- The catalog exposes 76 controls, including navigation, forms, dialogs,
  lists, grids, charts, maps, camera previews, media playback and drawing.
- In-progress text editing, scrolling and drawing stay on Android's UI thread.
  Completed interactions are delivered to the Lisp worker, with acknowledgments
  coordinating native state and subsequent snapshots.
- A shared `:drawing-pad` provides finger/stylus ink, brush size and color,
  completed-stroke events and read-only previews. Long gestures use bounded
  point thinning so drawing can continue beyond the event's point limit.

### Data and examples

- Selected Lisp variables can be saved to app-private storage and restored on
  startup. HTTPS requests and RSS/Atom feeds run asynchronously; applications
  can cache returned data and open links in the system browser.
- Hello and the interactive catalog demonstrate app structure and the shared
  controls. Six phone sample adaptations cover news, chat, shopping, mail,
  sleep charts and podcasts, with upstream attribution included.
- Evergreen News reads Planet Lisp and preserves cached articles and bookmarks.
  Evergreen Caster accepts a podcast feed, retains selections, and plays
  publisher audio/video alongside its bundled offline episodes.
- Evergreen Sketchbook is an original Lisp example with six ink colors, three
  brush sizes, undo/redo, named sketches, gallery previews and autosave.

### Building and distribution

- The `evergreen-compose-build:compose-apk` ASDF class packages and signs applications
  using EGCL and `egcl-target-android` runtime API 4. App builds need no JDK,
  Kotlin compiler, Gradle, Android SDK or NDK. ADB deploys the resulting APK.
- The source distribution includes the precompiled Android runtime, its Kotlin
  sources, dependency notices, examples, tests and maintainer build tools.
  App builds do not fetch dependencies from the network.
- Runtime bundle 1.4.0 uses protocol 1 and requires Android 9 / API 28 or later.
  Packaged native libraries and APK entries support 16 KB alignment.
- Distribution archives use a versioned top-level directory, normalized
  metadata, deterministic gzip output and a companion SHA-256 checksum.
  Private signing keys, local state, caches and unfinished examples are excluded.
- The project uses GPL-3.0-or-later WITH Classpath-exception-2.0, matching EGCL.
  Third-party code and assets retain their own license notices.
- Contributor and security policies, a code of conduct, citation metadata,
  GitHub issue forms, a pull request template and grouped GitHub Actions
  dependency updates follow Evergreen's project conventions.
- CI validates the distribution and fresh EGCL-only APK builds. Release
  automation checks matching version tags, supports manual build/test modes,
  and publishes verified archives, checksums and notes with build provenance.

### Known boundaries

- Validation is centered on Fedora 44 x86-64 app builds and an ARM64 Android
  phone. Tablet adaptive layouts, TV and Wear samples are not included.
- Applications ship Lisp source assets; packaging precompiled FASLs is pending.
  The APK builder currently needs `EGCL_HEAP_MB=2048` to avoid an EGCL allocation
  failure with the larger runtime bundle.
- Chat, mail, shopping and health examples use local sample data. They do not
  send messages, submit orders or connect to health accounts.
- Podcast downloads, automatic queue advancement and background playback are
  not implemented. Sketchbook does not yet provide pressure/tilt input, palm
  rejection or image export.
- Additional Compose libraries require a maintainer-built adapter and an
  updated shared runtime; arbitrary composables cannot be loaded by reflection.
- Host tests cannot verify JNI, lifecycle, permissions or rendering. Hosted CI
  and the complete Android instrumentation suite remain release-validation
  follow-ups; the source preparation checks are described in
  [the release guide](docs/RELEASING.md).
