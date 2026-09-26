// Route / RouteStep のユニットテスト。
//
// 設計書: docs/design/issue-2-station-search.md 4.3節
// 値オブジェクト（不変・==/hashCodeオーバーライド）としての振る舞いを検証する。
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/route/route.dart';

void main() {
  group('RouteStep', () {
    test('同じ内容を持つインスタンス同士は等価であること', () {
      const a = RouteStep(
        type: RouteStepType.transit,
        duration: Duration(minutes: 10),
        lineName: 'JR山手線',
        headsign: '池袋方面',
        departureStopName: '渋谷',
        arrivalStopName: '新宿',
      );
      const b = RouteStep(
        type: RouteStepType.transit,
        duration: Duration(minutes: 10),
        lineName: 'JR山手線',
        headsign: '池袋方面',
        departureStopName: '渋谷',
        arrivalStopName: '新宿',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('walk区分の場合、路線名等はnullでも生成できること', () {
      const step = RouteStep(
        type: RouteStepType.walk,
        duration: Duration(minutes: 3),
      );

      expect(step.type, RouteStepType.walk);
      expect(step.lineName, isNull);
      expect(step.headsign, isNull);
    });
  });

  group('Route', () {
    test('同じ内容を持つインスタンス同士は等価であること', () {
      const steps = [
        RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 3)),
        RouteStep(
          type: RouteStepType.transit,
          duration: Duration(minutes: 15),
          lineName: 'JR山手線',
        ),
      ];
      const a = Route(
        totalDuration: Duration(minutes: 30),
        transferCount: 1,
        steps: steps,
      );
      const b = Route(
        totalDuration: Duration(minutes: 30),
        transferCount: 1,
        steps: steps,
      );

      expect(a, equals(b));
    });

    test('stepsの内容が異なる場合は等価でないこと', () {
      const a = Route(
        totalDuration: Duration(minutes: 30),
        transferCount: 1,
        steps: [
          RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 3)),
        ],
      );
      const b = Route(
        totalDuration: Duration(minutes: 30),
        transferCount: 1,
        steps: [
          RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 5)),
        ],
      );

      expect(a, isNot(equals(b)));
    });
  });
}
