# 收藏 / 空间 / 互动 / 画质 进度追踪

本文件是五份设计文档的进度对照表，用于回答「哪些已经落地、哪些是缺口、哪些卡在实测」。
它不替代设计文档：契约、参数与界面细节仍以原文档为准。

- 五份文档：`bili-favorites-space-ui-design.md`、`bili-interaction-api-notes.md`、
  `bili-danmaku-comment-api-notes.md`、`bili-playback-quality-hdr-notes.md`、
  `bili-portrait-playback-notes.md`。
- 本文件的状态以代码与测试为准，不以文档描述为准。

## 0. 基线与核对方式

| 项 | 值 |
| --- | --- |
| 核对时间 | 2026-09-17 |
| 代码基线 | `9e7d99c`（2026-09-16 22:14:25 +0800，分支 `main`） |
| 文档撰写时间 | 2026-09-16 17:56–17:57 |
| `flutter analyze` | 无问题 |
| `flutter test` | 655 项通过（阶段 2–5 实施前为 605 项） |
| Android `arm64-v8a` debug 构建 | `cd android && ./gradlew assembleDebug` 成功，产物含 19 个 arm64-v8a 原生库 |

**关键前提：四份文档写于基线提交之前约 4 小时，而该提交本身就是收藏与空间功能的落地提交
（`bili_favorites_page.dart`、`bili_favorites_view_model.dart`、`bili_client_favorites.dart`
均在该提交中新增）。因此文档 §1「能力现状」描述的是实现前的快照，其中收藏相关的多条
判断在文档落笔时已经过期，不能按「待实现的缺失项」阅读。**

核对方式：`git log`/`git show` 确认提交范围，逐个符号读取实现与测试文件，
运行完整 `flutter analyze` 与 `flutter test`。状态分三类标注：

| 标注 | 含义 |
| --- | --- |
| 已落地 | 有实现且有测试锁定 |
| 缺口 | 无实现，或实现存在但行为与设计不符 |
| 待实测 | 实现前必须先跑通真实登录态，见 §6 |

## 1. 阶段状态总表

| 阶段 | 计划内容 | 状态 | 说明 |
| --- | --- | --- | --- |
| 0 | 确认数据契约 | 大部分完成 | 收藏读取链路已实现并被测试锁定；互动写接口已按契约实现，未联调 |
| 1 | 收藏浏览与空间 | 完成 | 收藏页、自己的空间、徽标、TV 关注数均已落地；返回后刷新已补 |
| 2 | 收藏管理与 TV | 完成（除待实测两项） | 播放页选择器、单条/批量移出、多选、TV 收藏均已实现 |
| 3 | HDR 与画质表达 | 完成 | 三态模型、按钮角标、会话信息行、能力探测、告警分类均已接入 |
| 4 | 评论点赞与普通弹幕发送 | 完成（未联调） | 评论点赞按 ID 共享 + 乐观回滚；弹幕发送成功后才插入 |
| 5 | 弹幕选中与互动 | 部分完成 | 暂停后点选 + 本地屏蔽已实现；点赞与撤回需实测后接入 |
| 6 | 竖屏视频播放 | 服务端契约已接入 | `dimension` 解析（详情顶层 + 分 P + PGC 分集）已落地并被测试锁定；容器/控件/全屏/PiP/弹幕接入未开始；feed/search 维度字段待实测 |

## 2. 阶段 0：数据契约

### 2.1 已落地

| 契约项 | 落点 | 锁定用例 |
| --- | --- | --- |
| 收藏夹列表（含计数） | `fetchFavoriteFolders`（`bili_client_favorites.dart`） | `bili_favorites_test.dart`「folder metadata preserves unknown counts and real zero」 |
| 收藏夹内容列表 | `fetchFavoriteItems`（同上），走 `BiliApiPaths.favResourceList` | 同上文件；分页与 `has_more` 用例 |
| 搜索与排序 | `keyword` 走服务端、`BiliFavoriteOrder` 三档 | 「search and sort are folder scoped and trust has_more」 |
| 失效视频与其他资源类型 | `BiliFavoriteItem.isAvailable` | 「keeps unavailable videos and other resource kinds visible」 |
| 未知计数与真实 0 | `BiliFavoriteFolder.mediaCount` 为 `int?` | 「folder metadata preserves unknown counts and real zero」 |
| 账号切换 | `BiliClient.sessionRevision` + `_accountSessionRevision` | 「logout during request cannot restore private contents」 |
| 请求取消与迟到结果 | 传输层取消语义 | `bili_transport_cancellation_test.dart`（7 个用例） |

收藏页还实现了跨页去重（`resourceKey = '$id:$type'`）、翻页失败保留已加载内容、
搜索态下不采信 `media_count` 作为匹配总数（`totalCount` 置 null）。

### 2.2 未确认的细节

以下不是缺口，但属于「文档标为待实测、实现已按某个假设编码」的项，实测时应一并回填：

| 项 | 当前实现假设 | 风险 |
| --- | --- | --- |
| `type` 参数 | 收藏内容列表固定发 `type: 0`，代码注释称 `type=1` 会变成跨夹搜索 | 若服务端语义相反，搜索会跨夹泄漏 |
| `has_more` 与 `media_count` 优先级 | `has_more` 优先，缺失时用 `pn * ps < media_count` 推导 | 推导式在计数含失效项时可能多翻一页空结果 |
| 收藏内容请求的 referer | 未显式传入，落到 `biliDefaultReferer` | 与播放页路径使用的 `biliVideoReferer` 不一致 |
| 收藏夹列表的 CSRF 前置 | 新公开路径 `fetchFavoriteFolders` 不调 `requireCsrfToken()`；播放页私有路径 `_fetchFavoriteFolders` 会调 | 两条同族 GET 的前置条件不同，需确认是否必需 |

### 2.3 两条收藏夹读取路径（需在阶段 2 前定论）

| 路径 | 用途 | 参数差异 | 调用方 |
| --- | --- | --- | --- |
| `_fetchFavoriteFolders(detail)`（`bili_client.dart` 私有） | 判断某视频的收藏归属 | 带 `rid`，因此 `fav_state` 有意义 | `fetchVideoEngagement`、`setVideoFavorite` |
| `fetchFavoriteFolders()`（`bili_client_favorites.dart` 公开） | 收藏页浏览收藏夹 | 不带 `rid`，`containsCurrentVideo` 恒为 false | `BiliFavoritesViewModel` |

两条路径都指向 `/x/v3/fav/folder/created/list-all`，但参数、referer、CSRF 前置均不同。
阶段 2 的「播放页 / 收藏页状态同步」必须让两者收敛到同一个真相源，否则播放页选择器与
收藏页列表可能给出不同的归属判断。

## 3. 阶段 1：收藏浏览与空间

### 3.1 已落地

| 交付项 | 落点 |
| --- | --- |
| 手机「我的」收藏入口 | `bili_hub_mine.dart` 的 `bili-mine-favorites` → `BiliHubPage._openFavorites` |
| 收藏夹切换 | `AppGlassSectionTabs` + `BiliFavoritesViewModel.selectFolder` |
| 搜索 | 服务端 `keyword`，草稿提交后才请求 |
| 排序 | `BiliFavoriteOrder` 三档，`showMediaGlassSheet` 选择 |
| 分页 | 首次加载与翻页分离，翻页错误内联展示且不遮罩列表 |
| 打开播放 | `_openVideo` → `BiliPlaybackPage` |
| 空夹 / 无结果 / 未登录 / 加载失败态 | `_FavoriteStatus` 四种文案分支 |
| 自己的空间 | `BiliHubPage._openOwnSpace`，`mid` 取自 `profile`，非法值退回登录 |
| 认证与大会员徽标 | `bili_user_space_page.dart` 头部渲染 `officialLabel` / `vipLabel` |
| 未知统计不渲染 | 三个统计均为 `int?`，`if (count case final int c)` 条件渲染 |
| TV 关注数 | `_TvFollowingSpaceProfileHeader` 补 `followingCount` |

「全部」tab：**实现中不存在**，页面只列真实收藏夹，`_activeFolderId` 无 null=全部 语义。
这与「首版按收藏夹浏览、『全部收藏』单独规划」的调整一致，无需改代码。

### 3.2 缺口

| 缺口 | 说明 | 落点 |
| --- | --- | --- |
| ~~播放返回后列表不刷新~~ | 已修复：`_openVideo` / TV 打开播放返回后调用 `_viewModel.refresh()` | 已关闭 |

## 4. 阶段 2：收藏管理与 TV（已实现）

### 4.1 已交付

| 交付项 | 实现方式 |
| --- | --- |
| 播放页收藏夹选择器 | `_FavoriteFolderPickerSheet`：加载归属、预选已有收藏夹，确认后提交 |
| 只提交增删差异 | `BiliFavoriteSelection.diff` 计算差异；`applyVideoFavoriteSelection` 只移出显式取消的收藏夹 |
| 单条移出 | 收藏页行内入口 + 离线缓存同形态的 `showMediaGlassDialog` 确认 |
| 批量移出 | 多选模式 + `removeItems`，用已验证的 `favResourceDeal` 批量提交 |
| 多选模式 | `isSelectionMode` 与 `selectedResourceKeys` 独立：允许「已选 0 项」 |
| 新建收藏夹 | `_FolderCreateSheet` → `createFavoriteFolder`（`/x/v3/fav/folder/add`，待实测） |
| TV 收藏浏览 | `BiliFavoritesTvView`：左栏收藏夹 + 右网格，共用手机版 view model |
| TV 管理入口 | 「管理」进入多选；返回键先退出多选再退出页面 |

### 4.2 行为不变量（已由测试锁定）

- 从 A 夹移出后 B 夹归属保留：`applyVideoFavoriteSelection` 只提交 `removeFolderIds`；
- 取消选择不提交：`selection.isEmpty` 时不发写请求；
- 移出失败不丢行：列表与选择保持原样，可直接重试；
- TV 首焦点在收藏夹栏，避免网格抢焦后侧栏立即收窄。

### 4.3 仍待实测

`/x/v3/fav/folder/add` 与 `/x/v3/fav/resource/batch-del` 的响应结构已按合理假设解析
（`createFavoriteFolder` 兼容 `id` / `media_id` / `folder.id`），但未经真实登录态验证。

## 5. 阶段 3/4/5：HDR、互动与弹幕

### 5.1 阶段 3：HDR 与画质表达（已实现）

新增 `lib/media/models/media_hdr_status.dart`，把三条信息轴分开：

| 轴 | 来源 | 取值 |
| --- | --- | --- |
| `source` | 清单解析（codec 字符串 + 清晰度 ID） | none / hdr10 / hlg / dolbyVision / unknown |
| `playability` | 轨道 `support.status` | notApplicable / playable / unknown / unplayable |
| `output` | 能力探测 | unknown / confirmed / unconfirmed / unsupported |

关键约束：`isOutputConfirmed` 只在探测返回已知 HDR 类型 **且** 输出为 `p010`
**且** 置信度为 `sessionProbe` 时为真。其余情况界面显示「输出未确认」，
绝不显示「已开启 HDR」。探测失败静默降级为未确认，不阻塞起播。

落点：清晰度按钮角标（`TuningOptionBadge`）、会话信息 HDR 行、`hdrNativeFrameUnsupported`
告警单独归类（按 `reasonRawValue` 判别，不按只有单一取值的枚举——否则
`runtimeTrackRejected` 会被误判为 HDR 告警）。

**仍未做**：DV 独立编码分组（`codecIdentityForTrack` 仍把 DV 折入 HEVC），
因为会撞上 `media_contract_test.dart` 与 `media_playback_shell_test.dart` 锁定的
「展示与身份分离」，需要先决定改测试意图还是保留折入。

### 5.2 阶段 4：评论点赞与普通弹幕发送（已实现，未联调）

| 能力 | 实现 |
| --- | --- |
| 评论点赞 | `BiliClient.setVideoCommentLike`（`/x/v2/reply/action`）；状态在 `BiliPlaybackViewModel` 按评论 ID 共享，主列表与楼中楼同步 |
| 乐观更新与回滚 | 先翻转状态与计数，失败回滚前值；不可解析的计数保持原文案不做增减 |
| 连点防护 | `pending` 标记阻止重复提交 |
| 弹幕发送 | `BiliClient.postVideoDanmaku`（`/x/v2/dm/post`）；`MediaDanmakuSessionSender` 扩展能力 |
| 成功后才插入 | 服务端返回 dmid 后才写入本地条目；分片刷新时参与快照重建，按 dmid 去重 |
| 超时保留草稿 | 超时返回 `pending`，不插入、不自动重发，界面提示对账 |

### 5.3 阶段 5：弹幕选中（部分实现）

`MediaDanmakuOverlay` 增加 `onEventSelected`：**仅在暂停时**接收触摸，
播放中仍然完全忽略指针事件，不抢占播放器手势。命中测试与绘制共用同一份
几何计算，从后往前遍历以命中上层弹幕。

点选面板提供「复制内容」与「按 senderHash 屏蔽/取消屏蔽发送者」。
`MediaDanmakuEvent` 新增 `hasServerId` 与 `senderHash`：源缺少 dmid 时用合成键，
该键只用于本地去重与渲染，**不用于服务端操作**——面板对这类弹幕不提供
需要服务端标识的动作。

**未做**：弹幕点赞与本人弹幕撤回，两者都需要实测确认端点与参数。

## 6. 待实测清单（需要真实登录态）

以下接口在实现前必须先用真实会话跑通，并回填契约表。未确认前不得编造默认语义。

| 接口 | 用途 | 影响阶段 |
| --- | --- | --- |
| `POST /x/v3/fav/folder/add` | 新建收藏夹 | 2 |
| `POST /x/v3/fav/resource/batch-del` | 批量移出 | 2 |
| `POST /x/v2/dm/post` | 发送弹幕（`plat`、`rnd` 取值） | 4 |
| `POST /x/v2/dm/thumbup/add` vs `/x/v2/dm/action` | 弹幕点赞（路径与参数二选一） | 5 |
| `POST /x/v2/dm/retract` | 撤回弹幕（`cid` 或 `oid`） | 5 |
| `POST /x/dm/report/add` | 举报弹幕（理由枚举） | 后续批次 |
| `POST /x/relation/modify` `act=5\|6` | 拉黑 / 取消拉黑 | 后续批次 |
| `GET /x/relation/blacks` | 黑名单列表 | 后续批次 |
| `GET /x/relation/fans` | 粉丝列表 | 后续批次 |
| `GET /x/v3/fav/resource/list` 参数复核 | §2.2 的四项假设 | 2 |

## 7. 五条调整逐条对照

| 调整 | 代码现状 | 剩余工作 |
| --- | --- | --- |
| 「全部收藏」单独规划 | 已符合：无「全部」tab，无 null=全部 语义 | 仅需改原文档 |
| 未知值与真实 0 分开 | 已符合：`mediaCount` 与三个空间统计均为 `int?`，有测试锁定；多选用**独立状态**，允许「已选 0 项」 | 仅需改原文档 |
| 收藏按钮改为选择收藏夹 | 已实现：选择器预选归属，确认后只提交增删差异 | 仅需改原文档 |
| HDR 区分来源与实际输出 | 已实现：三态模型 + 角标 + 会话信息行，未确认时显示「输出未确认」 | 原文档补三态约束 |
| 互动采用不同提交策略 | 已实现：评论点赞乐观更新并回滚；弹幕发送成功后才插入，超时保留草稿不重发 | 原文档替换 §10 第 5 步 |

## 8. 单列评估，不进入本批次

跨夹「全部收藏」、收藏夹重命名与删除、粉丝列表与他人公开收藏、服务端黑名单与举报、
历史弹幕、DV 独立编码分组、画质偏好记忆（应保存质量与编码意图，不得保存只对当前会话
有效的轨道 ID）。mode 8/9 沿用现有「分类并丢弃、不执行」的边界，不重开。

## 9. 执行顺序（阶段 2–5 已完成）

| 序 | 内容 | 状态 |
| --- | --- | --- |
| 1 | 修 `_openVideo` 返回后不刷新 | 已完成 |
| 2 | 收藏页单条移出（已验证的 `favResourceDeal`） | 已完成 |
| 3 | 播放页收藏夹选择器 + 只提交增删差异 | 已完成 |
| 4 | 多选模式（独立选择状态，含「已选 0 项」） | 已完成 |
| 5 | 新建收藏夹、批量移出 | 已实现，端点待实测 |
| 6 | TV 收藏浏览与管理入口 | 已完成 |
| 7 | HDR 三态表达与能力探测接入 | 已完成（DV 分组单列） |
| 8 | 评论点赞、弹幕发送 | 已实现，端点待联调 |

## 10. 回归入口（已更新为实际文件名）

| 范围 | 文件 |
| --- | --- |
| 收藏契约与 ViewModel | `test/bili_favorites_test.dart` |
| 收藏页 Widget | `test/bili_favorites_page_test.dart` |
| TV 收藏浏览 | `test/bili_favorites_tv_test.dart` |
| 空间资料与徽标 | `test/bili_user_space_profile_test.dart` |
| 空间分页 | `test/bili_user_space_pagination_test.dart` |
| Hub 分页与草稿 | `test/bili_hub_pagination_test.dart` |
| 传输取消 | `test/bili_transport_cancellation_test.dart` |
| HDR 三态与源判定 | `test/media_hdr_status_test.dart` |
| 弹幕发送与快照 | `test/bili_danmaku_provider_test.dart` |
| 弹幕发送栏 | `test/bili_danmaku_composer_test.dart` |
| 弹幕点选与触摸边界 | `test/media_danmaku_layer_test.dart` |
| 播放壳互动 | `test/media_playback_shell_test.dart` |
| 播放 view model（收藏夹选择、评论点赞） | `test/bili_playback_view_model_test.dart` |

设计文档 §7 中提到的 `test/bili_library_page_test.dart` 与
`test/bili_user_space_page_test.dart` 并不存在，对应覆盖在 `bili_favorites_page_test.dart`
与 `bili_user_space_profile_test.dart` 中。

## 11. 文档漂移清单（原文档需要修正的条目）

| 文档 | 位置 | 问题 |
| --- | --- | --- |
| 收藏与空间 | §1.1 | 「`title` 目前没有任何读取方」已过期，收藏页 tab 与语义标签都在用 |
| 收藏与空间 | §1.1 | 「读取收藏夹列表（仅判定归属）已实现（私有）」未反映新增的公开路径 |
| 收藏与空间 | §1.2 | 「关注数在 TV 缺失」已修复 |
| 收藏与空间 | §3.1/§3.2/§3.4 | 线框里的「全部」tab 与 `_activeFolderId` 的 null 语义 |
| 收藏与空间 | §7 | 回归入口文件名与实际不符 |
| 收藏与空间 | §3.1 | 未包含「播放返回后刷新」与「单条移出」之外的排序/搜索已有实现标记 |
| 互动接口 | §10 第 5 步 | 限频验证方式改为模拟响应测试 |
| 互动接口 | §7 | 指出评论点赞的展示层已存在（`liked` 已解析），缺的是写方法与可点 UI |
| 弹幕与评论 | §1 能力表 | 「评论点赞 不提供」应改为「只读展示，写操作未提供」 |
| 画质与 HDR | §5.2/§5.4 | 补「SDK 返回未知时不得显示已开启 HDR」的三态约束 |
| 全部四份 | 全文 | 引用的 `bili_client.dart` / `bili_quality_mapping.dart` 行号在 `9e7d99c` 后已漂移，建议改用符号名而非行号 |

## 12. 阶段 6：竖屏播放（服务端契约已接入）

SDK 0.6.2 基线确认（`pubspec.lock` 解析 0.6.2）。`bili-portrait-playback-notes.md` §2.1
标注的「模型与解析尚未接入」已完成：

| 契约项 | 落点 | 锁定用例 |
| --- | --- | --- |
| 声明尺寸值类型（含旋转派生） | `BiliVideoDimension`（`bili_models.dart`），`displayWidth/displayHeight/displayAspectRatio` | `bili_services_test.dart`「applies server rotation to the layout hint」 |
| 详情顶层 `dimension` | `BiliVideoDetail.dimension`，`_parseVideoDetail` 解析 | 同文件「parses top-level and per-page dimensions independently」 |
| 分 P `pages[].dimension` | `BiliVideoPageEntry.dimension`，多 P 各自携带 | 同上 |
| PGC 分集 `dimension` | `bili_client_region.dart` 分集构造，防御式解析 | 同文件缺省路径 |
| 缺失 / 非正数 / 畸形 → 未知 | `_parseVideoDimension`（`bili_client.dart`）统一收口 | 同文件「treats missing, non-positive and malformed sizes as unknown」 |

验证：`flutter analyze` 无问题；`flutter test` 684 项通过（含新增 3 项）。

仍未开始（按 `bili-portrait-playback-notes.md` §4 推进）：容器按比例布局、
`controlLayout`/`isFullscreen` 接入、全屏方向按内容选择、PiP 显式比例、`contentRect`
弹幕对齐、`_HomeVideoItem.vertical` 接线。feed/search 响应中的维度字段名需接口样本确认
（§4.6），确认前 `vertical` 保持 `false`。
