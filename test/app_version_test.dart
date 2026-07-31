import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:vesper_media/app/app_version.dart';

void main() {
  group('AppVersion.load', () {
    test('返回 package_info_plus 提供的版本号', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vesper',
        packageName: 'dev.ikaros.vesper',
        version: '1.3.2',
        buildNumber: '7',
        buildSignature: '',
      );
      expect(await AppVersion.load(), '1.3.2');
    });

    test('版本号变化后能读取到新值', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vesper',
        packageName: 'dev.ikaros.vesper',
        version: '1.4.0',
        buildNumber: '8',
        buildSignature: '',
      );
      expect(await AppVersion.load(), '1.4.0');
    });

    test('版本号为空时返回空字符串', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Vesper',
        packageName: 'dev.ikaros.vesper',
        version: '',
        buildNumber: '',
        buildSignature: '',
      );
      expect(await AppVersion.load(), '');
    });
  });
}
