# 图标源文件

[English](README.md) | 简体中文

图形由笔尖与连续的压力响应笔迹组成。

- `AppIcon.svg` 和 `AppIcon.pdf`：1024 × 1024 矢量母版。
- `MenuBarIcon.svg`：用于 18 点菜单栏图像的单色母版。
- `AppIcon-preview.png`：应用图标预览。
- `MenuBarIcon-appearance-preview.png`：浅色与深色外观预览。

运行时资源位于 `PenActor/Assets.xcassets`。
应用图标使用传统 macOS 的十个 PNG 尺寸，覆盖 16–1024 像素。
菜单栏图标使用保留矢量数据的模板 PDF，由 macOS 决定其显示颜色。

在仓库根目录运行以下命令，可重新生成母版、预览和资源目录输出：

```sh
swift scripts/generate-icons.swift
```

脚本在 SVG、PDF 和 PNG 输出之间共用同一套几何路径，不需要字体、第三方工具或网络访问。
PNG 是运行时位图资源，SVG/PDF 母版则是可编辑的矢量设计源文件。
