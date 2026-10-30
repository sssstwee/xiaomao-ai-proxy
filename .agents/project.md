# Project Context

FlClash is a multi-platform proxy client based on ClashMeta (mihomo), built with Flutter. It supports Android, Windows, macOS, and Linux, using a Material You design with Surfboard-like UI.

## Version Notes

- HarmonyOS checks use the pinned Flutter-OHOS 3.44.10 toolchain in `.github/harmony-pinned-shas.env`.
- Local SDK discovery uses `HOS_SDK_HOME` pointing to the SDK root that contains `default/sdk-pkg.json`.
- `.fvmrc` is local and ignored; trust the CI-pinned toolchain for parity.
- Dart SDK constraint: `>=3.8.0 <4.0.0`.

## Build Dependencies

Linux:

```bash
sudo apt-get install libayatana-appindicator3-dev libkeybinder-3.0-dev
```

Windows:

- GCC and Inno Setup.
- `ANDROID_NDK` env var for Android builds.

macOS:

```bash
npm install -g appdmg
```
