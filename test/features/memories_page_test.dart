import 'package:agent_voice_app/core/api/api_client.dart';
import 'package:agent_voice_app/core/api/api_models.dart';
import 'package:agent_voice_app/core/api/chat_record_models.dart';
import 'package:agent_voice_app/core/api/memory_models.dart';
import 'package:agent_voice_app/core/config/app_config.dart';
import 'package:agent_voice_app/features/conversations/personal_library_page.dart';
import 'package:agent_voice_app/features/memories/memories_page.dart';
import 'package:agent_voice_app/features/memories/memory_detail_page.dart';
import 'package:agent_voice_app/features/memories/memory_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const config = AppConfig(
  baseUrl: 'http://127.0.0.1:8000',
  accessToken: 'test-token',
  userId: '42',
);
const id = '11111111-1111-4111-8111-111111111111';
const secondId = '22222222-2222-4222-8222-222222222222';
MemoryRecord makeMemory({
  String text = '喜欢清晨散步，喝不加糖的咖啡。',
  String memoryId = id,
}) => MemoryRecord(
  id: memoryId,
  memory: text,
  userId: '42',
  agentId: 'mem0-chatbot',
  createdAt: '2026-10-14T00:00:00Z',
  updatedAt: '2026-10-14T08:30:00Z',
);

class FakeMemoryApi extends AgentApiClient {
  FakeMemoryApi() : super(config);
  MemoryRecord current = makeMemory();
  bool deleted = false;
  bool empty = false;
  Object? readFailure;
  Object? writeFailure;
  final listCursors = <String?>[];
  final historyCursors = <int?>[];
  int saves = 0;
  int deletions = 0;
  int bulkDeletions = 0;

  @override
  Future<List<ChatRecordDay>> chatRecords(String agentId) async => [
    ChatRecordDay(
      recordDate: '2026-10-13',
      latestAt: DateTime.utc(2026, 10, 13),
      conversationCount: 1,
    ),
  ];

  @override
  Future<ChatRecordDetail> chatRecordDetail(
    String agentId,
    String recordDate,
  ) async => ChatRecordDetail(
    recordDate: recordDate,
    conversations: [
      DailyChatConversation(
        threadId: 'source-thread',
        agentId: agentId,
        updatedAt: DateTime.utc(2026, 10, 13),
        title: '散步计划',
        messages: const [ChatItem(role: 'human', content: '明天去散步')],
      ),
    ],
  );

  @override
  Future<MemoryPage<MemoryRecord, String>> memories({
    int limit = 20,
    String? cursor,
  }) async {
    listCursors.add(cursor);
    if (readFailure != null) throw readFailure!;
    if (empty || deleted) return const MemoryPage(items: []);
    return cursor == null
        ? MemoryPage(items: [current], nextCursor: secondId)
        : MemoryPage(
            items: [makeMemory(memoryId: secondId, text: '周末想去海边看日落。')],
          );
  }

  @override
  Future<MemoryRecord> memory(String memoryId) async {
    if (readFailure != null) throw readFailure!;
    if (deleted) throw const ApiException(404, 'missing');
    return current;
  }

  @override
  Future<MemoryRecord> updateMemory(String memoryId, String text) async {
    saves++;
    if (writeFailure != null) throw writeFailure!;
    return current = MemoryRecord(
      id: memoryId,
      memory: text,
      userId: '42',
      agentId: 'mem0-chatbot',
      updatedAt: '2026-10-14T09:00:00Z',
    );
  }

  @override
  Future<int> deleteMemory(String memoryId) async {
    deletions++;
    if (writeFailure != null) throw writeFailure!;
    deleted = true;
    return 1;
  }

  @override
  Future<int> deleteMemories() async {
    bulkDeletions++;
    if (writeFailure != null) throw writeFailure!;
    empty = true;
    return 2;
  }

  @override
  Future<MemoryPage<MemoryHistoryEntry, int>> memoryHistory(
    String memoryId, {
    int limit = 20,
    int? cursor,
  }) async {
    historyCursors.add(cursor);
    if (readFailure != null) throw readFailure!;
    return cursor == null
        ? MemoryPage(
            items: [
              MemoryHistoryEntry(
                id: 1,
                memoryId: memoryId,
                event: 'ADD',
                newMemory: '喜欢咖啡',
                createdAt: '2026-10-14T00:00:00Z',
              ),
            ],
            nextCursor: 1,
          )
        : MemoryPage(
            items: [
              MemoryHistoryEntry(
                id: 2,
                memoryId: memoryId,
                event: deleted ? 'DELETE' : 'UPDATE',
                oldMemory: '喜欢咖啡',
                newMemory: deleted ? null : current.memory,
                updatedAt: '2026-10-14T09:00:00Z',
              ),
            ],
          );
  }
}

Widget memoryTestApp(
  Widget child, {
  bool dark = false,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.android,
  double keyboard = 0,
}) => MaterialApp(
  key: UniqueKey(),
  theme: ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorSchemeSeed: const Color(0xffd87568),
    platform: platform,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: child!,
  ),
  home: child,
);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'continuing history returns the selected thread through the library',
    (tester) async {
      final api = FakeMemoryApi();
      addTearDown(api.close);
      ThreadSummary? selected;
      await tester.pumpWidget(
        memoryTestApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.of(context).push<ThreadSummary>(
                    MaterialPageRoute(
                      builder: (_) => PersonalLibraryPage(
                        config: config,
                        agents: const [],
                        initialAgentId: 'mem0-chatbot',
                        api: api,
                      ),
                    ),
                  );
                },
                child: const Text('打开收藏页'),
              ),
            ),
          ),
        ),
      );
      await tapVisible(tester, find.text('打开收藏页'));
      await tapVisible(tester, find.text('历史对话'));
      await tapVisible(tester, find.byIcon(Icons.arrow_forward_ios_rounded));
      await tapVisible(tester, find.text('继续这段对话'));
      expect(selected?.threadId, 'source-thread');
      expect(selected?.agentId, 'mem0-chatbot');
      expect(find.text('打开收藏页'), findsOneWidget);
    },
  );

  testWidgets('list, edit, history pagination and deletion work together', (
    tester,
  ) async {
    final api = FakeMemoryApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      memoryTestApp(MemoriesPage(config: config, api: api)),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('加载更多'));
    expect(api.listCursors, [null, secondId]);
    expect(find.text('周末想去海边看日落。'), findsOneWidget);
    await tapVisible(tester, find.text(api.current.memory));
    expect(find.byType(MemoryDetailPage), findsOneWidget);
    await tapVisible(tester, find.text('编辑记忆'));
    await tester.enterText(
      find.byKey(const ValueKey('memory-editor')),
      '现在喜欢不加糖的茶。',
    );
    await tapVisible(tester, find.text('保存修改'));
    expect(api.saves, 1);
    expect(find.text('现在喜欢不加糖的茶。'), findsOneWidget);
    await tapVisible(tester, find.text('查看变更历史'));
    await tapVisible(tester, find.text('加载更多'));
    expect(api.historyCursors, [null, 1]);
    expect(find.text('变更前'), findsOneWidget);
    expect(find.text('变更后'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('删除这条记忆'));
    await tapVisible(tester, find.text('取消'));
    expect(api.deletions, 0);
    await tapVisible(tester, find.text('删除这条记忆'));
    await tapVisible(tester, find.text('确认删除'));
    expect(api.deletions, 1);
    await tapVisible(tester, find.text('查看变更历史'));
    await tapVisible(tester, find.text('加载更多'));
    expect(find.text('删除记忆'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('返回记忆列表'));
    expect(find.text('故事，才刚刚开始'), findsOneWidget);
  });

  testWidgets('bulk deletion confirms scope including unloaded memories', (
    tester,
  ) async {
    final api = FakeMemoryApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      memoryTestApp(MemoriesPage(config: config, api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('记忆管理'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('清空全部记忆'));
    expect(find.textContaining('包括尚未加载的记忆'), findsOneWidget);
    await tapVisible(tester, find.text('取消'));
    expect(api.bulkDeletions, 0);
    await tester.tap(find.byTooltip('记忆管理'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('清空全部记忆'));
    await tapVisible(tester, find.text('确认清空全部记忆'));
    expect(api.bulkDeletions, 1);
    expect(find.text('故事，才刚刚开始'), findsOneWidget);
  });

  testWidgets('uncertain writes require reviewing current state before retry', (
    tester,
  ) async {
    final api = FakeMemoryApi()
      ..writeFailure = const ApiException(504, 'timeout');
    addTearDown(api.close);
    await tester.pumpWidget(
      memoryTestApp(MemoryDetailPage(api: api, memoryId: id)),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('编辑记忆'));
    await tester.enterText(find.byKey(const ValueKey('memory-editor')), '新的偏好');
    await tapVisible(tester, find.text('保存修改'));
    expect(api.saves, 1);
    expect(find.textContaining('可能已在服务器完成'), findsOneWidget);
    expect(find.text('保存修改'), findsNothing);
    await tapVisible(tester, find.text('返回并核对当前状态'));
    expect(find.byType(MemoryDetailPage), findsOneWidget);
    expect(api.saves, 1);
  });

  testWidgets('unavailable and empty states allow an explicit refresh', (
    tester,
  ) async {
    final api = FakeMemoryApi()
      ..readFailure = const ApiException(503, 'disabled');
    addTearDown(api.close);
    await tester.pumpWidget(
      memoryTestApp(MemoriesPage(config: config, api: api)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('服务可能未启用'), findsOneWidget);
    api.readFailure = null;
    api.empty = true;
    await tapVisible(tester, find.text('重新加载'));
    expect(find.text('故事，才刚刚开始'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      testWidgets('320px and 200% text support $platform dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = FakeMemoryApi()
          ..current = makeMemory(text: '喜欢在海边散步，留出时间学习和陪伴家人。' * 12);
        addTearDown(api.close);
        Widget wrap(Widget page, {double keyboard = 0}) => memoryTestApp(
          page,
          dark: dark,
          scale: 2,
          platform: platform,
          keyboard: keyboard,
        );
        await tester.pumpWidget(
          wrap(
            PersonalLibraryPage(
              config: config,
              agents: const [],
              initialAgentId: 'mem0-chatbot',
              api: api,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('长期记忆'));
        await tapVisible(tester, find.text('加载更多'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(wrap(MemoryDetailPage(api: api, memoryId: id)));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('删除这条记忆'));
        expect(tester.takeException(), isNull);
        await tapVisible(tester, find.text('取消'));
        await tester.pumpWidget(
          wrap(MemoryHistoryPage(api: api, memoryId: id)),
        );
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('加载更多'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          wrap(MemoryEditPage(api: api, record: api.current), keyboard: 250),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('memory-editor')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(
          find.byKey(const ValueKey('memory-editor')),
          '更新后的日常',
        );
        await tester.scrollUntilVisible(
          find.text('保存修改'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
