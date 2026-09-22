import 'package:tobinori/domain/location/location_failure_reason.dart';

/// 緯度・経度を保持する値オブジェクト。
///
/// 設計書: docs/design/issue-1-current-location.md 3.3節
/// F-02・F-03からも参照される共通の位置情報の型。
class LocationPoint {
  const LocationPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationPoint &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// 現在地取得の結果を表すsealed class。
///
/// [GetCurrentLocationUseCase.call] の戻り値型として使用される。
/// UI都合の「取得中」等の状態は含まず、成功/失敗のみを表す。
sealed class LocationResult {
  const LocationResult();
}

/// 現在地取得に成功した場合の結果。
class LocationSuccess extends LocationResult {
  const LocationSuccess(this.point);

  final LocationPoint point;
}

/// 現在地取得に失敗した場合の結果。
class LocationFailureResult extends LocationResult {
  const LocationFailureResult(this.reason);

  final LocationFailureReason reason;
}
