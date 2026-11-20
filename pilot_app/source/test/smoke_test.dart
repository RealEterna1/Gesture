import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_collector/main.dart';

void main() {
  testWidgets('setup and enrollment screens build',
      (tester) async {
    await tester.pumpWidget(const GestureApp());
    await tester.pump();

    expect(find.text('注册模板'), findsWidgets);

    await tester.tap(find.text('注册模板').first);
    await tester.pumpAndSettle();

    expect(find.text('采集第 1 次'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
