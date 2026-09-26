import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/presentation/search/search_screen.dart';
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
