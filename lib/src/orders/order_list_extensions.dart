import 'order.dart';
import 'order_status.dart';

extension OrderListStats on List<LaundryOrder> {
  int countByStatus(OrderStatus status) =>
      where((order) => order.status == status).length;

  int get totalItems =>
      fold<int>(0, (sum, order) => sum + order.itemCount);
}

extension OrderListSearch on List<LaundryOrder> {
  /// Case-insensitive partial-match filter for the order search screen.
  /// Matches the query against the fields a rider would read off a bag/ticket:
  /// order code, customer name, phone, and address. An empty (or whitespace)
  /// query returns the list unchanged so callers can use this for the
  /// zero-state list as well.
  List<LaundryOrder> searchBy(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return this;
    return where((o) =>
            o.orderCode.toLowerCase().contains(q) ||
            o.customerName.toLowerCase().contains(q) ||
            o.phone.toLowerCase().contains(q) ||
            o.address.toLowerCase().contains(q))
        .toList(growable: false);
  }
}
