# 76 shared Compose controls

This is a practical app-development selection for 2026, based on Android's
[Material component catalog](https://developer.android.com/develop/ui/compose/components)
and its [lists and grids](https://developer.android.com/develop/ui/compose/lists)
and [pager](https://developer.android.com/develop/ui/compose/layouts/pager) APIs.
It is a curated catalog, not a measured popularity ranking. The runtime pins
Compose BOM 2024.09.03 / Material 3 1.3.0; inclusion here does not imply the latest
2026 Material Expressive appearance or alpha APIs.

All 76 controls below have native implementations shared by every Evergreen Compose app.
Layout helpers and child descriptors are additional and are **not** counted.
Use `(evergreen-compose:ui :control ... :children (list ...))`; applications need no Kotlin,
Java, Gradle or Android SDK. The [interactive gallery](../examples/catalog/app.lisp)
shows every control, real callbacks, light/dark themes and changing tab content.

## Catalog

Properties below are in addition to the common modifiers in [the guide](COMPOSE.md).
All interactive nodes require a stable string `:id`. `:on-click`, `:on-dismiss`,
`:on-confirm`, `:on-action`, `:on-left`, and `:on-right` take **no arguments**.
`:on-change` follows the value contracts below; `:on-submit` and `:on-error`
receive one string. Lisp owns visibility, selection and application state.

| # | Control | Properties and behavior |
|---:|---|---|
| 1 | `:button` | Filled Material button: `:text`, `:on-click`, optional children. |
| 2 | `:outlined-button` | Outlined button; same contract. |
| 3 | `:text-button` | Text button; same contract. |
| 4 | `:tonal-button` | Filled tonal button; same contract. |
| 5 | `:icon-button` | `:icon`, `:description`, `:on-click`; accepts legacy `:text` glyphs. |
| 6 | `:icon-toggle-button` | `:icon`, `:checked`, `:on-change` boolean. |
| 7 | `:fab` | Floating action button: `:text` (default `+`), children, `:on-click`. |
| 8 | `:chip` | Filter chip: `:text`, `:selected`, `:on-click`. |
| 9 | `:assist-chip` | Action chip: `:text`, `:on-click`. |
| 10 | `:input-chip` | `:text`, `:selected`, `:on-click`; `:on-dismiss` adds a remove button. |
| 11 | `:checkbox` | `:checked`, `:on-change` boolean. |
| 12 | `:tri-state-checkbox` | `:state :off`, `:on`, or `:mixed`; `:on-click` lets the app choose the next state. |
| 13 | `:radio-button` | `:selected`, `:on-click`; implement exclusive selection in Lisp. |
| 14 | `:switch` | `:checked`, `:on-change` boolean. |
| 15 | `:slider` | Integer `:value`, `:min` (0), `:max` (100), `:steps` (0); change on release. |
| 16 | `:range-slider` | Lower `:value`, upper `:end`; same bounds/steps; change returns `(low high)`. |
| 17 | `:segmented-buttons` | `:segment` children with `:text`, `:selected`, `:on-click`; `:multiple t` for independent selection. |
| 18 | `:text-field` | Outlined input: `:value`, `:label`, `:on-change` string. Additional options below. |
| 19 | `:filled-text-field` | Filled input, same contract as outlined input. |
| 20 | `:search-bar` | `:value`, `:label`, `:on-change`, `:on-submit`; children display native docked search results on focus. |
| 21 | `:date-picker` | `:value` is UTC epoch milliseconds or NIL; `:on-change` returns the selected UTC midnight or NIL. |
| 22 | `:date-range-picker` | Start `:value`, optional `:end`; change returns `(start end)`: `(NIL NIL)` when unset, or `(start NIL)` while choosing the end. |
| 23 | `:time-picker` | `:hour` (0–23), `:minute` (0–59), `:24-hour` (true); change returns `(hour minute)`. `:input-mode t` uses keyboard entry. |
| 24 | `:text` | `:text`, `:style` (`:headline`, `:title`, `:label`, body), `:font-size`, `:color`; optional `:on-click`. |
| 25 | `:icon` | Named vector `:icon`, semantic `:color`, accessibility `:description`. |
| 26 | `:image` | Bundled `:asset` basename; `:scale :fit` (default), `:crop`, or `:fill`; `:description`, `:on-click`, `:on-error`. |
| 27 | `:card` | `:children`, `:radius` (12), optional `:on-click`. |
| 28 | `:divider` | Horizontal by default; `:vertical t` for a vertical divider. Bound its length. |
| 29 | `:badge` | `:text` badge over `:children`, typically an icon. |
| 30 | `:linear-progress` | Integer percent `:value` (0–100); omit it for indeterminate progress. |
| 31 | `:circular-progress` | Same percent/indeterminate contract. |
| 32 | `:list-item` | `:text`, `:supporting`, `:overline`, leading `:icon`, trailing children; optional `:on-click`. |
| 33 | `:tooltip` | `:text` shown on long press/hover over its children. |
| 34 | `:snackbar` | `:text`, `:action-label`, `:on-action`, optional `:on-dismiss`; app controls visibility/duration. |
| 35 | `:lazy-column` | Virtualized vertical list; stable child IDs, `:spacing`, `:content-padding`. |
| 36 | `:lazy-row` | Virtualized horizontal list; same contract. |
| 37 | `:lazy-grid` | Virtualized vertical grid: `:columns` (2), `:spacing`, `:content-padding`. |
| 38 | `:horizontal-pager` | Keyed pages: `:page` (zero-based), `:spacing`, `:on-change` settled page index. |
| 39 | `:vertical-pager` | Same page contract, vertical gestures. |
| 40 | `:swipe` | Content child, `:on-right`, `:on-left`, `:right-label`, `:left-label`; app decides removal/update. |
| 41 | `:tabs` | `:tab` children with `:text`, `:selected`, `:on-click`; `:scrollable` defaults true. Lisp selects associated content. |
| 42 | `:bottom-bar` | Material navigation bar; `:nav-item` children with `:text`, `:icon`, `:selected`, `:on-click`. |
| 43 | `:navigation-rail` | Vertical navigation; same `:nav-item` children. |
| 44 | `:navigation-drawer` | `:open`, `:on-dismiss`; `:drawer-item` children with `:text`, `:icon`, `:selected`, `:on-click`. Other `:slot :drawer` children decorate the sheet; remaining children are main content. |
| 45 | `:top-bar` | Centered `:text` title, children with `:slot :navigation` at start; other children are actions. |
| 46 | `:bottom-app-bar` | Material bottom app bar with action children. |
| 47 | `:dropdown-menu` | `:expanded` (true), `:on-dismiss`; anchor children use `:slot :anchor`; `:menu-item` children use `:text`, `:icon`, `:on-click`. |
| 48 | `:dialog` | Custom dialog content and `:on-dismiss`; remove the node to close. |
| 49 | `:alert-dialog` | `:title`, `:text`, `:confirm-label` (OK), `:on-confirm`; optional `:on-dismiss` and `:dismiss-label` (Cancel). |
| 50 | `:bottom-sheet` | Native modal bottom sheet; content children and `:on-dismiss`. |

## Values and local interaction

Sliders keep their thumb movement native and emit once at the end of a drag or
accessibility adjustment. Use integer units, for example 0–1000 for tenths of a
percent. `:steps` counts internal stops, not interval size: 0–100 with 9 steps
selects multiples of ten. `:min` must be less than `:max`; range endpoints are
clamped into that interval and kept ordered. Numeric properties are integers;
floating-point Lisp properties are not part of this protocol.

Editors, boolean toggles, sliders, pickers and pagers retain local interaction
state until Lisp acknowledges it. A newer acknowledged Lisp value can correct
or reset them. Programmatic changes do not themselves trigger change callbacks.
Pagers emit after scrolling settles. Scrolling lists/grids does not call Lisp.

Dates use **Unix milliseconds**, not Common Lisp universal time or local time.
For whole-second universal time `u`, Unix milliseconds are
`(* 1000 (- u 2208988800))`. The picker normalizes dates to midnight UTC. Both date
controls accept `:input-mode` initially and `:show-mode-toggle` (default true).
They use Material's default 1900–2100 selectable year range. Put pickers in a
dialog or sheet when they should open transiently; selection and confirmation
are separate actions. See the gallery's `overlay` function.

Fields accept `:single-line` (true), `:read-only`, `:password`, `:error`,
`:supporting`, `:keyboard` (`:text`, `:number`, `:email`, `:phone`, `:password`),
and `:on-submit`. `:password t` obscures text; choosing a password keyboard alone
does not obscure it. Search uses its native search IME action and owns the
transient expanded state; search results are application-supplied children.

Buttons, selection controls, fields, sliders, pickers and navigation items accept
`:enabled nil`. Pagers disable gestures with it. Drawer `:enabled nil` disables
its swipe gesture; `:open` still controls its visibility. A snackbar is persistent
while included in the tree; it does not start an implicit timer.

## Images, icons, and layout

The built-in vector icon names are `:add`, `:close`, `:menu`, `:search`, `:home`,
`:favorite`, `:settings`, `:check`, `:delete`, `:edit`, `:back`, `:more`, `:person`,
`:star`, `:next`, `:down`, and `:info`. Navigation items retain support for legacy
text/glyph icons. Use children or image assets for other artwork. Give icon-only
actions meaningful `:description` text.

Images read PNG/JPEG/WebP assets off the UI thread. Add the file as an ASDF
`:static-file`; its basename becomes the APK asset name. Decoding bounds either
side to 2048 pixels to limit memory use. Supply a display size to avoid layout
jumps. Missing/invalid assets show “Image unavailable” and emit `:on-error` once
per failed load. Remote URLs, SVG and animated-image playback are not supported
by this asset-image adapter. Files belong to each app; there is no shared storage.

Give scrollable children a finite viewport. Grids and pagers default to 240dp
height unless `:height`, `:fill`, or row/column `:weight` provides a size; date
range pickers default to 480dp. Ordinary lazy lists need a constrained parent or
explicit size. A screen-level list normally uses `:weight 1` inside a column.
Stable IDs preserve item identity when sibling content changes.

Layout helpers remain `:theme`, `:column`, `:row`, `:box`, `:spacer`, and
`:scaffold`. Child descriptors are `:tab`, `:segment`, `:nav-item`, `:drawer-item`,
and `:menu-item`; use them only inside the matching parent control.

## Run the gallery

From this checkout:

```sh
EGCL_HEAP_MB=2048 egcl --no-init \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "evergreen-compose-build.asd"))' \
  --eval '(asdf:load-system "evergreen-compose-build")' \
  --eval '(asdf:load-asd (truename "examples/catalog/catalog.asd"))' \
  --eval '(asdf:make "catalog/apk")'
adb install --user 0 -r examples/catalog/build/catalog.apk
adb shell am start --user 0 -n dev.egcl.compose.catalog/android.app.NativeActivity
```

The gallery has its own application ID and sample state. It does not access
other applications or their data. See `tests/export-compose-catalog.lisp` for the
fixture generator used by native tests: those tests render the actual Lisp
sample trees, including every control, rather than a second hand-written gallery.

## Additional controls (51–75)

These controls use the same `ui` trees and shared runtime. Descriptor children
(`:option`, `:section`, `:point`, `:table-column`, `:table-row`, `:cell`, `:marker`)
are data for their parent and are not rendered independently.

| # | Control | Properties, children and callbacks |
|---|---|---|
| 51 | `:combo-box` | Editable autocomplete: `:value`, `:label`, `:on-change` (query string), `:on-select` (option value). `:option` children have `:text`, `:value` (defaults to ID), `:enabled`. Filtering is case-insensitive. Store the chosen display text in `:value`. |
| 52 | `:multi-select` | A group of independently selectable chips. Each `:option` has `:text`, `:selected`, `:enabled`, and its own `:on-change` (boolean). |
| 53 | `:pull-to-refresh` | Wrap scrollable content. `:refreshing` controls progress; `:on-refresh` takes no arguments. The native indicator starts immediately; publish the acknowledged final refreshing state when work finishes. |
| 54 | `:reorderable-list` | Long-press a handle to drag; accessible “Move earlier/later” actions are also available. `:columns` (default 1) allows a grid, `:height` defaults to 320, `:spacing`. `:on-move` receives **two arguments**, zero-based source and destination indices. Update the Lisp child order by removing the source and inserting at the destination. Give children stable IDs. |
| 55 | `:swipe-reveal` | Content children slide to expose children with `:slot :start` or `:slot :end`. `:reveal-width` defaults to 120 dp. Revealing an action does not invoke it; its own button callback does. Accessible actions can open/close the reveal. |
| 56 | `:accordion` | `:text` heading, `:expanded`, `:on-change` (boolean); content children appear when expanded. |
| 57 | `:async-image` | Coil image loading/caching. `:source` accepts HTTPS, content URI, or app-private file URI; `:asset` is an alternative for bundled images. Set width/height or `:fill`. `:scale :crop` or fit, `:description`, `:error-text`, `:on-load` (source string), `:on-error` (message). Includes loading and failure presentation. |
| 58 | `:markdown` | Markwon renders `:text` as selectable native rich text, including headings, lists, emphasis and links. Theme text color follows Compose. |
| 59 | `:photo-picker` | Button launches the system image picker, with document-provider fallback on older Android. `:text`, `:on-result` (one content URI), `:on-dismiss` on cancellation, `:on-error`. No broad photo-library permission needed. |
| 60 | `:document-picker` | Button opens a system document provider. `:mime` defaults to `"*/*"`; `:on-result` receives one content URI. Same cancellation/error contracts as photo picker. Read grants are persisted when the provider permits it. |
| 61 | `:number-stepper` | Integer `:value`, `:min` (0), `:max` (100), `:step` (1); `:on-change` receives the new integer. Buttons respond locally and disable at bounds. |
| 62 | `:otp-field` | Numeric input with `:length` (default 6, maximum 32), `:value`, `:label`, `:on-change`. Values remain **strings**, preserving leading zeros. Non-ASCII digits and non-digits are filtered. |
| 63 | `:list-detail` | Children with `:slot :list` and `:slot :detail`. At `:breakpoint` dp (default 600) both panes show, in a 1:2 ratio. Below it, `:show-detail` chooses the detail pane. The app supplies selection and Back buttons. |
| 64 | `:section-list` | Lazy list with sticky headers. `:section` children have `:text` and content children. Use globally unique stable IDs. Default bounded height 320 dp. |
| 65 | `:carousel` | Material 3 multi-browse carousel. `:item-width` (220), `:height` (180), `:spacing` (8), initial `:page` (0), and item children. Native scrolling/snapping owns position; this pinned Material API does not expose a page-change callback or programmatic page updates. Interactive items use their own callbacks. |
| 66 | `:zoom-image` | Image properties as above, plus native pinch zoom/pan and `:max-zoom` (5). Returning to scale 1 resets panning. |
| 67 | `:calendar` | Browsable month grid. `:value` and `:on-change` use UTC midnight Unix milliseconds. Children with a matching ISO `:date` (`"2026-10-04"`) form the selected day's agenda. Month labels are currently English, Monday first. |
| 68 | `:chart` | `:kind :bar` (default) or `:line`, `:color`, `:plot-height` (180). `:point` children have `:text` and integer `:value`. `:on-select` receives the tapped point ID. Values and labels are exposed to accessibility. |
| 69 | `:data-table` | `:table-column` children define `:text`, `:width` (140), `:numeric`, `:sortable`. `:table-row` children contain `:cell` children (`:text` or numeric `:value`), with row `:value`/`:selected`. Native heading clicks sort; `:page-size` defaults to 10. Parent `:on-select` receives row value, defaulting to row ID. |
| 70 | `:rating` | Integer `:value`, `:min` (1), `:max` (5), `:on-change`; up to 21 selectable ratings. |
| 71 | `:rich-text-editor` | Native editable text with Bold, Italic and Underline actions on selected text. `:value`/`:on-change` exchange HTML strings using Android's supported HTML subset. This is not a full browser document editor; HTML is normalized by Android. |
| 72 | `:map` | MapLibre native map. `:style` URL or JSON style, integer `:latitude`/`:longitude` in **millionths of a degree**, integer `:zoom`. `:marker` children have coordinates, `:text` and `:value`. `:on-select` receives marker value/ID; `:on-load` and `:on-error` receive strings. Default style is MapLibre's public demo; supply your own style/tile service for your app. No location access is requested. |
| 73 | `:media-player` | Media3 audio/video player with native playback controls. `:source` URI (including `"asset:///sample.wav"`), `:playing`, `:loop`, `:controls` (true). `:on-load` reports `"ready"`; `:on-error` reports failure. Playback pauses when the app pauses; removing the node releases the player. |
| 74 | `:camera` | CameraX preview and still capture. Starts from a “Start camera” button, which requests camera permission. `:active` can programmatically start/stop; `:lens :front` or default back; `:preview-height` (240). `:on-capture` receives an app-private cache file URI; `:on-error` reports denial/failure. Move captures into app storage if they must survive cache eviction. Removing the node unbinds its camera use cases. |
| 75 | `:web-view` | Android WebView with `:html` or HTTP(S) `:url`. `:javascript` defaults to false. `:on-load` receives the completed URL; `:on-error` receives a message. File/content access is disabled; no JavaScript-to-Lisp bridge is exposed. |

`:on-select`, `:on-result`, `:on-capture`, and `:on-load` take one string.
`:on-refresh` takes no arguments. `:on-move` takes two integers. As with existing
callbacks, callback properties need an explicit stable node ID.

Network images/maps/media/pages need `"android.permission.INTERNET"` in the APK
system's `:apk-permissions`; maps also need `"android.permission.ACCESS_NETWORK_STATE"`.
Camera use needs `"android.permission.CAMERA"` in that list and the runtime user's
grant. The shared runtime does not silently add these permissions to apps.

```lisp
:apk-permissions ("android.permission.INTERNET"
                  "android.permission.ACCESS_NETWORK_STATE"
                  "android.permission.CAMERA")
```

The gallery demonstrates all 76 controls using sample data. Camera capture and
system pickers launch only in response to their buttons; viewing a gallery
section does not open them.

## Drawing pad (76)

`:drawing-pad` provides immediate finger/stylus ink. Set `:view-width` and
`:view-height` (1–10000, defaults 1000×1400), `:paper-color`, `:pen-color` (hex RGB),
`:pen-width` (1–100 viewport units), and `:on-stroke`. The paper keeps its aspect
ratio and centers inside its available space. `:enabled nil` gives a preview.

A completed stroke callback receives `(color width ((x y) ...))`, with integer
viewport coordinates and at most 4096 points. Long gestures are progressively
thinned to retain the full gesture within that bound. Taps produce a dot; canceled gestures
produce no event. Native ink stays visible until the published snapshot acknowledges
the event. Return completed strokes as `:ink-stroke` children with unique IDs,
`:color` (hex RGB), `:width`, and SVG `:data`. Add a very short line segment to an
isolated point (for example `M100,200l0.01,0`) to retain its round dot.

The application owns undo, redo, and persistence. Change the drawing-pad ID when
switching documents so pending ink cannot leak into another page. See the complete
[Sketchbook example](../examples/evergreen-sketchbook/app.lisp), including a gallery
and durable state declaration. No pressure/tilt, palm rejection, or image export
is provided by this initial control.
