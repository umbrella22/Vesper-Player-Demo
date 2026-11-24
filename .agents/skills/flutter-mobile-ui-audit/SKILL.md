---
name: flutter-mobile-ui-audit
description: 开发或走查这个 Flutter 媒体客户端的手机 UI 时，检查跨页面的卡片层级、图文对齐、触控目标、字体缩放和导航动效。适用于页面改版、视觉反馈和同类问题排查。
---

# Flutter 手机 UI 走查

## 从用户路径开始

从实际入口走到操作完成，再返回原处。明确用户在看哪条内容、点击后预期发生什么。把截图对应到负责渲染的组件，用长短两种标题、真实长度的播放量和日期、缺图或空字段复现。全应用走查时，沿以下入口寻找同类问题。

| 入口 | 重点检查 |
| --- | --- |
| 首页推荐、搜索 → 分区目录 → 视频列表 | 图片比例、相邻卡片边界、标题和缓存按钮的点击范围、返回后的列表位置 |
| 我的 → 收藏、关注、历史、稍后再看、用户空间 | 行内信息顺序、长标题、移出确认与取消、选择态、失效内容 |
| 视频详情 → 播放、评论、弹幕、听视频 | 横竖屏、安全区、叠层文字、面板关闭后回到哪个控件 |
| 离线缓存、设置、登录、更新弹层 | 进度与错误状态、键盘遮挡、主次操作、返回和重试 |
| TV 模式的对应入口 | 用方向键检查焦点可见、激活和返回。电视卡片有独立的交互布局 |

## 用可测量的标准检查

- **卡片边界。** 一条视频的封面和文字共享一个带圆角的主题表面。手机网格优先复用 `BiliVideoGridCard`。封面比例由数据来源决定，番剧海报用 150∶210，排行榜与推荐缩略图用 16∶9。浅色、深色和缺图时都能看出卡片归属。
- **标题与动作。** 先确定图标跟随哪一行。收藏条目对齐标题第一行，分区网格对齐副标题。分别测图标中心与按钮矩形，用菜单边缘实际点一次，确认手势命中该动作。在本项目新建或调整的手机卡片上给次操作留 48×48 逻辑像素，复用 `IconButton` 的动作标签。Flutter 的平台检查基准是 Android 48 和 iOS 44。[Flutter 无障碍测试](https://docs.flutter.dev/ui/accessibility/accessibility-testing)
- **文字和空间。** 先给标题留够宽度，再排作者、统计、日期。宽度够时，播放量与时长居左、收藏日期居右。窄屏或大字时按组换行。日期的读屏标签保留“收藏于”。用 `LayoutBuilder` 和系统 `TextScaler` 检查实际可用空间，包括字号放大后的行高。对普通字号的小字，分别在常态和选中底色上测 4.5∶1 的对比度。[WCAG 文字对比度](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- **导航。** 明确新页面来自哪个方向、返回后回到哪里。分区目录从首页左缘展开，关闭时退回左缘。进入一个分类后使用常规详情导航。转场时长使用 `AppVisualTokens.motionDuration`，验证系统减少动态效果时仍能立即到达和返回。[Apple 动效指南](https://developer.apple.com/design/human-interface-guidelines/motion)

## 验证并交付

按问题选择正常手机宽度、320 逻辑像素窄屏、1.5 或 2 倍文字、深浅主题及横屏。卡片用 `WidgetTester.getRect` 分别测封面、标题、图标和热区。动效在推入和退出各取一帧，再检查结束位置。渲染和交互用仓库已有的 `flutter-add-widget-test`，响应式布局可配合 `flutter-build-responsive-layout`。涉及实机观感时，从正常入口操作，记录机型、操作结果和代表性截图。

在仓库根目录运行 `flutter analyze` 和 `flutter test`。报告具体改动、同类页面覆盖范围，以及哪些结果来自源码、组件测试或真机。通用方法见 [Flutter 官方技能目录](https://github.com/flutter/agent-plugins#available-skills) 与 [Material 卡片](https://developer.android.com/develop/ui/compose/components/card)。
