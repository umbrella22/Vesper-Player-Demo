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
- Wrapper version: Gradle 8.14 from `android/gradle/wrapper/gradle-wrapper.properties`
- If a tool requires the unpacked Gradle home instead of the wrapper, use:
  `android/.gradle/wrapper/dists/gradle-8.14-all/c2qonpi39x1mddn7hk5gh9iqj/gradle-8.14`

### SDK Android Project

- Directory: `third_party/vesper-player-sdk/lib/android/`
- Preferred entrypoint: `cd third_party/vesper-player-sdk/lib/android && ./gradlew <task>`
- Wrapper version: Gradle 9.4.0 from `third_party/vesper-player-sdk/lib/android/gradle/wrapper/gradle-wrapper.properties`
- Distribution root if a tool asks for the wrapper cache path:
  `third_party/vesper-player-sdk/lib/android/.gradle/wrapper/dists/gradle-9.4.0-bin`
- Current unpacked Gradle home if a tool needs the executable directory:
  `third_party/vesper-player-sdk/lib/android/.gradle/wrapper/dists/gradle-9.4.0-bin/lcvyxq3t37f6mx9miaydrrgs/gradle-9.4.0`

## Repository-Specific Constraints

- Android release output is intentionally `arm64-v8a` only. Do not broaden ABI settings unless the user explicitly asks.
- The app uses the bundled SDK submodule by default. Do not switch to an external SDK checkout unless the user asks for that test setup.
- Bilibili playback, search, login, and history behavior live in `lib/bili/`; app shell and navigation live in `lib/app/`; player integration helpers live in `lib/player/`.
- Preserve existing shell scripts in `scripts/` as the preferred build entrypoints when they already encode repository-specific setup.

## Practical Heuristics

- If the problem is in Dart UI or app behavior, start in `lib/` and only step into the SDK when a concrete SDK boundary is implicated.
- If the problem is in Android build logic, first decide whether it belongs to the app Android host or the SDK Android project; many issues only affect one of them.
- When a task mentions Gradle directly, include the exact project directory and Gradle version in your reasoning and validation notes.
