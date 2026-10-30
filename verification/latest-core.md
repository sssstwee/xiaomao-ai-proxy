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

The upstream `core/go.mod` remains **Go 1.27.0**. The build uses the actual
`openharmony/arm64` target from `sysit/ohos-go` v1.27.2-ohos-beta1, pinned at
`2a25fe67d7aa22202944297f7c8c6a64f49be194`. This community prerelease includes
the port's network-interface memory/file-descriptor leak fixes; Mihomo itself
remains the stable v1.19.33 release. No compatibility module or dependency
downgrade is used. `GOTOOLCHAIN=local` prevents automatic replacement with an
unadapted official toolchain.

The port intentionally exposes `runtime.GOOS == "linux"` while its build target
is `openharmony`. The wrapper's `onOhos` build constant controls socket protection,
the native UID API threshold and system-clock restrictions, so those paths do
not depend on the runtime identity. The SDK's absolute compiler wrapper supplies
the OHOS target, sysroot and `-D__MUSL__`.

Earlier Go 1.26.4 portability tests used a generated compatibility module and
passed, but the SIG's pinned Go 1.26 source did not actually register an OHOS
target. The first package attempt stopped at `go env` before compiling a client
library. That obsolete compatibility helper and its build paths are removed.

## Completed checks

- `CGO_ENABLED=0` portable Core tests on Go 1.27.2 with the unchanged module.
- Full `with_gvisor openharmony` Core tests, including refused socket protection,
  native API-26 UID lookup and UID-rule matching; `core/tun` and `core/platform`
  compile under the same tags.
- OHOS-tagged `go vet`, plus Android/arm64 cross-vet of `core`, `mobile`, `tun`
  and `platform`, preserving the upstream Android path.
- The SHA256-verified v1.27.2-ohos-beta1 Darwin arm64 toolchain archive passed
  `go env` and `go tool dist list` checks for the real `openharmony/arm64`
  target, then `go list -deps` and CGO-enabled cross-vet of `core`, `tun`,
  `platform` and `ohos` with the SDK compiler and an isolated Go build cache.
  Its package selection includes the mobile wrapper, `platform_ohos.go` and
  both `ohos/main.go` and `bridge.c`; desktop IPC is excluded.
- 93 targeted Flutter tests across Core library lifecycle, controller,
  protocol contracts and the service transport.
- 48 setup-hook tests cover source lock/check/apply/reverse, the arm64 OHOS
  target and hook selection using the root dependency resolution.
- Targeted Dart analysis of the adapted Core, service and setup hook: no issues.

The Go checks are reproducible without building a client:

```sh
dart core/prepare_mihomo.dart
cd core
GOTOOLCHAIN=go1.27.2 CGO_ENABLED=0 go test -mod=readonly -tags='with_gvisor openharmony' . ./tun ./platform
GOTOOLCHAIN=go1.27.2 CGO_ENABLED=0 go vet -mod=readonly -tags='with_gvisor openharmony' . ./tun ./platform
GOTOOLCHAIN=go1.27.2 GOOS=android GOARCH=arm64 CGO_ENABLED=0 go vet -mod=readonly -tags=with_gvisor . ./mobile ./tun ./platform
cd ..
dart core/prepare_mihomo.dart --reverse
```

Keep the `setup` and `rust_api` `build_assets: false` user-defines in place for
Flutter validation and the OHOS package pipeline. These serialized hook inputs
disable automatic host builds before a Dart command starts. OHOS builds use
explicit platform builders; the Go builder does not read these hook switches.

## Package build entry and remaining validation

The authorized OHOS build will call:

```sh
dart run plugins/setup/setup_hooks/bin/build_ohos.dart /path/to/repository
```

`GOROOT`/`PATH` must select the pinned OHOS Go 1.27 port; `OHOS_SDK_HOME` points to
the SDK's `default/openharmony` directory. The entry prepares the locked sources
without rewriting `go.mod`, builds only the arm64 shared-library target, and
copies `libclash.so`, generated `libclash.h`, and `bridge.h` to the OHOS host's
ABI directories. The explicit entry and Flutter hook share the build cache.
The OHOS target has no desktop Helper, so the explicit Go entry returns before
Rust Helper construction or toolchain detection. The separate explicit OHOS
Rust bridge build remains the package pipeline's responsibility. Environment
flags are not used to disable automatic hooks because hook sandboxing can
filter them; both `build_assets` user-defines must already be false.

No client shared library, HAP or APP was built during these checks. Linking,
HarmonyOS loader/CGO ABI, VPN consent/revoke, rapid start/stop, network changes,
lock-screen/background lifetime, profile upgrades and real application traffic
still require an authorized signed package on the Pura X View (API 26).
