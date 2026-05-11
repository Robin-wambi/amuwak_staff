import 'order.dart';
import 'order_status.dart';

extension OrderListStats on List<LaundryOrder> {
  int countByStatus(OrderStatus status) =>
      where((order) => order.status == status).length;

  int get totalItems =>
      fold<int>(0, (sum, order) => sum + order.itemCount);
}
