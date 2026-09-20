import 'package:agent_voice_app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the disconnected voice home', (tester) async {
    await tester.pumpWidget(const AgentVoiceApp());

    expect(find.text('Agent Voice'), findsOneWidget);
    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('先配置后端地址与短期 Token'), findsOneWidget);
  });
}
