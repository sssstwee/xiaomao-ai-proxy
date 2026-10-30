# Mihomo integration

The core is pinned to **Mihomo v1.19.33** through the exact FlClash v0.9.2
integration commit recorded in `mihomo.lock.json`. That public commit contains
the upstream stable release and the FlClash callbacks used by this client.
`patches/openharmony.patch` preserves the existing HarmonyOS feature and system
DNS integration. The gVisor OHOS replacement in `go.mod` is pinned to its
2026-10-24 revision, based on the same gVisor revision required by Mihomo.

The build tool verifies the source commit, stable-release ancestry and patch
SHA256, applies the patch automatically and embeds the locked Mihomo version in
the core. It rejects unrelated submodule edits. Use a complete submodule clone;
CI uses `fetch-depth: 0` so the stable ancestor is available for verification.

Prepare sources and run the Go tests without packaging a client:

```bash
dart run core/prepare_mihomo.dart --check
dart run core/prepare_mihomo.dart
cd core
GOTOOLCHAIN=go1.26.4 CGO_ENABLED=0 go test -mod=readonly -tags=with_gvisor ./...
cd ..
dart run core/prepare_mihomo.dart --reverse
```

`--check` accepts either pristine or exactly prepared sources without changing
them. Preparation and reversal are repeatable. Reversal removes only this patch
and refuses to discard subsequent edits. The source submodule therefore remains
at a remotely fetchable commit and can return to a clean checkout after checks.

Go tests do not verify the HarmonyOS dynamic-library ABI or phone VPN lifecycle.
Those require a separately authorized package build and signed-device testing.
