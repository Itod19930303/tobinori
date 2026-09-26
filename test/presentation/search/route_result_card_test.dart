// RouteResultCard のWidgetテスト。
//
// 設計書: docs/design/issue-2-station-search.md 4.1節・8章「テスト観点」
//
// 【Redフェーズの前提】
// RouteResultCard は空のプレースホルダーを返すスタブであり、本テストは失敗する想定。
// 【実装エージェントへの前提共有】
// - 総所要時間は「30分」のように分単位を含む文言で表示される想定（textContainingで緩く検証）。
// - 乗換回数は「1回」のように回数を含む文言で表示される想定。
// - 区間リストには路線名（例: JR山手線）・行き先（例: 池袋方面）が含まれる想定。
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/presentation/search/route_result_card.dart';

void main() {
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
      RouteStep(
        type: RouteStepType.transit,
        duration: Duration(minutes: 10),
        lineName: 'JR中央線',
        headsign: '高尾方面',
        departureStopName: '新宿',
        arrivalStopName: '吉祥寺',
      ),
      RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 2)),
    ],
  );

  Future<void> pumpCard(WidgetTester tester, Route route) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RouteResultCard(route: route)),
      ),
    );
  }

  testWidgets('総所要時間が表示されること', (tester) async {
    await pumpCard(tester, route);

    expect(find.textContaining('30'), findsWidgets);
  });

  testWidgets('乗換回数が表示されること', (tester) async {
    await pumpCard(tester, route);

    expect(find.textContaining('1'), findsWidgets);
  });

  testWidgets('徒歩・電車混在の区間リストが路線名・行き先を含めて表示されること', (tester) async {
    await pumpCard(tester, route);

    expect(find.textContaining('JR山手線'), findsOneWidget);
    expect(find.textContaining('池袋方面'), findsOneWidget);
    expect(find.textContaining('JR中央線'), findsOneWidget);
    expect(find.textContaining('高尾方面'), findsOneWidget);
  });
}
