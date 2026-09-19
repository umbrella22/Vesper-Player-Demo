# 收藏页与空间页设计

收藏与用户空间共用一类数据形状：一个头部（收藏夹 / UP 主）+ 一个可分页、可搜索的视频
列表。两个页面的差异在数据来源与操作集合：收藏页的列表来自用户自己的收藏夹，操作是
移出收藏夹与批量管理；空间页的列表来自某个 UP 主的投稿，操作是关注与打开播放。

线框图为低保真，只固定信息层级与交互位置，不固定像素。

## 1. 能力现状

### 1.1 收藏

| 能力 | 状态 | 位置 |
| --- | --- | --- |
| 判定某视频是否已收藏 | 已实现 | `fetchVideoEngagement`，`bili_client.dart:774-805` |
| 收藏 / 取消收藏 | 已实现 | `setVideoFavorite`，`bili_client.dart:894-950` |
| 读取收藏夹列表（仅判定归属） | 已实现（私有） | `_fetchFavoriteFolders`，`bili_client.dart:1062-1088` |
| 读取收藏夹内的视频列表 | **缺失** | — |
| 收藏夹增删改 | **缺失** | — |
| 批量移出收藏夹 | **缺失** | — |
| 独立收藏页面 | **缺失** | — |

模型的字段面同样偏窄。`BiliFavoriteFolder` 只有 `id`、`title`、`containsCurrentVideo`
三个字段（`bili_models.dart:129-139`），`title` 目前没有任何读取方。服务端返回的
`media_count`、`cover`、`attr`、`fav_state` 等字段没有被解析。

当前唯一的收藏界面是播放页互动条上的星标按钮，点击后加入**第一个收藏夹**，没有收藏夹
选择，也没有任何收藏夹浏览入口（`bili_playback_view_model.dart:369-376`、`:824-845`）。

### 1.2 空间页

`BiliUserSpacePage`（`lib/bili/app_mode/pages/bili_user_space_page.dart`）已实现完整的
加载、搜索、分页与错误处理，数据面完整但存在三处断口：

| 断口 | 现状 | 位置 |
| --- | --- | --- |
| 自己的空间进不去 | 我的页「空间」提示「空间页暂未接入。」 | `bili_hub_page.dart:511` |
| 认证标识未渲染 | `officialLabel`、`vipLabel` 已解析但页面不显示 | `bili_client_library.dart:68-96`，`bili_user_space_page.dart:509-593` |
| 关注数在 TV 缺失 | TV 头部不显示 `followingCount` | `bili_library_following_tv.dart:1329-1460` |

入口只有一个：关注列表的某一项（`bili_library_page.dart:1068-1071`）。页面本身按 mid
取数据，`fetchUserSpaceProfile(int mid)` 对任意 mid 都能工作，包括当前登录用户。

## 2. 需要补齐的接口

收藏页的列表数据没有现成接口可用，这是两个页面中唯一的阻塞项。

| 路径 | 用途 | 等级 | 备注 |
| --- | --- | --- | --- |
| `GET /x/v3/fav/resource/list` | 收藏夹内的视频列表 | 待实测 | 需要 `media_id`、`pn`、`ps`、`keyword`、`order`、`type`、`tid` |
| `GET /x/v3/fav/folder/created/list-all` | 收藏夹列表（含计数） | 已验证 | 已在用，但只解析了 3 个字段 |
| `POST /x/v3/fav/folder/add` | 新建收藏夹 | 待实测 | `title`、`privacy` |
| `POST /x/v3/fav/resource/batch-del` | 批量移出收藏夹 | 待实测 | `resources`、`media_id` |
| `POST /x/v3/fav/resource/deal` | 单个移出收藏夹 | 已验证 | 已在用 |

`list-all` 的响应包含每个收藏夹的视频计数，但字段名未确认，当前解析器只读取了
`id`/`title`/`fav_state`（`bili_client.dart:1100-1115`）。补上该字段后，收藏夹切换条上的
计数无需额外请求。切换条只在计数缺失时省略数字，不显示 `0`。

空间页不需要新接口。可选的增强数据来源：

| 路径 | 用途 | 等级 |
| --- | --- | --- |
| `GET /x/v3/fav/folder/created/list-all?up_mid={mid}` | 他人公开收藏夹 | 待实测 |
| `GET /x/relation/followings` | 关注列表 | 已验证 |
| `GET /x/relation/fans` | 粉丝列表 | 待实测 |

## 3. 收藏页

### 3.1 手机版线框

```text
┌───────────────────────────────────────────────┐
│ ←  我的收藏                              ⟳    │  GlassAppBar
├───────────────────────────────────────────────┤
│ [全部][默认收藏夹][番剧][学习]  ⟶   ＋        │  AppGlassSectionTabs + 新建
├───────────────────────────────────────────────┤
│ 🔍 搜索收藏内容                  排序：最近   │  搜索行 + 排序切换
├───────────────────────────────────────────────┤
│ ┌───────┐ 标题最长两行，超出省略               │
│ │ 16:9  │ 12.3万播放 · 12:34   UP主           │  _FavoriteVideoTile
│ │ 封面  │ 收藏于 09-12                          │
│ └───────┘                       [ 移出 ]       │
├───────────────────────────────────────────────┤
│ ┌───────┐ 标题……                              │
│ │ 封面  │ ……                                   │
│ └───────┘                       [ 移出 ]       │
├───────────────────────────────────────────────┤
│                  [ 加载更多 ]                  │
└───────────────────────────────────────────────┘
```

长按视频行进入多选模式：行左侧出现勾选框，AppBar 替换为「已选 N 项 / 移出 / 取消」。
移出是破坏性操作，执行前用 `showMediaGlassDialog` 确认，与离线缓存的删除确认保持
同一形态（`offline_cache_page.dart:224-291`）。

### 3.2 TV 版线框

```text
┌──────────────────────────────────────────────────────────────┐
│  我的收藏                                                     │
├──────────────┬───────────────────────────────────────────────┤
│ ● 全部  128  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐  │
│   默认   96  │  │ 封面   │ │ 封面   │ │ 封面   │ │ 封面   │  │
│   番剧   20  │  │ 标题   │ │ 标题   │ │ 标题   │ │ 标题   │  │
│   学习   12  │  │ 时长   │ │ 时长   │ │ 时长   │ │ 时长   │  │
│              │  └────────┘ └────────┘ └────────┘ └────────┘  │
│  [ 新建 ]    │  ┌────────┐ ┌────────┐ ...                    │
│              │  └────────┘ └────────┘                        │
│              │                 [ 加载更多 ]                   │
└──────────────┴───────────────────────────────────────────────┘
```

左侧收藏夹栏是 `TvFocusArea.rail`，右侧网格是 `TvFocusArea.content`。焦点进入网格时
侧栏收窄到 88 宽，失焦展开到 312，与 `_TvFollowingSpaceBrowser` 的收窄行为一致
（`bili_library_following_tv.dart:3-4`、`:188-192`）。空格键长按进入多选，遥控器返回键
先退出多选再退出页面。

### 3.3 组件落点

| 区域 | 组件 | 来源 |
| --- | --- | --- |
| 页面骨架 | `AppGlassScaffold` | `lib/app/design/app_glass_controls.dart:11` |
| 顶栏 | `GlassAppBar` | 同上 |
| 收藏夹切换（手机） | `AppGlassSectionTabs` + `AppGlassNavigationItem` | `app_glass_controls.dart:628`、`:187` |
| 收藏夹栏（TV） | `TvFocusGroupScope` + `TvFocusableSurface` | `lib/media/tv/media_tv_focusable.dart:71`、`:533` |
| 视频行（手机） | 新增 `_FavoriteVideoTile`，复用 `_LibraryVideoTile` 的封面比例与排版 | 参照 `bili_library_phone.dart:30-189` |
| 视频卡（TV） | `BiliTvVideoCard` | `lib/bili/tv_mode/widgets/bili_tv_video_card.dart:6` |
| 空态 | `_FavoriteEmptyView` | 参照 `bili_library_phone.dart:221-243` |
| 错误态 | `_FavoriteErrorView` | 参照 `bili_library_phone.dart:191-219` |
| 加载更多 | `_FavoriteLoadMore` | 参照 `bili_library_phone.dart:3-28` |
| 移出确认 | `showMediaGlassDialog` | `lib/media/player/media_glass_sheet.dart:204` |

TV 网格栅格沿用库页参数：`SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260,
mainAxisSpacing: 24, crossAxisSpacing: 22, childAspectRatio: 1.08)`，外层 padding 取
`tvFocusSafeInset`（`bili_library_page.dart:995-1019`）。

### 3.4 状态模型

页面持有一个 `signals` 视图模型，形状对齐 `OfflineCacheViewModel`
（`lib/download/view_models/offline_cache_view_model.dart:85-153`）：

| 信号 | 类型 | 说明 |
| --- | --- | --- |
| `_folders` | `List<BiliFavoriteFolder>` | 收藏夹列表，含计数 |
| `_activeFolderId` | `int?` | null 表示「全部」 |
| `_items` | `List<BiliFavoriteItem>` | 当前收藏夹内容 |
| `_loading` / `_loadingMore` | `bool` | 首次加载与翻页分开，翻页不遮罩列表 |
| `_hasMore` | `bool` | 由 `pn * ps < media_count` 判定 |
| `_keyword` | `String` | 服务端搜索关键词 |
| `_order` | `FavoriteOrder` | 最近收藏 / 最多播放 / 最多收藏 |
| `_selectedIds` | `Set<int>` | 多选集合，空集表示非多选模式 |
| `_error` | `String?` | 错误文案 |
| `_authenticationRequired` | `bool` | 未登录时置位，不发请求 |

派生量用 `computed`：`isSelectionMode`（`_selectedIds` 非空）、`activeFolder`
（按 `_activeFolderId` 在 `_folders` 中查找）。

切换收藏夹时把 `_items` 清空并重置 `_page`，避免上一个收藏夹的内容在切换瞬间残留。
翻页请求带请求代数守卫，迟到的响应不写入当前列表——`BiliUserSpacePage._requestGeneration`
是既有实现（`bili_user_space_page.dart:54`）。

### 3.5 状态与文案

| 状态 | 触发条件 | 呈现 |
| --- | --- | --- |
| 首次加载 | `_loading && _items.isEmpty` | 居中 `CircularProgressIndicator` |
| 未登录 | `!_authenticationRequired` 为假 | 锁图标 + 「登录后查看收藏」+ 主按钮 |
| 空收藏夹 | 请求成功且列表为空 | 「这个收藏夹还是空的。」+ 「去逛逛」 |
| 无匹配 | 关键词搜索后为空 | 「没有匹配的收藏内容。」 |
| 翻页失败 | `_loadingMore` 结束且错误 | 列表底部内联错误条 + 重试，保留已加载内容 |
| 移出成功 | 服务端 `code == 0` | 移除该行；若当前收藏夹变空则回到空态 |
| 移出失败 | 非 0 | 行保持原位，`biliErrorMessage` 提示 |

文案遵循既有措辞：错误态用「加载失败：」前缀，登录态用「登录状态已失效，请重新登录后
再试。」（`bili_user_space_page.dart:353-362`）。

## 4. 空间页改造

### 4.1 手机版线框

```text
┌───────────────────────────────────────────────┐
│ ←  UP 主空间                                  │  GlassAppBar
├───────────────────────────────────────────────┤
│  ┌────┐  名称  [认证] [大会员]                 │  头部：新增两个徽标
│  │头像│  UID 12345 · 签名两行                   │
│  └────┘   [投稿 128] [粉丝 1.2万] [关注 96]    │
├───────────────────────────────────────────────┤
│ 🔍 搜索投稿标题或 BV 号                        │  已实现
├───────────────────────────────────────────────┤
│  投稿视频                               ⟳     │
│ ┌───────┐ 标题两行                             │
│ │ 封面  │ 09-12 · 12.3万播放                    │
│ └───────┘                                       │
├───────────────────────────────────────────────┤
│                  [ 加载更多 ]                  │
└───────────────────────────────────────────────┘
```

改动集中在两处：头部增加 `officialLabel` 与 `vipLabel` 徽标；关注/粉丝统计变成可点击项，
点击进入关注列表或粉丝列表。统计数字为 0 时（`fromFollowing` 占位模型）不渲染该统计，
避免出现「粉丝 0」的假数据。

### 4.2 自己的空间

我的页的「空间」入口改为打开同一个页面，`mid` 取当前登录用户：

```dart
BiliHubViewModel.profile.value.mid
```

`profile` 已在页面的 `SignalBuilder` 内可用（`bili_hub_page.dart:453-457`、`:504`）。
`mid` 为 0 或负值时退回未登录提示，不发请求。

自己的空间与他人空间的结构差异只在操作集合：自己的空间不显示关注按钮，显示「编辑资料」
占位；此差异通过构造参数 `isSelf` 控制，不派生第二个页面。

### 4.3 TV 版

TV 已有一个内嵌的关注 + 空间双栏浏览器 `_TvFollowingSpaceBrowser`
（`bili_library_following_tv.dart:10-46`），它承担了与手机版 `BiliUserSpacePage` 相同的
职责。改造项只有一条：头部统计补齐 `followingCount`，与手机版保持一致。

独立全屏空间页在 TV 上不新增。关注栏的收窄/展开已覆盖同一交互，再开一层页面会让遥控器
返回栈变深。

## 5. 设计令牌

两个页面消费 `AppVisualTheme.of(context)` 的字段，不写裸色值
（`lib/media/design/app_visual_theme.dart:221-440`）：

| 用途 | 令牌 |
| --- | --- |
| 页面背景 | `visualTheme.background` |
| 卡片/行表面 | `visualTheme.surface` |
| 主/次/三级文字 | `visualTheme.textPrimary` / `.textSecondary` / `.textTertiary` |
| 分隔线 | `visualTheme.divider` |
| 破坏性操作（移出收藏） | `visualTheme.destructive` |
| 圆角 | `AppVisualTokens.contentRadius`（8）用于卡片，`controlRadius`（14）用于按钮 |
| 最小点击区 | `AppVisualTokens.minimumTapTarget`（44） |
| 动效 | `AppVisualTokens.motionDuration(context, AppVisualTokens.overlayDuration)` |

主题变体由 `VesperApp` 在根部选择：TV 固定 `AppVisualTokens.tvTheme()`，手机按
`AppThemeController.themeMode` 在亮/暗之间切换（`lib/app/app.dart:114-128`）。页面不感知
变体，只消费令牌。

## 6. 不变量

- 收藏页的列表数据必须来自 `/x/v3/fav/resource/list`，不得由 `/x/v3/fav/folder/created/list-all`
  的计数推断内容；
- 移出收藏夹后必须重新读取当前收藏夹与 `fetchVideoEngagement`，两者都可能已变化；
- 未登录时不发任何收藏或空间请求，先走登录流程；
- 切换收藏夹会清空上一收藏夹的列表，旧代数响应不得写入新列表；
- 空间页的 `mid` 只来自构造参数或当前用户 profile，不从 URL 或自由输入派生；
- TV 与手机共用同一视图模型与数据源，只在呈现层分支。

## 7. 回归入口

- `test/bili_services_test.dart`：新增收藏夹列表解析、收藏内容列表解析与移出参数的用例。
- `test/media_playback_shell_test.dart`：现有互动条的 busy 态与回滚用例需要覆盖「选择收藏夹」
  这一新增分支。
- `test/bili_library_page_test.dart`（新增）：收藏页的分页、切换收藏夹、多选与空/错误态。
- `test/bili_user_space_page_test.dart`（新增）：自己空间入口、徽标渲染、统计为 0 的不渲染规则。
- TV 侧沿用 `test/media_playback_shell_test.dart` 的焦点用例形态，覆盖收藏夹栏与网格的
  焦点区域切换。
