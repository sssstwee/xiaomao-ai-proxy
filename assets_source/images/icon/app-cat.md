# 小猫代理图标

2026-10-30 根据用户要求使用 imagegen 重新设计的扁平卡通小猫头像。
`app-cat.png` 是保留透明背景的原始设计稿；`assets/images/icon.png` 是其等比缩小并居中留出窄边距，使头像占据图标的绝大部分的 512×512 版本。

鸿蒙桌面使用 AppScope 的 `foreground.png` 与浅蓝色 `background.svg` 分层显示；启动窗口使用 entry 的 `icon.png`，应用内使用共享 `assets/images/icon.png`。三个运行时 PNG 保持一致，资源名未变。

重新导出运行时 PNG：

```sh
magick assets_source/images/icon/app-cat.png -resize 480x480 -background none -gravity center -extent 512x512 -depth 8 -strip PNG32:assets/images/icon.png
cp assets/images/icon.png ohos/AppScope/resources/base/media/foreground.png
cp assets/images/icon.png ohos/entry/src/main/resources/base/media/icon.png
```
