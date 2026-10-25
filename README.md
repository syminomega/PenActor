# PenActor

macOS 数位笔输入调试工具，使用 Swift 6、SwiftUI 和 AppKit，无第三方依赖。最低 macOS 14；已在 macOS 27.0.1 / Xcode 27.1 上构建。支持本应用输入观察、其他应用输入观察、稳定设备配置、可编辑压力曲线、指定应用压力重映射、入锋 / 缓冲出锋、压力趋势和笔迹测试。

## 运行

1. 用 Xcode 打开 `PenActor.xcodeproj`，选择共享 Scheme **PenActor** 和 **My Mac**，按 ⌘R。
2. 应用默认自动开始监听并打开设置，菜单栏显示 PenActor 图标；设置窗口打开时显示 Dock 图标并支持 ⌘Tab 切换；关闭窗口后隐藏 Dock 图标并继续后台运行。从菜单栏打开设置、调试、测试，或退出程序。使用 Wacom 等数位板前安装对应厂商的 macOS 驱动；使用 Apple Pencil 前通过系统 Sidecar 连接 iPad，将测试窗口移到 iPad 上。
3. 在「测试」页落笔，或切换到 PS / CSP 绘画。窗口置顶便于在其他应用中绘画时观察数据。
4. 需要时点击「请求权限」，在 **系统设置 → 隐私与安全性 → 输入监控** 中允许 PenActor，再点击「重新检查」。系统若要求退出并重新打开，请按提示重启。

命令行构建和测试（未配置本机签名时默认 ad-hoc；本机已配置 Apple Development）：

```sh
xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -derivedDataPath build build

xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build test

open build/Build/Products/Debug/PenActor.app
```

Intel Mac 测试将 `arch=arm64` 改为 `arch=x86_64`。工程未开启 App Sandbox，当前面向本机调试；未配置发布证书、公证、App Store 或分发流程。

## 授权与更新

0.5.9 起，「输入监控」和「辅助功能」请求按钮都会尝试打开对应系统设置页，避免已有拒绝记录时仅调用系统请求却无界面反馈。列表没有 PenActor 时可点 + 添加 `/Applications/PenActor.app`。

0.5.9 本机安装包改用 Apple Development 签名，最终 Bundle ID 为 `dev.SyminStudio.PenActor`。原 ad-hoc 身份随构建变化；这次切换新身份仍需授权一次，今后应沿用本机稳定签名。签名构建脚本及排查说明见 [授权与签名](docs/permissions-and-signing.md)。

## 随航长按右键实验

通用页可开启「屏蔽触摸长按右键（实验）」，初始仅对 Photoshop 生效，可添加其他应用。需要启动输入服务并授予辅助功能权限，独立于压力映射；重启后默认关闭。当前仅匹配公开 touch subtype 的右键，不保证随航一定携带该标记。请对照长按、实体鼠标右键和双指缩放／旋转／滚动，并观察拦截计数；未生效时导出 JSON 中的 `touchBlocking` 独立诊断。详见 [实验说明](docs/preferences.md#随航触摸长按右键实验056) 与 [可行性分析](docs/sidecar-touch-research.md)。

## 数据的含义

### 导出 JSON 日志

点击「调试」页顶部「导出 JSON」选择保存位置，可以在监听中或停止后导出。保存的是**按下按钮时**全部设备最近保留的最多 500 条事件，按采集顺序（最旧在前）排列，不受设备菜单选择影响。保存面板打开后的新事件不进入这份快照；取消保存不会改动采样。写入失败时显示错误。

出锋开启时，诊断在准备输出时记录，未输出的缓存数量见 `mapping.bufferedEventCount`；`delivery` 标识输出方式，`taper` 保留首尾包络系数。

日志采用 UTF-8、格式化 JSON，`schemaVersion` 为 2，主要包含：

- `events`：事件序号、系统 uptime 秒 `timestamp`、接收时间 `receivedAt`（UTC ISO 8601，毫秒）、事件名称与原生类型码、临时 Device ID、当时解析的 `identityAtCapture`、压力 / 倾斜 / 旋转 / 按钮、屏幕坐标和前台应用上下文。
- `sample.pressure`：保留系统 Float 值的序列化精度，不按面板的四位小数舍入。`null` 表示该事件未取得有效压力，`0` 才是有效零压力；proximity 事件没有 sample。
- `devices`：已观察稳定身份及最近硬件信息；实际 proximity 事件还会保留该事件当时的元数据。尚未收到元数据的历史事件可能仍带临时身份，可通过同一会话的 proximity 记录关联。
- `totalObservedEvents / retainedEventCount / discardedEventCount`：累计采集量、当前保留量和已淘汰量，判断日志是否缺失更早的起笔。应用重启或清空后重新计数。
- `profiles / mapping`：全部已保存配置、`mapping.defaults.devices` 设备默认设置快照、启用配置快照、映射状态、已修改事件计数及最近 500 条 tap 诊断。`mapping.diagnostics` 与 `events` 是独立事件流，不强行逐条匹配。诊断包含设备身份、目标 PID / bundle ID、配置 UUID、压力修改前后值和透传原因；鼠标事件另外记录 `tabletInputPressure / tabletOutputPressure`，两类压力字段分别映射。`outputPressure` 是写回后重新读取的实际值，包含系统字段的量化误差。
- `pencilGestures`：双击 / 挤压的累计摘要（不含逐条手势时间线），以及应用版本、系统版本和导出时间。

分析毫秒间隔时优先对相邻事件的 `timestamp` 求差乘 1000；它是系统事件时间，而不是回调收到时间。绝对坐标是数位板空间，`screenX / screenY` 是 CGEvent 全局屏幕点坐标。导出本身不加工数据。启用映射时，NSEvent 可能已经包含处理结果；修改前的系统事件压力应查看 tap 诊断。系统仍可能合并事件。

日志包含设备序列号 / 唯一标识、应用上下文及绘画位置，保存到本地，不自动上传。`Logs/` 和 `PenActor-*.json` 已加入 Git 忽略规则。旧版本进程的内存不能由新版本追溯导出，更新后需重新采集。

项目现象与第三方资料对照见 [输入观察记录](docs/input-observations.md)。

macOS 提供统一的 **AppKit NSEvent 数位笔事件**。Apple 在 [WWDC19 AppKit 演讲](https://developer.apple.com/videos/play/wwdc2019/210/)中说明了 Sidecar Apple Pencil 的 tablet subtype 与压力输入。它是本版的读取入口。

输入链路大致为：硬件 → 驱动 / Sidecar → 系统事件 → 绘画应用 → 笔刷。PenActor 观察的是**系统事件值**，不承诺获取未经驱动处理的原始硬件压力，也不能从事件反推出 PS/CSP 的最终笔刷压力曲线。

| 字段 | 含义 |
| --- | --- |
| 压力 | 系统归一化值 0…1；有效零值显示为 `0.0000` |
| 倾斜 X / Y | 系统归一化值 −1…1，不换算为度数；垂直通常为 0/0 |
| 笔轴旋转 | `NSEvent.rotation`，单位为度；与触控板旋转手势不同 |
| 切向压力 | `tangentialPressure`，范围 −1…1，只有部分笔支持 |
| 绝对 X / Y / Z | 驱动报告的数位板坐标，不是屏幕点或物理毫米 |
| 按钮 | `buttonMask`，同时显示十进制 / 十六进制 |
| 设备信息 | 驱动 / 系统报告的标识，不据此猜测产品型号 |
| 时间戳 | `NSEvent.timestamp` 为系统 uptime 秒；列表时间是本机接收时间 |
| 来源 | 本地监听为「本应用」，全局监听为「其他应用」 |
| 前台应用 | 收到回调时的前台应用，仅用于上下文观察，不保证是事件接收进程 |

硬件信息仅从 proximity 事件读取，用 `deviceID` 关联采样。`deviceID` 只用于感应会话，不是永久设备编号；同一支笔重新进入范围可能产生新 ID，也可能复用已有 ID。设备菜单按下述稳定身份归并多次连接，表示**已观察设备身份**，不是在线物理硬件清单。序列号、unique ID、vendor ID 等如果为 0，可能是驱动占位，不代表已辨认出某种硬件。

未收到 proximity 时仍显示有效采样，并显示「硬件信息待获取」。将笔移出感应范围后重新靠近，可能补齐元数据。离开范围保留历史读数；静止或长时间无新事件不自动判定断开。停止监听后保留面板数据。

## 稳定身份与自动切换

设备菜单不再以临时 `deviceID` 建立独立条目，而按确定性的、带版本号的匹配键归并：

1. 厂商有效且 Unique ID 非零：`v1:tool:<vendor>:<uniqueID>:<tool>`，识别同一支笔。
2. 缺少 Unique ID，但笔序列号有效：`v1:serial:<vendor>:<serial>:<vendorToolType>:<tool>`。
3. 缺少唯一标识：`v1:model:<vendor>:<tabletID>:<vendorToolType>:<tool>`，按型号和工具归组。你测试的 Sidecar 两组会话可匹配到同一条记录；多支同类 Pencil 会共享这个身份，不能宣称精确识别物理笔或 Pencil 代数。
4. 尚无有效硬件信息：保留临时会话；收到 proximity 后自动升级或合并到已有稳定身份，并保留采样与选择。缺少型号信息且所有标识均为零时不会把未知设备强行合并。

`tool` 使用固定的 `pen / eraser / cursor / unknown` 标记，不使用中文显示名称或 Swift 的随机 `hashValue`。型号、系统索引、会话编号和能力掩码不加入唯一笔匹配键；能力掩码和系统索引也不加入型号匹配键。界面显示匹配方式、可复制的配置匹配键和当前会话 Device ID。相同稳定身份重连复用条目并保留有界趋势；迟到的旧连接退出事件不覆盖新连接状态。笔与橡皮擦作为独立工具身份。

「笔变化时自动切换」默认开启，开关保存在本机偏好设置中。检测到新的活动身份（进入范围或产生采样）时自动切换；离开范围不触发切换。开启时仍可手动查看其他设备，同一支活动笔的后续事件不会立即抢回选择，直到活动笔身份再次变化。关闭后保持手动选择；重新开启立即选中最近活动身份。「清空记录」保留开关设置。

压力配置按稳定匹配键保存在本机；已观察设备与采样仍仅保存在内存中，应用重启后重新观察，相同有效硬件字段会生成相同匹配键。临时会话不能创建持久配置。

## 能力和缺失值

### Pencil 双击与挤压提示

面板的「Pencil 手势 · 本应用窗口」显示双击次数、挤压次数、当前阶段、完成 / 失败次数以及最近回调时间。把 PenActor 窗口移到 Sidecar iPad 并激活后测试；双击需在 Mac 的显示器 → iPad 设置中启用，挤压需要 Apple Pencil Pro。

双击同时接入本地 `NSEvent.changeMode` 和 SwiftUI `onPencilDoubleTap`。两个来源在 150 ms 内的首对回调合并为一次，界面标注已去重；这是按接收时间配对的启发式处理，不是系统提供的共同事件 ID。挤压通过 SwiftUI `onPencilSqueeze` 接入，显示活跃、结束或失败 / 取消阶段；重复 active 回调只计一次手势。SwiftUI 两个接口需要 macOS 14.5 或更新版本，较早系统仅接入 changeMode 双击事件。

提示为本窗口收到的手势，不强行关联到当前选中的设备，也不承诺后台读取 PS/CSP 中的手势。尚未收到不等于硬件不支持，需要真实 Sidecar 测试。停止监听后不计数；停止或窗口失活会标记进行中的挤压已中断；清空记录也会清除手势计数与时间。手势提示不修改或注入输入。

参考：[changeMode](https://developer.apple.com/documentation/appkit/nsevent/eventtype/changemode)、[onPencilDoubleTap](https://developer.apple.com/documentation/swiftui/view/onpencildoubletap(perform:))、[onPencilSqueeze](https://developer.apple.com/documentation/swiftui/view/onpencilsqueeze(perform:))。

### 数位笔字段

- 「未取得」：尚未收到有效字段。例如鼠标移动事件即使带 tablet subtype，也不能合法读取 `pressure`，此时压力留空。
- 「支持情况未知」：尚未取得能力掩码，或驱动上报的掩码为 0。仍保留合法事件中的读数。
- 「驱动声明支持」/「驱动未声明支持」：依据非零 `capabilityMask` 的对应位。位定义来自公开 macOS SDK `IOKit/hidsystem/IOLLEvent.h` 的 `NX_TABLET_CAPABILITY_*MASK`。缺少能力位属于驱动声明信息，不作为硬件绝对不支持的证明，因此不隐藏事件读数，也不把恒为 0 自动标成“不支持”。

不同 Apple Pencil、数位板笔及驱动不一定报告旋转、切向压力或完整硬件标识。本版不做 HID 枚举，不保证提供市场名称、压力级数、电量、固件版本等 NSEvent 没有提供的信息。

## 监听与排查

- 本地和全局监听器分别安装：全局监听不包含 PenActor 自己的事件。
- 本地回调原样返回事件；全局回调只观察，不阻止、改写或注入输入。压力修改由独立的主动 Quartz tap 实现，不在 NSEvent 监听器内执行。
- 权限状态、监听器安装结果和「是否收到笔事件」独立显示。即使未授权，系统也可能创建全局监听器，不能据此推断全局数据可用；本地测试不被权限状态锁住。
- 如果只有外部应用没数据，先检查输入监控授权并重启应用，保持同一个 `.app` 路径。移动构建产物或修改签名后可能需要系统重新确认授权。
- 如果有数值但没有硬件信息，尝试重新进入感应范围。如果完全无数据，检查驱动与 Sidecar 连接，并确认工具报告 tablet 事件；普通鼠标和触控板 Force Touch 会被忽略。
- macOS 27 的 **Sidecar 手指触控**不进入事件监听器。本版测试区采用自定义 `NSGestureRecognizer`，不使用阻塞式跟踪循环；笔迹仅接受 tablet 事件，手指模拟的普通鼠标输入不会冒充数位笔。详见 [TN3212](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support)。这不意味着可以全局读取其他应用里的手指触控。
- 高频输入保持读取事件层数值，面板最多刷新 60 Hz。最近事件保留 500 条，单设备趋势最多 600 个采样且仅绘制最近 5 秒，设备身份最多 32 个、会话映射最多 128 个，测试区笔迹最多 4096 个线段；超限淘汰旧数据。系统可能合并事件，事件计数不是硬件采样率。事件数据只在内存保留，不写盘或上传；自动切换开关保存在本机偏好设置中。
- 「清空记录」清除设备、采样、趋势、事件及笔迹；监听状态不变。
- 测试区的普通 `mouseUp` 也会结束已有笔手势；窗口失去焦点、应用切换、退出感应范围或回到移动事件时会取消遗留手势。macOS 27 上测试区使用非独占手势，避免丢失抬笔后阻挡工具栏按钮。可通过菜单栏「启动 / 停止输入服务」或 `⌘⇧P` 开始 / 停止监听。

## 压力重映射测试

实现原理、事件链路与代码入口见 [压力重映射技术说明](docs/pressure-remapping.md)；0.3.0 新增 [入锋与缓冲出锋说明](docs/stroke-taper.md)。

1. 打开「配置」页，在左侧选择设备。设备名称可单独重命名；Sidecar 仍按型号归组，不能区分多支同型号 Pencil。
2. 「编辑」选择「设备默认」，调整这台设备的压力曲线和入锋 / 出锋后保存。压力曲线横轴为输入、纵轴为输出，支持双击加点、拖动、删除内点、线性和轻压增强预设；端点固定，单调三次插值避免过冲。
3. 新增并命名配置，添加 PS / CSP 等生效应用。应用默认继承所属设备的参数，一般不必重复编辑曲线。
4. 有例外的应用可取消继承，在行末设置弹窗中单独覆盖曲线及入锋 / 出锋，或设为不映射；覆盖仅属于当前设备的这个配置。
5. 检查「通用」页的辅助功能权限，保存并启用配置。首次启用后将笔移出感应范围再靠近，以让 tap 收到新的 proximity。
6. 在相同笔刷设置下对照测试线性、轻压增强、禁用。增强预设的理论值为 `0.5 → 0.8`，写回值受系统字段量化影响。
7. 「调试」页查看输入 / 输出和透传原因并导出 JSON。**回调已修改不等于应用已采用修改值**，最终仍需真实设备和应用验证。

每台设备可保存多个配置，同时启用一个；不同设备各自启用、互不干扰。配置中的应用选择继承设备默认、单独覆盖或不映射。未列入配置的应用、未启用配置的 Wacom 等设备保持透传。设备默认或已启用配置的修改从下一笔生效，禁用 / 暂停立即生效。停止监听会停止映射，重启程序或重新监听不自动启用。关闭设置窗口继续后台运行，从菜单栏退出才停止服务。

`profiles.json` 升级至 schema 4，`defaults.json` 为 schema 2，位于 `~/Library/Application Support/PenActor/`。旧文件先备份，再按实际生效参数迁移为每设备默认及应用覆盖；保留原有配置身份、目标范围和效果。清空记录不删除配置。完整流程、迁移和文件字段见 [以设备为中心的配置](docs/preferences.md)。

实现使用 `.cgAnnotatedSessionEventTap / .tailAppendEventTap / .defaultTap`，在独立线程的 RunLoop 同步处理；直接读取 Quartz proximity 字段并复用稳定身份算法。仅匹配设备与事件目标 PID 对应 bundle ID 后修改 `tabletEventPointPressure` / `mouseEventPressure`。关闭出锋时修改并返回原事件；启用出锋时暂存并重发副本，保留坐标、倾斜、按钮、时间戳与顺序，并添加来源标记以避免重复处理。两类压力字段精度可能不同，因此分别映射；线性配置跳过相同值写入，零值保持零。身份、目标进程或接触阶段无法匹配时透传。

回调不执行 UI、磁盘、同步应用查询；配置和 PID 对照在回调外更新，诊断最多 500 条，会话和笔画锁定最多各 128 个。tap 创建失败、超时或系统停用后停止映射，保留原因，不循环自动重启。0.3.0 可分别启用入锋与出锋：入锋从零平滑恢复，出锋默认缓存 60 ms 并在抬笔后修整尾部，允许调节 10～200 ms；两项默认关闭。更长出锋会带来更明显延迟，短点画可能变淡，仍需实测起笔异常是否改善。应用自己的笔刷曲线也会继续生效。

参考：[CGEventTapCallBack](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback)、[tabletEventPointPressure](https://developer.apple.com/documentation/coregraphics/cgeventfield/tableteventpointpressure)、[mouseEventPressure](https://developer.apple.com/documentation/coregraphics/cgeventfield/mouseeventpressure)。

## 工程结构

- `PenModels.swift`：设备与采样模型、事件分类、会话关联及有界缓存。
- `PenEventDecoder.swift`：按事件类型读取合法字段；独立 tablet 事件不读取鼠标 subtype，proximity 事件不读取压力。
- `PenMonitor.swift`：本地 / 全局监听、授权状态、开始停止及限频发布；`EventMonitoring` 用于替换事件后端和测试。
- `ContentView.swift`、`TestPad.swift`：调试面板、趋势和基于手势的笔迹测试区。
- `PressureProfiles.swift`：单调曲线、配置数据与原子持久化。
- `StrokeTaper.swift`、`BufferedPenEvents.swift`：入锋包络、出锋缓冲与释放恢复。
- `PressureRemappingEngine.swift`：独立线程主动 tap、设备 / 应用匹配、笔画锁定和诊断。
- `PressureMappingPanel.swift`：共享压力 / 入锋出锋编辑器。
- `PreferencesWindowController.swift`、`PreferencesViews.swift`：原生工具栏分页设置与菜单栏运行生命周期。
- `MappingDefaults.swift`：设备默认、应用覆盖解析、旧配置迁移与原子持久化。
- `PenActorTests`：事件过滤、Quartz 事件字段解码、设备会话、缺失值、缓存上限与监听生命周期测试。Quartz 夹具只在进程内转换为 NSEvent，不向系统注入事件。

## 验证记录与实机验收

最近自动化验证：2026-10-25。`xcodebuild build` 成功（arm64 / x86_64），`xcodebuild test` 在 arm64 上通过 122 项测试，0 失败。本机界面已观察到来自驱动的本地 / 全局笔事件、proximity 进入 / 离开、硬件标识、压力趋势和有粗细变化的测试笔迹；未核实该设备具体型号，也未把该观察计为下表完整兼容性验收。压力重映射新增进程内 Quartz 夹具、曲线与持久化测试；测试不创建真实主动 tap，系统创建失败 / 停用由注入工厂验证。硬件兼容性必须使用真实笔输入单独验证，测试夹具不能替代设备验收。

| 输入链路 | 测试区 | Photoshop | Clip Studio Paint |
| --- | --- | --- | --- |
| Sidecar + Apple Pencil | 待实机验证 | 待实机验证 | 待实机验证 |
| Wacom 等数位板 + 厂商驱动 | 待实机验证 | 待实机验证 | 待实机验证 |

2026-10-21，用户反馈压力重映射「确实生效了」，记录为当前测试环境的初步实机验证；尚未逐项记录目标应用、曲线与笔刷设置，因此下表完整验收仍待完成。对同一笔刷比较线性、增强、禁用，检查点画、拖动、抬笔、目标应用切换与 Wacom 透传，并保留 schema 2 JSON。

每个组合检查：轻压到重压、抬笔归零、倾斜 X/Y、旋转（仅硬件支持时）、按钮、离开 / 重新进入感应范围、设备切换。前后台切换后检查来源标记，并确认 PS/CSP 笔迹没有被阻断。记录 macOS / iPadOS、笔和数位板型号、驱动及绘画软件版本；不可取得的字段保留“未取得/支持情况未知”。

## 后续研究

研究与测试方向见 [TODO](TODO.md)，包括在指定应用中屏蔽随航手指触摸，避免 Pencil 绘画时误触长按右键。当前仅记录，尚未实现。

## 苹果官方参考

- [NSEvent](https://developer.apple.com/documentation/appkit/nsevent)
- [pressure 及有效事件类型](https://developer.apple.com/documentation/appkit/nsevent/pressure)
- [tilt 的单位及方向](https://developer.apple.com/documentation/appkit/nsevent/tilt)
- [deviceID 与感应会话](https://developer.apple.com/documentation/appkit/nsevent/deviceid)
- [本地 / 全局事件监听](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)
- [CGPreflightListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()) / [CGRequestListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess())
- [Sidecar 与 Apple Pencil，WWDC19](https://developer.apple.com/videos/play/wwdc2019/210/)
- [macOS 27 Sidecar 手势，TN3212](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support)

## 图标资源

0.4.1 使用原创彩色应用图标与单色菜单栏模板图，矢量源文件、生成脚本和设计说明见 [图标设计](Design/Icons/README.md)。

0.5.2 将设置窗口改为按页面适配大小，配置保存按钮固定于底部；调试页按实时数值、设备详情和事件记录分区，避免纵向堆叠。
