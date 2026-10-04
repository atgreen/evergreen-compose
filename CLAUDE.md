# Agent Instructions

## Beads

Use `bd` for all durable task tracking. Read `.agents/skills/beads/SKILL.md` and
run `bd prime` for current workflow context. Start with `bd ready`, inspect the
issue with `bd show <id>`, then claim it with `bd update <id> --claim`. Record
new bugs and follow-ups when discovered; model blockers with `bd dep add`.
Close issues only after their work is verified. Use `bd remember` for persistent
project knowledge, not memory files or markdown task lists.

Issues live in `.beads/dolt/`. `.beads/issues.jsonl` is a passive export, not the
sync protocol. Remote synchronization uses `bd dolt push/pull` and
`refs/dolt/data`, separately from code branches. Honor the user's active sync
instructions; report when no remote is configured.

## Build and validation

- `sh tools/check.sh`: host suite, runner failure paths, Slynk asset helper,
  and Compose examples. Compose protocol and demo tests run in the host suite. Set `EGCL` to choose the executable.
- `egcl --no-init --load tests/asdf.lisp`: ASDF tests plus APK component/load
  consistency. Requires `egcl-target-android` with `egcl-apk-asdf`.
- `egcl --eval '(require :asdf)' --eval '(asdf:load-asd (truename "evergreen-compose.asd"))'
  --eval '(asdf:make "evergreen-compose/apk")'`: build the demo APK.
- `shellcheck tools/*.sh tests/*.sh`: shell checks.

A host test does not verify JNI or device behavior. Report the validation scope,
including any device or hosted-CI checks that could not run. Keep failures
nonzero; do not replace a failing gate with a printed warning.

## Architecture and conventions

Evergreen Compose is the sole Android app model: `ui` produces immutable Lisp trees,
`run-compose-app` publishes snapshots, and the shared precompiled Compose runtime
owns Android layout, scrolling, animation and input. Application callbacks run
on the Lisp worker. App APK builds use `evergreen-compose-build:compose-apk` and require no
Java/Kotlin/Gradle/SDK. Only runtime maintainers run `tools/build-compose-runtime.sh`.
Protocol/renderer changes require rebuilding and verifying `runtime/compose-v1`.

Keep platform-neutral protocol and state logic testable without Android.
`load-order.sexp` is the source of truth for loaders and APK components.
The retained Canvas/GLES renderer is retired.

APK assets have flat basenames. JNI references crossing threads must be global
references. Do not replace the integer coordinate model with
accumulating exact rationals; see the project memories in `bd prime`.

Use a reproducing test for behavioral fixes, run appropriate checks, record
results in the bead, and close completed work. Preserve unrelated user edits.
Do not commit or push code unless the current user request authorizes it.

## Shell operations

Use noninteractive commands: `cp -f`, `mv -f`, `rm -f`, and `cp -rf` / `rm -rf`
when recursion is needed. Scope destructive operations carefully. Use
`scp -o BatchMode=yes`, `ssh -o BatchMode=yes`, `apt-get -y`, `dnf -y`, and
`HOMEBREW_NO_AUTO_UPDATE=1` for Homebrew when relevant. Never invoke `bd edit`;
it opens an interactive editor.

AGENTS.md and CLAUDE.md carry the same project instructions. Mirror substantive
changes across both.
