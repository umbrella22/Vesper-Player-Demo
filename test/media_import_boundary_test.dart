import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 依赖边界守护：lib/media/ 禁止 import/export lib/bili/ 与 lib/app/。
///
/// 抽取安全规则 §1.1：壳不依赖任何平台实现，方向只允许
/// bili/ → media/、app/ → media/、main.dart → 两者。
/// 视觉主题已下沉为 `lib/media/design/app_visual_theme.dart`（模板包一部分）。
void main() {
  test('lib/media 内不得引用 lib/bili 与 lib/app', () {
    final mediaDir = Directory('lib/media');
    expect(
      mediaDir.existsSync(),
      isTrue,
      reason: 'lib/media 骨架应已存在（Phase 0 交付物）',
    );

    final violations = <String>[];
    for (final entity in mediaDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final lines = File(entity.path).readAsStringSync().split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        // 按 URI 路径段判断：匹配到独立的 bili/bilibili 或 app 段才算
        // 引用上层，避免误伤 capabilities 等包含子串的路径。
        final uri = trimmed
            .replaceFirst(RegExp(r'^(import|export)\s+'), '')
            .replaceAll("'", '')
            .replaceAll('"', '');
        if (!uri.contains('/')) {
          continue;
        }
        final segments = uri.split('/');
        final isBili = segments.any(
          (segment) => segment == 'bili' || segment.startsWith('bili'),
        );
        final isApp = segments.any((segment) => segment == 'app');
        if (isBili || isApp) {
          violations.add('${entity.path}: $trimmed');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '发现对 bili/app 的引用：\n${violations.join('\n')}',
    );
  });
}
