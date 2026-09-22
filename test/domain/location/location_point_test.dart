// LocationPoint / LocationResult（LocationSuccess / LocationFailureResult）のユニットテスト。
//
// 設計書: docs/design/issue-1-current-location.md 3.3節
// - LocationPoint: 値オブジェクト（緯度・経度、const・不変・==/hashCodeオーバーライド）
// - LocationResult: sealed class（LocationSuccess(point) / LocationFailureResult(reason)）
//   GetCurrentLocationUseCase.call() の戻り値型として使用される。
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_point.dart';

void main() {
  group('LocationPoint', () {
    test('同じ緯度経度を持つインスタンス同士は等価であること', () {
      const a = LocationPoint(latitude: 35.681236, longitude: 139.767125);
      const b = LocationPoint(latitude: 35.681236, longitude: 139.767125);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('緯度または経度が異なるインスタンス同士は等価でないこと', () {
      const a = LocationPoint(latitude: 35.681236, longitude: 139.767125);
      const b = LocationPoint(latitude: 35.0, longitude: 139.767125);
      const c = LocationPoint(latitude: 35.681236, longitude: 139.0);

      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });

    test('constコンストラクタで生成できる不変クラスであること', () {
      const point = LocationPoint(latitude: 1.0, longitude: 2.0);

      expect(point.latitude, 1.0);
      expect(point.longitude, 2.0);
    });
  });

  group('LocationResult', () {
    test('LocationSuccessはLocationPointを保持すること', () {
      const point = LocationPoint(latitude: 35.0, longitude: 139.0);
      const result = LocationSuccess(point);

      expect(result, isA<LocationResult>());
      expect(result.point, equals(point));
    });

    test('LocationFailureResultはLocationFailureReasonを保持すること', () {
      const result = LocationFailureResult(LocationFailureReason.timeout);

      expect(result, isA<LocationResult>());
      expect(result.reason, LocationFailureReason.timeout);
    });

    test('LocationResultはswitch式で網羅的にパターンマッチできること（sealed class）', () {
      const LocationResult success = LocationSuccess(
        LocationPoint(latitude: 0, longitude: 0),
      );
      const LocationResult failure = LocationFailureResult(
        LocationFailureReason.unknown,
      );

      String describe(LocationResult result) => switch (result) {
            LocationSuccess() => 'success',
            LocationFailureResult() => 'failure',
          };

      expect(describe(success), 'success');
      expect(describe(failure), 'failure');
    });
  });
}
