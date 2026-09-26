import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';

/// `connectivityStatusProvider`がオフラインの時のみ表示する固定バナー。
///
/// 設計書: docs/design/issue-2-station-search.md 4.1節
/// F-01/F-03/F-04からも共通利用される共有Widget。
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityStatusProvider);
    final isOffline = connectivity.valueOrNull == ConnectivityStatus.offline;

    if (!isOffline) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'オフライン中です。新しい検索はできません。',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
      ),
    );
  }
}
