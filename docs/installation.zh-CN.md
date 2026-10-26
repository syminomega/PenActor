# 安装与首次启动

[English](installation.md) | 简体中文

## 下载与安装

1. 从官方 [GitHub Releases](https://github.com/syminomega/PenActor/releases) 下载
   `PenActor-<version>-macos-universal.dmg` 及对应的 `.sha256` 文件。
   GitHub 自动提供的“Source code”压缩包是源码，不是编译后的应用。
2. 在终端中进入下载目录并校验文件。将下方示例版本替换为实际下载的文件名。
   校验成功会显示 `OK`。校验和可以发现损坏或不匹配的下载；如果安装包和校验文件都来自
   不可信来源，校验成功也不能证明可信。
3. 打开 DMG，将 **PenActor.app** 拖到 **Applications** 快捷方式上。
   替换旧版本前先退出正在运行的应用。复制完成后弹出 DMG。
4. 打开 `/Applications/PenActor.app`，不要直接在磁盘映像中运行应用。

```sh
cd ~/Downloads
shasum -a 256 -c PenActor-0.6.3-macos-universal.dmg.sha256
```

通用版本支持运行 macOS 14 或更新系统的 Apple Silicon 和 Intel Mac。
应用在菜单栏中运行。打开设置时显示 Dock 图标，关闭设置后输入服务继续运行。
每次启动后映射默认暂停。

## 未公证的构建

当前本地发布构建使用 **Apple Development** 签名，**尚未经过 Apple 公证**。
开发签名与面向公开分发的 Developer ID 签名不同。
本地代码签名有效，不等于已通过 Gatekeeper 或 Apple 的恶意软件检查。
macOS 可能阻止首次启动，具体提示随系统版本和下载方式而变化。

如果出现“无法验证开发者”或“Apple 无法检查是否包含恶意软件”等提示，可先尝试打开应用一次，
然后进入**系统设置 → 隐私与安全性**，在安全性部分找到被拦截的应用。
确认信任此次下载后选择**仍要打开**，再确认后续提示。
参阅 Apple 的[安全打开应用说明](https://support.apple.com/en-us/102445)。
受管理的 Mac 可能限制此选项。

## 如果提示应用已损坏

仅凭“已损坏”提示不能判断是下载隔离属性导致。
请先从官方发布页重新下载，对照 SHA-256 校验和，并校验复制后的应用签名：

```sh
codesign --verify --deep --strict --verbose=2 "/Applications/PenActor.app"
```

如果校验和或签名校验失败，请停止操作，重新获取文件或报告问题。
移除隔离属性不能修复已损坏或被修改的应用。
如果系统明确识别到恶意软件、提示应用会损坏电脑或授权已撤销，不要绕过提示，应按系统建议处理。

仅当你信任官方下载、上述检查通过，而且仍存在与隔离属性有关的首次启动限制时，
才可以手动移除**这一个应用**的 quarantine 属性：

```sh
xattr -dr com.apple.quarantine "/Applications/PenActor.app"
open "/Applications/PenActor.app"
```

此操作移除下载文件的隔离属性，绕过该副本相应的 Gatekeeper 首次启动检查。
它**不会**为应用完成公证、证明应用安全，或授予输入监控及辅助功能权限。
如果属性不存在，无需移除。如果终端提示权限不足，请检查是否拥有该安装副本，或联系 Mac
管理员；不要把命令范围扩大到其他文件夹。不要全局关闭 Gatekeeper、清除所有扩展属性，
也不要通过重新签名下载的应用来绕过问题。

## 输入权限

启动后，在通用设置中请求输入监控权限以观察其他应用，请求辅助功能权限以主动修改压力映射。
按 macOS 要求重新启动，再重新检查权限。未授予输入监控时，本地笔输入测试仍可能工作。
隐私权限与首次启动安全检查是两件不同的事。

## 更新与问题反馈

在 Applications 中替换应用前先退出 PenActor。
已保存设置位于 `~/Library/Application Support/PenActor/`，与应用包分开保存。
签名身份变化可能需要重新授予隐私权限。

反馈安装问题时，请附上下载文件名、macOS 版本、Mac 架构、完整提示和校验和及签名检查结果，
通过项目的 [issue 页面](https://github.com/syminomega/PenActor/issues) 提交。
校验和及签名检查不能替代在干净系统上的下载测试；大范围分发前，应在另一台 Mac 上验证首次启动。
