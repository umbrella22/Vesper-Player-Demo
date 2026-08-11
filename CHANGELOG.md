# Changelog

## [1.8.0](https://github.com/umbrella22/Vesper-Player-Demo/compare/vesper_media-v1.7.0...vesper_media-v1.8.0) (2026-08-11)


### Features

* sdk修正 ([ddf9583](https://github.com/umbrella22/Vesper-Player-Demo/commit/ddf958391092f09538e62fdc23e6748f84bb92db))
* 重构代码 ([e0b565f](https://github.com/umbrella22/Vesper-Player-Demo/commit/e0b565f74ed6f870c8595cd4ae90ec6d4ee9246c))

## [1.7.0](https://github.com/umbrella22/Vesper-Player-Demo/compare/vesper_media-v1.6.0...vesper_media-v1.7.0) (2026-08-04)


### Features

* Enhance TV mode functionality and UI responsiveness ([d9088aa](https://github.com/umbrella22/Vesper-Player-Demo/commit/d9088aa747912e9b1ac43b2b77198e8b0d050f60))

## [1.6.0](https://github.com/umbrella22/Vesper-Player-Demo/compare/vesper_media-v1.5.1...vesper_media-v1.6.0) (2026-08-03)


### Features

* enhance BiliServices tests with new probe timeout and abort scenarios ([78198a8](https://github.com/umbrella22/Vesper-Player-Demo/commit/78198a877c9acd74c7fd58c14c0f1ea54edce372))


### Bug Fixes

* update BiliQrLoginController tests to use value property for pollResult and errorMessage ([78198a8](https://github.com/umbrella22/Vesper-Player-Demo/commit/78198a877c9acd74c7fd58c14c0f1ea54edce372))

## [1.5.1](https://github.com/umbrella22/Vesper-Player-Demo/compare/vesper_media-v1.5.0...vesper_media-v1.5.1) (2026-08-02)


### Bug Fixes

* 修复构建顺序问题 ([90fa00a](https://github.com/umbrella22/Vesper-Player-Demo/commit/90fa00afe293922e36e5a078af7ba4305dbdfb63))

## [1.5.0](https://github.com/umbrella22/Vesper-Player-Demo/compare/vesper_media-v1.4.1...vesper_media-v1.5.0) (2026-08-02)


### Features

* 添加 iOS 发布 IPA 工作流并更新 Android APK 构建逻辑 ([62eff7e](https://github.com/umbrella22/Vesper-Player-Demo/commit/62eff7e4a673707a10e875ba1bd1d7435b7cffac))

## [1.4.1](https://github.com/umbrella22/Vesper-Player-Demo/compare/vesper_media-v1.4.0...vesper_media-v1.4.1) (2026-07-31)


### Bug Fixes

* 更新工作流以支持通过 Release Please 创建的标签构建 Android 发布 APK ([58b7e85](https://github.com/umbrella22/Vesper-Player-Demo/commit/58b7e851fdbd2d1d086afa346507985448af7447))

## [1.4.0](https://github.com/umbrella22/Vesper-Player-Demo/compare/vesper_media-v1.3.2...vesper_media-v1.4.0) (2026-07-31)


### Features

* Enhance offline cache management and playback features ([f9e3542](https://github.com/umbrella22/Vesper-Player-Demo/commit/f9e3542d026bf4b5c0d2c79fbb9b92c56a0f35e5))
* enhance playback view model with comments and related videos functionality ([cda514d](https://github.com/umbrella22/Vesper-Player-Demo/commit/cda514da417c0ecfbf6910a585ccbbe46d6f8aad))
* Implement playback recovery mechanism and comment replies loading ([c4d0f1f](https://github.com/umbrella22/Vesper-Player-Demo/commit/c4d0f1f314c807ab4b50b2a7e58bf32c243504fc))
* integrate liquid glass widgets for enhanced UI effects ([559295d](https://github.com/umbrella22/Vesper-Player-Demo/commit/559295d32b66261360ac8db13378b6b78ea6ea03))
* Refactor Bili UI mode handling and add offline download capabilities ([40e5634](https://github.com/umbrella22/Vesper-Player-Demo/commit/40e563412cbd32fe96fc5ea11abe8ae1dfea68c8))
* **tv:** enhance layout and caching for TV home page ([b363141](https://github.com/umbrella22/Vesper-Player-Demo/commit/b363141c4f10eac5cbf0c4339ccecff3df7db543))
* 优化 HTTP 请求头的可变性管理 ([3a1005d](https://github.com/umbrella22/Vesper-Player-Demo/commit/3a1005d264e1782742b9ea899014788fbf58680a))
* 优化播放上下文标签的布局和间距，增加测试用例 ([f4e1de6](https://github.com/umbrella22/Vesper-Player-Demo/commit/f4e1de6399433fb52964588df6b81068c421faa4))
* 引入 AppGlassScaffold 以替代 GlassScaffold，增强组件一致性并更新相关测试 ([fadee32](https://github.com/umbrella22/Vesper-Player-Demo/commit/fadee329e8b1a3bf6304e5d5e7cd7dcce3dbd482))
* 更新 Gradle 版本至 9.6.0，并调整 SDK 包装器分发管理 ([c54ed24](https://github.com/umbrella22/Vesper-Player-Demo/commit/c54ed240acae59eced1f2157dc5a37c12702b8e1))
* 更新 TV 页面逻辑，优化返回键处理和搜索框聚焦功能 ([762cc07](https://github.com/umbrella22/Vesper-Player-Demo/commit/762cc072a941cf66f488120acc84dd17d4e3fc52))
* 更新子模块 ([2cd5bc4](https://github.com/umbrella22/Vesper-Player-Demo/commit/2cd5bc4b361cb4a99664c25550e9661b407a3b59))
* 更新系统 UI 模式，支持边缘到边缘的覆盖恢复 ([17976a9](https://github.com/umbrella22/Vesper-Player-Demo/commit/17976a979a0f19d33426fa90471c932faf644a89))
* 添加对 HCPP 平台支持的检测，更新相关逻辑和测试用例 ([10cb2a7](https://github.com/umbrella22/Vesper-Player-Demo/commit/10cb2a7c5459f32c0a257427f993a3cfdfc16edd))
* 添加对 TextureView 播放的支持，优化 Android 设备的播放兼容性 ([0356811](https://github.com/umbrella22/Vesper-Player-Demo/commit/0356811256b725322af0b8a42646aadd2b30c7f9))
* 添加对未知下载状态的支持 ([c628171](https://github.com/umbrella22/Vesper-Player-Demo/commit/c628171b0838eecccdb2f92db0c018b826419cec))
* 添加应用版本号读取功能，更新设置和 TV 页面以显示版本信息 ([0f6a386](https://github.com/umbrella22/Vesper-Player-Demo/commit/0f6a3862ab5ca8d705e947ffc92b358bd4f063ef))
* 添加源归一化插件支持，更新相关配置和依赖 ([927118e](https://github.com/umbrella22/Vesper-Player-Demo/commit/927118e34e34f37f070da9484db20a1401f16f32))
* 添加系统展示相关功能，更新 UI 样式和方向设置 ([24c657d](https://github.com/umbrella22/Vesper-Player-Demo/commit/24c657d2f7e880ac765fa20b561625b57baa8f76))


### Bug Fixes

* 更新 SDK 并修复 Android FFmpeg 构建 ([c95a4ed](https://github.com/umbrella22/Vesper-Player-Demo/commit/c95a4ed1a448bc559a8fcb669a5194e5297ed83b))
