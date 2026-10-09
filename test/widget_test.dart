// F-01（現在地取得）の起動時挙動、およびF-02（検索画面）がホーム画面として
// 表示されることを確認する最小限のWidgetテスト。
//
// 設計書: docs/design/issue-1-current-location.md 2章、
//         docs/design/issue-2-station-search.md 3章
// アプリ起動時に`currentLocationProvider`経由で現在地取得処理
// （`fetchCurrentLocation`相当）が呼ばれ、ProviderScope配下で
// `TobinoriApp`が正しく動作することを確認する。
// `main.dart`のホーム画面は`SearchScreen`（F-02）であり、
// `LocationStatusBanner`は`SearchScreen`からは直接使用しない設計判断のため
// （`presentation/search/search_screen.dart`のコメント参照）、
// ここでは`SearchScreen`（目的駅名入力欄）が表示されることを確認する。

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';
import 'package:tobinori/data/location/location_repository.dart';
import 'package:tobinori/domain/location/get_current_location_usecase.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/search_route_usecase.dart';
import 'package:tobinori/main.dart';
import 'package:tobinori/presentation/search/search_screen.dart';
import 'package:tobinori/providers/history/search_history_provider.dart';
import 'package:tobinori/providers/location/current_location_provider.dart';
import 'package:tobinori/providers/route/route_search_provider.dart';

import 'helpers/fake_search_history_repository.dart';

class _MockSearchRouteUseCase extends Mock implements SearchRouteUseCase {}

/// テスト用のフェイクUseCase。呼び出し回数を記録し、
/// 現在地取得成功結果を即座に返す。
class _FakeGetCurrentLocationUseCase extends GetCurrentLocationUseCase {
  _FakeGetCurrentLocationUseCase() : super(LocationRepository());

  int callCount = 0;

  @override
  Future<LocationResult> call() async {
    callCount++;
    return const LocationSuccess(
      LocationPoint(latitude: 35.0, longitude: 139.0),
    );
  }
}

void main() {
  testWidgets('起動時にfetchCurrentLocation相当の処理が1回呼ばれること', (
    WidgetTester tester,
  ) async {
    final fakeUseCase = _FakeGetCurrentLocationUseCase();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          getCurrentLocationUseCaseProvider.overrideWithValue(fakeUseCase),
          searchHistoryRepositoryProvider.overrideWithValue(
            FakeSearchHistoryRepository(),
          ),
        ],
        child: const TobinoriApp(),
      ),
    );

    // initState直後（microtask経由）の呼び出しを反映させる。
    await tester.pumpAndSettle();

    expect(fakeUseCase.callCount, 1);
  });

  testWidgets('ProviderScope配下でSearchScreen（F-02）がホーム画面として表示されること', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          getCurrentLocationUseCaseProvider.overrideWithValue(
            _FakeGetCurrentLocationUseCase(),
          ),
          searchHistoryRepositoryProvider.overrideWithValue(
            FakeSearchHistoryRepository(),
          ),
        ],
        child: const TobinoriApp(),
      ),
    );

    expect(find.byType(SearchScreen), findsOneWidget);

    await tester.pump();

    expect(find.byType(SearchScreen), findsOneWidget);
  });

  // 設計書: docs/design/issue-4-search-history.md 3.2節・7章
  // SearchScreen単体では保存リスナーが起動しないため、TobinoriApp経由で確認する。
  testWidgets('検索成功後に、その駅名が履歴に保存されること', (WidgetTester tester) async {
    const origin = LocationPoint(latitude: 35.0, longitude: 139.0);
    const route = Route(
      totalDuration: Duration(minutes: 30),
      transferCount: 0,
      steps: [
        RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 3)),
      ],
    );
    final searchUseCase = _MockSearchRouteUseCase();
    when(() => searchUseCase.call(
          origin: origin,
          destinationStationName: '渋谷',
        )).thenAnswer((_) async => route);
    final historyRepository = FakeSearchHistoryRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          getCurrentLocationUseCaseProvider.overrideWithValue(
            _FakeGetCurrentLocationUseCase(),
          ),
          searchRouteUseCaseProvider.overrideWithValue(searchUseCase),
          connectivityStatusProvider.overrideWith(
            (ref) => Stream.value(ConnectivityStatus.online),
          ),
          searchHistoryRepositoryProvider.overrideWithValue(historyRepository),
        ],
        child: const TobinoriApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '渋谷');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, '検索'));
    await tester.pumpAndSettle();

    expect(historyRepository.savedNames, ['渋谷']);
  });
}
