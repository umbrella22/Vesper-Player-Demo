# Repository Guidance

This workspace is a Flutter mobile app shell that consumes the published Vesper
Player packages. Treat this app and the upstream SDK repository as separate
build surfaces.

## Project Map

- App root: this repository.
- Flutter app code: `lib/`.
- Vesper Flutter packages are consumed from pub.dev through version constraints
  in `pubspec.yaml`.
- Native helper scripts live in `scripts/` (see `scripts/README.md` for a per-script overview of purpose and callers).

## Default Workflow

- Prefer the smallest possible change in the responsible layer first: `lib/`
  for app behavior and the upstream Vesper repository for SDK behavior.
- Do not edit generated or cached outputs under `build/`, `android/build/`, `ios/Flutter/`, or `.gradle/` unless the task is explicitly about generated artifacts.
- Keep app changes and SDK changes logically separated. If both are required,
  validate each repository in its own working directory and publish the SDK
  artifacts before validating this app as an external consumer.
- This repository is mobile-only for current work. Do not spend time on Flutter desktop paths unless the user explicitly asks.

## State Management Conventions

- Reactive UI state uses `signals` (`package:signals/signals_flutter.dart`). View models and page-local UI state are signals (`signal<T>` + `ReadonlySignal`, consumed with `SignalBuilder`), as in `BiliHubViewModel`, `BiliPlaybackViewModel`, and `OfflineCacheViewModel`.
- `ChangeNotifier` is reserved for imperative SDK-boundary controllers (`BiliOfflineDownloadController`, `BiliExternalPlaybackManager`, `AppThemeController`). Their state is adapted to signals by the owning view model; do not introduce `ChangeNotifier` in page-facing view models.
- App-level mutable state is owned by an injectable controller created in the composition root (`BiliUiModeController` is the pattern), never by top-level globals in `main.dart` or elsewhere.
- Singletons (`.instance`) are fallback defaults for tests and direct construction only. The single runtime source of truth is the composition root in `lib/platform_app.dart`, which creates the selected provider's client and app-level controllers and injects them down through `VesperAppHost -> HomePage -> ...`. `lib/main.dart` only delegates to `runPlatformApp()`.
- Do not read `X.instance` directly inside a widget or view model in a production path: it bypasses the injected instance and creates a second copy of session state (cookies, WBI keys, download metadata) that can silently diverge from the app's session. When a widget needs a dependency, add an optional constructor parameter defaulting to `.instance`.

## Validation

- Default Flutter validation from the repository root: `flutter analyze` and `flutter test`.
- For app Android changes, validate from `android/` with that project's wrapper.
- For iOS native or packaging changes, prefer `bash scripts/build_ios_no_codesign.sh` over raw `xcodebuild` unless the user asks for a lower-level flow.
- If raw `xcodebuild` or direct iOS package resolution was run, rerun `bash scripts/prepare_flutter_workspace.sh` before going back to `flutter analyze`, `flutter test`, or `flutter run`.

## Android And Gradle Rules

- Always be explicit that Gradle tasks in this repository operate on the app
  Android project. SDK Gradle tasks run in the upstream Vesper checkout.

### App Android Project

- Directory: `android/`
- Preferred entrypoint: `cd android && ./gradlew <task>`
- Wrapper version: Gradle 9.4.1 from `android/gradle/wrapper/gradle-wrapper.properties`
- If a tool requires the unpacked Gradle home instead of the wrapper, use:
  `android/.gradle/wrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj/gradle-9.4.1`

## Repository-Specific Constraints

- Android release output is intentionally `arm64-v8a` only. Do not broaden ABI settings unless the user explicitly asks.
- The default integration path expects hosted Vesper packages to resolve their
  published Android Maven and iOS SwiftPM artifacts. Local SDK overrides are a
  separate, explicit test setup.
- Bilibili playback, search, login, and history behavior live in `lib/bili/`; app shell and navigation live in `lib/app/`; player integration helpers live in `lib/media/player/`.
- Preserve existing shell scripts in `scripts/` as the preferred build entrypoints when they already encode repository-specific setup.

## Practical Heuristics

- If the problem is in Dart UI or app behavior, start in `lib/` and only step into the SDK when a concrete SDK boundary is implicated.
- If the problem is in Android build logic, first decide whether it belongs to
  this app host or to an artifact published by the upstream SDK.
- When a task mentions Gradle directly, include the exact project directory and Gradle version in your reasoning and validation notes.
