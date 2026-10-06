import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot:
      (String name, List<int> bytes, [Map<String, Object?>? arguments]) async {
        final directory = Directory('../artifacts/mobile-ui');
        await directory.create(recursive: true);
        await File('${directory.path}/$name.png').writeAsBytes(bytes);
        return true;
      },
);
