# 授权按钮与跨版本授权

核查日期：2026-10-25，修复版本：0.5.9。

## 输入监控按钮

旧实现只调用 `CGRequestListenEventAccess()`。系统请求不等于每次都弹提示或打开设置；此前已拒绝、已有授权记录时，按钮可能看似没有反应。

现在两个授权入口都会先调用各自系统请求，然后尝试打开对应的隐私设置页：输入监控使用 `Privacy_ListenEvent`，辅助功能使用 `Privacy_Accessibility`。系统设置 URL 属于尽力跳转；启动 URL 失败时退回隐私概览，仍失败则显示手动路径。导航成功只表示系统接受了打开请求，不代表权限已经授予。本次已在实际安装的 0.5.9 中通过界面点击，确认系统设置打开「输入监控」页面。

如果列表没有 PenActor，使用 + 选择 `/Applications/PenActor.app`。授权后按系统提示退出并重新打开应用，再检查状态。不要同时运行 Xcode 构建目录和 Applications 中的两个副本，避免为另一个构建授权。本窗口内测试不要求输入监控权限。

不会自动操作权限开关、清空 TCC、修改隐私数据库或把用户拒绝当作授权。

## 为什么更新后要重新授权

本机安装版使用 ad-hoc 签名：`Signature=adhoc`、无 TeamIdentifier，指定要求（designated requirement，DR）由具体构建的 `cdhash` 构成。代码一变，构建哈希通常就变。固定 bundle ID 和安装路径不足以保证身份跨构建稳定。

苹果 [TN3127：代码签名要求](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) 明确说明，ad-hoc 的 DR 绑定具体代码版本；隐私授权依赖签名身份。其 [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/) 说明系统如何用 DR 识别更新。

持续使用同一稳定签名身份，并保持 bundle ID 与安装位置，可避免因每次代码哈希变化而引发的重复授权。系统升级、用户撤销、身份变化等仍可能要求重新确认，不能承诺永不再询问。从旧 ad-hoc 包切换到稳定签名的第一次，通常仍需再授权一次。

## 本机状态与可用构建方式

初次检查时本机没有有效签名身份。用户确认允许创建后，Xcode 个人团队通过项目自动签名流程成功生成 Apple Development 证书；证书管理面板的手动创建项当时处于禁用状态。0.5.9 改用该开发证书安装，不要求上传商店或公证。跨版本 DR 验证已完成，但真实隐私授权能否保留仍需以后实际更新验证。

后续可在 Xcode 的账号与证书设置中配置 Apple Development 签名用于本机开发，或用 Developer ID Application 用于直接分发。使用 Apple 账号的流程由用户在 Xcode 完成，项目不存储账号、密码或私钥。正式分发另需考虑公证，不能把签名成功等同于已公证。

项目提供只构建、不安装的 Apple 证书签名脚本：

```sh
security find-identity -v -p codesigning
scripts/build-signed.sh <证书的40位SHA-1> <10位Team-ID>
```

脚本要求所选身份已在钥匙串可用，命令行覆盖项目的 ad-hoc 开发默认值，构建 arm64 / x86_64，并验证 Apple 签名锚及 Team ID。输出在 `build/Signed/Build/Products/Release/PenActor.app`；脚本不自动下载证书、扩大信任、授权或替换运行中的应用。本机已实际通过该脚本构建及 Apple 签名锚／Team ID 验证，也验证了不传命令行签名参数的默认工程构建。另将一个不运行的应用副本改变构建号后用同一证书重签，它仍满足原包的 DR；这验证代码变化不再直接改变授权身份约束，不等于已经验证 TCC 授权跨实际安装保留。

也可另行研究本机专用自签名身份及稳定 DR，适用于只在自己机器上使用；这需要单独创建、保管证书和私钥，不是当前脚本支持的 Apple 签名流程。本次未自动创建证书或改动钥匙串信任。

不要用仅包含 bundle ID、缺少证书约束的宽松 DR 来伪造跨版本身份，也不要通过关闭系统安全保护解决授权问题。

## 本机签名配置与最终 Bundle ID

工程通过 `Config/Signing.xcconfig` 加载可选的 `Config/Signing.local.xcconfig`。默认没有本地配置时使用 ad-hoc，方便其他人直接构建；本机 local 文件已设置 Apple Development 和个人 Team ID，且加入 Git 忽略。今后本机正常 Xcode／xcodebuild 构建会沿用稳定开发签名；请勿再用 `CODE_SIGN_IDENTITY=-` 安装测试产物覆盖它。自动化测试可单独使用 ad-hoc，不将该测试产物安装为日常使用版。

最终主应用标识为 `dev.SyminStudio.PenActor`，测试包为 `dev.SyminStudio.PenActor.tests`；保持同一大小写写法。旧安装版 `dev.penactor.PenActor` 的启动偏好、自动切换选项、触摸实验目标及窗口位置会一次性迁移，不覆盖新域已有设置；曲线配置仍使用原有 Application Support/PenActor 文件夹，无需搬迁。映射与触摸过滤的启用状态不迁移，重启仍默认关闭。此前讨论的 `dev.symin.PenActor` 只用于中间构建，未安装为日常版。

此次 Bundle ID 和签名同时改变，仍需在新身份下授权一次。不要用重置所有隐私权限来处理旧条目；如系统列表保留旧身份，可由用户移除旧 PenActor 条目并添加新安装包。

实际页面检查发现系统列表仍显示旧 PenActor 条目开启，而新标识进程的预检未通过。因此旧条目显示开启不能证明新签名身份已授权；用户需要按上文对新安装包重新授权。此测试只验证跳转，没有自动切换隐私权限。

## 签名验证副本与权限列表名称（2026-10-25）

本轮签名测试曾留下 `SigningIdentityProbe.fixture` 与 `SigningIdentityProbe-SyminStudio.fixture`，它们仍保留完整应用 bundle 结构及与主应用相同的标识。即使扩展名不是 `.app`，Launch Services 仍可能识别并参与名称解析，导致隐私列表显示测试副本文件名。

已将这两个自建测试副本撤销 Launch Services 注册、压缩归档为 ZIP 并移除原始 bundle 目录，重新注册 `/Applications/PenActor.app`。随后退出并重新打开系统设置，实际确认「设备控制和数据访问」列表恢复为单一 `PenActor`，两个测试名不再显示。没有改动授权开关、清空 TCC 或修改正式包的签名与 Bundle ID。

后续身份验证不要将完整同标识应用副本长期留在构建目录；改扩展名为 fixture 不足以隔离系统发现。实验完成必须清理其系统注册和原始 bundle 结构，需保留时仅保留压缩归档。优先采用无应用 bundle 的独立签名夹具，或在完成后立即清理的隔离临时目录。

后续部署的旧版本备份也仅保留 ZIP，避免将同一标识的版本号命名 `.app` 长期放在构建目录再次干扰名称解析。0.5.10 已按此方式部署；更新前验证新包满足已安装版的 DR，不再创建同标识测试副本。
