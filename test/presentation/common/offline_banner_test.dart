// OfflineBanner のWidgetテスト。
//
// 設計書: docs/design/issue-2-station-search.md 4.1節
// F-01/F-03/F-04からも共通利用される想定の共有Widget。
//
// 【Redフェーズの前提】
// OfflineBanner は空のプレースホルダーを返すスタブであり、本テストは失敗する想定。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';
import 'package:tobinori/presentation/common/offline_banner.dart';

void main() {
  Future<void> pumpBanner(
    WidgetTester tester, {
    required Stream<ConnectivityStatus> connectivityStream,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStatusProvider.overrideWith((ref) => connectivityStream),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OfflineBanner()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('オンライン時は「オフライン中です」が表示されないこと', (tester) async {
    await pumpBanner(
      tester,
      connectivityStream: Stream.value(ConnectivityStatus.online),
    );

    expect(find.textContaining('オフライン中です'), findsNothing);
  });

  testWidgets('オフライン時は「オフライン中です」が表示されること', (tester) async {
    await pumpBanner(
      tester,
      connectivityStream: Stream.value(ConnectivityStatus.offline),
    );

    expect(find.textContaining('オフライン中です'), findsOneWidget);
  });
}
