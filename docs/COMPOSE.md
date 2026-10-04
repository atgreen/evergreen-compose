# Lisp applications with Compose

Evergreen Compose's Android model has three parts:

1. Application functions return immutable UI data and callbacks change Lisp state.
2. The shared Lisp host sends snapshots and drains a queue of semantic events.
3. A precompiled Kotlin runtime renders the tree with real Compose components.

The runtime is shared across applications as a build artifact; Android still
loads it in each application's own process. There is no shared service or shared
application state. App developers write no Java/Kotlin or JNI.

## Your application

An `app.lisp` begins with `(load "evergreen-compose.lisp")` and defines
`cl-user::android-main`, accepting the window argument. Inside it,
`(evergreen-compose:run-compose-app #'view)` runs a zero-argument function returning a UI tree.
See [Hello Evergreen Compose](../examples/hello/app.lisp) for a complete small app.

```lisp
(evergreen-compose:ui :column :padding 16 :spacing 12 :children
  (list (evergreen-compose:ui :text :text "Shopping" :style :title)
        (evergreen-compose:ui :button :id "add" :text "Add item" :on-click #'add-item)))
```

Every interactive node needs a **unique, stable string ID**. Give list items
stable IDs derived from their data, not their current index. Unnamed decorative
nodes receive structural IDs. Duplicate IDs and unknown widget names fail on the
Lisp side before publication. NIL entries in `:children` are omitted.

`ui` returns ordinary lists; app functions can freely compose them. Treat a
returned tree as immutable. Callbacks close over application data, never Java
objects. `:on-click`, `:on-dismiss`, `:on-right` and `:on-left` take no arguments.
`:on-change` receives text, a boolean, an integer, or a pair of integers
according to the [control contract](COMPOSE-CONTROLS.md). `:on-confirm` and
`:on-action` take no arguments; `:on-submit` and `:on-error` receive a string. Every dispatched event invalidates the view. Call
`evergreen-compose:invalidate` explicitly after state changes made outside callbacks.

The latest tree supplies callbacks. Events for removed controls are ignored;
sequence numbers reject duplicate deliveries. Keep IDs attached to the same
logical item to avoid routing an old action to a different item.

## Components

See the [76-control catalog](COMPOSE-CONTROLS.md) for the complete API and
interactive gallery. It includes native buttons, selection controls, fields,
pickers, images, progress, lists, grids, pagers, navigation, menus and overlays.
Layout helpers (`:theme`, `:row`, `:column`, `:box`, `:spacer`, `:scaffold`) are
additional. Rows/columns accept `:spacing`; their children accept `:weight`.
Scaffold children use `:slot :top`, `:bottom`, or `:fab`; remaining children are
content. Scaffold applies content and IME insets.

Common modifier properties: `:fill`, `:fill-width`, integer `:width`, `:height`,
`:padding`, `:background`, `:radius`, and accessibility `:description`. Sizes are
Compose dp; font sizes are sp. Standard interactive controls accept `:enabled`.
Rows, columns, boxes, text, cards, images and list items also accept `:on-click`.

Colors accept Android hex strings or semantic names: `:primary`, `:on-primary`,
`:surface`, `:surface-variant`, `:on-surface`, `:muted`, `:error`,
`:error-container`, `:primary-container`. Prefer roles so content updates with
the theme. Unsupported property names are currently passed through and ignored
by adapters; follow the catalog above.

## State and lifecycle

Lisp owns application state. Compose owns transient UI state: scroll position,
text selection and IME composition, animation and gestures. Stable IDs preserve
Compose state across publications. A text field applies a Lisp value only after
that snapshot acknowledges its latest edit, preventing old snapshots from
erasing more recent keystrokes.

Changed node records cross JNI once per publication; scrolling and animations make no
per-frame Lisp calls. Evergreen Compose compares node definitions and sends only changed records after the initial
snapshot. Unchanged lists are retained on Android. Lazy lists virtualize composition;
application view functions still run after callbacks, so cache expensive static data
or page very large data sets. The publication queue retains only its latest resolved
snapshot. `run-compose-app :trace t` logs view, encoding and transfer timings without
logging application content.

The shared host supplies lifecycle, saved-state, ViewModel and back-dispatcher
owners to its ComposeView, including when the Activity is a plain NativeActivity. It pauses/resumes with the Activity and disposes composition and
references on teardown. UI state survives recomposition. To retain app data across Activity recreation,
process death, and force-stop, pass an explicit list of special variables:

```lisp
(evergreen-compose:run-compose-app #'view
  :state '(*bookmarks* *draft* *dark*)
  :on-start #'refresh-feed)
```

The host restores these variables before `:on-start`, then saves changed values
after each publication. Data is a versioned readable Lisp value in an app-private
atomic file. Only named variables are restored; `*read-eval*` is disabled.
Keep temporary UI overlays and active playback out of this list. Values must be
readably printable; use lists, strings, numbers and symbols, not closures or JNI
objects. Uninstalling or clearing app storage removes the file. This is a small
app-state store, not a database for large datasets. The older `save-state` and
`restore-state` APIs still provide Android instance state.

## Live data

`http-get` and `fetch-feed` run HTTPS requests on shared background workers.
Callbacks run on the Lisp worker and automatically request a new UI snapshot:

```lisp
(evergreen-compose:fetch-feed "https://planet.lisp.org/rss20.xml"
  (lambda (items status failure)
    (if failure
        (setf *notice* failure)
        (setf *articles* items))))
```

Feed items have `:key`, `:title`, `:link`, `:summary`, `:author`, `:date`, and
`:audio` (an HTTPS audio/video enclosure URL or an empty string). RSS 2.0 and
Atom are supported; HTML becomes plain text. The parser rejects DTDs. Each feed
returns at most 50 entries. `http-get` has the same callback arguments but returns
text instead of items. HTTP failures report the status; transport failures use
zero. Declare `:apk-permissions ("android.permission.INTERNET")` in your APK system.

Requests have connect/read timeouts, a 2 MiB response limit, a bounded redirect
count, and at most eight pending Lisp callbacks. Network failure does not erase
app-owned cached data. The samples keep stable IDs for bookmarked/queued entries
across refreshes. `open-url` opens the original article in the user's browser.

## Packaging

Define an APK system using `evergreen-compose-build:compose-apk`, derived from
`egcl-apk-asdf:android-apk`. All normal `:apk-*` settings apply. The entry must be
`app.lisp`. File components become flat application assets; do not duplicate
framework asset basenames. The packager adds the framework and the pinned bundle.

The default bundle is `runtime/compose-v1/`. `bundle.sexp` records protocol,
minimum SDK, version and SHA-256 for every DEX/resource/native entry. The builder checks
them before signing, along with EGCL runtime ABI/version checks. It enables DEX
loading and platform Back callbacks in EGCL's NativeActivity manifest; the rest of the manifest is generated
by EGCL. App package IDs and labels are independent of the prelinked resource
package. Minimum SDK is 28; the current default target is 34.

The APK contains precompiled `classes*.dex`, prelinked `resources.arsc` and
`res/`, Lisp assets, EGCL's native library, and bundled dependency libraries for
the selected EGCL processor architectures. An AAR alone is insufficient: it
still needs dependency resolution, DEX conversion and resource linking.

`evergreen-compose-build:*compose-runtime-directory*` can select a compatible extracted
bundle. Ship its notices alongside it. Checksums detect accidental corruption;
they are not signatures or a substitute for trusting the distribution source.

## Runtime maintainers

Only runtime contributors need JDK 21, Android SDK platform 35 and build-tools 34,
Python 3 and Gradle. The wrapper pins Gradle 8.7; the project pins Kotlin 1.9.24,
AGP 8.6.1, Compose compiler 1.5.14 and Compose BOM 2024.09.03.

```sh
JAVA_HOME=/path/to/jdk21 ANDROID_HOME=/path/to/sdk sh tools/build-compose-runtime.sh
```

The build compiles and shrinks the runtime, then exports already-linked code
and resources. It never changes an application's signing identity. Inspect the
bundle diff and rerun packaging/device checks after changing it. Published Evergreen Compose
source distributions must include `runtime/compose-v1`, not just Kotlin sources.
App builds never invoke this script.

For bridge instrumentation tests on a connected device:

```sh
egcl --no-init --load tests/export-compose-catalog.lisp
android/compose/gradlew -p android/compose assembleDebug assembleDebugAndroidTest
adb install --user 0 -r android/compose/build/outputs/apk/debug/evergreen-compose-runtime-debug.apk
adb install --user 0 -r android/compose/build/outputs/apk/androidTest/debug/evergreen-compose-runtime-debug-androidTest.apk
# Permission race test starts with CAMERA denied on this isolated test app.
adb shell pm revoke --user 0 dev.egcl.compose.runtime android.permission.CAMERA
adb shell am instrument --user 0 -w -e class dev.egcl.compose.CameraPermissionTest dev.egcl.compose.runtime.test/androidx.test.runner.AndroidJUnitRunner
adb shell am instrument --user 0 -w -e class 'dev.egcl.compose.BridgeTest,dev.egcl.compose.CatalogTest,dev.egcl.compose.ExpandedTest,dev.egcl.compose.NativeHostTest,dev.egcl.compose.PlatformTest' dev.egcl.compose.runtime.test/androidx.test.runner.AndroidJUnitRunner
```

These use an isolated runtime test app. Also install
the **release bundle's** Lisp APK examples: instrumentation alone does not
validate JNI, R8 or the pure-Lisp packager. `tests/compose-no-toolchain.sh` builds
three app identities with an empty environment, fresh ASDF caches/configuration,
and only EGCL on PATH. Its shell harness needs normal host shell utilities;
the APK build processes have access to no external build commands.

### Adding Compose libraries

Composable functions are compiler-transformed Kotlin functions, so Evergreen Compose cannot
invoke arbitrary composables by reflection. Add a dependency to the maintainer
project, add an adapter alongside `Renderer.kt`, and add its node name to
`*compose-components*` in `src/compose.lisp`. Define its properties, child slots,
state ownership and semantic callbacks, then test and rebuild the shared bundle.
Applications can then use it entirely from Lisp.

Dependencies must work with the runtime's pinned Compose/Kotlin versions. A
library requiring manifest components, providers, permissions, assets or native
libraries needs explicit packaging support; the exporter accepts
DEX, linked resources, META-INF notices and an explicit allowlist of native
libraries. It checks native ELF alignment for 16 KB Android pages. It must not silently promise support
for such a dependency. A runtime protocol change requires a versioned migration
on both sides of the bridge.

Android's [ComposeView interoperability guidance](https://developer.android.com/develop/ui/compose/migrate/interoperability-apis/compose-in-views)
and [swipe-to-dismiss guidance](https://developer.android.com/develop/ui/compose/touch-input/user-interactions/swipe-to-dismiss)
explain the underlying Android APIs.


## Migrating from Bliss

The project and public Lisp package are now **Evergreen Compose** (`evergreen-compose`).
Use `evergreen-compose.asd`, `evergreen-compose-build.asd`, `evergreen-compose:ui`, and
`evergreen-compose:run-compose-app`. The default build target is `evergreen-compose/apk`.
The old software/Canvas/GLES and retained-page renderers have been removed,
along with their examples and build helpers. There is no second widget API to
maintain. The default demo uses the small Hello example.

The runtime's JVM namespace is `dev.egcl.compose`. The sample application IDs are
`dev.egcl.compose.demo`, `dev.egcl.compose.hello`, and `dev.egcl.compose.catalog`.
These install alongside the former `org.bliss.*` development apps; they do not
migrate those apps' private data. New applications should choose their own ID.
