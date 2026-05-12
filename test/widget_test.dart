import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/main.dart';

void main() {
  testWidgets('App opens to login screen first', (WidgetTester tester) async {
    await tester.pumpWidget(const AmuwakStaffApp());

    // The login subtitle is unique to the login screen, so use it as the anchor.
    expect(find.text('Login to manage laundry orders'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('Empty login fields show validation messages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AmuwakStaffApp());

    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(find.text('Enter your email or phone'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('Wrong login shows error', (WidgetTester tester) async {
    await tester.pumpWidget(const AmuwakStaffApp());

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'wrong@amuwak.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrongpassword');

    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(find.text('Invalid staff login details.'), findsOneWidget);
  });

  testWidgets('Correct login opens staff dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AmuwakStaffApp());

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'staff@amuwak.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Staff Workspace'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Assigned orders'),
      find.byType(Scrollable).first,
      const Offset(0, -100),
    );

    expect(find.text('Assigned orders'), findsOneWidget);
  });
}
