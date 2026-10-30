# OHOS UI compatibility

`material_ui` 1.5.0 and `cupertino_ui` 1.1.1 are the official published
Flutter UI libraries used by FlClash v0.9.2. Their exhaustive switches do
not yet include the `TargetPlatform.ohos` enum added by Flutter OHOS.

The versioned patches only add OHOS to each Android switch branch or
switch-expression pattern. The original widget implementations, visual
design, assets, APIs, and copyright headers are preserved. No application
platform detection is changed.

The patched packages are isolated in `third_party/material_ui` and
`third_party/cupertino_ui`, referenced by root dependency overrides. No shared
pub-cache files are changed. Each package's `OHOS_ADAPTATION.md` records the
official archive SHA-256 and retained license. The diffs here are audit copies;
they can be applied with `git apply` inside a clean official package checkout.
These patches require the OHOS Flutter SDK; the standard Flutter SDK does not
define `TargetPlatform.ohos`.

Sources:

- https://pub.dev/packages/material_ui/versions/1.5.0
- https://pub.dev/packages/cupertino_ui/versions/1.1.1
- https://github.com/flutter/packages/tree/main/packages/material_ui
- https://github.com/flutter/packages/tree/main/packages/cupertino_ui

The CPF-Flutter `flutter_packages` OHOS branch `oh-3.47.7-dev` at
`06ef5c4c07888d17317f930fa49e16ab368009f6` was checked first. Its UI packages
also lacked OHOS enum branches, so it could not supply this compatibility.
