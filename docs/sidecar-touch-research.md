# 随航长按右键的选择性抑制：可行性分析

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

通用页现提供默认关闭、按应用限制的 touch subtype 右键过滤，以及独立右键计数和 JSON 诊断。该实现仅用于测试上述第一分支，尚无随航实机命中结果。不会在未知来源时降级为拦截所有右键。使用和边界见 [设置说明](preferences.md#随航触摸长按右键实验056)。
