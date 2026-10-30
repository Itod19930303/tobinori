import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_state.dart';
import 'package:tobinori/presentation/common/offline_banner.dart';
import 'package:tobinori/presentation/search/destination_search_field.dart';
import 'package:tobinori/presentation/search/route_result_view.dart';
import 'package:tobinori/presentation/search/search_history_list.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/presentation/widgets/location_status_banner.dart'
    show locationFailureMessage;
import 'package:tobinori/providers/location/current_address_provider.dart';
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
/// 現在地の状態表示については、`LocationStatusBanner`（F-01が提供するWidget）を
/// そのまま再利用すると、「取得中」表示（`CircularProgressIndicator`、
/// ティッカー駆動のアニメーション）が`pumpAndSettle`ベースのWidgetテストで
/// 無限に停止しない問題を引き起こすため、本画面ではスピナーを使わず、
/// `currentLocationProvider`の状態（取得中／失敗理由）ごとの案内文＋
/// AppBarの再取得アクションという最小構成に留める。
/// 取得中に「取得できませんでした」と出さないよう、状態で文言を出し分ける。
/// `routeSearchProvider`が`notFound`へ遷移したことを`ref.listen`で検知し、
/// 画面上部にフラッシュメッセージ（`SnackBar`等）を表示する。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  // 履歴タップで入力欄を外から書き換えるため、画面側で保持する。
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _searchFromHistory(String stationName) {
    FocusScope.of(context).unfocus();
    _controller.text = stationName;
    ref
        .read(routeSearchProvider.notifier)
        .search(destinationStationName: stationName);
  }

  void _showDeleteFailed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('履歴を削除できませんでした')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = ref.watch(connectivityStatusProvider);
    final isOffline = connectivity.valueOrNull == ConnectivityStatus.offline;

    final locationState = ref.watch(currentLocationProvider);
    final locationPoint = ref.watch(currentLocationPointProvider);
    final isLocationUnavailable = locationPoint == null;

    final routeSearchState = ref.watch(routeSearchProvider);
    final isLoading = routeSearchState.status == RouteSearchStatus.loading;

    // 優先度判定（設計書5章備考）: offline/locationUnavailableが同時に成立する場合、
    // オフライン表示を優先し、現在地未取得の案内は表示しない。
    final canSearch = !isOffline && !isLocationUnavailable && !isLoading;

    // 結果表示中（loading/success）は結果を主役にするため履歴を出さない。
    final showHistory = routeSearchState.status != RouteSearchStatus.loading &&
        routeSearchState.status != RouteSearchStatus.success;

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
            if (!isOffline)
              _LocationStatusMessage(
                state: locationState,
                onOpenSettings: () =>
                    ref.read(locationRepositoryProvider).openAppSettings(),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: DestinationSearchField(
                controller: _controller,
                enabled: canSearch,
                onSubmit: (destinationStationName) {
                  ref
                      .read(routeSearchProvider.notifier)
                      .search(destinationStationName: destinationStationName);
                },
              ),
            ),
            if (showHistory)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RouteResultView(state: routeSearchState),
                    Expanded(
                      child: SearchHistoryList(
                        enabled: canSearch,
                        onSelect: _searchFromHistory,
                        onDeleteFailed: _showDeleteFailed,
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: RouteResultView(state: routeSearchState),
              ),
          ],
        ),
      ),
    );
  }
}

/// 現在地の取得状態に応じた案内文を出すWidget。
///
/// 取得中（初期・取得中）は「取得しています」、失敗時は原因別の文言を出し、
/// 取得に成功したときは何も出さない。スピナーは使わない（クラス冒頭のコメント参照）。
class _LocationStatusMessage extends StatelessWidget {
  const _LocationStatusMessage({
    required this.state,
    required this.onOpenSettings,
  });

  final LocationState state;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      LocationInitial() || LocationLoading() => const Padding(
          padding: EdgeInsets.all(16),
          child: Text('現在地を取得しています…'),
        ),
      LocationLoaded(:final point) => _CurrentLocationLabel(point: point),
      LocationFailed(:final reason) => Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text(locationFailureMessage(reason))),
              if (reason == LocationFailureReason.permissionDeniedForever) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onOpenSettings,
                  child: const Text('設定を開く'),
                ),
              ],
            ],
          ),
        ),
    };
  }
}

/// 取得済みの現在地を「現在地: 住所」の形で表示するWidget。
///
/// 住所の取得中は「住所を取得しています…」、住所を取得できなかったときは
/// 座標（小数4桁）にフォールバックする。スピナーは使わない。
class _CurrentLocationLabel extends ConsumerWidget {
  const _CurrentLocationLabel({required this.point});

  final LocationPoint point;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref.watch(currentAddressProvider);
    final text = address.when(
      loading: () => '住所を取得しています…',
      error: (_, _) => _coordinates(point),
      data: (value) => value ?? _coordinates(point),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '現在地: $text',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  static String _coordinates(LocationPoint point) =>
      '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
}
