import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/main.dart';

void main() {
  testWidgets('shows staff login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const AmuwakStaffApp());

    expect(find.text('Amuwak Staff'), findsOneWidget);
    expect(find.text('Login to manage laundry orders'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
