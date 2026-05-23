import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';
import 'package:amuwak_staff/src/sync/sync_errors_provider.dart';
import 'package:amuwak_staff/src/sync/sync_errors_screen.dart';

class _MockOutboxRepo extends Mock implements OutboxRepository {}

/// Stub `OutboxData` row — we only assert against forTable / op / rowId /
/// lastError / id, so the rest are sensible defaults.
OutboxData _stubOutboxRow({
  required String id,
  required String forTable,
  required String op,
  required String rowId,
  String? lastError,
}) {
  return OutboxData(
    id: id,
    forTable: forTable,
    op: op,
    rowId: rowId,
    payloadJson: '{}',
    createdAt: DateTime.utc(2026, 5, 23),
    retryCount: 6,
    lastAttemptedAt: DateTime.utc(2026, 5, 23, 12),
    lastError: lastError,
    status: 'dead_letter',
  );
}

PullDeadLetterData _stubPullRow({
  required String id,
  required String forTable,
  required String errorText,
}) {
  return PullDeadLetterData(
    id: id,
    forTable: forTable,
    rowPayloadJson: '{}',
    errorText: errorText,
    recordedAt: DateTime.utc(2026, 5, 23),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<OutboxData> outboxRows,
  required List<PullDeadLetterData> pullRows,
  OutboxRepository? outboxRepoOverride,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        outboxDeadLetteredProvider.overrideWith(
          (ref) => Stream<List<OutboxData>>.value(outboxRows),
        ),
        pullDeadLetteredProvider.overrideWith(
          (ref) => Stream<List<PullDeadLetterData>>.value(pullRows),
        ),
        if (outboxRepoOverride != null)
          outboxRepositoryProvider.overrideWithValue(outboxRepoOverride),
      ],
      child: const MaterialApp(home: SyncErrorsScreen()),
    ),
  );
}

void main() {
  testWidgets(
    'renders the empty-state message when there are no errors',
    (tester) async {
      await _pumpScreen(tester, outboxRows: const [], pullRows: const []);
      await tester.pumpAndSettle();

      expect(find.text('No sync errors.'), findsOneWidget);
    },
  );

  testWidgets(
    'renders outbox dead-letter rows with a Retry button that requeues',
    (tester) async {
      final mockOutbox = _MockOutboxRepo();
      when(() => mockOutbox.watchDeadLettered()).thenAnswer(
        (_) => Stream<List<OutboxData>>.value([
          _stubOutboxRow(
            id: 'k-1',
            forTable: 'orders',
            op: 'update',
            rowId: 'AMW-A',
            lastError: 'network down',
          ),
        ]),
      );
      when(() => mockOutbox.requeue(any())).thenAnswer((_) async {});

      await _pumpScreen(
        tester,
        outboxRows: [
          _stubOutboxRow(
            id: 'k-1',
            forTable: 'orders',
            op: 'update',
            rowId: 'AMW-A',
            lastError: 'network down',
          ),
        ],
        pullRows: const [],
        outboxRepoOverride: mockOutbox,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('AMW-A'), findsOneWidget);
      expect(find.textContaining('network down'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();

      verify(() => mockOutbox.requeue('k-1')).called(1);
    },
  );

  testWidgets(
    'renders pull dead-letter rows as read-only (no Retry button)',
    (tester) async {
      await _pumpScreen(
        tester,
        outboxRows: const [],
        pullRows: [
          _stubPullRow(
            id: 'orders:AMW-Z:123',
            forTable: 'orders',
            errorText: 'TypeError: null is not a String',
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('orders'), findsWidgets);
      expect(find.textContaining('TypeError'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      expect(find.text('Server fix required'), findsOneWidget);
    },
  );
}
