// NearestStation / Route.nearestStation / RouteStep.departureStopLocation のユニットテスト。
//
// 設計書: docs/design/issue-3-route-guidance.md 3.3節・7章「テスト観点」
//
// 【Redフェーズの前提】
// - lib/domain/route/nearest_station.dart に NearestStation({required String name, LocationPoint? location}) を新設
// - Route に `NearestStation? get nearestStation` を追加
// - RouteStep に `LocationPoint? departureStopLocation`（任意の名前付き引数）を追加
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/nearest_station.dart';
import 'package:tobinori/domain/route/route.dart';

void main() {
  const shibuyaLocation = LocationPoint(latitude: 35.658, longitude: 139.7016);
  const shinjukuLocation = LocationPoint(latitude: 35.69, longitude: 139.70);

  const walk = RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 3));

  Route routeOf(List<RouteStep> steps) => Route(
        totalDuration: const Duration(minutes: 30),
        transferCount: 0,
        steps: steps,
      );

  group('Route.nearestStation', () {
    test('先頭が徒歩・次が電車なら、その電車の乗車駅名と座標を返すこと', () {
      final route = routeOf(const [
        walk,
        RouteStep(
          type: RouteStepType.transit,
          duration: Duration(minutes: 10),
          departureStopName: '渋谷',
          departureStopLocation: shibuyaLocation,
        ),
      ]);

      final station = route.nearestStation;

      expect(station, isNotNull);
      expect(station!.name, '渋谷');
      expect(station.location, shibuyaLocation);
    });

    test('電車が複数ある場合は最初の電車区間の乗車駅を返すこと', () {
      final route = routeOf(const [
        walk,
        RouteStep(
          type: RouteStepType.transit,
          duration: Duration(minutes: 10),
          departureStopName: '渋谷',
          departureStopLocation: shibuyaLocation,
        ),
        RouteStep(
          type: RouteStepType.transit,
          duration: Duration(minutes: 10),
          departureStopName: '新宿',
          departureStopLocation: shinjukuLocation,
        ),
      ]);

      expect(route.nearestStation!.name, '渋谷');
      expect(route.nearestStation!.location, shibuyaLocation);
    });

    test('乗車駅の座標が無い場合、locationはnullで駅名は返すこと', () {
      final route = routeOf(const [
        walk,
        RouteStep(
          type: RouteStepType.transit,
          duration: Duration(minutes: 10),
          departureStopName: '渋谷',
        ),
      ]);

      expect(route.nearestStation!.name, '渋谷');
      expect(route.nearestStation!.location, isNull);
    });

    test('電車区間が無い場合はnullであること', () {
      expect(routeOf(const [walk]).nearestStation, isNull);
    });

    test('stepsが空の場合はnullであること', () {
      expect(routeOf(const []).nearestStation, isNull);
    });

    test('電車区間はあるがdepartureStopNameがnullならnullであること', () {
      final route = routeOf(const [
        walk,
        RouteStep(type: RouteStepType.transit, duration: Duration(minutes: 10)),
      ]);

      expect(route.nearestStation, isNull);
    });

    test('電車区間はあるがdepartureStopNameが空文字ならnullであること', () {
      final route = routeOf(const [
        walk,
        RouteStep(
          type: RouteStepType.transit,
          duration: Duration(minutes: 10),
          departureStopName: '',
        ),
      ]);

      expect(route.nearestStation, isNull);
    });
  });

  group('RouteStep.departureStopLocation', () {
    RouteStep step(LocationPoint? location) => RouteStep(
          type: RouteStepType.transit,
          duration: const Duration(minutes: 10),
          departureStopName: '渋谷',
          departureStopLocation: location,
        );

    test('同じdepartureStopLocationなら等価でhashCodeも一致すること', () {
      expect(step(shibuyaLocation), equals(step(shibuyaLocation)));
      expect(step(shibuyaLocation).hashCode, step(shibuyaLocation).hashCode);
    });

    test('departureStopLocationが異なれば等価でないこと', () {
      expect(step(shibuyaLocation), isNot(equals(step(shinjukuLocation))));
      expect(step(shibuyaLocation), isNot(equals(step(null))));
    });

    test('toStringにdepartureStopLocationが含まれること', () {
      expect(step(shibuyaLocation).toString(), contains('departureStopLocation'));
    });
  });

  group('NearestStation', () {
    test('name・locationが同じなら等価でhashCodeも一致すること', () {
      const a = NearestStation(name: '渋谷', location: shibuyaLocation);
      const b = NearestStation(name: '渋谷', location: shibuyaLocation);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('nameまたはlocationが異なれば等価でないこと', () {
      const base = NearestStation(name: '渋谷', location: shibuyaLocation);

      expect(base, isNot(equals(const NearestStation(name: '新宿', location: shibuyaLocation))));
      expect(base, isNot(equals(const NearestStation(name: '渋谷'))));
    });
  });
}
