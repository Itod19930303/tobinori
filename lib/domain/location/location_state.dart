import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_point.dart';

/// `currentLocationProvider`（Riverpod）が保持する状態を表すsealed class。
///
/// 設計書: docs/design/issue-1-current-location.md 3.3節・4章
sealed class LocationState {
  const LocationState();
}

/// 起動直後、まだ取得を開始していない状態。
class LocationInitial extends LocationState {
  const LocationInitial();
}

/// 取得処理中の状態。
class LocationLoading extends LocationState {
  const LocationLoading();
}

/// 取得に成功した状態。
class LocationLoaded extends LocationState {
  const LocationLoaded(this.point);

  final LocationPoint point;
}

/// 取得に失敗した状態。
class LocationFailed extends LocationState {
  const LocationFailed(this.reason);

  final LocationFailureReason reason;
}
