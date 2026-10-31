# HarmonyOS wake recovery

## Attribution

The reported symptom is that requests stop working after long standby until the
user reconnects the VPN. Two source-level gaps were confirmed:

- The HarmonyOS adapter did not instantiate `PowerManager`. Its VPN service
  observed network availability/loss but did not recover when the same Wi-Fi
  network survived a sleep/wake cycle.
- FlClash's Go `handleResetNetwork` closed tracked business connections and DNS
  clients, but left Hysteria2's shared QUIC transport alive. Closing a QUIC stream
  does not close that shared transport.

These gaps belong to the HarmonyOS adapter and FlClash's Go wrapper. They do not
establish a defect in upstream mihomo or the HarmonyOS kernel. The currently
pinned sing-quic already contains the earlier UDP-session cleanup fix.

OpenHarmony publishes `sleeping` and `napped` in the device idle event:
[publisher implementation](https://github.com/openharmony/resourceschedule_device_standby/blob/024c5b8c7260adf7c06f62498cf7a086882865f1/services/notification/src/standby_state_subscriber.cpp).
The pinned Hysteria2 client's `CloseWithError` clears its connection and allows a
later dial to establish a new transport:
[client implementation](https://github.com/MetaCubeX/sing-quic/blob/1c242664697a/hysteria2/client.go).

## Behavior

The VPN service owns the idle/screen-on observer for exactly its running lifetime.
An active/screen-on event schedules one routed probe after 500 ms; overlapping
events share it. The existing probe uses the configured test URL when no URL is
supplied, matching delay-test behavior. Any HTTP response demonstrates connectivity;
an HTTP authentication response does not count as a broken transport.

Only a failed network probe triggers the existing network reset. It closes stale
business connections, resets the reusable Hysteria2 transports, and clears DNS
state. Other protocol clients are not closed: their `Close` may be terminal.
The VPN and TUN remain established. Node selection, routing, DNS policy, and
background traffic during standby retain their existing owners.

Stopping/destroying the service cancels scheduled work. Intent revisions prevent
a late failed probe from resetting a stopped or subsequently restarted service.
RPC errors, a saturated probe queue, and a missing core reply do not count as
network failures. The reply watchdog releases the in-flight guard so a later
wake can try again.

## Verification and limits

- Native lifecycle tests execute production ArkTS with SDK fakes. Coverage includes
  unchanged-network wake, a missed idle event, duplicate events, healthy HTTP 401,
  sleeping/napping, stop/destroy/restart races, retired observers, RPC errors,
  missing replies, and observer startup failure.
- Baseline regression checks fail against the previous ArkTS and Go implementations.
  Go tests verify that a cached stale transport prevents dialing before reset and
  that a subsequent local TCP dial succeeds after reset without closing terminal
  protocol clients. These transport lifecycle tests use a fake stale-state adapter;
  they do not reproduce a physical QUIC sleep/wake session.
- The real HarmonyOS SDK compiler and ArkTS 1.1 linter check both changed ETS
  units and their dependencies without emitting code. The check reports zero
  errors; SDK `@throws` warnings remain visible in the recorded diagnostics.
- Root Flutter analysis/tests and Go tests/vet validate shared-layer compatibility.
  Native client build hooks are disabled during local Flutter validation and
  restored before committing.

Local results on 2026-10-31: 33 native lifecycle tests and 4184 Flutter tests passed.
The repository's no-native-Rust runner excluded 18 files that require compiled
Rust client libraries. `flutter analyze --no-fatal-infos` passed with one existing
`use_null_aware_elements` info in `current_outbound.dart`. Go tests and vet passed
for `with_gvisor` and the `with_gvisor openharmony` core/TUN/platform paths;
`go mod verify` passed. SDK checking reported 0 errors and 19 `@throws` warnings.

No client package was built or installed for this change. The updated binary has
not undergone physical-device long-standby acceptance. A later authorized package
must verify unchanged-Wi-Fi wake, Wi-Fi/cellular transitions, background pushes,
and recovery after a prolonged lock while keeping healthy connections intact.
