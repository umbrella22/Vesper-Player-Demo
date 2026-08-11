# scripts/ 总览

仓库的本地辅助脚本。除 `rewrite_playcover_native_assets.dart`（Dart，仓库主语言）外均为 bash。

| 脚本 | 用途（一句话） | 谁调用它 | 用法 |
|---|---|---|---|
| `build_ios_no_codesign.sh` | 生成 SDK optional plugin/FFI artifacts 并无签名构建 iOS 应用（debug/release），iOS 出包的统一入口 | 本机开发；CI `ios-release-ipa.yml` | `bash scripts/build_ios_no_codesign.sh [debug\|release]` |
| `prepare_flutter_workspace.sh` | 归档 stale 的 Swift package 链接并 `flutter pub get`，初始化/构建前必跑 | 本机初始化；`build_ios_no_codesign.sh`；Android CI `android-release-apk.yml` | `bash scripts/prepare_flutter_workspace.sh` |
| `sync_ios_swiftpm_platforms.sh` | 把 iOS 部署目标同步到 Flutter 生成的 SwiftPM manifest | Xcode scheme PreAction（每次 Xcode 构建）；`build_ios_no_codesign.sh` | `bash scripts/sync_ios_swiftpm_platforms.sh [仓库根目录]` |
| `sign_ios_flutter_native_asset_frameworks.sh` | Xcode 构建阶段钩子：给 Flutter native asset framework 补签名 | Xcode build phase（`project.pbxproj`），勿手动执行 | — |
| `rewrite_playcover_native_assets.dart` | 把 PlayCover 版 App 的 native asset 路径改写为 `@executable_path` 相对路径 | CI `ios-release-ipa.yml`；配套单元测试 `test/rewrite_playcover_native_assets_test.dart` | `dart run scripts/rewrite_playcover_native_assets.dart <Runner.app 路径>` |
| `tag_release.sh` | 手动打 tag 的应急/备用发版脚本（从 `pubspec.yaml` 升版 → 提交 → 打 `v<x.y.z>`） | 仅本地手动应急；正常发版走 release-please | `bash scripts/tag_release.sh [--push] [patch\|minor\|major\|<x.y.z>]` |

## 构建链路速览

```
本机 / CI 出 iOS 包
  build_ios_no_codesign.sh
    ├─ prepare_flutter_workspace.sh      # flutter pub get + 清理 stale 链接
    ├─ sync_ios_swiftpm_platforms.sh     # SwiftPM 部署目标同步
    ├─ (SDK) scripts/vesper ios stage-optional-plugins-release
    ├─ (SDK) scripts/vesper ios ffi
    ├─ flutter build ios --config-only
    └─ xcodebuild（无签名）

每次 Xcode 构建（scheme PreAction 自动）
  sync_ios_swiftpm_platforms.sh          # 只做轻量同步，不跑 pub get

PlayCover 打包（CI）
  rewrite_playcover_native_assets.dart   # 改写 native asset 路径

手动应急发版
  tag_release.sh                         # 升版 → 提交 → 打 tag
```

## 约定

- 所有脚本以仓库根目录为基准解析路径（`$(dirname "$0")/..`），从任意目录调用均可。
- 保持脚本自包含：`build_ios_no_codesign.sh` 内含全部 iOS 构建前置步骤，不依赖包装器。
- 被 Xcode 直接调用的钩子（`sync_ios_swiftpm_platforms.sh`、`sign_ios_flutter_native_asset_frameworks.sh`）必须保持独立文件，不能合并进其他脚本。
