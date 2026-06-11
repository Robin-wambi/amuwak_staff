import '../shared/phone.dart';
import 'order.dart';
import 'order_status.dart';

extension OrderListStats on List<LaundryOrder> {
  int countByStatus(OrderStatus status) =>
      where((order) => order.status == status).length;

  int get totalItems =>
      fold<int>(0, (sum, order) => sum + order.itemCount);
}

/// A run of orders that share a calendar day, with a ready-to-render header
/// label. [day] is null for the "Now" group (immediate orders with no
/// [LaundryOrder.relevantDate]).
class OrderDayGroup {
  const OrderDayGroup({
    required this.day,
    required this.label,
    required this.orders,
  });

  final DateTime? day;
  final String label;
  final List<LaundryOrder> orders;
}

extension OrderListGrouping on List<LaundryOrder> {
  /// Groups orders into day sections for a list screen, keyed on
  /// [LaundryOrder.relevantDate]'s calendar day.
  ///
  /// The "Now" group (orders with no relevant date — immediate pickups) always
  /// comes first. Dated groups, and the orders within every group, are ordered
  /// soonest-first by default, or most-recent-first when [newestFirst] is set
  /// (completed work). Ties break on [LaundryOrder.orderCode] so the order is
  /// stable.
  List<OrderDayGroup> groupByDay({
    required bool newestFirst,
    DateTime Function()? now,
  }) {
    final reference = now ?? DateTime.now;
    final dated = <DateTime, List<LaundryOrder>>{};
    final nowBucket = <LaundryOrder>[];
    for (final order in this) {
      final date = order.relevantDate;
      if (date == null) {
        nowBucket.add(order);
      } else {
        // relevantDate (capturedAt/scheduledFor) is UTC when sourced from
        // Supabase; bucket by the LOCAL calendar day so a late-night order
        // doesn't land under the previous day's header. toLocal() is a no-op
        // when the value is already local.
        final local = date.toLocal();
        final day = DateTime(local.year, local.month, local.day);
        (dated[day] ??= <LaundryOrder>[]).add(order);
      }
    }

    int compare(LaundryOrder a, LaundryOrder b) {
      final da = a.relevantDate;
      final db = b.relevantDate;
      final byDate = (da == null || db == null) ? 0 : da.compareTo(db);
      final directed = newestFirst ? -byDate : byDate;
      return directed != 0 ? directed : a.orderCode.compareTo(b.orderCode);
    }

    final days = dated.keys.toList()
      ..sort((a, b) => newestFirst ? b.compareTo(a) : a.compareTo(b));

    return [
      if (nowBucket.isNotEmpty)
        OrderDayGroup(
          day: null,
          label: 'Now',
          orders: nowBucket..sort(compare),
        ),
      for (final day in days)
        OrderDayGroup(
          day: day,
          label: LaundryOrder.formatDay(day, now: reference),
          orders: dated[day]!..sort(compare),
        ),
    ];
  }
}

extension OrderListSearch on List<LaundryOrder> {
  /// Case-insensitive partial-match filter for the order search screen.
  /// Matches the query against the fields a rider would read off a bag/ticket:
  /// order code, customer name, phone, and address. An empty (or whitespace)
  /// query returns the list unchanged so callers can use this for the
  /// zero-state list as well.
  ///
  /// Phone is matched on the Ugandan national significant number
  /// ([ugandaNationalDigits]) so a local query (`0700123456`) still matches an
  /// internationally-stored number (`+256 700 123 456`) and vice versa,
  /// regardless of spacing.
  List<LaundryOrder> searchBy(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return this;
    final queryDigits = ugandaNationalDigits(q);
    return where((o) =>
            o.orderCode.toLowerCase().contains(q) ||
            o.customerName.toLowerCase().contains(q) ||
            o.address.toLowerCase().contains(q) ||
            (queryDigits.isNotEmpty &&
                ugandaNationalDigits(o.phone).contains(queryDigits)))
        .toList(growable: false);
  }
}
