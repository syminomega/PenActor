# 开发指南

[English](development.md) | 简体中文

## 环境要求与命令

使用支持 Swift 6 的 Xcode，并配备能够编译工程中带可用性保护的 macOS 27 API 的 SDK。
最低部署版本仍为 macOS 14。共享方案名称为 **PenActor**，项目没有第三方包依赖。

在仓库根目录运行：

```sh
# Compile both supported architectures without launching the app.
xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/Release ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build

# Run the full fixture and UI suite in a separate build directory.
xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Tests test

# Run one test suite (test IDs remain stable across source-file splits).
xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Tests -only-testing:PenActorTests/PressureMappingTests test
```

需要时，在 macOS 测试目标中添加 `arch=arm64` 或 `arch=x86_64`。
测试源码按应用职责组织。共享夹具和后端替身位于 `PenActorTests/Support/`；
两个原有 XCTest 类保留原名称，测试方法通过 extension 按主题分组。

测试宿主使用临时配置仓库，跳过启动时的观察流程，不迁移用户真实配置。
Quartz 夹具不会投递真实系统输入，tap 失败路径通过注入工厂测试。
界面测试覆盖渲染、导航、窗口尺寸、草稿状态和压力条。
部分渲染测试会将 PNG 预览写入系统临时目录。

日常应用运行时，请在独立的 derived-data 目录中进行构建和测试。
不要将测试产物安装并覆盖日常应用。Sidecar、数位板和绘画应用的实机验证与夹具测试分开进行。

## 签名

应用 bundle ID 为 `dev.SyminStudio.PenActor`，测试包在其后添加 `.tests`。
`Config/Signing.xcconfig` 提供可移植的 ad-hoc 默认签名，并可选包含已被 Git 忽略的
`Config/Signing.local.xcconfig`。如需稳定的本地开发身份，请通过已有的 Xcode 签名配置
设置本地文件，例如：

```xcconfig
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = YOURTEAMID
```

日常构建应保持相同的 bundle ID、签名团队和安装路径。
ad-hoc 签名随代码变化，可能导致权限需要重新授权。切换到新身份也可能需要授权；
稳定签名并不能保证每次系统更新都保留 TCC 状态。

也可以使用已有的 Apple 签名身份构建通用 Release 应用：

```sh
security find-identity -v -p codesigning
scripts/build-signed.sh <40-character-identity-SHA-1> <10-character-team-ID>
```

脚本会校验签名和团队，将产物写入
`build/Signed/Build/Products/Release/PenActor.app`。
它不会安装证书、修改信任、授予隐私权限或替换已安装应用。
下方提供 DMG 打包流程；项目尚未配置公证和自动发布上传。

避免保留与正式应用具有相同 bundle ID 的完整应用形态签名探针或版本备份。
即使修改扩展名，Launch Services 仍可能发现它们，导致隐私设置中的名称混淆。
需要保留的备份请保存为 ZIP 归档。

## DMG 打包

使用当前 Xcode 签名配置创建通用 Release DMG：

```sh
scripts/package-dmg.sh
```

脚本在 `build/Packaging` 中构建，在不改动签名的情况下打包应用，并输出
`build/Release/PenActor-<version>-macos-universal.dmg` 和对应的 `.dmg.sha256`
校验文件。版本号读取自编译后的应用 Info.plist。
映像包含 `PenActor.app`、Applications 快捷方式和两种语言的安装指南。
脚本检查应用签名、双架构、已编译语言资源、映像完整性和挂载后的内容，不覆盖已有输出文件。

打包已经构建的应用，或选择其他产物目录：

```sh
scripts/package-dmg.sh \
  --app build/Signed/Build/Products/Release/PenActor.app \
  --output-dir build/ReleaseCandidate
```

指定应用的 bundle ID 必须为 `dev.SyminStudio.PenActor`，具有有效代码签名、
arm64/x86_64 两种架构和两种已编译语言资源。
没有本地签名覆盖时，默认的新构建使用 ad-hoc 签名；当前维护者构建使用 Apple Development
签名。它们都不是使用 Developer ID 签名并完成公证的公开分发构建。
如需该流程，请获取 Developer ID Application 身份，并遵循 Apple 的
[公证指南](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
打包脚本不会修改签名配置、安装或启动应用、授予权限、移除隔离属性或提交公证请求。

在 GitHub 分发时，通过[仓库 Releases 页面](https://github.com/syminomega/PenActor/releases)
创建发布，选择与应用版本对应的标签，同时上传 DMG 和校验文件。
发布说明中写明当前签名及公证状态，并链接到[安装说明](installation.zh-CN.md)。
公开链接前先提交并推送打包与文档改动。脚本只生成本地产物，不创建标签、推送提交或发布 GitHub Release。
应在另一台 Mac 上测试通过浏览器实际下载后的首次启动；本地打包检查无法复现接收者干净系统的
Gatekeeper 和 TCC 状态。

## 修改约定

- 按职责组织代码，保持磁盘目录和 Xcode 分组一致。
- 将无关模型、仓库、事件处理和视图拆开。紧密相关的私有辅助实现保留在所属对象旁，
  不添加没有实际用途的抽象层。
- 英文为默认文档，每次修改同时维护完整的简体中文对应文档。源码注释保持英文。
  除非任务明确要求调整文案或本地化，否则保留现有界面语言。
- 注释应解释职责归属、API 限制和顺序假设，避免复述代码。
- 结构重构期间，保留持久化键、schema 兼容性、压力字段精度、笔画边界和取消、重发语义。
- 逻辑修改运行相关测试。移动源码或修改 target membership 后运行构建，跨模块重构运行完整测试。
- 记录实际验证及其限制；夹具通过不等于设备兼容性认证。

## 本地化与翻译

### 支持的语言与资源

PenActor 提供**简体中文（`zh-Hans`）**和**英文（`en`）**。
应用使用 macOS 语言偏好，包括为单个应用指定的语言；没有独立的应用内语言偏好。
更改首选语言后需要重新启动应用。

`PenActor/Localizable.xcstrings` 是唯一的 Xcode String Catalog，负责 SwiftUI、AppKit、
错误提示、帮助和无障碍文案及显示标签。开发语言和源语言均为英文，源键使用可读的英文短语，
简体中文译文保存在同一目录中。工程的 `developmentRegion` 与目录的 `sourceLanguage`
均为 `en`，`knownRegions` 包含 `en` 和 `zh-Hans`。英文是开发语言回退值。保持这些设置一致，
并将目录加入应用资源编译阶段。本项目没有 storyboard，也没有独立的 Interface Builder 翻译目录。

功能开发时同步维护翻译。PenActor 最低支持 macOS 14，可使用 `String(localized:comment:)`。
字符串保存到模型属性，或传给接收 `String` 的辅助函数时，优先显式本地化：

```swift
let title = String(localized: "Pressure curve", comment: "Pressure response editor title")
Text(title)

// Translate the complete sentence, keeping values as typed interpolations.
let name = String(localized: "Profile \(profileNumber)", comment: "New profile name")
```

SwiftUI 中的直接字面量也可以被提取，但普通 `String` 变量、三元表达式和自定义辅助函数参数
不会自动完成本地化，需要显式解析。不要通过拼接翻译片段组成句子；使用完整的插值短语，
人类可读列表使用 `ListFormatter`。

### 新增与审阅文案

1. 添加可读的英文源短语，并为有歧义的术语或动态参数提供有用的译者注释。仅在含义相同时复用源键。
2. 在 Xcode 中构建以提取字符串，然后补全翻译目录中的**两种**语言，英文值必须与源键一致。
   不要使用中文短语作为本地化键，也不要为创建英文键而改写稳定数据值。
   保留 `%@`、`%lld`、`%llu` 和 `%d` 等参数类型；翻译需要调整顺序时，使用位置占位符。
3. 保留专有名称（`PenActor`、`Sidecar`、`Apple Pencil`、`SwiftUI`）和快捷键符号。
   统一使用 Input Monitoring / 输入监控、Accessibility / 辅助功能等 macOS 术语。
4. 翻译标题、按钮、空状态、错误、工具提示和无障碍标签及值。
   两种语言都检查默认和最小窗口尺寸；英文应简洁，但不能改变原意。
5. 新增或修改用户可见文案后，完成目录校验和两种语言的测试再交付。

| 英文 | 简体中文 | 含义 |
| --- | --- | --- |
| Profile | 配置 | 属于一台设备的命名应用规则集合 |
| Device defaults | 设备默认 | 一台设备的基础压力配置 |
| Entry taper | 入锋 | 笔画开始时的压力渐入 |
| Exit taper | 出锋 | 通过输入缓冲实现的笔画末端压力渐隐 |
| Pass through | 透传 / 不映射 | 保持系统输入不变 |

### 稳定数据与显示文案

不要翻译 bundle ID、JSON 键、偏好键、确定性设备身份键、应用规则标识或用户输入的名称。
已有配置名称保持保存时的原样，只有新建配置的默认名称使用当前语言。

部分旧版 Codable 原始值为中文，包括事件来源、挤压状态和工具名称。必须保留原值。
显示时分别使用 `EventSource.label`、`PencilSqueezeStatus.label` 和
`PenDeviceInfo.localizedToolType`。设备身份解析继续使用原始工具值。

映射状态和诊断原因字符串同样原样保留在日志中；`localizedStatus` 和 `localizedReason`
只在界面显示时翻译：通过匹配旧原始值，调用使用英文源键的显式 `String(localized:)`。
Xcode 可以正常提取这些显示键。不要将中文原始值作为本地化查找键。未知诊断值保持原样。
不要在高频事件 tap 处理中执行本地化。
导出的诊断值与日志解释性备注不属于需要翻译的用户界面。

### 验证命令

```sh
python3 scripts/check-localizations.py

xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Localization -testLanguage en -testRegion US test

xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Localization -testLanguage zh-Hans -testRegion CN test
```

校验器检查英文源语言及源键、源值一致性、语言覆盖、翻译完成状态、过时条目和格式参数。
`LocalizationTests` 检查编译后的语言资源、格式化结果和稳定数据。
既有渲染及窗口测试会按指定的测试语言运行。
显示文案应与本地化后的预期值比较；持久化数据或诊断值的断言保持语言无关。

新增语言时，请更新工程本地化列表，翻译全部目录条目，扩充校验器支持的语言集合，
并将新语言加入渲染和格式验证。不要添加空的语言列并声称已经支持该语言。

## 双语文档

英文是默认首页和文档语言。保留 `README.md` 和已有英文文件名，在相邻位置添加完整的
中文译文，后缀使用 `.zh-CN.md`。例如，`docs/usage.md` 对应
`docs/usage.zh-CN.md`。文档文件名约定独立于应用本地化标识 `zh-Hans`。

每篇文档在标题下提供 English/简体中文切换入口。
文档内链接应指向同语言页面，包括相应译文的标题锚点。
两种语言的事实、章节结构、示例、数值和限制说明保持一致；可执行围栏代码块保持完全相同。
创建、编辑、移动或删除面向读者的文档时，在同一次修改中更新两种语言及受影响链接。
不要留下待翻译占位，也不要静默推迟另一种语言的更新。

仓库内的 [bilingual-docs](../.agents/skills/bilingual-docs/SKILL.md) skill 提供此工作流程。
`AGENTS.md` 要求文档工作使用该 skill，也可通过 `$bilingual-docs` 显式调用。
代理指令文件（`AGENTS.md`、`SKILL.md` 和其他工具入口）保持唯一的英文版本；
生成文件、第三方文件和源码注释不要求配对文档。

在仓库根目录运行文档检查器：

```sh
python3 .agents/skills/bilingual-docs/scripts/check_docs.py
```

检查器验证译文配对、语言切换入口、章节结构、代码块一致性，以及本地链接和标题锚点。
还需人工对照两种语言的语义，因为结构检查不能判断翻译质量。
仅修改文档时，执行该检查并审阅内容即可，不需要重新构建应用或执行设备测试。
