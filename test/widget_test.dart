import 'package:flutter_test/flutter_test.dart';

import 'package:flutterstudy4/main.dart';

void main() {
  testWidgets('shows test library UI', (WidgetTester tester) async {
    await tester.pumpWidget(const Study4CloneApp());

    expect(find.text('New Economy TOEIC Test 1'), findsOneWidget);
    expect(find.text('New Economy TOEIC Test 10'), findsOneWidget);
    expect(find.text('#TOEIC'), findsWidgets);
    expect(find.text('Chi tiết'), findsWidgets);
  });
}
