// SearchScreen のWidgetテスト。
//
// 設計書: docs/design/issue-2-station-search.md 3章・4.1節・8章「テスト観点」
//
// 【Redフェーズの前提】
// SearchScreen / OfflineBanner / DestinationSearchField / RouteResultView は
// 空のプレースホルダー（SizedBox.shrink()等）を返すスタブであり、本テストは
// すべて失敗する想定（Green実装で下記の表示・操作仕様を満たすこと）。
//
// 【実装エージェントへの前提共有】
// - オフラインバナーの文言は「オフライン中です」を含むことを期待する。
// - 現在地未取得時の案内文言は「現在地」を含むことを期待する（文言自体は柔軟）。
// - 検索ボタンはテキスト「検索」を持つ`ElevatedButton`として実装される想定。
// - 目的駅名入力欄は`TextField`として実装される想定。
// - 該当駅なし時のフラッシュメッセージは`SnackBar`で「見つかりませんでした」を含む想定。
// - APIエラー時のメッセージは「取得できませんでした」を含む想定。
import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';
import 'package:tobinori/data/location/address_repository.dart';
import 'package:tobinori/data/location/location_repository.dart';
import 'package:tobinori/domain/location/get_current_location_usecase.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/location/location_state.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/route_exceptions.dart';
import 'package:tobinori/domain/route/search_route_usecase.dart';
import 'package:tobinori/presentation/search/route_result_card.dart';
import 'package:tobinori/presentation/search/search_screen.dart';
import 'package:tobinori/providers/location/current_address_provider.dart';
import 'package:tobinori/providers/location/current_location_provider.dart';
import 'package:tobinori/providers/history/search_history_provider.dart';
import 'package:tobinori/providers/route/route_search_provider.dart';

import '../../helpers/fake_search_history_repository.dart';

class MockSearchRouteUseCase extends Mock implements SearchRouteUseCase {}

class MockGetCurrentLocationUseCase extends Mock
    implements GetCurrentLocationUseCase {}

class MockLocationRepository extends Mock implements LocationRepository {}

class _FakeAddressRepository implements AddressRepository {
  _FakeAddressRepository(this._lookup);

  final Future<String?> Function(LocationPoint point) _lookup;

  @override
  Future<String?> addressOf(LocationPoint point) => _lookup(point);
}

/// 指定した現在地状態に固定する偽Notifier（取得処理は走らせない）。
class _FixedLocationNotifier extends CurrentLocationNotifier {
  _FixedLocationNotifier(LocationState initial)
      : super(MockGetCurrentLocationUseCase()) {
    state = initial;
  }

  @override
  Future<void> fetchCurrentLocation() async {}
}

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
        headsign: '池袋方面',
        departureStopName: '渋谷',
        arrivalStopName: '新宿',
      ),
    ],
  );

  late MockSearchRouteUseCase useCase;
  // 実DB（sqflite）はテストで使えないため、全テストで偽Repositoryにoverrideする。
  late FakeSearchHistoryRepository historyRepository;

  setUpAll(() {
    registerFallbackValue(origin);
  });

  setUp(() {
    useCase = MockSearchRouteUseCase();
    historyRepository = FakeSearchHistoryRepository();
  });

  late MockLocationRepository locationRepository;

  setUp(() {
    locationRepository = MockLocationRepository();
  });

  // 現在地の状態は[locationState]で直接指定できる。省略時は従来どおり
  // [locationPoint]（nullなら失敗＝unknown扱い、非nullなら取得済み）から決める。
  Future<void> pumpSearchScreen(
    WidgetTester tester, {
    LocationPoint? locationPoint = origin,
    LocationState? locationState,
    Stream<ConnectivityStatus>? connectivityStream,
    Future<String?> Function(LocationPoint point)? addressLookup,
  }) async {
    final effectiveLocationState = locationState ??
        (locationPoint == null
            ? const LocationFailed(LocationFailureReason.unknown)
            : LocationLoaded(locationPoint));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchRouteUseCaseProvider.overrideWithValue(useCase),
          searchHistoryRepositoryProvider.overrideWithValue(historyRepository),
          locationRepositoryProvider.overrideWithValue(locationRepository),
          // 実機の逆ジオコーディングはテストで使えないため、常に偽物へ差し替える。
          addressRepositoryProvider.overrideWithValue(
            _FakeAddressRepository(
              addressLookup ?? (_) async => '東京都新宿区西新宿',
            ),
          ),
          currentLocationProvider.overrideWith(
            (ref) => _FixedLocationNotifier(effectiveLocationState),
          ),
          connectivityStatusProvider.overrideWith(
            (ref) =>
                connectivityStream ?? Stream.value(ConnectivityStatus.online),
          ),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();
  }

  Finder findSearchButton() => find.widgetWithText(ElevatedButton, '検索');
  Finder findDestinationField() => find.byType(TextField);

  bool isButtonDisabled(WidgetTester tester, Finder finder) {
    final button = tester.widget<ElevatedButton>(finder);
    return button.onPressed == null;
  }

  group('オフライン時', () {
    testWidgets('OfflineBannerが表示され、検索ボタンが非活性になること', (tester) async {
      await pumpSearchScreen(
        tester,
        connectivityStream: Stream.value(ConnectivityStatus.offline),
      );

      expect(find.textContaining('オフライン中です'), findsOneWidget);
      expect(isButtonDisabled(tester, findSearchButton()), isTrue);
    });
  });

  group('現在地未取得時', () {
    testWidgets('検索ボタンが非活性で案内文が表示されること', (tester) async {
      await pumpSearchScreen(tester, locationPoint: null);

      expect(isButtonDisabled(tester, findSearchButton()), isTrue);
      expect(find.textContaining('現在地'), findsWidgets);
    });
  });

  group('現在地の状態表示', () {
    for (final state in <LocationState>[
      const LocationInitial(),
      const LocationLoading(),
    ]) {
      testWidgets(
        '${state.runtimeType}では「取得しています」が出て、'
        '「取得できませんでした」は出ず、検索ボタンは非活性になること',
        (tester) async {
          await pumpSearchScreen(tester, locationState: state);

          expect(find.text('現在地を取得しています…'), findsOneWidget);
          expect(find.textContaining('取得できませんでした'), findsNothing);
          expect(isButtonDisabled(tester, findSearchButton()), isTrue);
        },
      );
    }

    const failureCases = <LocationFailureReason, String>{
      LocationFailureReason.serviceDisabled:
          '位置情報サービスがオフになっています。端末の設定から有効にしてください。',
      LocationFailureReason.permissionDenied: '位置情報の利用が許可されていません。',
      LocationFailureReason.permissionDeniedForever:
          '位置情報の利用が許可されていません。アプリの設定から位置情報を許可してください。',
      LocationFailureReason.timeout: '現在地の取得に時間がかかっています。',
      LocationFailureReason.unknown: '現在地を取得できませんでした。',
    };
    failureCases.forEach((reason, message) {
      testWidgets('$reasonでは原因に対応した文言が出ること', (tester) async {
        await pumpSearchScreen(tester, locationState: LocationFailed(reason));

        expect(find.text(message), findsOneWidget);
        expect(find.text('現在地を取得しています…'), findsNothing);
        expect(isButtonDisabled(tester, findSearchButton()), isTrue);
        // 「設定を開く」は永久拒否のときだけ。
        expect(
          find.text('設定を開く'),
          reason == LocationFailureReason.permissionDeniedForever
              ? findsOneWidget
              : findsNothing,
        );
      });
    });

    testWidgets('「設定を開く」を押すとアプリの設定画面を開く処理が1回呼ばれること', (tester) async {
      when(() => locationRepository.openAppSettings())
          .thenAnswer((_) async {});
      await pumpSearchScreen(
        tester,
        locationState:
            const LocationFailed(LocationFailureReason.permissionDeniedForever),
      );

      await tester.tap(find.text('設定を開く'));
      await tester.pump();

      verify(() => locationRepository.openAppSettings()).called(1);
    });

    testWidgets('取得済みのときは失敗・取得中の案内が出ず、検索ボタンが活性であること', (tester) async {
      await pumpSearchScreen(tester, locationState: const LocationLoaded(origin));
      await tester.pump();

      expect(find.textContaining('現在地を取得'), findsNothing);
      expect(find.textContaining('位置情報'), findsNothing);
      expect(isButtonDisabled(tester, findSearchButton()), isFalse);
    });

    group('現在地の住所表示', () {
      testWidgets('取得済みのときは「現在地: 住所」が表示されること', (tester) async {
        await pumpSearchScreen(
          tester,
          locationState: const LocationLoaded(origin),
          addressLookup: (_) async => '東京都新宿区西新宿',
        );
        await tester.pump();

        expect(find.text('現在地: 東京都新宿区西新宿'), findsOneWidget);
      });

      testWidgets('住所の取得中は「住所を取得しています…」が表示されること', (tester) async {
        final completer = Completer<String?>();
        await pumpSearchScreen(
          tester,
          locationState: const LocationLoaded(origin),
          addressLookup: (_) => completer.future,
        );
        await tester.pump();

        expect(find.text('現在地: 住所を取得しています…'), findsOneWidget);

        completer.complete('東京都新宿区西新宿');
        // Futureの完了 → Providerの更新 → 再描画の順に反映されるまで待つ。
        await tester.pumpAndSettle();

        expect(find.text('現在地: 東京都新宿区西新宿'), findsOneWidget);
        expect(find.textContaining('住所を取得しています'), findsNothing);
      });

      testWidgets('住所がnullのときは座標（小数4桁）にフォールバックすること', (tester) async {
        await pumpSearchScreen(
          tester,
          locationState: const LocationLoaded(origin),
          addressLookup: (_) async => null,
        );
        await tester.pump();

        expect(find.text('現在地: 35.6812, 139.7671'), findsOneWidget);
      });

      testWidgets('住所の取得が例外になっても座標にフォールバックし、画面が壊れないこと', (tester) async {
        await pumpSearchScreen(
          tester,
          locationState: const LocationLoaded(origin),
          addressLookup: (_) async => throw Exception('geocoder'),
        );
        await tester.pump();

        expect(find.text('現在地: 35.6812, 139.7671'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('現在地の座標が渡されて住所を取りに行くこと', (tester) async {
        LocationPoint? requested;
        await pumpSearchScreen(
          tester,
          locationState: const LocationLoaded(origin),
          addressLookup: (p) async {
            requested = p;
            return '東京都千代田区丸の内';
          },
        );
        await tester.pump();

        expect(requested, origin);
      });

      for (final state in <LocationState>[
        const LocationInitial(),
        const LocationLoading(),
        const LocationFailed(LocationFailureReason.timeout),
      ]) {
        testWidgets('${state.runtimeType}のときは「現在地: 」を表示しないこと', (tester) async {
          await pumpSearchScreen(tester, locationState: state);
          await tester.pump();

          expect(find.textContaining('現在地: '), findsNothing);
        });
      }

      testWidgets('オフライン時は「現在地: 」を表示しないこと', (tester) async {
        await pumpSearchScreen(
          tester,
          locationState: const LocationLoaded(origin),
          connectivityStream: Stream.value(ConnectivityStatus.offline),
        );
        await tester.pump();

        expect(find.textContaining('現在地: '), findsNothing);
      });
    });

    testWidgets('オフライン時は、取得中でも現在地に関する案内が出ないこと', (tester) async {
      await pumpSearchScreen(
        tester,
        locationState: const LocationLoading(),
        connectivityStream: Stream.value(ConnectivityStatus.offline),
      );

      expect(find.textContaining('オフライン中です'), findsOneWidget);
      expect(find.text('現在地を取得しています…'), findsNothing);
    });
  });

  group('オフラインかつ現在地未取得（優先度判定）', () {
    testWidgets(
      'OfflineBanner（オフライン表示）が優先して表示され、'
      'locationUnavailable用の案内文は表示されないこと',
      (tester) async {
        await pumpSearchScreen(
          tester,
          locationPoint: null,
          connectivityStream: Stream.value(ConnectivityStatus.offline),
        );

        expect(find.textContaining('オフライン中です'), findsOneWidget);
        expect(find.textContaining('現在地を取得できませんでした'), findsNothing);
      },
    );
  });

  group('検索リクエスト中（loading）', () {
    testWidgets('入力欄・検索ボタンが非活性になること', (tester) async {
      final completer = Completer<Route>();
      when(() => useCase.call(
            origin: origin,
            destinationStationName: destinationStationName,
          )).thenAnswer((_) => completer.future);

      await pumpSearchScreen(tester);

      await tester.enterText(findDestinationField(), destinationStationName);
      await tester.pump();
      await tester.tap(findSearchButton());
      await tester.pump();

      expect(isButtonDisabled(tester, findSearchButton()), isTrue);
      final field = tester.widget<TextField>(findDestinationField());
      expect(field.enabled, isFalse);

      completer.complete(route);
      await tester.pumpAndSettle();
    });
  });

  group('正常系', () {
    testWidgets(
      '駅名を入力し検索ボタンを押すとローディング表示→成功時にRouteResultCardが表示されること',
      (tester) async {
        final completer = Completer<Route>();
        when(() => useCase.call(
              origin: origin,
              destinationStationName: destinationStationName,
            )).thenAnswer((_) => completer.future);

        await pumpSearchScreen(tester);

        await tester.enterText(
          findDestinationField(),
          destinationStationName,
        );
        await tester.pump();
        await tester.tap(findSearchButton());
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        completer.complete(route);
        await tester.pumpAndSettle();

        expect(find.byType(RouteResultCard), findsOneWidget);
      },
    );
  });

  group('該当駅なし', () {
    testWidgets(
      '画面上部にフラッシュメッセージが表示され、結果表示エリアは検索結果カードを表示せず'
      '直前の表示のまま、入力欄の値もクリアされていないこと',
      (tester) async {
        when(() => useCase.call(
              origin: origin,
              destinationStationName: destinationStationName,
            )).thenThrow(const RouteNotFoundException());

        await pumpSearchScreen(tester);

        await tester.enterText(
          findDestinationField(),
          destinationStationName,
        );
        await tester.pump();
        await tester.tap(findSearchButton());
        await tester.pumpAndSettle();

        expect(find.textContaining('見つかりませんでした'), findsOneWidget);
        expect(find.byType(RouteResultCard), findsNothing);

        final field = tester.widget<TextField>(findDestinationField());
        expect(field.controller?.text, destinationStationName);
      },
    );
  });

  group('APIエラー', () {
    testWidgets('エラーメッセージが表示されること', (tester) async {
      when(() => useCase.call(
            origin: origin,
            destinationStationName: destinationStationName,
          )).thenThrow(const RouteApiException('通信に失敗しました'));

      await pumpSearchScreen(tester);

      await tester.enterText(findDestinationField(), destinationStationName);
      await tester.pump();
      await tester.tap(findSearchButton());
      await tester.pumpAndSettle();

      expect(find.textContaining('取得できませんでした'), findsOneWidget);
    });
  });

  // ---- F-04 検索履歴（設計書: docs/design/issue-4-search-history.md 2章・7章）----
  group('検索履歴（F-04）', () {
    const loadFailedText = '履歴を読み込めませんでした';
    const historyHeader = '検索履歴';

    void stubAnySearch() {
      when(() => useCase.call(
            origin: any(named: 'origin'),
            destinationStationName: any(named: 'destinationStationName'),
          )).thenAnswer((_) async => route);
    }

    void verifyNoSearch() {
      verifyNever(() => useCase.call(
            origin: any(named: 'origin'),
            destinationStationName: any(named: 'destinationStationName'),
          ));
    }

    FakeSearchHistoryRepository withHistory() {
      historyRepository = FakeSearchHistoryRepository(
        initial: [
          historyEntry(3, '東京'),
          historyEntry(2, '渋谷'),
          historyEntry(1, '新宿'),
        ],
      );
      return historyRepository;
    }

    testWidgets('履歴があるとき、初期表示で履歴が新しい順に表示されること', (tester) async {
      withHistory();
      await pumpSearchScreen(tester);
      await tester.pump();

      expect(find.text(historyHeader), findsOneWidget);
      final tokyo = tester.getTopLeft(find.text('東京駅')).dy;
      final shibuya = tester.getTopLeft(find.text('渋谷駅')).dy;
      final shinjuku = tester.getTopLeft(find.text('新宿駅')).dy;
      expect(tokyo, lessThan(shibuya));
      expect(shibuya, lessThan(shinjuku));
    });

    testWidgets('履歴が正常に読み込めているときは「履歴を読み込めませんでした」が表示されないこと', (tester) async {
      withHistory();
      await pumpSearchScreen(tester);
      await tester.pump();

      expect(find.text(loadFailedText), findsNothing);
    });

    testWidgets('履歴0件のときは履歴ヘッダーも表示されないこと', (tester) async {
      await pumpSearchScreen(tester);
      await tester.pump();

      expect(find.text(historyHeader), findsNothing);
      expect(find.text('すべて削除'), findsNothing);
      expect(find.text(loadFailedText), findsNothing);
    });

    testWidgets('loadFailedのときは文言が表示され、検索は通常どおり行えること', (tester) async {
      historyRepository.failFindAll = true;
      stubAnySearch();
      await pumpSearchScreen(tester);
      await tester.pump();

      expect(find.text(loadFailedText), findsOneWidget);

      await tester.enterText(findDestinationField(), destinationStationName);
      await tester.pump();
      await tester.tap(findSearchButton());
      await tester.pumpAndSettle();

      expect(find.byType(RouteResultCard), findsOneWidget);
    });

    testWidgets(
      '履歴行（表示は「新宿駅」）をタップすると、入力欄に「新宿」が入り'
      'destinationStationName: "新宿" で検索が1回実行されること',
      (tester) async {
        withHistory();
        stubAnySearch();
        await pumpSearchScreen(tester);
        await tester.pump();

        await tester.tap(find.text('新宿駅'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(findDestinationField());
        expect(field.controller?.text, '新宿');
        verify(() => useCase.call(
              origin: origin,
              destinationStationName: '新宿',
            )).called(1);
      },
    );

    testWidgets('オフライン中は履歴行をタップしても検索されないが、「×」で削除できること', (tester) async {
      withHistory();
      stubAnySearch();
      await pumpSearchScreen(
        tester,
        connectivityStream: Stream.value(ConnectivityStatus.offline),
      );
      await tester.pump();

      // オフラインでも履歴は閲覧できる。
      expect(find.text('新宿駅'), findsOneWidget);

      await tester.tap(find.text('新宿駅'), warnIfMissed: false);
      await tester.pumpAndSettle();
      verifyNoSearch();

      await tester.tap(find.byTooltip('新宿駅を履歴から削除'));
      await tester.pumpAndSettle();
      expect(find.text('新宿駅'), findsNothing);
      expect(historyRepository.deletedIds, [1]);
    });

    testWidgets('現在地未取得中は履歴行をタップしても検索されないが、「×」で削除できること', (tester) async {
      withHistory();
      stubAnySearch();
      await pumpSearchScreen(tester, locationPoint: null);
      await tester.pump();

      await tester.tap(find.text('新宿駅'), warnIfMissed: false);
      await tester.pumpAndSettle();
      verifyNoSearch();

      await tester.tap(find.byTooltip('新宿駅を履歴から削除'));
      await tester.pumpAndSettle();
      expect(find.text('新宿駅'), findsNothing);
    });

    testWidgets('loading中とsuccess時は履歴が表示されないこと', (tester) async {
      withHistory();
      final completer = Completer<Route>();
      when(() => useCase.call(
            origin: origin,
            destinationStationName: destinationStationName,
          )).thenAnswer((_) => completer.future);
      await pumpSearchScreen(tester);
      await tester.pump();
      expect(find.text(historyHeader), findsOneWidget);

      await tester.enterText(findDestinationField(), destinationStationName);
      await tester.pump();
      await tester.tap(findSearchButton());
      await tester.pump();

      // loading
      expect(find.text(historyHeader), findsNothing);
      expect(find.text('新宿駅'), findsNothing);

      completer.complete(route);
      await tester.pumpAndSettle();

      // success
      expect(find.byType(RouteResultCard), findsOneWidget);
      expect(find.text(historyHeader), findsNothing);
    });

    testWidgets('notFound / error のときは履歴が表示されること', (tester) async {
      withHistory();
      when(() => useCase.call(
            origin: origin,
            destinationStationName: destinationStationName,
          )).thenThrow(const RouteNotFoundException());
      await pumpSearchScreen(tester);
      await tester.pump();

      await tester.enterText(findDestinationField(), destinationStationName);
      await tester.pump();
      await tester.tap(findSearchButton());
      await tester.pumpAndSettle();

      expect(find.textContaining('見つかりませんでした'), findsOneWidget);
      expect(find.text(historyHeader), findsOneWidget);

      when(() => useCase.call(
            origin: origin,
            destinationStationName: destinationStationName,
          )).thenThrow(const RouteApiException('通信に失敗しました'));
      await tester.tap(findSearchButton());
      await tester.pumpAndSettle();

      expect(find.textContaining('取得できませんでした'), findsOneWidget);
      expect(find.text(historyHeader), findsOneWidget);
    });

    testWidgets('削除に失敗すると「履歴を削除できませんでした」のSnackBarが表示されること', (tester) async {
      withHistory().failDelete = true;
      await pumpSearchScreen(tester);
      await tester.pump();

      await tester.tap(find.byTooltip('新宿駅を履歴から削除'));
      await tester.pumpAndSettle();

      expect(find.text('履歴を削除できませんでした'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      // 失敗時は一覧を変えない。
      expect(find.text('新宿駅'), findsOneWidget);
    });

    testWidgets('全件削除に失敗したときもSnackBarが表示されること', (tester) async {
      withHistory().failDeleteAll = true;
      await pumpSearchScreen(tester);
      await tester.pump();

      await tester.tap(find.text('すべて削除'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('削除'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('履歴を削除できませんでした'), findsOneWidget);
    });
  });
}
