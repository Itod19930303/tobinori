// LocationStatusBanner のWidgetテスト。
//
// 設計書: docs/design/issue-1-current-location.md 3.1節・7章
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/location/location_state.dart';
import 'package:tobinori/presentation/widgets/location_status_banner.dart';

void main() {
  Future<void> pumpBanner(
    WidgetTester tester, {
    required LocationState state,
    VoidCallback? onRefetch,
    VoidCallback? onOpenSettings,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationStatusBanner(
            state: state,
            onRefetch: onRefetch ?? () {},
            onOpenSettings: onOpenSettings ?? () {},
          ),
        ),
      ),
    );
  }

  // 「現在地を再取得」ボタンを探すためのfinder。
  // アイコンボタン（リフレッシュアイコン）として実装される想定（3.1節）。
  Finder findRefetchButton() => find.byIcon(Icons.refresh);

  Finder findOpenSettingsButton() => find.widgetWithText(
        ElevatedButton,
        '設定を開く',
      );

  group('LocationLoaded状態', () {
    testWidgets('「現在地を再取得」ボタン（アイコンボタン）が表示されること', (tester) async {
      const point = LocationPoint(latitude: 35.0, longitude: 139.0);
      await pumpBanner(tester, state: const LocationLoaded(point));

      expect(findRefetchButton(), findsOneWidget);
    });

    testWidgets('「現在地を再取得」ボタンをタップするとonRefetchコールバックが呼ばれること', (tester) async {
      const point = LocationPoint(latitude: 35.0, longitude: 139.0);
      var called = false;
      await pumpBanner(
        tester,
        state: const LocationLoaded(point),
        onRefetch: () => called = true,
      );

      await tester.tap(findRefetchButton());
      await tester.pump();

      expect(called, isTrue);
    });
  });

  group('LocationInitial状態', () {
    testWidgets('LocationLoadingと同一のローディング表示がされ、再取得ボタンは表示されない（またはタップ不可）であること',
        (tester) async {
      await pumpBanner(tester, state: const LocationInitial());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(findRefetchButton(), findsNothing);
    });
  });

  group('LocationLoading状態', () {
    testWidgets('ローディング表示がされ、再取得ボタンは表示されない（またはタップ不可）であること', (tester) async {
      await pumpBanner(tester, state: const LocationLoading());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(findRefetchButton(), findsNothing);
    });
  });

  group('LocationFailed状態', () {
    testWidgets('serviceDisabledの場合、対応するメッセージと「現在地を再取得」ボタンが表示されること',
        (tester) async {
      await pumpBanner(
        tester,
        state: const LocationFailed(LocationFailureReason.serviceDisabled),
      );

      expect(find.textContaining('位置情報サービス'), findsOneWidget);
      expect(findRefetchButton(), findsOneWidget);
    });

    testWidgets('permissionDeniedの場合、対応するメッセージと「現在地を再取得」ボタンが表示されること',
        (tester) async {
      await pumpBanner(
        tester,
        state: const LocationFailed(LocationFailureReason.permissionDenied),
      );

      expect(find.byType(Text), findsWidgets);
      expect(findRefetchButton(), findsOneWidget);
    });

    testWidgets('timeoutの場合、対応するメッセージと「現在地を再取得」ボタンが表示されること', (tester) async {
      await pumpBanner(
        tester,
        state: const LocationFailed(LocationFailureReason.timeout),
      );

      expect(find.textContaining('時間がかかっ'), findsOneWidget);
      expect(findRefetchButton(), findsOneWidget);
    });

    testWidgets('unknownの場合、対応するメッセージと「現在地を再取得」ボタンが表示されること', (tester) async {
      await pumpBanner(
        tester,
        state: const LocationFailed(LocationFailureReason.unknown),
      );

      expect(find.textContaining('取得できません'), findsOneWidget);
      expect(findRefetchButton(), findsOneWidget);
    });

    testWidgets(
      'permissionDeniedForeverの場合、対応するメッセージと「設定を開く」ボタンが表示され、'
      '「現在地を再取得」ボタンは表示されないこと',
      (tester) async {
        await pumpBanner(
          tester,
          state: const LocationFailed(
            LocationFailureReason.permissionDeniedForever,
          ),
        );

        expect(find.textContaining('設定'), findsWidgets);
        expect(findOpenSettingsButton(), findsOneWidget);
        expect(findRefetchButton(), findsNothing);
      },
    );

    testWidgets(
      '(permissionDeniedForeverを除く)状態で「現在地を再取得」ボタンをタップすると'
      'onRefetchコールバックが呼ばれること',
      (tester) async {
        var called = false;
        await pumpBanner(
          tester,
          state: const LocationFailed(LocationFailureReason.timeout),
          onRefetch: () => called = true,
        );

        await tester.tap(findRefetchButton());
        await tester.pump();

        expect(called, isTrue);
      },
    );

    testWidgets(
      'permissionDeniedForever状態で「設定を開く」ボタンをタップするとonOpenSettingsが呼ばれ、'
      'onRefetchは呼ばれないこと',
      (tester) async {
        var refetchCalled = false;
        var openSettingsCalled = false;
        await pumpBanner(
          tester,
          state: const LocationFailed(
            LocationFailureReason.permissionDeniedForever,
          ),
          onRefetch: () => refetchCalled = true,
          onOpenSettings: () => openSettingsCalled = true,
        );

        await tester.tap(findOpenSettingsButton());
        await tester.pump();

        expect(openSettingsCalled, isTrue);
        expect(refetchCalled, isFalse);
      },
    );
  });
}
