import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/domain/history/search_history_entry.dart';
import 'package:tobinori/providers/history/search_history_provider.dart';

/// 検索履歴の一覧（ヘッダー＋行）。
///
/// 設計書: docs/design/issue-4-search-history.md 3.1節
/// SnackBarは表示せず、削除失敗は[onDeleteFailed]で呼び出し側へ通知する。
class SearchHistoryList extends ConsumerWidget {
  const SearchHistoryList({
    super.key,
    required this.enabled,
    required this.onSelect,
    required this.onDeleteFailed,
  });

  final bool enabled;

  /// 引数は保存されている`stationName`（「駅」なし）。
  final ValueChanged<String> onSelect;
  final VoidCallback onDeleteFailed;

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    // await後にrefが破棄済みになり得るため、先にnotifierを取得しておく。
    final notifier = ref.read(searchHistoryProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('検索履歴をすべて削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = await notifier.clear();
    if (!success) onDeleteFailed();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchHistoryProvider);
    final theme = Theme.of(context);

    switch (state.status) {
      case SearchHistoryStatus.loading:
        return const SizedBox.shrink();
      case SearchHistoryStatus.loadFailed:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '履歴を読み込めませんでした',
            style: theme.textTheme.bodySmall,
          ),
        );
      case SearchHistoryStatus.loaded:
        break;
    }
    if (state.entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text('検索履歴', style: theme.textTheme.titleSmall),
              ),
              TextButton(
                onPressed: () => _confirmClear(context, ref),
                child: const Text('すべて削除'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: state.entries.length,
            itemBuilder: (context, index) {
              final entry = state.entries[index];
              return SearchHistoryTile(
                entry: entry,
                enabled: enabled,
                onTap: () => onSelect(entry.stationName),
                onDelete: () async {
                  final notifier = ref.read(searchHistoryProvider.notifier);
                  final success = await notifier.remove(entry.id);
                  if (!success) onDeleteFailed();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class SearchHistoryTile extends StatelessWidget {
  const SearchHistoryTile({
    super.key,
    required this.entry,
    required this.enabled,
    required this.onTap,
    required this.onDelete,
  });

  final SearchHistoryEntry entry;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            enabled: enabled,
            label: '${entry.displayName}を検索',
            excludeSemantics: true,
            child: ListTile(
              enabled: enabled,
              leading: const Icon(Icons.history),
              title: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: enabled ? onTap : null,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: '${entry.displayName}を履歴から削除',
          onPressed: onDelete,
        ),
      ],
    );
  }
}
