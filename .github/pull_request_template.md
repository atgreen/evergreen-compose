## What changed

<!-- Describe the concrete problem and the behavior before and after this change. -->

Tracking: <!-- GitHub issue and Bead, for example: Closes #123; bliss-abcde -->

## Validation

<!-- List exact commands and results, including failures and checks not run. -->

```text
command
result
```

Affected paths and tested environments:

- [ ] Lisp UI protocol, callbacks or state
- [ ] Shared Compose controls or rendering
- [ ] JNI, lifecycle, keyboard or permissions
- [ ] APK packaging or signing
- [ ] Network, feeds, private storage or platform services
- [ ] Examples or documentation

Host, Android version, device/emulator and ABI:

<!-- Distinguish host tests, debug instrumentation and release-bundle Lisp APK checks. -->

## Runtime and packaging

- [ ] JNI references and ownership remain valid across threads, or JNI is unchanged.
- [ ] Event acknowledgments and stable control IDs are preserved, or the protocol is unchanged.
- [ ] The precompiled runtime was rebuilt and verified, or its sources and dependencies are unchanged.
- [ ] APK asset names, loader consistency and 16 KB native alignment were checked where affected.
- [ ] Existing application signing keys and private user data are preserved.

<!-- Explain alternatives or checks that do not apply; leave inapplicable boxes unchecked. -->

## Documentation and release impact

- [ ] User-facing documentation is updated, or behavior is unchanged.
- [ ] `CHANGELOG.md` is updated, or the release baseline is unchanged.
- [ ] New source files have SPDX headers and third-party notices are preserved.
- [ ] Performance claims include the device, workload, warmup, sample count and comparison.
- [ ] Contributed code and asset provenance is disclosed, including AI-assisted work.
