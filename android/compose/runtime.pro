# SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
# SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

# JNI resolves this stable entry point by name from the application classloader.
-keep public class dev.egcl.compose.ComposeHost { public *; }

# Android recreates the shared headless fragment by its class name.
-keep public class dev.egcl.compose.ResultFragment { public <init>(); }
