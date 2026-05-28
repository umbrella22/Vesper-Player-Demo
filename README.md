# Vesper Player Demo

Vesper Player Demo 是一个 Flutter 移动端客户端 demo，核心目标是验证
`vesper-player-sdk` 在真实业务外壳中的集成可行性。项目用视频平台客户端
常见的浏览、登录、搜索和播放流程作为测试场景，观察 Vesper Player 在
Android 原生 DASH、iOS DASH-to-HLS bridge、progressive 后备、本地会话、
构建打包等链路里的表现。

**本项目不是任何平台的官方客户端，也不是完整产品。它只用于技术验证、学习和
兼容性测试，不隶属于、代表或关联任何视频平台。使用本项目时请遵守目标服务的
用户协议、版权规则和当地法律法规。**

**本项目没有任何授权的 Testflight 发放以及任何收费版本，请注意辨别和考虑安全性问题。
Vesper Player Demo 从未在任何平台上架和收费（包括AppStore与Testflight、Google Play 等）**

**如果您在任何平台上看到有人以收费方式提供本项目的服务或应用，请注意这是未经授权的行为，并且与我们的原始意图不符。我们强烈谴责将本项目用于商业盈利的行为，由此引发的任何安全风险与此项目无关。**

## 当前项目已有功能

- App 模式：面向手机触控场景，提供视频平台客户端风格的首页、搜索、登录、播放
  和离线缓存入口。
- TV 模式：面向大屏和遥控器操作场景，提供更适合横屏浏览的首页和视频
  观看体验。
- 通过本地 path dependency 接入 `vesper-player-sdk`，用于验证 Vesper Player
  在 Flutter 移动应用中的真实集成效果。
- 已实现登录态、搜索、播放历史、分 P 播放、SDK 调试信息展示等接近真实
  客户端的基础链路。

## 功能介绍

### 浏览与账号

- 视频平台国际版风格。
- 通过目标视频平台 Web 登录接口实现二维码登录。
- 登录 cookie 本地持久化，并在下次启动时恢复登录状态。
- 首页 feed、关键词搜索、BV 号直达和视频链接粘贴打开。
- 搜索结果和视频卡片可直接进入播放页。
- 播放历史本地持久化，并展示在首页。

### 播放验证

- 支持视频多分 P 选择、番剧分集选择。
- 播放页有意关闭评论和弹幕控制，把重点放在播放器接入本身。
- 播放页下方展示视频元数据和 Vesper SDK session 信息，方便调试当前流。

### 本地数据

- 播放历史存储在 app support 目录下的项目数据文件中。
- 登录 cookie session 存储在 app support 目录下的项目数据文件中。
- 旧版临时目录数据会在下次加载时自动迁移到 app support 目录。

## 当前范围

- Android：`minSdk 26`，当前 release 目标为 `arm64-v8a`，仅提供ARM64。
- iOS：支持客户端、登录、搜索、feed、DASH-to-HLS bridge
- Flutter desktop：当前阶段不在目标范围内。
- 目标视频平台流程主要面向 guest Web API 能解析的公开视频。需要登录、地区受限
  或受保护的视频可能无法解析或播放。

## 工作区结构

- App 根目录：当前 Flutter 仓库。
- Flutter 业务代码：`lib/`。
- 本地播放器 SDK：`third_party/vesper-player-sdk`，作为 git submodule 引入。
- Flutter 通过 `pubspec.yaml` 中的本地 path dependency 消费 Vesper SDK。
- 原生辅助脚本：`scripts/`。

```text
lib/
  app/        App shell 和导航
  bili/       目标视频平台 API、WBI、搜索、详情、播放和历史
  player/     Player SDK 参数辅助逻辑
  danmaku/    为 SDK 实验和测试保留的弹幕解析工具
  download/   离线缓存任务规划和导出入口
scripts/
  prepare_flutter_workspace.sh
  prepare_ios_build.sh
  build_ios_no_codesign.sh
third_party/
  vesper-player-sdk/
```

## 初始化

```sh
git submodule update --init --recursive
bash scripts/prepare_flutter_workspace.sh
bash third_party/vesper-player-sdk/scripts/ios/build-player-ffi-xcframework.sh release
flutter analyze
flutter test
flutter run
```

## 构建

```sh
flutter build apk --release --target-platform android-arm64
bash scripts/build_ios_no_codesign.sh
```

Android 默认只构建 `arm64-v8a`。如果修改 Android release 配置，请保持
`android/gradle.properties` 中的 ABI 设置和 `android/app/build.gradle.kts` 的
打包排除规则一致，避免 transitive native plugin 把非 arm64 `.so` 文件带进
最终 APK。

iOS 推荐使用 `bash scripts/build_ios_no_codesign.sh`。如果直接运行 raw
`xcodebuild`，之后需要重新执行 `bash scripts/prepare_flutter_workspace.sh`，
再回到 `flutter analyze`、`flutter test` 或 `flutter run`。

## 验证记录

当前仓库阶段建议至少跑：

```sh
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
bash scripts/build_ios_no_codesign.sh
```

涉及目标视频平台 API、播放地址解析或真实播放链路的改动，仍然建议在真机上做一次
端到端 smoke test。公开视频可用性、guest API 返回结构和流媒体可用性都可能在
服务端独立变化。

## 协议

本仓库根目录代码使用 Apache License 2.0 开源，见 [LICENSE](LICENSE)。

`third_party/vesper-player-sdk` 是独立的 SDK 子模块，保留其自己的许可证、版权
声明和上游项目边界。使用或分发该子模块时，请同时遵守它自己的 license 文件。

## 致谢

开发过程中参考了以下开源项目和作者公开资料，用于理解公开视频 API 行为、
登录流程、搜索流程、播放工作流和客户端交互设计：

- Nemo2011 的公开视频 API 相关项目
- nICEnnnnnnnLee 的视频下载工具项目
- zhw2590582/ArtPlayer
- yichengchen 的 tvOS 客户端 demo

本项目没有复制这些项目的源码；相关项目的许可证和版权归原作者所有。
