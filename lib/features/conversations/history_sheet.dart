import 'package:flutter/material.dart';

import '../../core/api/api_models.dart';

class HistorySheet extends StatelessWidget {
  const HistorySheet({
    super.key,
    required this.threads,
    required this.onSelected,
  });

  final List<ThreadSummary> threads;
  final ValueChanged<ThreadSummary> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(
                    '历史会话',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  Text('${threads.length} 条'),
                ],
              ),
            ),
            Expanded(
              child: threads.isEmpty
                  ? const Center(child: Text('暂无历史会话'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: threads.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final thread = threads[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.chat_bubble_outline),
                          ),
                          title: Text(
                            thread.title?.trim().isNotEmpty == true
                                ? thread.title!
                                : '未命名会话',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(thread.agentId),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(context);
                            onSelected(thread);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
