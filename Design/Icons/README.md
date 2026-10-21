# PenActor 图标

原创标记：向右上方的笔尖代表绘画输入，从笔尖连续延伸、逐渐增粗的曲线代表笔压响应。0.4.2 缩小笔尖主体并调整留白，避免笔迹看起来是分离的装饰线。

- `AppIcon.svg`、`AppIcon.pdf`：1024 × 1024 彩色矢量母版，蓝紫渐变底、浅色笔尖和青色压力曲线。
- `MenuBarIcon.svg`：18 点显示尺寸、24 单位坐标系的单色矢量母版。小尺寸简化内部细节，保持与应用图标相同的轮廓。
- `AppIcon-preview.png`：应用图标预览。
- `MenuBarIcon-appearance-preview.png`：浅色 / 深色底对照预览；实际菜单栏颜色由系统决定。

工程资源位于 `PenActor/Assets.xcassets`：应用图标导出 macOS 传统 AppIcon 所需的 10 个尺寸（16～1024 像素），兼容最低 macOS 14；菜单栏使用 PDF，启用 Preserve Vector Data 和 Template Image，不手动判断系统深浅色。

应用图标的 SVG / PDF 是矢量设计源文件；供传统 AppIcon 使用的 PNG 是构建资源，不将这些 PNG 宣称为矢量或 Icon Composer 的分层 Liquid Glass 图标。后续若采用 Icon Composer，可从矢量母版拆出背景、笔尖及曲线图层。

在仓库根目录运行 `swift scripts/generate-icons.swift` 可重新导出全部资源。脚本用同一组路径生成 SVG、PDF 和 PNG，不依赖字体、第三方工具或外部网络。

已验证 Debug 构建及 arm64 / x86_64 Release 构建成功；编译产物 AppIcon 已写入应用 Info.plist，MenuBarIcon 在 Assets.car 中保留矢量表示和 template 属性。真实菜单栏位置 / 选中态仍以系统实际显示为准。

设计参考：[Apple App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)、[Apple Menu bar extras](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#Menu-bar-extras)。遵循黑色与透明区域定义菜单栏图形，由系统着色的约定。
