// RouteSearchNotifier（routeSearchProvider）のユニットテスト。
//
// 設計書: docs/design/issue-2-station-search.md 4.2節・5章・8章「テスト観点」
//
// 【Redフェーズの前提】
// RouteSearchNotifier.search() は未実装（UnimplementedErrorをthrowするスタブ）。
// currentLocationPointProvider（F-01）・connectivityStatusProvider（本Issue4.2節）を
// ProviderContainerのoverrideで差し替えて検証する。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/route_exceptions.dart';
import 'package:tobinori/domain/route/search_route_usecase.dart';
import 'package:tobinori/providers/location/current_location_provider.dart';
import 'package:tobinori/providers/route/route_search_provider.dart';

class MockSearchRouteUseCase extends Mock implements SearchRouteUseCase {}

void main() {
  const origin = LocationPoint(latitude: 35.681236, longitude: 139.767125);
  const destinationStationName = '渋谷';

  const route = Route(
    totalDuration: Duration(minutes: 30),
    transferCount: 1,
    steps: [
      RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 3)),
      RouteStep(
        type: RouteStepType.transit,
        duration: Duration(minutes: 15),
        lineName: 'JR山手線',
      ),
    ],
  );

  late MockSearchRouteUseCase useCase;

  setUpAll(() {
    registerFallbackValue(origin);
  });

  setUp(() {
    useCase = MockSearchRouteUseCase();
  });

  ProviderContainer buildContainer({
    LocationPoint? locationPoint = origin,
    Stream<ConnectivityStatus>? connectivityStream,
  }) {
    final container = ProviderContainer(
      overrides: [
        searchRouteUseCaseProvider.overrideWithValue(useCase),
        currentLocationPointProvider.overrideWithValue(locationPoint),
        connectivityStatusProvider.overrideWith(
          (ref) => connectivityStream ?? Stream.value(ConnectivityStatus.online),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('初期状態はidleであること', () {
    final container = buildContainer();
    expect(container.read(routeSearchProvider).status, RouteSearchStatus.idle);
  });

  group('正常系', () {
    test(
      '検索成功時に loading → success へ遷移し、状態にRouteが保持されること',
      () async {
        final container = buildContainer();
        // connectivityStatusProviderのストリーム購読を確定させる。
        await Future<void>.delayed(Duration.zero);

        when(() => useCase.call(
              origin: origin,
              destinationStationName: destinationStationName,
            )).thenAnswer((_) async => route);

        final states = <RouteSearchStatus>[];
        container.listen(
          routeSearchProvider,
          (previous, next) => states.add(next.status),
          fireImmediately: false,
        );

        await container
            .read(routeSearchProvider.notifier)
            .search(destinationStationName: destinationStationName);

        expect(states, contains(RouteSearchStatus.loading));
        expect(states.last, RouteSearchStatus.success);
        expect(container.read(routeSearchProvider).route, route);
      },
    );
  });

  group('異常系', () {
    test('RouteNotFoundException発生時にnotFoundへ遷移すること', () async {
      final container = buildContainer();
      await Future<void>.delayed(Duration.zero);

      when(() => useCase.call(
            origin: origin,
            destinationStationName: destinationStationName,
          )).thenThrow(const RouteNotFoundException());

      await container
          .read(routeSearchProvider.notifier)
          .search(destinationStationName: destinationStationName);

      expect(
        container.read(routeSearchProvider).status,
        RouteSearchStatus.notFound,
      );
    });

    test('RouteApiException発生時にerrorへ遷移すること', () async {
      final container = buildContainer();
      await Future<void>.delayed(Duration.zero);

      when(() => useCase.call(
            origin: origin,
            destinationStationName: destinationStationName,
          )).thenThrow(const RouteApiException('通信に失敗しました'));

      await container
          .read(routeSearchProvider.notifier)
          .search(destinationStationName: destinationStationName);

      expect(
        container.read(routeSearchProvider).status,
        RouteSearchStatus.error,
      );
    });
  });

  group('ガード系', () {
    test('オフライン時にsearch()を呼び出してもAPI呼び出しが発生せず、状態がofflineのままであること', () async {
      final container = buildContainer(
        connectivityStream: Stream.value(ConnectivityStatus.offline),
      );
      await Future<void>.delayed(Duration.zero);

      await container
          .read(routeSearchProvider.notifier)
          .search(destinationStationName: destinationStationName);

      expect(
        container.read(routeSearchProvider).status,
        RouteSearchStatus.offline,
      );
      verifyNever(() => useCase.call(
            origin: any(named: 'origin'),
            destinationStationName: any(named: 'destinationStationName'),
          ));
    });

    test(
      'currentLocationPointProviderがnull（現在地未取得）の時にsearch()を呼び出しても'
      'API呼び出しが発生せず、locationUnavailableのままであること',
      () async {
        final container = buildContainer(locationPoint: null);
        await Future<void>.delayed(Duration.zero);

        await container
            .read(routeSearchProvider.notifier)
            .search(destinationStationName: destinationStationName);

        expect(
          container.read(routeSearchProvider).status,
          RouteSearchStatus.locationUnavailable,
        );
        verifyNever(() => useCase.call(
              origin: any(named: 'origin'),
              destinationStationName: any(named: 'destinationStationName'),
            ));
      },
    );

    test('入力が空文字の場合にAPI呼び出しが発生しないこと', () async {
      final container = buildContainer();
      await Future<void>.delayed(Duration.zero);

      await container
          .read(routeSearchProvider.notifier)
          .search(destinationStationName: '   ');

      verifyNever(() => useCase.call(
            origin: any(named: 'origin'),
            destinationStationName: any(named: 'destinationStationName'),
          ));
    });

    test(
      'loading中にsearch()を再度呼び出しても、Repository・UseCaseの呼び出しが'
      '2重に発生しないこと（二重送信ガード）',
      () async {
        final container = buildContainer();
        await Future<void>.delayed(Duration.zero);

        final completer = Completer<Route>();
        when(() => useCase.call(
              origin: origin,
              destinationStationName: destinationStationName,
            )).thenAnswer((_) => completer.future);

        final notifier = container.read(routeSearchProvider.notifier);
        final first = notifier.search(
          destinationStationName: destinationStationName,
        );
        // search()冒頭のオフライン判定（connectivityStatusProvider.futureの確定待ち）が
        // 非同期であるため、loadingへ遷移するまで1ティック待つ。
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(routeSearchProvider).status,
          RouteSearchStatus.loading,
        );

        // loading中に2回目のsearch()を呼び出す。
        await notifier.search(destinationStationName: destinationStationName);

        completer.complete(route);
        await first;

        verify(() => useCase.call(
              origin: origin,
              destinationStationName: destinationStationName,
            )).called(1);
      },
    );

    test(
      '優先度判定: オフラインかつ現在地未取得の場合、状態はofflineが優先され'
      'locationUnavailableにはならないこと',
      () async {
        final container = buildContainer(
          locationPoint: null,
          connectivityStream: Stream.value(ConnectivityStatus.offline),
        );
        await Future<void>.delayed(Duration.zero);

        await container
            .read(routeSearchProvider.notifier)
            .search(destinationStationName: destinationStationName);

        expect(
          container.read(routeSearchProvider).status,
          RouteSearchStatus.offline,
        );
        expect(
          container.read(routeSearchProvider).status,
          isNot(RouteSearchStatus.locationUnavailable),
        );
      },
    );
  });

  group('検索中にオフラインへ遷移するケースの振り分け', () {
    test(
      'loading中にconnectivityStatusProviderがofflineを通知した場合（APIからの応答を待たずに'
      '接続断が検知された場合）はoffline状態へ遷移すること',
      () async {
        final connectivityController =
            StreamController<ConnectivityStatus>.broadcast();
        addTearDown(connectivityController.close);
        final container = buildContainer(
          connectivityStream: connectivityController.stream,
        );
        // routeSearchProviderを先に読み、connectivityStatusProviderの購読を
        // 開始させておく（broadcast streamは購読前に発行されたイベントを
        // 再生しないため、実アプリの起動順序（Provider生成→イベント発生）に
        // 合わせて明示的に先読みする）。
        container.read(routeSearchProvider);

        connectivityController.add(ConnectivityStatus.online);
        await Future<void>.delayed(Duration.zero);

        final completer = Completer<Route>();
        when(() => useCase.call(
              origin: origin,
              destinationStationName: destinationStationName,
            )).thenAnswer((_) => completer.future);

        final future = container
            .read(routeSearchProvider.notifier)
            .search(destinationStationName: destinationStationName);
        // search()冒頭のオフライン判定（connectivityStatusProvider.futureの確定待ち）が
        // 非同期であるため、loadingへ遷移するまで1ティック待つ。
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(routeSearchProvider).status,
          RouteSearchStatus.loading,
        );

        // APIの応答を待たずに接続断を通知する。
        connectivityController.add(ConnectivityStatus.offline);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(routeSearchProvider).status,
          RouteSearchStatus.offline,
        );

        // 後からAPI応答が来ても状態はoffline系のまま扱われることを想定（クラッシュしないことを確認）。
        completer.complete(route);
        await future;
      },
    );

    test(
      'loading中、connectivityStatusProviderはonlineのまま（接続断は検知されていない）で'
      'Routes API呼び出しがタイムアウト／通信エラーとなった場合はerror状態へ遷移すること'
      '（オンラインだがAPI失敗のケースと接続断そのもののケースを区別できること）',
      () async {
        final connectivityController =
            StreamController<ConnectivityStatus>.broadcast();
        addTearDown(connectivityController.close);
        final container = buildContainer(
          connectivityStream: connectivityController.stream,
        );
        container.read(routeSearchProvider);

        connectivityController.add(ConnectivityStatus.online);
        await Future<void>.delayed(Duration.zero);

        when(() => useCase.call(
              origin: origin,
              destinationStationName: destinationStationName,
            )).thenThrow(const RouteApiException('タイムアウトしました'));

        await container
            .read(routeSearchProvider.notifier)
            .search(destinationStationName: destinationStationName);

        expect(
          container.read(routeSearchProvider).status,
          RouteSearchStatus.error,
        );
      },
    );
  });

  group('オフライン復帰時の状態遷移', () {
    test(
      'offline状態から接続が復帰（online）した場合にidleへ戻ること'
      '（設計書5章「offlineから接続復帰した場合はidleへ戻す」）',
      () async {
        final connectivityController =
            StreamController<ConnectivityStatus>.broadcast();
        addTearDown(connectivityController.close);
        final container = buildContainer(
          connectivityStream: connectivityController.stream,
        );
        container.read(routeSearchProvider);

        connectivityController.add(ConnectivityStatus.offline);
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(routeSearchProvider).status,
          RouteSearchStatus.offline,
        );

        connectivityController.add(ConnectivityStatus.online);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(routeSearchProvider).status,
          RouteSearchStatus.idle,
        );
      },
    );

    test(
      'offline以外の状態（idle）でオンライン通知を受けても状態が変化しないこと'
      '（offline経由でない限りidleへの再代入は発生しないことの確認）',
      () async {
        final connectivityController =
            StreamController<ConnectivityStatus>.broadcast();
        addTearDown(connectivityController.close);
        final container = buildContainer(
          connectivityStream: connectivityController.stream,
        );
        container.read(routeSearchProvider);

        connectivityController.add(ConnectivityStatus.online);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(routeSearchProvider).status,
          RouteSearchStatus.idle,
        );
      },
    );
  });
}
