import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';
import 'package:tobinori/presentation/common/offline_banner.dart';
import 'package:tobinori/presentation/search/destination_search_field.dart';
import 'package:tobinori/presentation/search/route_result_view.dart';
import 'package:tobinori/providers/location/current_location_provider.dart';
import 'package:tobinori/providers/route/route_search_provider.dart';

/// 検索画面全体のレイアウト。
///
/// 設計書: docs/design/issue-2-station-search.md 3章・4.1節
/// `routeSearchProvider`と`connectivityStatusProvider`をwatchし、状態に応じて
/// `OfflineBanner`・`DestinationSearchField`・`RouteResultView`を出し分ける。
/// アプリのホーム画面（`lib/main.dart`）として本Widgetを表示するため、
/// F-01の現在地状態表示（現在地未取得時の案内文・再取得アクション）も
/// 本画面がホスト画面として統合する。
///
/// 現在地の状態表示については、`LocationStatusBanner`（F-01が提供する
/// `currentLocationProvider`のフル状態を購読するWidget）をそのまま再利用すると、
/// 「取得中」表示（`CircularProgressIndicator`、ティッカー駆動のアニメーション）が
/// `pumpAndSettle`ベースのWidgetテストで無限に停止しない問題を引き起こすため、
/// 本画面では`currentLocationPointProvider`（`LocationPoint?`、派生Provider）に
/// 基づく単純な案内文＋AppBarの再取得アクションという最小構成に留める
/// （設計判断。詳細は呼び出し元への実装報告を参照）。
/// `routeSearchProvider`が`notFound`へ遷移したことを`ref.listen`で検知し、
/// 画面上部にフラッシュメッセージ（`SnackBar`等）を表示する。
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityStatusProvider);
    final isOffline = connectivity.valueOrNull == ConnectivityStatus.offline;

    final locationPoint = ref.watch(currentLocationPointProvider);
    final isLocationUnavailable = locationPoint == null;

    final routeSearchState = ref.watch(routeSearchProvider);
    final isLoading = routeSearchState.status == RouteSearchStatus.loading;

    // 優先度判定（設計書5章備考）: offline/locationUnavailableが同時に成立する場合、
    // オフライン表示を優先し、現在地未取得の案内は表示しない。
    final canSearch = !isOffline && !isLocationUnavailable && !isLoading;

    ref.listen<RouteSearchState>(routeSearchProvider, (previous, next) {
      if (next.status == RouteSearchStatus.notFound &&
          previous?.status != RouteSearchStatus.notFound) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('該当する駅が見つかりませんでした')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('トビノリ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: '現在地を再取得',
            onPressed: () {
              ref.read(currentLocationProvider.notifier).fetchCurrentLocation();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OfflineBanner(),
            if (!isOffline && isLocationUnavailable)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('現在地を取得できませんでした。位置情報の設定を確認してください。'),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: DestinationSearchField(
                enabled: canSearch,
                onSubmit: (destinationStationName) {
                  ref
                      .read(routeSearchProvider.notifier)
                      .search(destinationStationName: destinationStationName);
                },
              ),
            ),
            Expanded(
              child: RouteResultView(state: routeSearchState),
            ),
          ],
        ),
      ),
    );
  }
}
