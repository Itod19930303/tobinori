// RouteGuidanceNotifier（routeGuidanceProvider）/ RouteGuidanceState のユニットテスト。
//
// 設計書: docs/design/issue-3-route-guidance.md 3.2節・4章・7章
//
// 【Redフェーズの前提（実装エージェントへ）】
// - lib/providers/route/route_guidance_provider.dart に以下を定義する。
//   enum RouteGuidanceStatus { idle, launching, launched, failed }
//   class RouteGuidanceState { const RouteGuidanceState({required this.status}); ==/hashCode }
//   routeGuidanceProvider: StateNotifierProvider<RouteGuidanceNotifier, RouteGuidanceState>
//   startRouteGuidanceUseCaseProvider: Provider<StartRouteGuidanceUseCase>
//   mapsLauncherRepositoryProvider: Provider<MapsLauncherRepository>
//   RouteGuidanceNotifier.startGuidance(NearestStation)
// - 初期状態は idle。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/guidance_launch_result.dart';
import 'package:tobinori/domain/route/nearest_station.dart';
import 'package:tobinori/domain/route/start_route_guidance_usecase.dart';
import 'package:tobinori/providers/route/route_guidance_provider.dart';

class MockStartRouteGuidanceUseCase extends Mock
    implements StartRouteGuidanceUseCase {}

void main() {
  const station = NearestStation(
    name: '渋谷',
    location: LocationPoint(latitude: 35.658, longitude: 139.7016),
  );

  late MockStartRouteGuidanceUseCase useCase;

  setUpAll(() {
    registerFallbackValue(station);
  });

  setUp(() {
    useCase = MockStartRouteGuidanceUseCase();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [startRouteGuidanceUseCaseProvider.overrideWithValue(useCase)],
    );
    addTearDown(container.dispose);
    return container;
  }

  List<RouteGuidanceStatus> recordStatuses(ProviderContainer container) {
    final statuses = <RouteGuidanceStatus>[];
    container.listen<RouteGuidanceState>(
      routeGuidanceProvider,
      (_, next) => statuses.add(next.status),
    );
    return statuses;
  }

  group('RouteGuidanceState', () {
    test('同じstatusなら等価でhashCodeも一致すること', () {
      const a = RouteGuidanceState(status: RouteGuidanceStatus.failed);
      const b = RouteGuidanceState(status: RouteGuidanceStatus.failed);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('statusが異なれば等価でないこと', () {
      const a = RouteGuidanceState(status: RouteGuidanceStatus.idle);
      const b = RouteGuidanceState(status: RouteGuidanceStatus.launched);
      expect(a, isNot(equals(b)));
    });
  });

  test('初期状態はidleであること', () {
    final container = buildContainer();
    expect(
        container.read(routeGuidanceProvider).status, RouteGuidanceStatus.idle);
  });

  for (final result in [
    GuidanceLaunchResult.launchedMapsApp,
    GuidanceLaunchResult.launchedBrowser,
  ]) {
    test('$result: idle → launching → launched と遷移すること', () async {
      when(() => useCase.call(any())).thenAnswer((_) async => result);
      final container = buildContainer();
      final statuses = recordStatuses(container);

      await container
          .read(routeGuidanceProvider.notifier)
          .startGuidance(station);

      expect(statuses,
          [RouteGuidanceStatus.launching, RouteGuidanceStatus.launched]);
      verify(() => useCase.call(station)).called(1);
    });
  }

  test('失敗: idle → launching → failed と遷移すること', () async {
    when(() => useCase.call(any()))
        .thenAnswer((_) async => GuidanceLaunchResult.failed);
    final container = buildContainer();
    final statuses = recordStatuses(container);

    await container.read(routeGuidanceProvider.notifier).startGuidance(station);

    expect(
        statuses, [RouteGuidanceStatus.launching, RouteGuidanceStatus.failed]);
  });

  test('UseCaseが想定外の例外を投げてもfailedに落ち、クラッシュしないこと', () async {
    when(() => useCase.call(any())).thenThrow(Exception('unexpected'));
    final container = buildContainer();
    final statuses = recordStatuses(container);

    await container.read(routeGuidanceProvider.notifier).startGuidance(station);

    expect(
        statuses, [RouteGuidanceStatus.launching, RouteGuidanceStatus.failed]);
  });

  test('launching中の再呼び出しではUseCaseが2回呼ばれないこと', () async {
    final completer = Completer<GuidanceLaunchResult>();
    when(() => useCase.call(any())).thenAnswer((_) => completer.future);
    final container = buildContainer();
    final notifier = container.read(routeGuidanceProvider.notifier);

    final first = notifier.startGuidance(station);
    await notifier.startGuidance(station);

    expect(container.read(routeGuidanceProvider).status,
        RouteGuidanceStatus.launching);
    completer.complete(GuidanceLaunchResult.launchedMapsApp);
    await first;

    verify(() => useCase.call(any())).called(1);
    expect(container.read(routeGuidanceProvider).status,
        RouteGuidanceStatus.launched);
  });

  test('failedの後に再度呼ぶと、再びlaunchingを経由すること', () async {
    when(() => useCase.call(any()))
        .thenAnswer((_) async => GuidanceLaunchResult.failed);
    final container = buildContainer();
    final notifier = container.read(routeGuidanceProvider.notifier);
    await notifier.startGuidance(station);
    final statuses = recordStatuses(container);

    await notifier.startGuidance(station);

    expect(
        statuses, [RouteGuidanceStatus.launching, RouteGuidanceStatus.failed]);
    verify(() => useCase.call(station)).called(2);
  });
}
