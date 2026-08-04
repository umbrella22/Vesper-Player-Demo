import 'package:flutter_test/flutter_test.dart';

import '../scripts/rewrite_playcover_native_assets.dart';

void main() {
  test('rewrites bundled native assets relative to the app executable', () {
    final manifest = <String, dynamic>{
      'native-assets': <String, dynamic>{
        'ios_arm64': <String, dynamic>{
          'package:objective_c/objective_c.dylib': <dynamic>[
            'absolute',
            'objective_c.framework/objective_c',
          ],
          'package:example/example.dylib': <dynamic>[
            'absolute',
            'Frameworks/example.framework/example',
          ],
        },
      },
    };

    expect(rewritePlayCoverNativeAssetPaths(manifest), 2);
    final iosAssets =
        manifest['native-assets']['ios_arm64'] as Map<String, dynamic>;
    expect(iosAssets['package:objective_c/objective_c.dylib'], <dynamic>[
      'absolute',
      '@executable_path/Frameworks/objective_c.framework/objective_c',
    ]);
    expect(iosAssets['package:example/example.dylib'], <dynamic>[
      'absolute',
      '@executable_path/Frameworks/example.framework/example',
    ]);
  });

  test('keeps system and already absolute native asset paths unchanged', () {
    final manifest = <String, dynamic>{
      'native-assets': <String, dynamic>{
        'ios_arm64': <String, dynamic>{
          'package:system/system.dylib': <dynamic>['system', 'System'],
          'package:absolute/absolute.dylib': <dynamic>[
            'absolute',
            '/Library/Frameworks/absolute.framework/absolute',
          ],
          'package:patched/patched.dylib': <dynamic>[
            'absolute',
            '@executable_path/Frameworks/patched.framework/patched',
          ],
        },
      },
    };

    expect(rewritePlayCoverNativeAssetPaths(manifest), 0);
  });
}
