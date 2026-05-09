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
  final String status;
  final String timeLabel;
  final int itemCount;
  final String phone;
  final String address;
  final String notes;
}