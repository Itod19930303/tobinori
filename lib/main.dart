import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/presentation/search/search_screen.dart';
import 'package:tobinori/providers/history/search_history_provider.dart';
import 'package:tobinori/providers/location/current_location_provider.dart';

void main() {
  runApp(const ProviderScope(child: TobinoriApp()));
}

/// アプリのルートWidget。
///
/// 設計書: docs/design/issue-1-current-location.md 2章
/// 起動直後（`initState`相当のタイミング）に
/// `currentLocationProvider`の`fetchCurrentLocation()`を1回だけ呼び出す。
class TobinoriApp extends ConsumerStatefulWidget {
  const TobinoriApp({super.key});

  @override
  ConsumerState<TobinoriApp> createState() => _TobinoriAppState();
}

class _TobinoriAppState extends ConsumerState<TobinoriApp> {
  @override
  void initState() {
    super.initState();
    // 検索成功時の履歴保存リスナー（F-04）を画面に依存させず常駐させるため、起動時に生成する。
    ref.read(searchHistoryProvider);
    // アプリ起動時に現在地取得を1回だけ自動実行する（F-01の核心機能）。
    Future.microtask(
      () => ref.read(currentLocationProvider.notifier).fetchCurrentLocation(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'トビノリ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const SearchScreen(),
    );
  }
}
