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
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/route_exceptions.dart';
import 'package:tobinori/domain/route/search_route_usecase.dart';
import 'package:tobinori/presentation/search/route_result_card.dart';
import 'package:tobinori/presentation/search/search_screen.dart';
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
        headsign: '池袋方面',
        departureStopName: '渋谷',
        arrivalStopName: '新宿',
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

  Future<void> pumpSearchScreen(
    WidgetTester tester, {
    LocationPoint? locationPoint = origin,
    Stream<ConnectivityStatus>? connectivityStream,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchRouteUseCaseProvider.overrideWithValue(useCase),
          currentLocationPointProvider.overrideWithValue(locationPoint),
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
}
