# Preparing Evergreen Compose 0.0.1

The source archive includes the precompiled `runtime/compose-v1/` bundle.
Application developers build and sign APKs with EGCL; they do not rebuild the
Kotlin runtime. See [Build and run](../README.md#build-and-run) for the verified
Fedora package pair and the distinction between package dependencies and tools
actually invoked by the app build.

## Build and verify

The shared CI/release gate can be run locally with matching EGCL and
`egcl-target-android`, Python 3, shellcheck and ordinary shell tools:

```sh
sh tools/check-release.sh
```

It runs the host suite and shell checks, prepares `dist/release/`, proves the
archive is reproducible, then extracts it into a temporary directory and runs
ASDF checks, three EGCL-only APK builds and 16 KB alignment checks there. The
four downloadable assets are the source archive (including the precompiled
runtime), its `.sha256` file, `RELEASE-NOTES.md`, and `SHA256SUMS`. Only that
validated directory is uploaded by Actions. Use a dedicated output directory
as the script's first argument if needed; unexpected files cause a failure.

When Android adapter sources change, first rebuild the bundle as described in
[Runtime maintainers](COMPOSE.md#runtime-maintainers). Run the host and ASDF
checks, shellcheck, and the device tests from that guide. Verify a release Lisp
APK on a device as well as the debug instrumentation app.

The public ASDF systems and examples use version `0.0.1`. The precompiled
runtime keeps its independent version `1.4.0` and protocol `1`; these are not
the library release number. Android version codes retain their existing values
so development installations can still be updated using their original keys.
The proposed release tag is `v0.0.1`, with [CHANGELOG.md](../CHANGELOG.md) as the
release notes. The tag and publication are separate from local preparation.

Run the local gates (Python and shellcheck are maintainer tooling):

```sh
EGCL_HEAP_MB=2048 sh tools/check.sh
EGCL_HEAP_MB=2048 XDG_CACHE_HOME=/tmp/evergreen-compose-release-cache \
  egcl --no-init --load tests/asdf.lisp
shellcheck tools/*.sh tests/*.sh
```

Create the release candidate:

```sh
python3 tools/source-dist.py dist/evergreen-compose-0.0.1.tar.gz
(cd dist && sha256sum -c evergreen-compose-0.0.1.tar.gz.sha256)
```

The archive root is `evergreen-compose-0.0.1/`. File order, ownership, modes and timestamps
are normalized, and gzip embeds neither a filename nor a timestamp: unchanged
inputs produce identical archive bytes. Executable permission is preserved.
The companion `.sha256` file records its checksum. This packages the **current
working tree**, including uncommitted source changes. It does not commit, tag,
upload or publish anything. Review the changes before publishing the artifact.

The archive includes source, examples, documentation, licenses, tests, build
tools, the Gradle wrapper and the precompiled runtime. It excludes build/cache
directories, local signing keys, SDK paths, optional Slynk assets, `egcl.env`,
Git/Beads databases and local agent configuration. `.agents` skills and the
mirrored contributor instructions are included. Symlinks in release inputs are
rejected. Preserve local `.egcl-apk-key` files separately: existing apps need
their original key for updates.

The distribution also includes `SECURITY.md`, `CONTRIBUTING.md`,
`CODE_OF_CONDUCT.md`, `CITATION.cff` and the GitHub contribution templates.

The unfinished `examples/evergreen-survey/` draft and `tests/more-samples.lisp`
are excluded from 0.0.1. They remain in the checkout for future work.

Extract into an empty directory and run these checks there:

```sh
release_check=$(mktemp -d)
tar -xzf dist/evergreen-compose-0.0.1.tar.gz -C "$release_check"
cd "$release_check/evergreen-compose-0.0.1"
sh tests/compose-no-toolchain.sh
EGCL_HEAP_MB=2048 XDG_CACHE_HOME="$release_check/cache" \
  egcl --no-init --load tests/asdf.lisp
python3 tools/native_alignment.py build/evergreen-compose.apk \
  examples/hello/build/hello.apk examples/catalog/build/catalog.apk
```

The first check starts with fresh configuration/cache directories and an empty
environment, exposing only `egcl` on PATH to each APK build. A fresh extraction
also exercises creation of new signing identities. The extracted directory
must include the distributed runtime, and the system must have the matching
EGCL Android target package installed. No network fetch is needed by these app
builds. The shell test harness and Python alignment checker are verification
tools, separate from the Lisp APK builder.

Before publication, review the final archive and its checksum, resolve any
outstanding release gates, and run hosted CI. Android instrumentation and
release-APK phone checks must be reported separately from host checks. Earlier
scoped drawing/service tests do not constitute a complete instrumentation run;
the existing canvas/palette screenshot tests require follow-up. Publication is
not performed by `source-dist.py`.

## Names and contents

The public Lisp system/package is `evergreen-compose`; the Android namespace is
`dev.egcl.compose`. Examples use `.demo`, `.hello` and `.catalog` beneath that
namespace. References to the former Bliss name belong only in the migration
note or historical issue records. Beads issue identifiers retain their original
prefix so existing references remain valid; they are not product branding.

The public repository is `https://github.com/atgreen/evergreen-compose`.
Native storage and activity-result identifiers keep their original spelling
for compatibility with installed development apps. These are internal keys,
not public Lisp names or distribution filenames.

The runtime's DEX, resource table, resources and native libraries are intentional
distribution files. Its manifest records their checksums. Runtime dependency
notices are described in [LICENSES.md](../LICENSES.md) and shipped with apps.
Build intermediates, generated APKs, Python bytecode and private keys are not
source-release inputs.

## GitHub Actions

`ci.yml` runs on pushes, pull requests and manual dispatch. It calls
`validate.yml`, which installs checksum-pinned EGCL and Android target RPMs
from Evergreen's stable `v0.0.1` release on Fedora 44 and runs the shared gate.
Successful runs retain the complete release asset set for 14 days.

`release.yml` uses the same validation workflow after checking release metadata:

| Trigger | Result |
| --- | --- |
| Push `v0.0.1` (or a later matching version tag) | Publish a normal GitHub release after validation. |
| Manual `build` (default) | Validate and upload workflow artifacts only. |
| Manual `test` | Publish `test-vVERSION-RUN-ATTEMPT` as a prerelease, without moving latest. |

The version tag must match `evergreen-compose.asd`; citation metadata and a
matching changelog entry are required. Mismatched tags, missing files, extra
files and checksum failures stop the release. Each job has a timeout. Release
runs queue per ref so an interrupted publication is not replaced by a competing
run. A rerun does not overwrite an existing release: inspect any draft left by
a failed upload before removing or completing it. Test prereleases are retained
until a maintainer removes them.

Only the publish job gets repository-write and attestation permissions. It
uses the `release` environment, verifies downloaded artifacts, attests the
archive's provenance, creates a draft with all assets, then publishes it.
No APK signing secrets are needed: test APKs use disposable identities and
are not release assets. The archive's precompiled runtime is verified, not
rebuilt with Gradle by this workflow.

Before enabling publication in GitHub, configure the `release` environment's
branch/tag restrictions and any desired reviewers. Allow GitHub Actions and
the pinned actions in repository settings. A successful local/container run
does not verify GitHub artifact transport, environment protection, attestations
or release publishing; exercise manual `build`, then `test`, on the hosted
repository before pushing the first version tag. Android instrumentation and
phone validation remain separate gates.
