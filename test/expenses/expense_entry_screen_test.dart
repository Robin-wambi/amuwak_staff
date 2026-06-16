import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/expenses/expense.dart';
import 'package:amuwak_staff/src/expenses/expense_entry_screen.dart';

void main() {
  testWidgets('saving records the chosen category, amount and note',
      (tester) async {
    Expense? saved;

    await tester.pumpWidget(MaterialApp(
      home: ExpenseEntryScreen(
        save: (e) async => saved = e,
        idGenerator: () => 'fixed-id',
        clock: () => DateTime.utc(2026, 6, 17, 12),
      ),
    ));

    await tester.tap(find.text(ExpenseCategory.fuel.label));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('expense_amount')), '15000');
    await tester.enterText(find.byKey(const Key('expense_note')), 'boda');
    await tester.tap(find.byKey(const Key('expense_save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.category, ExpenseCategory.fuel);
    expect(saved!.amountUgx, 15000);
    expect(saved!.note, 'boda');
    expect(saved!.id, 'fixed-id');
    expect(saved!.spentAt, DateTime.utc(2026, 6, 17, 12));
  });

  testWidgets('defaults to the first category when none is tapped',
      (tester) async {
    Expense? saved;

    await tester.pumpWidget(MaterialApp(
      home: ExpenseEntryScreen(save: (e) async => saved = e),
    ));

    await tester.enterText(find.byKey(const Key('expense_amount')), '8000');
    await tester.tap(find.byKey(const Key('expense_save')));
    await tester.pumpAndSettle();

    expect(saved!.category, ExpenseCategory.detergent);
    expect(saved!.amountUgx, 8000);
  });

  testWidgets('rejects a non-positive amount and does not save',
      (tester) async {
    var calls = 0;

    await tester.pumpWidget(MaterialApp(
      home: ExpenseEntryScreen(save: (e) async => calls++),
    ));

    await tester.enterText(find.byKey(const Key('expense_amount')), '0');
    await tester.tap(find.byKey(const Key('expense_save')));
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Enter an amount greater than 0.'), findsOneWidget);
  });
}
