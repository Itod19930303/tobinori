import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';
import 'package:tobinori/data/route/route_repository.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/route_exceptions.dart';
import 'package:tobinori/domain/route/search_route_usecase.dart';
import 'package:tobinori/providers/location/current_location_provider.dart';

/// 設計書: docs/design/issue-2-station-search.md 4.2節
/// すべて手書き（コード生成なし）のRiverpodで実装する。

/// `http.Client`のDIポイント。
final httpClientProvider = Provider<http.Client>((ref) {
  return http.Client();
});

/// Google Maps Platform APIキー。
///
/// `--dart-define-from-file`経由で注入する（設計書4.4節・8.3節参照）。
/// コードへの直書きは行わず、ビルド時定数として注入された値を返す。
/// ローカル動作確認手順は呼び出し元への報告を参照。
final mapsApiKeyProvider = Provider<String>((ref) {
  return const String.fromEnvironment('MAPS_API_KEY');
});

/// `RouteRepository`のDIポイント。
final routeRepositoryProvider = Provider<RouteRepository>((ref) {
  return RouteRepositoryImpl(
    client: ref.watch(httpClientProvider),
    apiKey: ref.watch(mapsApiKeyProvider),
  );
});

/// `SearchRouteUseCase`のDIポイント。
final searchRouteUseCaseProvider = Provider<SearchRouteUseCase>((ref) {
  return SearchRouteUseCase(ref.watch(routeRepositoryProvider));
});

/// `RouteSearchState.status`（状態遷移）。
///
/// 設計書: docs/design/issue-2-station-search.md 5章
enum RouteSearchStatus {
  idle,
  loading,
  success,
  notFound,
  error,
  locationUnavailable,
  offline,
}

/// `routeSearchProvider`が保持する状態。
///
/// 設計書: docs/design/issue-2-station-search.md 4.2節
class RouteSearchState {
  const RouteSearchState({
    required this.status,
    this.route,
    this.errorMessage,
    this.lastQuery,
  });

  const RouteSearchState.idle()
      : status = RouteSearchStatus.idle,
        route = null,
        errorMessage = null,
        lastQuery = null;

  final RouteSearchStatus status;
  final Route? route;
  final String? errorMessage;
  final String? lastQuery;

  RouteSearchState copyWith({
    RouteSearchStatus? status,
    Route? route,
    String? errorMessage,
    String? lastQuery,
  }) {
    return RouteSearchState(
      status: status ?? this.status,
      route: route ?? this.route,
      errorMessage: errorMessage ?? this.errorMessage,
      lastQuery: lastQuery ?? this.lastQuery,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RouteSearchState &&
        other.status == status &&
        other.route == route &&
        other.errorMessage == errorMessage &&
        other.lastQuery == lastQuery;
  }

  @override
  int get hashCode => Object.hash(status, route, errorMessage, lastQuery);

  @override
  String toString() =>
      'RouteSearchState(status: $status, route: $route, '
      'errorMessage: $errorMessage, lastQuery: $lastQuery)';
}

/// 検索画面の状態（`RouteSearchState`）を管理するNotifier。
///
/// 設計書: docs/design/issue-2-station-search.md 4.2節・5章
class RouteSearchNotifier extends StateNotifier<RouteSearchState> {
  RouteSearchNotifier(this._ref) : super(const RouteSearchState.idle()) {
    // `connectivityStatusProvider`がofflineを検知した時点で、他のどの状態からでも
    // offlineへ遷移させる（設計書5章）。オンライン復帰時はidleへ戻す（自動再検索はしない）。
    _ref.listen<AsyncValue<ConnectivityStatus>>(
      connectivityStatusProvider,
      (previous, next) {
        next.whenData((status) {
          if (status == ConnectivityStatus.offline) {
            if (state.status != RouteSearchStatus.offline) {
              state = state.copyWith(status: RouteSearchStatus.offline);
            }
          } else if (state.status == RouteSearchStatus.offline) {
            state = const RouteSearchState.idle();
          }
        });
      },
    );
  }

  final Ref _ref;

  /// 目的駅名で検索を実行する。
  ///
  /// 5章の状態遷移・二重送信ガード・優先度判定（offline優先）に従う。
  Future<void> search({required String destinationStationName}) async {
    // 二重送信ガード: loading中は新しいリクエストを発行しない。
    if (state.status == RouteSearchStatus.loading) {
      return;
    }

    final trimmed = destinationStationName.trim();
    if (trimmed.isEmpty) {
      return;
    }

    // オフライン優先判定: offline/locationUnavailableが同時に成立する場合、
    // offlineを優先する（設計書5章備考）。
    // `connectivityStatusProvider.future`はStreamProviderの初回値（または直近の
    // 確定値）を確定的に待つAPIであり、`Future.delayed(Duration.zero)`のような
    // タイミング依存の回避策を使わずにオフライン判定を確定させることができる。
    final connectivity = await _ref.read(connectivityStatusProvider.future);
    if (connectivity == ConnectivityStatus.offline) {
      state = state.copyWith(status: RouteSearchStatus.offline);
      return;
    }

    final origin = _ref.read(currentLocationPointProvider);
    if (origin == null) {
      state = state.copyWith(status: RouteSearchStatus.locationUnavailable);
      return;
    }

    state = RouteSearchState(
      status: RouteSearchStatus.loading,
      route: state.route,
      lastQuery: trimmed,
    );

    try {
      final route = await _ref.read(searchRouteUseCaseProvider).call(
            origin: origin,
            destinationStationName: trimmed,
          );
      // 検索中にofflineへ遷移していた場合はAPI応答を無視する（7章#3参照）。
      if (state.status == RouteSearchStatus.offline) {
        return;
      }
      state = RouteSearchState(
        status: RouteSearchStatus.success,
        route: route,
        lastQuery: trimmed,
      );
    } on RouteNotFoundException {
      if (state.status == RouteSearchStatus.offline) {
        return;
      }
      state = RouteSearchState(
        status: RouteSearchStatus.notFound,
        route: state.route,
        lastQuery: trimmed,
      );
    } on RouteApiException catch (e) {
      if (state.status == RouteSearchStatus.offline) {
        return;
      }
      state = RouteSearchState(
        status: RouteSearchStatus.error,
        route: state.route,
        errorMessage: e.message,
        lastQuery: trimmed,
      );
    }
  }
}

/// 検索画面全体の状態（`RouteSearchState`）を保持するProvider。
final routeSearchProvider =
    StateNotifierProvider<RouteSearchNotifier, RouteSearchState>((ref) {
  return RouteSearchNotifier(ref);
});
