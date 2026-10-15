import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/config/app_config.dart';
import '../memories/memories_page.dart';
import 'chat_record_widgets.dart';
import 'chat_records_page.dart';

class PersonalLibraryPage extends StatelessWidget {
  const PersonalLibraryPage({
    super.key,
    required this.config,
    required this.agents,
    required this.initialAgentId,
    this.api,
  });

  final AppConfig config;
  final List<AgentCapability> agents;
  final String initialAgentId;
  final AgentApiClient? api;

  Future<void> _openRecords(BuildContext context) async {
    final thread = await Navigator.of(context).push<ThreadSummary>(
      MaterialPageRoute(
        builder: (_) => ChatRecordsPage(
          config: config,
          agents: agents,
          initialAgentId: initialAgentId,
          api: api,
        ),
      ),
    );
    if (context.mounted && thread != null) Navigator.of(context).pop(thread);
  }

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('记忆与对话'),
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: RecordLayout(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            const RecordHero(
              eyebrow: 'YOUR PERSONAL COLLECTION',
              title: '关于你的，\n都在这里。',
              description: '有些话值得回看，有些小事值得记住。',
              icon: Icons.collections_bookmark_outlined,
            ),
            const SizedBox(height: 28),
            Text(
              '两种方式，留住日常',
              style: TextStyle(
                color: palette.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _CollectionCard(
              title: '长期记忆',
              eyebrow: 'MEMORY',
              description: '小美记住的偏好与习惯。\n随时查看、修改，或让它忘记。',
              tag: 'Mem0 · 小美',
              icon: Icons.psychology_outlined,
              color: palette.lavender,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => MemoriesPage(config: config, api: api),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _CollectionCard(
              title: '历史对话',
              eyebrow: 'CONVERSATIONS',
              description: '按日期回看聊过的内容。\n找到熟悉的话题，继续聊下去。',
              tag: '最近 30 天 · 所有助手',
              icon: Icons.auto_stories_outlined,
              color: palette.blush,
              onTap: () => _openRecords(context),
            ),
            const SizedBox(height: 24),
            Text(
              '记忆是从聊天中提炼的信息，对话是原本的聊天记录。整理记忆不会删除历史对话。',
              style: TextStyle(color: palette.muted, fontSize: 12, height: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.title,
    required this.eyebrow,
    required this.description,
    required this.tag,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final String eyebrow;
  final String description;
  final String tag;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = RecordPalette(context);
    return Material(
      color: palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: palette.accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 10,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          title,
                          style: TextStyle(
                            color: palette.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: palette.accent,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                description,
                style: TextStyle(color: palette.muted, height: 1.7),
              ),
              const SizedBox(height: 16),
              RecordTag(label: tag),
            ],
          ),
        ),
      ),
    );
  }
}
