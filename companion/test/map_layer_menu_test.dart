import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a null-valued PopupMenuItem never reaches onSelected',
      (tester) async {
    final selected = <Object?>[];
    var canceled = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PopupMenuButton<Object?>(
          onSelected: selected.add,
          onCanceled: () => canceled++,
          itemBuilder: (_) => const [
            PopupMenuItem<Object?>(value: null, child: Text('NULL ITEM')),
            PopupMenuItem<Object?>(value: 'real', child: Text('REAL ITEM')),
          ],
          child: const Text('OPEN'),
        ),
      ),
    ));

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NULL ITEM'));
    await tester.pumpAndSettle();
    expect(selected, isEmpty, reason: 'Flutter treats null as a dismissal');
    expect(canceled, 1);

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REAL ITEM'));
    await tester.pumpAndSettle();
    expect(selected, ['real']);
  });
}
