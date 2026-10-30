# OHOS compatibility provenance

- Official pub.dev package: `material_ui` version `1.5.0`.
- Source archive: https://pub.dev/api/archives/material_ui-1.5.0.tar.gz
- Archive SHA-256: `32d98f11cf5942a095a8c3e01b03e4de3b17941437713dcf36b1088fb62e23d2`.
- License: BSD-3-Clause, retained in `LICENSE` and source headers.
- Kept package runtime sources, shaders (when present), and original metadata.
- Local patch: `../../tool/patches/material_ui-1.5.0-ohos.patch`.

The patch adds `TargetPlatform.ohos` to the existing Android switch branches
and switch-expression patterns. Widget implementations, design, assets, and
APIs remain the official version. No shared pub-cache files are patched.

The CPF-Flutter `flutter_packages` branch `oh-3.47.7-dev` at
`06ef5c4c07888d17317f930fa49e16ab368009f6` was checked first, but its UI
packages also omitted OHOS enum cases, so it could not supply this patch.
