// RouteGuidanceButton / RouteResultView（ボタン組み込み）のWidgetテスト。
//
// 設計書: docs/design/issue-3-route-guidance.md 3.1節・7章「Widgetテスト」
//
// 前提:
// - ボタンは`FilledButton`系で、ラベルに「{駅名}まで徒歩で案内」を含む。
// - 失敗時のSnackBarの文言は「Googleマップを起動できませんでした」。
// - RouteResultView はProviderScope配下で描画する。
// - launching中は静的表示（ボタン非活性のみ）で、pumpAndSettleが止まること。
import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/guidance_launch_result.dart';
import 'package:tobinori/domain/route/nearest_station.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/start_route_guidance_usecase.dart';
import 'package:tobinori/presentation/search/route_guidance_button.dart';
import 'package:tobinori/presentation/search/route_result_card.dart';
import 'package:tobinori/presentation/search/route_result_view.dart';
import 'package:tobinori/providers/route/route_guidance_provider.dart';
import 'package:tobinori/providers/route/route_search_provider.dart';

class MockStartRouteGuidanceUseCase extends Mock
    implements StartRouteGuidanceUseCase {}

void main() {
  const station = NearestStation(
    name: '渋谷',
    location: LocationPoint(latitude: 35.658, longitude: 139.7016),
  );

  const routeWithTransit = Route(
    totalDuration: Duration(minutes: 30),
    transferCount: 0,
    steps: [
      RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 3)),
      RouteStep(
        type: RouteStepType.transit,
        duration: Duration(minutes: 15),
        lineName: 'JR山手線',
        headsign: '池袋方面',
        departureStopName: '渋谷',
        departureStopLocation: LocationPoint(latitude: 35.658, longitude: 139.7016),
        arrivalStopName: '新宿',
      ),
    ],
  );

  const walkOnlyRoute = Route(
    totalDuration: Duration(minutes: 5),
    transferCount: 0,
    steps: [
      RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 5)),
    ],
  );

  late MockStartRouteGuidanceUseCase useCase;

  setUpAll(() {
    registerFallbackValue(station);
  });

  setUp(() {
    useCase = MockStartRouteGuidanceUseCase();
  });

  Future<void> pumpWidgetUnderTest(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          startRouteGuidanceUseCaseProvider.overrideWithValue(useCase),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
  }

  Finder findButton() => find.byType(FilledButton);

  group('RouteGuidanceButton', () {
    testWidgets('ラベルに最寄り駅名が含まれること', (tester) async {
      await pumpWidgetUnderTest(tester, const RouteGuidanceButton(station: station));

      expect(find.textContaining('渋谷まで徒歩で案内'), findsOneWidget);
    });

    testWidgets('セマンティクスラベルに駅名が含まれること', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(tester, const RouteGuidanceButton(station: station));

      expect(
        find.bySemanticsLabel(RegExp('渋谷まで徒歩で案内')),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('セマンティクスにtapアクションがあり、launching中は無効になること', (tester) async {
      final handle = tester.ensureSemantics();
      final completer = Completer<GuidanceLaunchResult>();
      when(() => useCase.call(any())).thenAnswer((_) => completer.future);
      await pumpWidgetUnderTest(tester, const RouteGuidanceButton(station: station));

      var data = tester.getSemantics(findButton());
      expect(data.label, contains('渋谷まで徒歩で案内'));
      expect(data.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);

      await tester.tap(findButton());
      await tester.pump();

      data = tester.getSemantics(findButton());
      expect(data.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);

      completer.complete(GuidanceLaunchResult.launchedMapsApp);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(findButton()).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('1タップでUseCaseが正しいNearestStationで1回呼ばれ、ダイアログが出ないこと', (tester) async {
      when(() => useCase.call(any()))
          .thenAnswer((_) async => GuidanceLaunchResult.launchedMapsApp);
      await pumpWidgetUnderTest(tester, const RouteGuidanceButton(station: station));

      await tester.tap(findButton());
      await tester.pumpAndSettle();

      verify(() => useCase.call(station)).called(1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('launching中は非活性になり、連打してもUseCaseは1回だけであること', (tester) async {
      final completer = Completer<GuidanceLaunchResult>();
      when(() => useCase.call(any())).thenAnswer((_) => completer.future);
      await pumpWidgetUnderTest(tester, const RouteGuidanceButton(station: station));

      await tester.tap(findButton());
      await tester.pump();

      expect(tester.widget<FilledButton>(findButton()).onPressed, isNull);

      await tester.tap(findButton(), warnIfMissed: false);
      await tester.pump();
      verify(() => useCase.call(any())).called(1);

      completer.complete(GuidanceLaunchResult.launchedMapsApp);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(findButton()).onPressed, isNotNull);
    });

    testWidgets('failedへの遷移でSnackBarが表示されること', (tester) async {
      when(() => useCase.call(any()))
          .thenAnswer((_) async => GuidanceLaunchResult.failed);
      await pumpWidgetUnderTest(tester, const RouteGuidanceButton(station: station));

      await tester.tap(findButton());
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Googleマップを起動できませんでした'), findsOneWidget);
    });

    for (final result in [
      GuidanceLaunchResult.launchedMapsApp,
      GuidanceLaunchResult.launchedBrowser,
    ]) {
      testWidgets('$result のときはSnackBarを出さないこと', (tester) async {
        when(() => useCase.call(any())).thenAnswer((_) async => result);
        await pumpWidgetUnderTest(tester, const RouteGuidanceButton(station: station));

        await tester.tap(findButton());
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsNothing);
      });
    }
  });

  group('RouteResultView（ボタン組み込み）', () {
    testWidgets('successかつ最寄り駅ありならRouteGuidanceButtonが表示されること', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const RouteResultView(
          state: RouteSearchState(
            status: RouteSearchStatus.success,
            route: routeWithTransit,
          ),
        ),
      );

      expect(find.byType(RouteResultCard), findsOneWidget);
      expect(find.byType(RouteGuidanceButton), findsOneWidget);
      expect(find.textContaining('渋谷まで徒歩で案内'), findsOneWidget);
    });

    testWidgets('successでも最寄り駅が無い（電車区間なし）ならボタンが表示されないこと', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const RouteResultView(
          state: RouteSearchState(
            status: RouteSearchStatus.success,
            route: walkOnlyRoute,
          ),
        ),
      );

      expect(find.byType(RouteResultCard), findsOneWidget);
      expect(find.byType(RouteGuidanceButton), findsNothing);
    });

    for (final status in [
      RouteSearchStatus.idle,
      RouteSearchStatus.error,
      RouteSearchStatus.notFound,
      RouteSearchStatus.offline,
      RouteSearchStatus.locationUnavailable,
    ]) {
      testWidgets('$status ではボタンが表示されないこと', (tester) async {
        await pumpWidgetUnderTest(
          tester,
          RouteResultView(
            state: RouteSearchState(status: status, route: routeWithTransit),
          ),
        );

        expect(find.byType(RouteGuidanceButton), findsNothing);
      });
    }

    testWidgets('loadingではボタンが表示されないこと', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const RouteResultView(
          state: RouteSearchState(
            status: RouteSearchStatus.loading,
            route: routeWithTransit,
          ),
        ),
      );

      expect(find.byType(RouteGuidanceButton), findsNothing);
    });
  });
}
