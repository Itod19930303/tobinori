import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/presentation/widgets/location_status_banner.dart';
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
      home: const _HomePage(),
    );
  }
}

/// F-02（検索画面）着手までの最小限のプレースホルダー画面。
///
/// このIssue（F-01）には専用画面がないため（設計書2章）、
/// 現在地取得状態を表示する`LocationStatusBanner`のみを配置する。
class _HomePage extends ConsumerWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationState = ref.watch(currentLocationProvider);
    final notifier = ref.read(currentLocationProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('トビノリ')),
      body: SafeArea(
        child: Column(
          children: [
            LocationStatusBanner(
              state: locationState,
              onRefetch: notifier.fetchCurrentLocation,
              onOpenSettings: () {
                ref.read(locationRepositoryProvider).openAppSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}
