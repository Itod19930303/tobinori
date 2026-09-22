// F-01（現在地取得）の起動時挙動を確認する最小限のWidgetテスト。
//
// 設計書: docs/design/issue-1-current-location.md 2章
// アプリ起動時に`currentLocationProvider`経由で現在地取得処理
// （`fetchCurrentLocation`相当）が呼ばれ、ProviderScope配下で
// `TobinoriApp`が正しく動作することを確認する。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/data/location/location_repository.dart';
import 'package:tobinori/domain/location/get_current_location_usecase.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/main.dart';
import 'package:tobinori/presentation/widgets/location_status_banner.dart';
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

  testWidgets('ProviderScope配下でLocationStatusBannerが表示されること', (
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

    expect(find.byType(LocationStatusBanner), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(LocationStatusBanner), findsOneWidget);
  });
}
