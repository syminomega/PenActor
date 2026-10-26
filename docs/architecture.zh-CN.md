# 架构说明

[English](architecture.md) | 简体中文

PenActor 按职责组织目录，将输入、配置、应用管理器、窗口和可复用组件分别归组。
这些目录表示同一个应用 target 内的源码边界，并不是独立的框架。

## 源码地图

| 目录 | 职责 |
| --- | --- |
| `PenActor/Application/` | 应用入口、代理、菜单栏操作与应用生命周期 |
| `PenActor/InputEvent/` | AppKit 观察、安全的事件解码、笔身份与 Pencil 手势统计 |
| `PenActor/PressureCore/` | Quartz tap 生命周期、笔画处理、笔锋包络与缓冲派发 |
| `PenActor/Options/` | 曲线、配置、设备默认设置、应用规则与兼容解码 |
| `PenActor/Options/Repositories/` | 校验 JSON 读取结果并原子替换文件 |
| `PenActor/Managers/` | 由 `PenMonitor` 在主 actor 上进行协调 |
| `PenActor/Diagnostics/` | 有界观察历史、设备状态、映射快照与日志序列化 |
| `PenActor/Windows/PreferencesWindow/` | 原生窗口导航和尺寸调整，以及通用、配置、调试、测试页面 |
| `PenActor/Components/` | 可复用 SwiftUI 控件、压力显示与面板样式 |
| `PenActor/Utils/` | 标识格式化与系统设置跳转 |
| `PenActor/Localizable.xcstrings` | 英文与简体中文界面翻译 |
| `PenActor/Assets.xcassets/` | 应用与菜单栏的运行时图标 |
| `PenActorTests/` | 按职责分组的测试；共享夹具位于 `Support/` |

`Config/` 保存签名配置，`Design/` 保存可编辑设计源文件，`scripts/` 保存构建、图标生成和
诊断工具。`build/` 和 `Logs/` 是已被 Git 忽略的本地输出目录。

## 观察与显示

`AppKitEventBackend` 在主 actor 上安装本地与全局观察器。
`PenEventDecoder` 先对事件分类，再读取数位笔专属字段：独立数位笔事件和带 tablet subtype
的鼠标事件，其有效访问器并不相同。尤其是 `mouseMoved`，不能读取 `NSEvent.pressure`。

`PenStore` 将会话 ID 解析为稳定设备身份，并维护有界历史。`PenMonitor` 立即采集事件，
再以最高 60 Hz 的频率发布界面快照。导出直接读取采集缓冲，因此也包含尚未发布的事件。
存储上限为 500 条事件、每设备 600 个采样、32 台设备和 128 条会话关联。

身份解析优先使用厂商与工具唯一标识，其次为序列号，再其次为型号元数据；信息不足时回退到
临时会话身份。型号身份可能将多支实体笔归为一组，不能证明它对应唯一的实体设备。
配置会保存身份键，因此带版本号的身份键必须保持确定性。

## 主动压力处理

独立的处理链路如下：

```text
Quartz annotated-session tap
  -> PressureMappingProcessor: device/app matching and stroke-latched settings
  -> pressure curve -> entry envelope
  -> direct return OR BufferedPenEvents -> exit envelope -> replay
```

`PressureRemappingEngine` 负责工作线程的 RunLoop、事件 tap、重发调度和锁。
处理器与队列是确定性的值类型；测试提供事件和时间，不向系统投递输入。
界面操作和磁盘 I/O 必须留在 tap 回调之外。状态锁保护可变处理状态，独立的输出锁则将
事件投递与停止、更新操作串行化。

配置只作用于已识别、已启用的设备和指定目标 bundle ID。目标 PID 来自 Quartz 事件，
通过运行中的应用映射表解析。AppKit 观察到的前台应用仅作为诊断上下文，不能替代事件路由判断。

设置在笔画开始时锁定。禁用配置或暂停映射立即生效。鼠标压力字段与数位笔压力字段分别映射，
线性配置避免重复写入相等值。入锋在不同事件形式之间共享同一实体笔画的进度。

出锋会暂存事件副本，直到回看窗口到期。重发通过
`eventSourceUserData = 0x50454E4143544F52` 绕过应用自身的 tap。
队列跨设备保持接收顺序，上限为 2,048 条事件。键盘或目标应用边界、取消和溢出会排空待发事件，
并在必要时释放接触状态。tap 失败后停止映射，不反复自动重启。
不要在顺手清理代码时修改这些顺序和恢复规则。

## 配置与界面职责

`MappingDefaults` 使用所属设备的默认配置解析每个配置中的应用规则。
兼容字段用于迁移和旧夹具，不能重新成为全局配置的新入口。仓库对象在写入前执行校验。
`PenMonitor` 协调备份和迁移；读取或迁移失败时，阻止配置写入和映射。

`ContentView` 承载各页面和全局状态控制。各页面负责自己的临时状态。
`DeviceProfileDraftState` 比较已保存与编辑中的值，并防止切换选择后的迟到回调覆盖新状态。
`PreferencesWindowController` 负责原生导航与尺寸调整。
测试区负责本地绘画和手势识别，不过滤其他应用的输入。

磁盘目录与 Xcode 分组保持一致。每个 Swift 文件还必须在 `project.pbxproj` 中属于正确的
编译 target；仅在磁盘上移动文件并不足够。
