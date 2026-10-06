import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authored Dart string literals contain no Cyrillic', () {
    final List<String> failures = <String>[];
    for (final String root in <String>['lib', 'test', 'integration_test']) {
      for (final FileSystemEntity entity in Directory(
        root,
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.contains('/l10n/generated/')) continue;
        final ParseStringResult parsed = parseString(
          content: entity.readAsStringSync(),
          path: entity.path,
        );
        parsed.unit.accept(_StringAudit(entity.path, failures));
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('client resource files contain no Cyrillic outside ARB', () {
    final List<String> failures = <String>[];
    for (final String root in <String>['assets', 'android', 'ios']) {
      for (final FileSystemEntity entity in Directory(
        root,
      ).listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!<String>['.json', '.xml', '.plist'].any(entity.path.endsWith)) {
          continue;
        }
        if (_containsCyrillic(entity.readAsStringSync())) {
          failures.add(entity.path);
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}

final class _StringAudit extends RecursiveAstVisitor<void> {
  new(this.path, this.failures);

  final String path;
  final List<String> failures;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (_containsCyrillic(node.value)) {
      failures.add('$path:${node.offset}');
    }
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitInterpolationString(InterpolationString node) {
    if (_containsCyrillic(node.value)) {
      failures.add('$path:${node.offset}');
    }
    super.visitInterpolationString(node);
  }
}

bool _containsCyrillic(String value) => value.runes.any(
  (rune) =>
      (rune >= 0x0400 && rune <= 0x052f) ||
      (rune >= 0x2de0 && rune <= 0x2dff) ||
      (rune >= 0xa640 && rune <= 0xa69f),
);
