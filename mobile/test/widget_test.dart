import 'package:flutter_test/flutter_test.dart';

import 'package:calendar/main.dart';

void main() {
  testWidgets('app starts on the auth screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Calendar++'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
