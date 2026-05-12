import 'order_status.dart';

class LaundryOrder {
  const LaundryOrder({
    required this.orderId,
    required this.customerName,
    required this.serviceType,
    required this.status,
    required this.timeLabel,
    required this.itemCount,
    required this.phone,
    required this.address,
    required this.notes,
  });

  final String orderId;
  final String customerName;
  final String serviceType;
  final OrderStatus status;
  final String timeLabel;
  final int itemCount;
  final String phone;
  final String address;
  final String notes;

  LaundryOrder copyWith({
    String? orderId,
    String? customerName,
    String? serviceType,
    OrderStatus? status,
    String? timeLabel,
    int? itemCount,
    String? phone,
    String? address,
    String? notes,
  }) {
    return LaundryOrder(
      orderId: orderId ?? this.orderId,
      customerName: customerName ?? this.customerName,
      serviceType: serviceType ?? this.serviceType,
      status: status ?? this.status,
      timeLabel: timeLabel ?? this.timeLabel,
      itemCount: itemCount ?? this.itemCount,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LaundryOrder &&
        other.orderId == orderId &&
        other.customerName == customerName &&
        other.serviceType == serviceType &&
        other.status == status &&
        other.timeLabel == timeLabel &&
        other.itemCount == itemCount &&
        other.phone == phone &&
        other.address == address &&
        other.notes == notes;
  }

  @override
  int get hashCode => Object.hash(
        orderId,
        customerName,
        serviceType,
        status,
        timeLabel,
        itemCount,
        phone,
        address,
        notes,
      );
}
