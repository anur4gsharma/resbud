import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/main.dart';

void main() {
  testWidgets('shows the Resbud app shell', (tester) async {
    await tester.pumpWidget(const ResbudApp());

    expect(find.text('Resbud'), findsOneWidget);
  });
}
