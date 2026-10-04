# Contributing to Evergreen Compose

Evergreen Compose (`evergreen-compose`) is an experimental toolkit for native Android
apps written in Evergreen Common Lisp. Lisp owns application state and UI
descriptions; a shared Compose runtime handles Android rendering and input.
Changes can cross that boundary, so explain both the behavior and how it was
verified.

## Before starting

- Search the [issues](https://github.com/atgreen/evergreen-compose/issues) and existing
  Beads work to avoid duplicating an investigation.
- Follow [SECURITY.md](SECURITY.md) for suspected vulnerabilities and the
  [Code of Conduct](CODE_OF_CONDUCT.md) when participating.
- Open an issue before investing heavily in a substantial behavior or design
  change.
- Read the [Compose guide](docs/COMPOSE.md), [control catalog](docs/COMPOSE-CONTROLS.md),
  and [repository instructions](AGENTS.md) for the area you will change.

Like Evergreen, this project uses [Beads](https://github.com/gastownhall/beads)
for durable tracking. In a configured checkout, run `bd prime` and `bd ready`,
then claim or create a Bead before changing code. Record results, dependencies
and follow-ups as you work. Sync when a remote is configured. A first-time
contributor can start with a GitHub issue; a maintainer will associate it with
a Bead before the change lands.

## Build an application

Install matching EGCL and `egcl-target-android` packages as described in the
[README](README.md#build-and-run). The checkout or distribution must include
`runtime/compose-v1/`.

```sh
EGCL_HEAP_MB=2048 egcl --no-init \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "evergreen-compose.asd"))' \
  --eval '(asdf:make "evergreen-compose/apk")'
```

Application builds use EGCL without Java, Kotlin, Gradle, an Android SDK or an
NDK. ADB is used to install and run the resulting APK. Keep `.egcl-apk-key`
private and backed up: future updates to an installed app need the same key.

## Change the shared runtime

Only runtime maintainers need the Android toolchain. Follow the pinned setup
and rebuild instructions in [Runtime maintainers](docs/COMPOSE.md#runtime-maintainers).
After a Kotlin adapter or protocol change, rebuild and verify the distributed
`runtime/compose-v1/` bundle; changing sources alone does not update app builds.

- Keep application-specific behavior in Lisp examples and reusable controls in
  the shared runtime.
- Give callback-bearing controls stable IDs and preserve event acknowledgment
  behavior when changing the protocol.
- Keep JNI references valid across thread boundaries. Local references cannot
  be passed between threads; use global references with explicit ownership.
- Preserve the flat APK asset namespace and the `load-order.sexp` loader list.
- Retain upstream license notices and add the project's SPDX copyright and
  license headers to new source files.

## Validate a change

Start with a reproducing test for behavioral fixes, then run the affected
suite. The usual local gates are:

```sh
EGCL_HEAP_MB=2048 sh tools/check.sh
EGCL_HEAP_MB=2048 XDG_CACHE_HOME=/tmp/evergreen-compose-check-cache \
  egcl --no-init --load tests/asdf.lisp
shellcheck tools/*.sh tests/*.sh
```

Packaging changes also need `sh tests/compose-no-toolchain.sh`, preferably
from a fresh release extraction as described in [RELEASING.md](docs/RELEASING.md).
That check builds signed apps with fresh caches and only EGCL on the build
process's PATH.

Native changes need the appropriate Android instrumentation tests and a
release-bundle Lisp APK check on a device or emulator. Report Android version,
ABI and device details. Host tests alone do not prove JNI, keyboard, lifecycle,
permissions, scrolling or rendering behavior. A debug instrumentation app
does not prove the shrunk release runtime works in EGCL's NativeActivity.

Keep failures nonzero. Do not silence failures, weaken assertions or omit a
required check to make a result appear successful. Record existing failures
and distinguish them from regressions. Performance claims need a controlled
comparison, a described workload and repeated measurements on the relevant
device.

## Submit a pull request

Keep changes focused. Link the GitHub issue and Bead, describe the behavior
before and after, and give exact validation commands and results. Identify
host, instrumentation and release-APK coverage separately, including checks
that could not run. Update public documentation and the changelog when the
interface or release baseline changes. Disclose the provenance of contributed
code and assets, including AI-assisted work.

Contributions use `GPL-3.0-or-later WITH Classpath-exception-2.0`, the same
license as Evergreen Common Lisp. Third-party code and assets retain their
existing terms; see [LICENSES.md](LICENSES.md).
