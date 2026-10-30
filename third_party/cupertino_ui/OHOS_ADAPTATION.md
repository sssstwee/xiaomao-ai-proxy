# OHOS compatibility provenance

- Official pub.dev package: `cupertino_ui` version `1.1.1`.
- Source archive: https://pub.dev/api/archives/cupertino_ui-1.1.1.tar.gz
- Archive SHA-256: `c23816577a1280cff409e989541767887011f8f1d8c1863a794ed308af46f2a9`.
- License: BSD-3-Clause, retained in `LICENSE` and source headers.
- Kept package runtime sources, shaders (when present), and original metadata.
- Local patch: `../../tool/patches/cupertino_ui-1.1.1-ohos.patch`.

The patch adds `TargetPlatform.ohos` to the existing Android switch branches
and switch-expression patterns. Widget implementations, design, assets, and
APIs remain the official version. No shared pub-cache files are patched.

The CPF-Flutter `flutter_packages` branch `oh-3.47.7-dev` at
`06ef5c4c07888d17317f930fa49e16ab368009f6` was checked first, but its UI
packages also omitted OHOS enum cases, so it could not supply this patch.
