import 'package:tobinori/domain/location/location_point.dart';

/// 経路案内の目的地となる最寄り駅（最初の電車区間の乗車駅）。
///
/// 設計書: docs/design/issue-3-route-guidance.md 3.3節
class NearestStation {
  const NearestStation({required this.name, this.location});

  final String name;
  final LocationPoint? location;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NearestStation &&
        other.name == name &&
        other.location == location;
  }

  @override
  int get hashCode => Object.hash(name, location);

  @override
  String toString() => 'NearestStation(name: $name, location: $location)';
}
