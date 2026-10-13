import 'dart:async';

import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/api/chat_record_models.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/conversations/chat_record_detail_page.dart';
import 'package:agent_voice_app/features/conversations/chat_record_widgets.dart';
import 'package:agent_voice_app/features/conversations/chat_records_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const config = AppConfig(
  baseUrl: 'http://127.0.0.1:8000',
  accessToken: 'test-token',
  userId: '42',
);
const agents = [
  AgentCapability(
    id: 'chatbot',
    description: 'Chat',
    speechMode: 'streaming',
    cancelExecution: true,
  ),
  AgentCapability(
    id: 'research-assistant',
    description: 'Research',
    speechMode: 'final_message',
    cancelExecution: false,
  ),
];
final day = ChatRecordDay(
  recordDate: '2026-10-13',
  latestAt: DateTime.utc(2026, 10, 13, 9, 40),
  conversationCount: 1,
);
final detail = ChatRecordDetail(
  recordDate: day.recordDate,
  conversations: [
    DailyChatConversation(
      threadId: 'thread-1',
      agentId: 'chatbot',
      updatedAt: day.latestAt,
      title: '为今天留一点灵感',
      messages: const [
        ChatItem(role: 'human', content: '帮我规划一下今天的安排。'),
        ChatItem(
          role: 'ai',
          content: '当然。先为最重要的事留出一小时，再给自己安排一次散步。\n今天，也记得慢一点。',
          memoryStatus: MemoryStatus.savedSearchFailed,
        ),
        ChatItem(role: 'tool', content: '工具查询结果'),
      ],
    ),
  ],
);

class FakeRecordsApi extends AgentApiClient {
  FakeRecordsApi() : super(config);
  Object? failure;
  List<ChatRecordDay> records = [day];
  final calls = <String>[];
  Completer<List<ChatRecordDay>>? pending;

  @override
  Future<List<ChatRecordDay>> chatRecords(String agentId) async {
    calls.add(agentId);
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return records;
  }

  @override
  Future<ChatRecordDetail> chatRecordDetail(
    String agentId,
    String recordDate,
  ) async {
    calls.add('$agentId/$recordDate');
    if (failure != null) throw failure!;
    return detail;
  }
}

Widget app(
  Widget child, {
  TargetPlatform platform = TargetPlatform.android,
  bool dark = false,
  double textScale = 1,
}) => MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    platform: platform,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorSchemeSeed: const Color(0xffd87568),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: child,
);

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    return;
  }
  await tester.scrollUntilVisible(
    finder,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  test('UTC date labels do not shift at the local midnight boundary', () {
    expect(
      recordDateLabel(
        '2026-10-13',
        now: DateTime.parse('2026-10-14T01:00:00+08:00'),
      ),
      '今天',
    );
    expect(recordTime(DateTime.parse('2026-10-13T01:30:00+08:00')), '17:30');
  });

  testWidgets('opens detail and returns the selected continuation thread', (
    tester,
  ) async {
    final api = FakeRecordsApi();
    addTearDown(api.close);
    ThreadSummary? selected;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<ThreadSummary>(
                  MaterialPageRoute(
                    builder: (_) => ChatRecordsPage(
                      config: config,
                      agents: agents,
                      initialAgentId: 'chatbot',
                      api: api,
                    ),
                  ),
                );
              },
              child: const Text('打开记录'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开记录'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('1 段对话 · 最近 09:40'));
    await tester.tap(find.text('1 段对话 · 最近 09:40'));
    await tester.pumpAndSettle();
    expect(find.text('聊天详情'), findsOneWidget);
    await scrollTo(tester, find.text('记忆处理完成，本轮回忆暂不可用'));
    expect(find.text('记忆处理完成，本轮回忆暂不可用'), findsOneWidget);
    await scrollTo(tester, find.text('工具记录'));
    await tester.tap(find.text('工具记录'));
    await tester.pumpAndSettle();
    expect(find.text('工具查询结果'), findsOneWidget);
    await scrollTo(tester, find.text('继续这段对话'));
    await tester.tap(find.text('继续这段对话'));
    await tester.pumpAndSettle();
    expect(selected?.threadId, 'thread-1');
    expect(api.calls, ['chatbot', 'chatbot/2026-10-13']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty and authentication error states support refresh and retry',
    (tester) async {
      final api = FakeRecordsApi()..records = [];
      addTearDown(api.close);
      await tester.pumpWidget(
        app(
          ChatRecordsPage(
            config: config,
            agents: agents,
            initialAgentId: 'chatbot',
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('故事，从下一句开始'));
      api.failure = const ApiException(401, 'expired');
      await tester.tap(find.byTooltip('刷新聊天记录'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('登录已过期，请返回个人主页重新登录。'));
      api.failure = null;
      api.records = [day];
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(find.text('1 段对话 · 最近 09:40'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching agents ignores a stale earlier response', (
    tester,
  ) async {
    final api = FakeRecordsApi()..pending = Completer<List<ChatRecordDay>>();
    addTearDown(api.close);
    await tester.pumpWidget(
      app(
        ChatRecordsPage(
          config: config,
          agents: agents,
          initialAgentId: 'chatbot',
          api: api,
        ),
      ),
    );
    await tester.pump();
    final oldRequest = api.pending!;
    api.pending = null;
    api.records = [];
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('研究助手').last);
    await tester.pump(const Duration(milliseconds: 300));
    oldRequest.complete([day]);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('故事，从下一句开始'));
    expect(api.calls, ['chatbot', 'research-assistant']);
    expect(find.text('1 段对话 · 最近 09:40'), findsNothing);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('small-screen layout supports $platform and large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeRecordsApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        app(
          ChatRecordsPage(
            config: config,
            agents: agents,
            initialAgentId: 'chatbot',
            api: api,
          ),
          platform: platform,
          dark: true,
          textScale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('1 段对话 · 最近 09:40'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('1 段对话 · 最近 09:40'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('继续这段对话'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('detail authentication failures can be retried', (tester) async {
    final api = FakeRecordsApi();
    api.failure = const ApiException(401, 'expired');
    addTearDown(api.close);
    await tester.pumpWidget(
      app(ChatRecordDetailPage(api: api, agentId: 'chatbot', record: day)),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('重新加载'));
    expect(find.text('登录已过期，请返回个人主页重新登录。'), findsOneWidget);
    api.failure = null;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('继续这段对话'));
    expect(find.text('暂时无法打开记录'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
