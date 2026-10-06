import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final List<File> sourceFiles = Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  test('production libraries use ordinary imports instead of part files', () {
    final directive = RegExp(r'^\s*part(?:\s+of)?\s', multiLine: true);
    final List<String> offenders = sourceFiles
        .where((file) => directive.hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList(growable: false);

    expect(offenders, isEmpty);
  });

  test('UI helpers are widget classes rather than widget functions', () {
    final widgetFunction = RegExp(
      r'^\s*(?:Widget|PreferredSizeWidget)\s+(?!build\b)[A-Za-z_]\w*\s*\(',
      multiLine: true,
    );
    final List<String> offenders = sourceFiles
        .where((file) => widgetFunction.hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList(growable: false);

    expect(offenders, isEmpty);
  });

  test('SharedPreferences stays behind the common preferences tool', () {
    final allowed = {
      'lib/src/common/preferences/preferences_datasource_tool.dart',
      'lib/src/feature/initialization/logic/composition_root.dart',
    };
    final List<String> offenders = sourceFiles
        .where((file) => file.readAsStringSync().contains('SharedPreferences'))
        .map((file) => file.path)
        .where((path) => !allowed.contains(path))
        .toList(growable: false);

    expect(offenders, isEmpty);
  });
}
