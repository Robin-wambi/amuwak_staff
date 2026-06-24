import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/orders/widgets/order_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The order card grows contextual CRUD: a long-press actions menu (Edit /
/// Mark-as / Delete) and swipe-to-delete with a confirm dialog. All action
/// callbacks are optional — with none supplied the card is exactly the old
/// tap-only summary, so every existing list keeps working unchanged.
LaundryOrder _order({
  OrderStatus status = OrderStatus.inProgress,
  String id = 'o1',
}) =>
    LaundryOrder(
      orderId: id,
      orderCode: 'AMW-1',
      customerName: 'Ada',
      serviceType: ServiceType.washAndIron,
      status: status,
      timeLabel: 'Today',
      itemCount: 3,
      phone: '0700',
      address: 'Kira',
      notes: '',
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('OrderCard without action callbacks', () {
    testWidgets('renders tap-only and has no Dismissible', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(
        OrderCard(order: _order(), onTap: () => tapped = true),
      ));

      expect(find.byType(Dismissible), findsNothing);
      await tester.tap(find.text('Ada'));
      expect(tapped, isTrue);
    });
  });

  group('long-press actions menu', () {
    testWidgets('Edit invokes onEdit', (tester) async {
      var edited = false;
      await tester.pumpWidget(_host(
        OrderCard(
          order: _order(),
          onTap: () {},
          onEdit: () => edited = true,
          onDelete: () {},
          onAdvanceStatus: () {},
        ),
      ));

      await tester.longPress(find.text('Ada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      expect(edited, isTrue);
    });

    testWidgets('an in-progress order offers Mark as Ready for delivery',
        (tester) async {
      var advanced = false;
      await tester.pumpWidget(_host(
        OrderCard(
          order: _order(status: OrderStatus.inProgress),
          onTap: () {},
          onAdvanceStatus: () => advanced = true,
        ),
      ));

      await tester.longPress(find.text('Ada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as Ready for delivery'));
      await tester.pumpAndSettle();
      expect(advanced, isTrue);
    });

    testWidgets(
        'a pending-pickup order routes proof steps to the card tap, not a '
        'proof-less status jump', (tester) async {
      var advanced = false;
      var tapped = false;
      await tester.pumpWidget(_host(
        OrderCard(
          order: _order(status: OrderStatus.pendingPickup),
          onTap: () => tapped = true,
          onAdvanceStatus: () => advanced = true,
        ),
      ));

      await tester.longPress(find.text('Ada'));
      await tester.pumpAndSettle();
      // No proof-less "Mark as In progress" — pickup needs proof capture.
      expect(find.textContaining('Mark as'), findsNothing);
      await tester.tap(find.text('Confirm pickup'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
      expect(advanced, isFalse);
    });
  });

  group('visible action icons (long-press is undiscoverable)', () {
    testWidgets('an Edit icon invokes onEdit without a long-press',
        (tester) async {
      var edited = false;
      await tester.pumpWidget(_host(
        OrderCard(order: _order(), onTap: () {}, onEdit: () => edited = true),
      ));

      final editIcon = find.byTooltip('Edit order');
      expect(editIcon, findsOneWidget);
      await tester.tap(editIcon);
      await tester.pumpAndSettle();
      expect(edited, isTrue);
    });

    testWidgets('the overflow button opens the actions sheet', (tester) async {
      var deleted = false;
      await tester.pumpWidget(_host(
        OrderCard(
          order: _order(),
          onTap: () {},
          onEdit: () {},
          onDelete: () => deleted = true,
        ),
      ));

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      // The same sheet the long-press opens — drive its Delete entry through to
      // the confirm dialog.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });

    testWidgets('a tap-only card shows neither icon (keeps the chevron)',
        (tester) async {
      await tester.pumpWidget(_host(
        OrderCard(order: _order(), onTap: () {}),
      ));

      expect(find.byTooltip('Edit order'), findsNothing);
      expect(find.byTooltip('More actions'), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });

  group('swipe-to-delete', () {
    testWidgets('confirming the dialog invokes onDelete', (tester) async {
      var deleted = false;
      await tester.pumpWidget(_host(
        OrderCard(
          order: _order(),
          onTap: () {},
          onDelete: () => deleted = true,
        ),
      ));

      await tester.drag(find.text('Ada'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      // A confirm dialog guards the destructive action.
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });

    testWidgets('cancelling the dialog does not invoke onDelete',
        (tester) async {
      var deleted = false;
      await tester.pumpWidget(_host(
        OrderCard(
          order: _order(),
          onTap: () {},
          onDelete: () => deleted = true,
        ),
      ));

      await tester.drag(find.text('Ada'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isFalse);
    });
  });
}
