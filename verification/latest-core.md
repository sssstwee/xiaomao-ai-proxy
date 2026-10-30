# FlClash v0.9.2 HarmonyOS Core adaptation

Verified on 2026-10-30, Asia/Shanghai. The application source baseline is the
official FlClash v0.9.2 commit `7fd417fb`; its Core protocol and mobile lifecycle
remain the basis of this port.

## Source and boundaries

- Mihomo stays at stable `v1.19.33`, through FlClash's public integration commit
  `c5062921054902b25215a6a933e72ccd714c9bfa`. `core/mihomo.lock.json` verifies
  that commit, the official stable ancestor and the OHOS patch SHA256.
- The patch carries the existing mobile feature/system-DNS integration and
  enables UID rules for the new native UID callbacks. Protocols and rule policy
  remain in Mihomo and the imported profile.
- `core/ohos/` is a thin C ABI over the current `core.InvokeMethod`, `StartTun`
  and event interfaces. It does not restore the old `Action` protocol or the old
  Go implementation. The callbacks separately acknowledge socket protection,
  resolve UID, and resolve package name.
- OHOS uses `CoreLib` and the current `Service` byte transport, including
  `CoreMethodResponse.error` and spilled-response files. Its configuration must
  succeed before a VPN start intent is submitted. Android retains its upstream
  listener semantics.
- OHOS does not compile the desktop IPC/process owner, change file ownership,
  or write the system clock. API 26 uses the native UID query; a refused socket
  protection acknowledgement fails the dial. Provider/cache/profile paths and
  response spill-directory checks remain those of v0.9.2.

## Go toolchain compatibility

The upstream `core/go.mod` remains **Go 1.27.0**. The available OHOS Go fork is
on Go 1.26, so `prepare_ohos_modfile.dart` generates ignored `.ohos.mod` and
`.ohos.sum` files. Only the main module's Go directive changes to `1.26.0`;
dependency versions and replacements are copied unchanged. A different upstream
Go requirement requires explicit compatibility review.

Go 1.26.4 compiled and passed the full portable Core tests and the OHOS-tagged
Core tests. This establishes the current source/API compatibility, not the
OHOS runtime or dynamic-library ABI. The OHOS build uses `GOTOOLCHAIN=local`
with the separately pinned OHOS Go 1.26 toolchain, preventing an automatic
switch to an unadapted official Go toolchain.

## Completed checks

- `CGO_ENABLED=0` portable Core tests on Go 1.26.4 with the compatibility module.
- Full `with_gvisor openharmony` Core tests, including refused socket protection,
  native API-26 UID lookup and UID-rule matching; `core/tun` and `core/platform`
  compile under the same tags.
- OHOS-tagged `go vet`, plus Android/arm64 cross-vet of `core`, `mobile`, `tun`
  and `platform`, preserving the upstream Android path.
- 93 targeted Flutter tests across Core library lifecycle, controller,
  protocol contracts and the service transport.
- 27 distinct setup-hook tests covering source lock/check/apply/reverse,
  compatibility-module generation, the arm64 OHOS target and hook selection.
- Targeted Dart analysis of the adapted Core, service and setup hook: no issues.

The Go checks are reproducible without building a client:

```sh
dart core/prepare_mihomo.dart
dart core/prepare_ohos_modfile.dart
cd core
GOTOOLCHAIN=go1.26.4 CGO_ENABLED=0 go test -mod=readonly -modfile=.ohos.mod -tags='with_gvisor openharmony' . ./tun ./platform
GOTOOLCHAIN=go1.26.4 CGO_ENABLED=0 go vet -mod=readonly -modfile=.ohos.mod -tags='with_gvisor openharmony' . ./tun ./platform
GOTOOLCHAIN=go1.26.4 GOOS=android GOARCH=arm64 CGO_ENABLED=0 go vet -mod=readonly -modfile=.ohos.mod -tags=with_gvisor . ./mobile ./tun ./platform
cd ..
dart core/prepare_mihomo.dart --reverse
```

For Flutter validation, keep the temporary `setup` and `rust_api`
`build_assets: false` switches in place as the repository's verification runner
does. Restore them before any separately authorized package build.

## Package build entry and remaining validation

The authorized OHOS build will call:

```sh
FLCLASH_OHOS_BUILD=1 dart run plugins/setup/setup_hooks/bin/build_ohos.dart /path/to/repository
```

`GOROOT`/`PATH` must select the pinned OHOS Go 1.26; `OHOS_SDK_HOME` points to
the SDK's `default/openharmony` directory. The entry prepares the locked sources
and compatibility module, builds only the arm64 shared-library target, and
copies `libclash.so`, generated `libclash.h`, and `bridge.h` to the OHOS host's
ABI directories. The explicit entry and Flutter hook share the build cache.
The environment flag must exist before starting Dart; it suppresses automatic
host Core/Helper and Rust hooks before the explicit OHOS entry runs.

No client shared library, HAP or APP was built during these checks. Linking,
HarmonyOS loader/CGO ABI, VPN consent/revoke, rapid start/stop, network changes,
lock-screen/background lifetime, profile upgrades and real application traffic
still require an authorized signed package on the Pura X View (API 26).
