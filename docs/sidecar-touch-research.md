# 随航长按右键的选择性抑制：可行性分析

> 历史研究记录：相关右键屏蔽实验已在 0.6.3 移除，当前应用不拦截触摸或右键。此文仅保留实测结论和未来研究方向。

研究日期：2026-10-22。本文是文档与代码分析，不代表完成实机拦截验证；首轮分析未修改输入处理；后续 0.5.6 已加入下述实验。

目标：在指定应用内阻止随航手指长按触发右键，保留双指缩放、旋转、滚动，以及 Pencil 和实体鼠标的正常操作。

## 官方说明与边界

苹果 [TN3212](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support) 对 macOS 27 / iPadOS 27 说明：第三方框架兼容路径中，静止长按模拟右键按下，可能随后拖动，触摸离开模拟右键抬起；双指捏合或旋转会同时模拟 magnify 与 rotate 手势。直接触摸通过手势识别器处理，不经过 AppKit 本地／全局事件监视器。

这说明两类交互在语义上可以分开；文档没有保证兼容路径生成的右键经过 Quartz event tap，也没有保证它带有可识别的 Sidecar 来源标记。不能从“都是鼠标事件”推导出外部工具一定能拦截。

[NSIsTouchNative](https://developer.apple.com/documentation/bundleresources/information-property-list/nsistouchnative) 是目标应用声明自身支持触摸的方式，不是 PenActor 按应用关闭长按的外部控制接口。本文不建议修改 Photoshop 的应用包或签名。

## 本地 SDK 与现有代码

当前 Xcode SDK 的 `AppKit/NSEvent.h` 为鼠标事件定义了 `NSEventSubtypeTouch`（Swift `.touch`）。这是值得采集的候选信息，不等于“Sidecar 长按”标识，也不能据此假设所有 touch subtype 都应丢弃。Core Graphics 的公开 `CGEventMouseSubtype` 文档主要区分普通鼠标、tablet point 与 tablet proximity；源 PID、source state、user data 也没有被公开定义为唯一触摸来源。

官方接口：[NSEvent.EventSubtype.touch](https://developer.apple.com/documentation/appkit/nsevent/eventsubtype/touch)、[CGEventMouseSubtype](https://developer.apple.com/documentation/coregraphics/cgeventmousesubtype)、[CGEventField](https://developer.apple.com/documentation/coregraphics/cgeventfield)。

现有 PenActor 的 AppKit 解码器仅接受 tablet 事件。Quartz tap 的 mask 虽包含右键，但压力处理器会在非 tablet 输入处返回，不生成映射诊断。因此现有 JSON 没有记录某个触摸右键，不能证明它没有到达 tap。调查需要独立于映射启用状态的诊断采集，不能依赖当前压力日志判断。

## 下一步：先观察，再决定拦截方式

1. 增加用户主动开启、默认关闭的短时只读输入诊断。分别记录 Quartz tap 和 AppKit 本地／全局事件，保留流的来源，不宣称逐条一一对应。
2. 捕获右键 down/drag/up、Control 修饰变化，以及对照用的左键；记录 uptime、坐标、subtype、按钮、event number、源／目标 PID、source state、user data 和有效的 tablet 元数据。对不适用字段标记未取得，避免把占位值当证据。禁止记录键盘文本。
3. 在 PenActor 自身窗口内另设原生手势测试，用于验证触摸取消及长按生命周期；本应用的回调结果不能替代 PS 内部路径验证。
4. 在 PS 与 CSP 分别测试：单指长按、Pencil 同时伴随手指长按、实体鼠标右键、触控板副点按、Control 点击、笔按钮右键、双指缩放／旋转／滚动。覆盖手指先落／后落、移动、应用切换和随航重连。
5. 对比事件可见性与来源特征。时间间隔、Pencil 活动、坐标位于 iPad 显示区域只能作为相关证据，不能独立证明触摸来源。

## 可行性分支

| 实测结果 | 处理方向 |
| --- | --- |
| Quartz 可见，且来源特征稳定可区分 | 在指定目标应用内选择性抑制右键事件序列；不处理缩放、旋转和滚动 |
| Quartz 可见，但与实体鼠标无法可靠区分 | 只提供明确标注副作用的可选右键限制实验，不称为精确触摸识别 |
| 只在目标应用进程内生成，Quartz 不可见 | 现有外部 tap 方案无法阻止；需要目标应用适配或其他经单独验证的路径 |

第一版选择性拦截必须从右键按下时决定，并持续跟踪同一交互的拖动、抬起。若按下已交付，不能中途盲目吞掉抬起；若按下已被抑制，取消、关闭选项、切换目标和退出时须有明确的状态收尾策略。事件编号仅是关联线索，仍需实测合成事件是否一致。保留 Pencil 数位笔事件与正常 Control 点击，不全局清除 Control 状态。

仅仅不拦截 magnify/rotate，并不能证明手势体验不受影响：系统手势竞争和取消可能仍有影响。因此验收必须同时包含双指交互，以及异常时所有点击能否恢复。

## 当前结论

选择性抑制在交互设计上合理，但公开文档不足以证明外部全局拦截可用。首个实验应回答“右键是否到达 tap”和“是否有可靠来源差异”，再实现过滤，避免把全禁右键误称为保留其他交互的触摸屏蔽。

## 0.5.6 候选过滤实验

历史实验曾提供 touch subtype 右键过滤，但未命中随航长按；该功能已在 0.6.3 从应用移除。以下实测结果保留作为未来研究依据。

## 2026-10-22 用户实测反馈：现有 tap 未观察到随航长按右键

环境为本轮用户正在使用的 Sidecar 与 Photoshop；PenActor 版本为 0.5.6。以下证据来自用户现场反馈，尚无该次导出 JSON，未独立核实系统、iPadOS 和 Photoshop 的精确版本。

| 操作 | 用户反馈 |
| --- | --- |
| 开启实验后，在 PS 内随航手指长按 | 菜单仍出现，观察和拦截计数均不增加 |
| 同样条件下，用实体鼠标右键／触控板副点按 | 普通右键会增加观察计数，tap 状态正常 |

结论限于现有 annotated-session tap：这次长按未以右键事件到达候选过滤器，而普通右键链路正常。因为观察计数在 subtype 和应用匹配结果之外累计，所以单纯扩大 `.touch` 匹配、移除目标应用条件或禁用普通右键，不能解决当前观察不到的这条输入。

结合苹果 `NSIsTouchNative` 文档关于 AppKit 向目标应用注入模拟手势识别器的说明，较强的解释是该右键在应用内部由触摸手势转换产生，绕过现有全局鼠标 tap。此为推断，不等于已证明所有 Quartz 层、所有应用或系统版本均无法观察。尚未验证 PID 专属 tap，也不把它当作已确认可用的解决方案。

公开的 `NSIsTouchNative` 用于应用自己声明原生触摸处理；未找到 PenActor 可从外部按应用关闭单独长按识别器的公开接口。Adobe 官方的 [画布与手势设置说明](https://helpx.adobe.com/photoshop/desktop/get-started/learn-the-basics/navigate-and-pan-images.html) 提供整体关闭手势的设置，没有在该说明中提供随航长按的独立开关；整体关闭不能作为保留双指缩放／旋转的等价替代，也尚未测试是否会阻止这条模拟路径。

后续研究应优先验证系统／目标应用原生开关，或目标应用内可用的手势适配机制，并分别验证双指操作是否保留。应用插件能否介入 AppKit 手势也需要单独论证，不作已可实现的承诺。不修改 PS 应用包，不写入未经文档支持的 defaults 键，不把 Esc 自动关闭菜单视为阻止了长按或修复了手势状态。

当前建议关闭这项实验过滤，保留已有压力映射。候选过滤器及日志用于后续其他版本／应用的对照，当前不应宣称解决了 PS 随航长按问题。

## 2026-10-22 系统手势控制入口核查

核查范围：苹果官方文档、本机 Xcode SDK 公开 AppKit / CoreGraphics 头文件、相关本地偏好设置的键名，以及 Photoshop 应用声明。全程只读，没有修改系统设置、PS 应用包或其偏好设置；未做进程注入或私有接口调用。

### 已找到的公开入口

| 入口 | 能控制的内容 | 作用边界 |
| --- | --- | --- |
| `NSView.gestureRecognizers` / `removeGestureRecognizer` | 访问或移除所属视图的识别器 | 需要持有应用内部的 NSView，不是按 PID 访问其他应用视图的接口 |
| `NSGestureRecognizer.isEnabled` | 禁用指定识别器，正在识别时会取消 | 对当前进程持有的识别器生效 |
| `NSPressGestureRecognizer.minimumPressDuration` / `numberOfTouchesRequired` | 配置长按时长与触摸数量 | 用于所属应用的长按识别器，不是系统随航全局参数 |
| `NSGestureRecognizerDelegate.shouldReceive` / `gestureRecognizerShouldBegin` | 拒绝某个触摸或识别过程 | 需要参与目标识别器的委托处理 |
| `NSIsTouchNative`（Info.plist） | 声明自行处理触摸，避免注入额外鼠标模拟识别器 | 应用启动适配声明；整体关闭兼容层，不能视为只关闭长按且保留兼容缩放／旋转 |
| `NSView.exclusiveGestureBehavior` / `NSViewGestureRecognizerIsExclusive` | 控制视图层级之间的手势互斥 | 可能与交互阻塞有关，但不是禁用右键长按的开关 |
| `CGEvent.tapCreateForPid` | 观察／过滤路由至指定 PID 的 Quartz 事件 | 可作为剩余诊断候选，不提供目标进程的 NSGestureRecognizer；尚未实测能否看见这次长按 |

文档：[识别器列表](https://developer.apple.com/documentation/appkit/nsview/gesturerecognizers)、[启停识别器](https://developer.apple.com/documentation/appkit/nsgesturerecognizer/isenabled)、[长按识别器](https://developer.apple.com/documentation/appkit/nspressgesturerecognizer)、[互斥声明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsviewgesturerecognizerisexclusive)、[PID 事件 tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreateforpid(pid:place:options:eventsofinterest:callback:userinfo:))。

### 本机可验证信息

本机 `/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app/Contents/Info.plist` 报告版本 `27.11.0`、bundle ID `com.adobe.Photoshop`。未声明 `NSIsTouchNative` 或 `NSViewGestureRecognizerIsExclusive`。这些缺省声明与兼容模拟／默认手势互斥的解释相符，但不能单独证明实际运行时内部实现。

读取到的 Sidecar 偏好域包含显示模式与 Pencil 双击等设置，未发现独立长按右键控制键。常见全局、触控板和辅助功能偏好中未发现可明确映射到随航长按的键。该检查只说明当前可见配置没有入口，不证明所有系统组件都不存在未公开实现，也不将虚构的 `defaults write` 键作为修复方案。苹果 [iPadOS 27 随航使用说明](https://support.apple.com/guide/ipad/use-your-ipad-as-a-second-display-ipad2b1aa3be/27/ipados/27) 也未提供本研究目标对应的独立长按开关。

### 对 PenActor 的结论

已有应用内控制入口，未找到公开、受支持的跨进程系统管理入口。即便能在目标应用内部控制识别器，也必须先准确识别兼容层负责长按的对象，不能假设它必然是公开 `NSPressGestureRecognizer`，更不能批量删除长按识别器。

若继续做外部工具方向，最小且独立的下一项验证是只读 PID 专属 tap 与现有 session tap 的对照；这一步尚未实现，不能预告它一定能够拦截。如果该层同样不可见，后续需依赖目标应用适配或另行研究受支持的进程内扩展能力，普通后台程序不能仅凭辅助功能授权直接修改 PS 的 Cocoa 识别器。
