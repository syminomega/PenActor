# 笔事件交付频率分析

## 2026-10-26 提供日志的分析

按完整 leftMouseDown → leftMouseUp 笔画提取 leftMouseDragged，排除悬停、proximity、独立 tablet 包及跨笔间隔。使用系统事件 timestamp，合并笔内间隔后按 (间隔数 / 间隔总时间) 统计：

| 应用事件层 | Sidecar / Pencil | Wacom Intuos Pro |
| --- | ---: | ---: |
| 完整笔画数 | 3 | 1 |
| 拖动事件 | 228 | 423 |
| 平均交付频率 | 83.75 次/秒 | 106.18 次/秒 |
| 平均间隔 | 11.94 ms | 9.42 ms |
| 中位间隔 | 12.34 ms | 7.54 ms |
| P95 间隔 | 21.16 ms | 13.19 ms |
| 最大间隔 | 31.57 ms | 42.64 ms |
| 超过 16.67 ms 的间隔 | 36/225 | 12/422 |

Pencil 的 tap 保留了 500 条记录：第一笔前段已淘汰；后两笔分别保留 230、198 条，对应约 237.81、237.59 次/秒。旧日志没有 tap 事件类型字段，不能排除伴随包，因此这不是独立位置更新率，更不是硬件采样率。Wacom 当时未开启映射，没有 tap 对照。

两次条件不同：Pencil 在 PS 内，映射开启、入锋开启、出锋关闭；Wacom 在 PenActor 内，映射关闭。因此不能把差别归因于硬件、映射开销或 Sidecar 单一因素，也不能仅凭截图确认折角原因。

Apple 说明 AppKit 默认合并鼠标移动、拖动与 tablet 事件：[isMouseCoalescingEnabled](https://developer.apple.com/documentation/appkit/nsevent/ismousecoalescingenabled)。这与 tap 和应用层频率不同相符，但不能确认 Photoshop 内部最终消费多少点。软件的 60 Hz UI 发布只控制显示，原记录在该定时器之前逐事件采集。

可复算：`python3 scripts/analyze-pen-log.py /path/to/SideCarApplePencilPro.json /path/to/WacomIntuosPro.json`。原始个人日志不纳入仓库。

