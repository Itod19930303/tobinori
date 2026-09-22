// LocationState（sealed class）のユニットテスト。
//
// 設計書: docs/design/issue-1-current-location.md 3.3節
// - LocationInitial（起動直後、未取得）
// - LocationLoading（取得処理中）
// - LocationLoaded（final LocationPoint point を保持）
// - LocationFailed（final LocationFailureReason reason を保持）
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/location/location_state.dart';

void main() {
  group('LocationState', () {
    test('LocationInitialはconstで生成でき、LocationStateのサブタイプであること', () {
      const state = LocationInitial();
      expect(state, isA<LocationState>());
    });

    test('LocationLoadingはconstで生成でき、LocationStateのサブタイプであること', () {
      const state = LocationLoading();
      expect(state, isA<LocationState>());
    });

    test('LocationLoadedはLocationPointを保持すること', () {
      const point = LocationPoint(latitude: 35.0, longitude: 139.0);
      const state = LocationLoaded(point);

      expect(state, isA<LocationState>());
      expect(state.point, equals(point));
    });

    test('LocationFailedはLocationFailureReasonを保持すること', () {
      const state = LocationFailed(LocationFailureReason.serviceDisabled);

      expect(state, isA<LocationState>());
      expect(state.reason, LocationFailureReason.serviceDisabled);
    });

    test('LocationStateはswitch式で4パターンを網羅的にパターンマッチできること（sealed class）', () {
      const point = LocationPoint(latitude: 0, longitude: 0);
      const states = <LocationState>[
        LocationInitial(),
        LocationLoading(),
        LocationLoaded(point),
        LocationFailed(LocationFailureReason.unknown),
      ];

      String describe(LocationState state) => switch (state) {
            LocationInitial() => 'initial',
            LocationLoading() => 'loading',
            LocationLoaded() => 'loaded',
            LocationFailed() => 'failed',
          };

      expect(states.map(describe), [
        'initial',
        'loading',
        'loaded',
        'failed',
      ]);
    });
  });
}
