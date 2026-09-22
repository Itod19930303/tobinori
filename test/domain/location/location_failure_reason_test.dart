// LocationFailureReason（enum）のユニットテスト。
//
// 設計書: docs/design/issue-1-current-location.md 3.3節
// 値: serviceDisabled, permissionDenied, permissionDeniedForever, timeout, unknown
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';

void main() {
  test('LocationFailureReasonは設計書で定義された5つの値を持つこと', () {
    expect(LocationFailureReason.values, hasLength(5));
    expect(
      LocationFailureReason.values,
      containsAll(<LocationFailureReason>[
        LocationFailureReason.serviceDisabled,
        LocationFailureReason.permissionDenied,
        LocationFailureReason.permissionDeniedForever,
        LocationFailureReason.timeout,
        LocationFailureReason.unknown,
      ]),
    );
  });
}
