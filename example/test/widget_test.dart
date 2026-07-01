import 'package:flutter_test/flutter_test.dart';

import 'package:easy_mail_example/main.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const EasyMailExampleApp());
    expect(find.text('Mail Login'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
