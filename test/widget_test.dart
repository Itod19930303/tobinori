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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/data/location/location_repository.dart';
import 'package:tobinori/domain/location/get_current_location_usecase.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/main.dart';
import 'package:tobinori/presentation/search/search_screen.dart';
import 'package:tobinori/providers/location/current_location_provider.dart';

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
        ],
        child: const TobinoriApp(),
      ),
    );

    expect(find.byType(SearchScreen), findsOneWidget);

    await tester.pump();

    expect(find.byType(SearchScreen), findsOneWidget);
  });
}
