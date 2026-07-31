# Repository Guidance

This workspace is a Flutter mobile app shell around a vendored Vesper Player SDK.
Treat the app root and the SDK Android project as two separate build surfaces.

## Project Map

- App root: this repository.
- Flutter app code: `lib/`.
- Local SDK source: `third_party/vesper-player-sdk`.
- Flutter packages from the SDK are consumed through local path dependencies in `pubspec.yaml`.
- Native helper scripts live in `scripts/`.

## Default Workflow

- Prefer the smallest possible change in the owning layer first: `lib/` for app behavior, `third_party/vesper-player-sdk` only when the issue is clearly inside the SDK.
- Do not edit generated or cached outputs under `build/`, `android/build/`, `ios/Flutter/`, or `.gradle/` unless the task is explicitly about generated artifacts.
- Keep app changes and SDK changes logically separated. If both are required, validate each side in its own working directory.
- This repository is mobile-only for current work. Do not spend time on Flutter desktop paths unless the user explicitly asks.

## State Management Conventions

- Reactive UI state uses `signals` (`package:signals/signals_flutter.dart`). View models and page-local UI state are signals (`signal<T>` + `ReadonlySignal`, consumed with `SignalBuilder`), as in `BiliHubViewModel`, `BiliPlaybackViewModel`, and `OfflineCacheViewModel`.
- `ChangeNotifier` is reserved for imperative SDK-boundary controllers (`BiliOfflineDownloadController`, `BiliExternalPlaybackManager`, `AppThemeController`). Their state is adapted to signals by the owning view model; do not introduce `ChangeNotifier` in page-facing view models.
- App-level mutable state is owned by an injectable controller created in the composition root (`BiliUiModeController` is the pattern), never by top-level globals in `main.dart` or elsewhere.
- Singletons (`.instance`) are fallback defaults for tests and direct construction only. The single runtime source of truth is the composition root in `lib/main.dart`, which creates `BiliClient` and `BiliOfflineDownloadController` and injects them down through `VesperApp -> HomePage -> ...`.
- Do not read `X.instance` directly inside a widget or view model in a production path: it bypasses the injected instance and creates a second copy of session state (cookies, WBI keys, download metadata) that can silently diverge from the app's session. When a widget needs a dependency, add an optional constructor parameter defaulting to `.instance`.

## Validation

- Default Flutter validation from the repository root: `flutter analyze` and `flutter test`.
- For app Android changes, validate from `android/` with that project's wrapper.
- For SDK Android changes, validate from `third_party/vesper-player-sdk/lib/android/` with that project's wrapper.
- For iOS native or packaging changes, prefer `bash scripts/build_ios_no_codesign.sh` over raw `xcodebuild` unless the user asks for a lower-level flow.
- If raw `xcodebuild` or direct iOS package resolution was run, rerun `bash scripts/prepare_flutter_workspace.sh` before going back to `flutter analyze`, `flutter test`, or `flutter run`.

## Android And Gradle Rules

- Always be explicit about which Android project you are operating on before running Gradle tasks.
- Do not mix the app's Gradle installation with the SDK's Gradle installation.

### App Android Project

- Directory: `android/`
- Preferred entrypoint: `cd android && ./gradlew <task>`
- Wrapper version: Gradle 9.4.0 from `android/gradle/wrapper/gradle-wrapper.properties`
- If a tool requires the unpacked Gradle home instead of the wrapper, use:
  `android/.gradle/wrapper/dists/gradle-9.4.0-bin/lcvyxq3t37f6mx9miaydrrgs/gradle-9.4.0`

### SDK Android Project

- Directory: `third_party/vesper-player-sdk/lib/android/`
- Preferred entrypoint: `cd third_party/vesper-player-sdk/lib/android && ./gradlew <task>`
- Wrapper version: Gradle 9.6.0 from `third_party/vesper-player-sdk/lib/android/gradle/wrapper/gradle-wrapper.properties`
- The SDK wrapper distribution follows the active `GRADLE_USER_HOME`; prefer
  the SDK's wrapper and do not reuse the app project's Gradle 9.4.0 install.

## Repository-Specific Constraints

- Android release output is intentionally `arm64-v8a` only. Do not broaden ABI settings unless the user explicitly asks.
- The app uses the bundled SDK submodule by default. Do not switch to an external SDK checkout unless the user asks for that test setup.
- Bilibili playback, search, login, and history behavior live in `lib/bili/`; app shell and navigation live in `lib/app/`; player integration helpers live in `lib/player/`.
- Preserve existing shell scripts in `scripts/` as the preferred build entrypoints when they already encode repository-specific setup.

## Practical Heuristics

- If the problem is in Dart UI or app behavior, start in `lib/` and only step into the SDK when a concrete SDK boundary is implicated.
- If the problem is in Android build logic, first decide whether it belongs to the app Android host or the SDK Android project; many issues only affect one of them.
- When a task mentions Gradle directly, include the exact project directory and Gradle version in your reasoning and validation notes.
