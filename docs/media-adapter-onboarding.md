# 单供应商二开接入指南

仓库每次构建只装配一个视频供应商。`lib/media/` 提供通用播放壳，
`lib/<provider>/` 实现站点解析、认证、浏览页和可选能力，
`lib/platform_app.dart` 选择当前供应商。运行时不维护供应商注册表或切换状态。

保留 B 站参考实现时，播放站点接入的最短路径只修改两处：

1. 新增 `lib/<provider>/**`；
2. 替换 `lib/platform_app.dart` 中的静态装配。

`lib/main.dart` 和 `lib/media/**` 不随供应商变化。

这条边界覆盖功能接入。应用名称、包标识、图标、隐私声明和发布配置属于
产品品牌化，按目标发行渠道另行修改。最短路径无需删除 `lib/bili/**`；它可以
作为未被当前 `platform_app.dart` 装配的参考实现留在 fork 中。

## 1. 运行链路

```text
lib/main.dart
  -> runPlatformApp()                         lib/platform_app.dart
  -> VesperApp(VesperAppHost)                 lib/app/app.dart
  -> <ProviderHomePage>                       lib/<provider>/
  -> <ProviderPlaybackPage>
  -> MediaPlaybackViewModel + MediaPlaybackPage
  -> MediaPlatformAdapter.resolvePlayback()
  -> ResolvedMediaPlayback.toSource()
  -> VesperPlayerController
```

目录职责：

```text
lib/media/
  adapter/media_platform_adapter.dart         平台解析与静态能力基类
  playback/media_playback_binding.dart        单次播放的动态能力绑定
  playback/media_playback_view_model.dart     播放编排
  playback/media_playback_page.dart           手机、宽屏和 TV 播放壳
  capabilities/                               互动、内容、弹幕、历史契约
  models/                                     通用详情、剧集和解析结果

lib/<provider>/
  <provider>_client.dart                      网络、认证和站点解析
  <provider>_media_adapter.dart               MediaPlatformAdapter 子类
  <provider>_home_page.dart                   浏览入口
  <provider>_playback_page.dart               会话 VM、binding 和播放页槽位

lib/platform_app.dart                         当前供应商的唯一静态装配文件
```

## 2. 最小适配器

`MediaPlatformAdapter` 是带缺省能力的 `base` 抽象基类。新供应商使用
`extends`，子类声明为 `final`、`base` 或 `sealed`；唯一必须覆盖的方法是
`resolvePlayback`。

```dart
import 'package:vesper_media/media/media.dart';
import 'package:vesper_player/vesper_player.dart';

final class ExampleMediaAdapter extends MediaPlatformAdapter {
  const ExampleMediaAdapter({required this.client});

  final ExampleClient client;

  @override
  Future<ResolvedMediaPlayback> resolvePlayback({
    required MediaDetail detail,
    required MediaPlaybackEntry entry,
  }) async {
    final hlsUri = await client.resolveHlsUri(
      mediaId: detail.mediaId,
      entryId: entry.entryId,
    );
    return ResolvedMediaPlayback(
      title: detail.title,
      subtitle: entry.title,
      uri: hlsUri.toString(),
      protocol: VesperPlayerSourceProtocol.hls,
      transportLabel: 'HLS',
      isLocalFile: false,
    );
  }
}
```

未覆盖的能力具有以下缺省语义：

| Adapter 成员 | 缺省值 | 播放壳行为 |
|---|---|---|
| `danmaku` | `null` | 不挂载弹幕层 |
| `history` | `null` | 不查询或写入观看历史 |
| `qualityPolicy` | 空策略 | 不显示 codec 子选项 |
| `dlnaConfig` | `null` | 不显示投屏入口 |

互动和内容面板不属于 adapter。它们依赖单次播放的状态与 widget 生命周期，
通过 `MediaPlaybackBinding` 提供。

## 3. 通用播放标识

浏览页在进入播放前构造 `MediaDetail` 和 `MediaPlaybackEntry`：

- `MediaDetail.mediaId` 是供应商内稳定的内容标识；
- `MediaPlaybackEntry.entryId` 是供应商内稳定的可播放条目标识；
- `entryId` 对播放壳完全不透明，可直接包含语言或线路维度，
  例如 `episode-01-cht`、`episode-01-chs`；
- `platformExtras` 只传递供应商私有字段，`lib/media/` 不读取其中的 key；
- `pages` 按播放页中的选集顺序排列，单视频也提供一个 entry。

`ResolvedMediaPlayback` 携带最终媒体 URI、协议、请求头、轨道、字幕和清晰度选项。
清晰度分组由供应商生成，播放壳不反向推测站点质量 ID。

当前 `ResolvedMediaPlayback.toSource()` 按 WebVTT 创建外挂字幕。非 WebVTT 字幕
需要先转换，或先扩展通用字幕源契约并增加对应测试。

## 4. 单次播放绑定

`MediaPlaybackBinding` 在供应商播放页创建，并与页面级 view model 一起销毁。
它包含两个可选 builder：

| Binding 成员 | 调用时机 | 用途 |
|---|---|---|
| `engagementBuilder` | 每次信号追踪 build | 返回当前点赞、收藏、分享等动作快照 |
| `contentSurfacesBuilder` | 播放页初始化时一次 | 创建简介、评论和相关内容面板 |

```dart
late final ExamplePlaybackViewModel _session;
late final MediaPlaybackBinding _binding;

void initializePlaybackBinding() {
  _binding = MediaPlaybackBinding(
    engagementBuilder: _session.buildEngagementCapability,
    contentSurfacesBuilder: (host) => ExampleContentSurfaces(
      viewModel: _session,
      host: host,
    ),
  );
}
```

`engagementBuilder` 在 `SignalBuilder` 调用栈中执行。builder 读取的 signals 会驱动
计数、选中态和 busy 状态刷新。长期存活的 adapter 不捕获页面 view model，
也不需要构造后的 `attach` 调用。

没有互动和内容面板的平台使用缺省的 `const MediaPlaybackBinding()`。

## 5. 播放页包装层

供应商包装层管理 `MediaPlaybackViewModel` 生命周期，并把页面级能力接到
`MediaPlaybackPage`。最小 HLS 平台不需要额外 binding：

```dart
final class ExamplePlaybackPage extends StatefulWidget {
  const ExamplePlaybackPage({
    super.key,
    required this.detail,
    required this.entry,
    required this.adapter,
  });

  final MediaDetail detail;
  final MediaPlaybackEntry entry;
  final MediaPlatformAdapter adapter;

  @override
  State<ExamplePlaybackPage> createState() => _ExamplePlaybackPageState();
}

final class _ExamplePlaybackPageState extends State<ExamplePlaybackPage> {
  late final MediaPlaybackViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = MediaPlaybackViewModel(
      detail: widget.detail,
      initialEntry: widget.entry,
      adapter: widget.adapter,
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MediaPlaybackPage(viewModel: _viewModel);
  }
}
```

平台特有呈现经已有槽位注入：

- `binding`：互动和内容面板；
- `deviceControls`：亮度和音量控制；
- `presentation`：方向、全屏和系统栏；
- `contentTabsTrailing`、`tuningCacheEntry`、`tvControlBarExtras`：平台扩展 UI；
- `tvFallbackHome`：TV 返回栈底页面；
- `recoveryDialogBuilder`：解析恢复提示；
- `onPushPlayback`：相关内容跳转。

## 6. 静态应用装配

`lib/main.dart` 固定调用 `runPlatformApp()`。供应商选择只发生在
`lib/platform_app.dart`，不建立运行时注册表。

不需要 TV 模式和自定义系统呈现的平台可以采用最小装配：

```dart
import 'package:flutter/widgets.dart';
import 'package:vesper_media/app/app.dart';
import 'package:vesper_media/example/example_home_page.dart';

final class PlatformApp extends StatelessWidget {
  const PlatformApp({super.key});

  @override
  Widget build(BuildContext context) {
    return VesperApp(
      host: VesperAppHost(
        appTitle: 'Example Media',
        homeBuilder: (_) => const ExampleHomePage(),
      ),
    );
  }
}

Future<void> runPlatformApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PlatformApp());
}
```

供应商级启动工作也放在 `runPlatformApp()`：例如恢复认证、初始化持久化客户端、
创建下载控制器或读取设备模式。`main.dart` 不承载这些依赖。

`VesperAppHost` 的可选成员支持 TV 和宿主呈现：

- `tvModeListenable`：动态手机/TV 模式；不提供时固定手机模式；
- `refreshPreferredOrientations`：启动和恢复前台时刷新方向策略；
- `tvSystemUiStyle`、`systemUiStyleForBrightness`：系统栏策略。

当前 B 站装配保留玻璃质量初始化、设备模式判断、单例客户端和下载控制器注入，
可作为完整参考。

## 7. 可选能力

### Adapter 静态能力

- 弹幕：覆盖 `danmaku`，返回稳定的 `MediaDanmakuProvider` 实例；
- 历史：覆盖 `history`，实现 `MediaHistoryStore`；
- 清晰度：覆盖 `qualityPolicy`，并在每次解析结果中提供 `qualityOptions`；
- DLNA：覆盖 `dlnaConfig`，提供平台请求头和格式适配配置。

### Binding 动态能力

- 互动：`engagementBuilder` 返回按展示顺序排列的
  `MediaEngagementActionSpec`；没有投币概念的平台不声明 `coin`；
- 内容：`contentSurfacesBuilder` 返回 `MediaContentSurfaces`；
  `commentsTabLabel == null` 或评论 builder 返回 `null` 时评论 tab 隐藏。

下载仍属于供应商应用层，通过 `tuningCacheEntry` 注入，不属于 adapter 契约。

## 8. 验收

仓库根目录执行：

```bash
dart analyze lib test
flutter test --no-pub
git diff --check
```

自动化门禁：

- 最小 adapter 只覆盖 `resolvePlayback` 仍可编译；
- `lib/media/**` 不 import `lib/bili/**` 或 `lib/app/**`；
- `lib/main.dart` 和 `lib/app/app.dart` 不 import 具体供应商；
- 未声明能力时，对应 UI 不渲染；
- binding 的互动和内容状态随当前播放 entry 更新；
- 原 B 站回归测试保持全绿。

真机门禁：

- 首帧、持续播放和错误恢复；
- seek、切集、后台恢复和退出历史写入；
- 横竖屏、全屏和系统栏；
- 目标平台声明的字幕、清晰度、弹幕、DLNA；
- 失效播放地址重新解析。

接入完成的结构性判据：新供应商只新增 `lib/<provider>/**` 并修改
`lib/platform_app.dart`，没有修改 `lib/main.dart` 或 `lib/media/**`。

## 9. B 站参考实现

| 接缝 | 参考文件 |
|---|---|
| 静态应用装配 | `lib/platform_app.dart` |
| Adapter | `lib/bili/bili_media_platform_adapter.dart` |
| 详情、entry 与解析结果映射 | `lib/bili/common/services/bili_media_mapper.dart` |
| 清晰度和 codec 映射 | `lib/bili/common/services/bili_quality_mapping.dart` |
| 会话级互动 builder | `lib/bili/common/view_models/bili_playback_view_model.dart` |
| Binding 与播放页槽位 | `lib/bili/common/pages/bili_playback_page.dart` |
| 简介、评论和相关内容 | `lib/bili/common/pages/bili_playback_content_surfaces.dart` |
| 弹幕 provider | `lib/danmaku/services/bili_danmaku_provider.dart` |
| 历史 adapter | `lib/bili/common/services/bili_media_history_adapter.dart` |
| 设备控制 | `lib/bili/common/services/bili_device_controls.dart` |
| 通用播放编排 | `lib/media/playback/media_playback_view_model.dart` |
| 通用播放页 | `lib/media/playback/media_playback_page.dart` |
