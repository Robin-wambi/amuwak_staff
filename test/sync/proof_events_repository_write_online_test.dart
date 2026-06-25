import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/sync/proof_events_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit-tests [ProofEventsRepository.insertEvent] through the
/// [ProofEventsRepository.forTest] seam: the dispatched upsert payload and the
/// missing-write [StateError] guard, without a live SupabaseClient. The pure
/// payload shape is pinned separately in supabase_payloads_test.dart; here we
/// verify the repository wires the right payload and reacts to an empty result
/// (a write the server silently dropped) instead of reporting a false success.
void main() {
  final clock = DateTime.utc(2026, 6, 24, 10, 30);

  ProofEvent event({String id = 'pe1'}) => ProofEvent(
        id: id,
        type: ProofEventType.pickup,
        capturedAt: DateTime.utc(2026, 6, 24, 9),
        count: 3,
        photoPaths: const ['a.jpg', 'b.jpg'],
        notes: 'left at gate',
      );

  /// A repo whose upsert dispatch records the column map and reports whether
  /// the write persisted (empty rows ⇒ nothing written ⇒ StateError).
  ProofEventsRepository repoThatUpserts({
    required void Function(Map<String, dynamic> values) record,
    bool persisted = true,
  }) =>
      ProofEventsRepository.forTest(
        clock: () => clock,
        upsertRow: (values) async {
          record(values);
          return persisted ? [<String, dynamic>{'id': values['id']}] : const [];
        },
      );

  test('dispatches the proof-event payload + captured_by for the order',
      () async {
    late Map<String, dynamic> values;
    final repo = repoThatUpserts(record: (v) => values = v);

    await repo.insertEvent(event(),
        orderId: 'o9', actorStaffId: 'staff-7');

    expect(values['id'], 'pe1');
    expect(values['order_id'], 'o9');
    expect(values['type'], 'pickup');
    expect(values['captured_at'], '2026-06-24T09:00:00.000Z');
    expect(values['item_count'], 3);
    expect(values['notes'], 'left at gate');
    expect(values['captured_by'], 'staff-7');
    expect(values['created_at'], '2026-06-24T10:30:00.000Z');
    expect(values['updated_at'], '2026-06-24T10:30:00.000Z');
  });

  test('throws StateError when the write did not persist', () async {
    final repo = repoThatUpserts(record: (_) {}, persisted: false);
    expect(
      () => repo.insertEvent(event(), orderId: 'o9', actorStaffId: 's'),
      throwsStateError,
    );
  });

  test('a forTest instance without upsertRow trips a descriptive assert',
      () async {
    final repo = ProofEventsRepository.forTest(clock: () => clock);
    expect(
      () => repo.insertEvent(event(), orderId: 'o9', actorStaffId: 's'),
      throwsA(isA<AssertionError>()
          .having((e) => e.message, 'message', contains('upsertRow'))),
    );
  });
}
