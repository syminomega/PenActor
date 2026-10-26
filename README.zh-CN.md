# PenActor

[English](README.md) | 简体中文

PenActor 是一款 macOS 菜单栏工具，用于观察数位笔输入，并调整指定应用中的笔压响应。
项目使用 Swift 6、SwiftUI 和 AppKit，没有第三方依赖，最低支持 macOS 14。
界面支持英文和简体中文，跟随 macOS 的语言偏好，包括为单个应用设置的语言。
切换语言后需要重新启动应用。

## 功能

- 观察本应用和其他应用的数位笔事件、设备元数据与压力历史。
- 保存设备默认设置和命名配置，支持按应用独立覆盖。
- 编辑单调压力曲线，以及可选的入锋和出锋效果。
- 测试笔迹，以及当前窗口的 Pencil 双击和挤压回调。
- 导出 JSON 诊断快照，供离线分析。

## 安装预编译版本

从 [GitHub Releases](https://github.com/syminomega/PenActor/releases) 下载通用 DMG
和对应的 SHA-256 校验文件，再将 PenActor 拖入 Applications。
如果尚未列出二进制发布版本，请按下方说明从源码构建。
当前构建使用开发签名，尚未经过 Apple 公证。
[安装与首次启动排查](docs/installation.zh-CN.md)说明了校验步骤、macOS 安全提示，
以及仅针对本应用的隔离属性移除命令。

## 快速开始

使用 Xcode 打开 `PenActor.xcodeproj`，选择共享方案 **PenActor** 和 **My Mac**，然后运行。
使用数位板前，请安装厂商提供的 macOS 驱动。使用 Apple Pencil 时，请通过 Sidecar
连接 iPad，并将测试窗口移到 iPad 上。

应用启动后显示在菜单栏中。打开设置时会显示 Dock 图标；关闭设置后，输入服务继续运行。
在**通用**页检查输入监控和辅助功能权限。每次启动应用后，映射默认处于暂停状态。

在**配置**页选择已识别的设备，保存设备默认设置，添加配置和目标应用，再手动启用配置。
在**调试**页观察事件，在**测试**页进行本地绘画测试。**⌘⇧R** 可暂停全部映射。

## 构建与测试

```sh
xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Development build

xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Tests test
```

如果没有本地配置覆盖，工程默认使用 ad-hoc 签名。请将测试构建与日常使用的应用分开，
详见[开发指南](docs/development.zh-CN.md)。

## 文档

- [安装说明](docs/installation.zh-CN.md)：DMG 安装、首次启动和安全提示。
- [使用与诊断](docs/usage.zh-CN.md)：配置、权限、笔锋与 JSON 导出。
- [架构说明](docs/architecture.zh-CN.md)：源码目录、职责归属与事件流。
- [开发指南](docs/development.zh-CN.md)：构建、测试、签名、本地化与贡献约定。
- [研究记录](docs/research.zh-CN.md)：保留的观察结果和待验证的设备问题。
- [图标源文件](Design/Icons/README.zh-CN.md)：设计素材与重新生成方式。

PenActor 观察的是经过驱动或 Sidecar 处理后的系统事件值，而非原始硬件力度。
诊断夹具不能证明所有设备、绘画应用和笔刷都已兼容。日志保存在本地，可能包含设备标识、
应用上下文和绘画坐标。
