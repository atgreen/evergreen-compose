# Licenses

Evergreen Compose is Copyright (c) 2026 Anthony Green and is licensed under the
[GNU General Public License, version 3 or later](LICENSE), with the
[Classpath Exception](LICENSE.classpath-exception), matching Evergreen Common Lisp:

`GPL-3.0-or-later WITH Classpath-exception-2.0`

These terms cover Evergreen Compose's own source, examples, tooling and compiled
adapters. Third-party components retain the licenses described below.

## Sample adaptations

Evergreen News adapts the JetNews layout from Android Open Source Project
Compose Samples (Apache-2.0). Its replacement Common Lisp articles and
illustrations use this project's license. Upstream attribution is retained in
`examples/evergreen-news/NOTICE`. The imported snack data and photographs in
`examples/evergreen-snack/` come from the Apache-2.0 Jetsnack sample, copyright
The Android Open Source Project.

Evergreen Chat, Reply, Evergreen Lagged and Evergreen Caster adapt the Jetchat,
Reply, JetLagged and Jetcaster phone sample designs respectively. Their NOTICE
files identify the upstream Apache-2.0 work. Chat's imported photographs and
sticker, Reply's mail fixtures and photographs, and Lagged's synthetic readings
retain their upstream license. Caster's bundled transcripts, synthetic narration
and cover art are original Evergreen sample content under the project license.

## Precompiled Compose runtime

`runtime/compose-v1/` contains code compiled from the Evergreen Compose adapter sources in
`android/compose/`, AndroidX (including Compose, Material 3, Lifecycle and
SavedState), the Kotlin standard library, Kotlin coroutines, and their transitive
annotation/collection dependencies. The Evergreen Compose adapters use the
project license above. The listed AndroidX/Kotlin upstream libraries are licensed under
Apache-2.0; the license text is included in `LICENSE-APACHE`. AndroidX is copyright
The Android Open Source Project; Kotlin and kotlinx libraries are copyright
JetBrains and contributors. Dependency metadata/notices present in the APK's
META-INF are retained in the bundle. The Gradle wrapper is Apache-2.0, copyright
Gradle, Inc. and contributors.

Build inputs and pinned versions are in `android/compose/build.gradle.kts` and
`android/compose/gradle/wrapper/gradle-wrapper.properties`. Bundle checksums are
in `runtime/compose-v1/bundle.sexp`. EGCL's separately installed native runtime
retains its own license; see the EGCL distribution.
## MapLibre native library

BSD 2-Clause License

Copyright (c) 2021 MapLibre contributors

Copyright (c) 2018-2021 MapTiler.com

Copyright (c) 2014-2020 Mapbox

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in
  the documentation and/or other materials provided with the
  distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Additional shared dependencies

Coil 2.7.0 and its OkHttp/Okio dependencies, Markwon 4.6.2, AndroidX CameraX 1.4.2,
and AndroidX Media3 1.4.1 are distributed under Apache-2.0. Their published metadata
and notices are retained in the runtime bundle. MapLibre 11.8.0 is BSD-2-Clause,
with its upstream notice reproduced above; the map's own attribution control is
retained. Styles, tiles, photos, documents and media loaded by an application have
their own licenses. The bundled gallery landscape and tone are original fixtures.

CommonMark Java 0.13.0 uses BSD-2-Clause; its LICENSE.txt is preserved in the
bundle META-INF entries.
