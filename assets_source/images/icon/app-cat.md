# 野猫代理图标

2026-10-31 根据用户提供的猫头刺绣照片，使用内置 imagegen 提取为扁平猫头标志，保留尖耳、两侧毛簇与半眯眼神，去除布料和刺绣纹理。
`app-cat.png` 是保留透明背景的原始设计稿；`assets/images/icon.png` 是其等比缩小并居中留出窄边距，使头像宽度约占图标的 90%的 512×512 版本。

鸿蒙桌面使用 AppScope 的 `foreground.png` 与浅蓝色 `background.svg` 分层显示；启动窗口使用 entry 的 `icon.png`，应用内使用共享 `assets/images/icon.png`。三个运行时 PNG 保持一致，资源名未变。

重新导出运行时 PNG：

```sh
magick assets_source/images/icon/app-cat.png -resize 468x468 -background none -gravity center -extent 512x512 -depth 8 -strip PNG32:assets/images/icon.png
cp assets/images/icon.png ohos/AppScope/resources/base/media/foreground.png
cp assets/images/icon.png ohos/entry/src/main/resources/base/media/icon.png
```

生成提示摘要：以用户照片为唯一形状参考，深炭灰均匀描边、米白脸部，透明背景，无文字、阴影或图标底板。原始生成图保留 alpha；后续仅按既有命令导出运行时尺寸。此次仅更新资源和显示名称，未构建客户端安装包。
