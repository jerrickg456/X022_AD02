import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmesh/app/app.dart';

void main() {
  testWidgets('SonicMeshApp loads home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SonicMeshApp());
    expect(find.text('SONICMESH'), findsOneWidget);
    expect(find.text('BROADCAST CONSOLE'), findsOneWidget);
    expect(find.text('RECEIVER CONSOLE'), findsOneWidget);
    expect(find.text('DSP DIAGNOSTICS'), findsOneWidget);
  });
}
