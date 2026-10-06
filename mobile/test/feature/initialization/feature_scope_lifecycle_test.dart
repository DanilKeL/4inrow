import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_bloc.dart';
import 'package:four3/src/feature/initialization/widget/initialization_root_scope.dart';

void main() {
  testWidgets(
    'feature scope keeps one bloc per identity and closes it on replacement',
    (tester) async {
      InitializationBloc? captured;

      Widget build(String identity) => MaterialApp(
        home: InitializationRootScope(
          key: ValueKey(identity),
          child: Builder(
            builder: (context) {
              captured = InitializationRootScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(build('first'));
      await tester.pump();
      final InitializationBloc first = captured!;
      expect(first.state, isA<InitializationState$Ready>());

      await tester.pumpWidget(build('first'));
      expect(captured, same(first));
      expect(first.isClosed, isFalse);

      await tester.pumpWidget(build('second'));
      await tester.pump();
      final InitializationBloc second = captured!;
      expect(second, isNot(same(first)));
      expect(first.isClosed, isTrue);
      expect(second.state, isA<InitializationState$Ready>());

      await tester.pumpWidget(const SizedBox());
      expect(second.isClosed, isTrue);
    },
  );
}
