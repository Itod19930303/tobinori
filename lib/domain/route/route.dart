/// 経路ステップの種別。
///
/// 設計書: docs/design/issue-2-station-search.md 4.3節
enum RouteStepType {
  /// 徒歩区間
  walk,

  /// 電車（乗換案内）区間
  transit,
}

/// 経路の1区間（徒歩または電車）を表すドメインモデル。
///
/// 設計書: docs/design/issue-2-station-search.md 4.3節
class RouteStep {
  const RouteStep({
    required this.type,
    required this.duration,
    this.lineName,
    this.headsign,
    this.departureStopName,
    this.arrivalStopName,
  });

  final RouteStepType type;
  final String? lineName;
  final String? headsign;
  final String? departureStopName;
  final String? arrivalStopName;
  final Duration duration;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RouteStep &&
        other.type == type &&
        other.lineName == lineName &&
        other.headsign == headsign &&
        other.departureStopName == departureStopName &&
        other.arrivalStopName == arrivalStopName &&
        other.duration == duration;
  }

  @override
  int get hashCode => Object.hash(
        type,
        lineName,
        headsign,
        departureStopName,
        arrivalStopName,
        duration,
      );

  @override
  String toString() =>
      'RouteStep(type: $type, lineName: $lineName, headsign: $headsign, '
      'departureStopName: $departureStopName, arrivalStopName: $arrivalStopName, '
      'duration: $duration)';
}

/// 最短経路1件を表すドメインモデル。
///
/// 設計書: docs/design/issue-2-station-search.md 4.3節
class Route {
  const Route({
    required this.totalDuration,
    required this.transferCount,
    required this.steps,
  });

  final Duration totalDuration;
  final int transferCount;
  final List<RouteStep> steps;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Route) return false;
    if (other.totalDuration != totalDuration) return false;
    if (other.transferCount != transferCount) return false;
    if (other.steps.length != steps.length) return false;
    for (var i = 0; i < steps.length; i++) {
      if (other.steps[i] != steps[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(totalDuration, transferCount, Object.hashAll(steps));

  @override
  String toString() =>
      'Route(totalDuration: $totalDuration, transferCount: $transferCount, '
      'steps: $steps)';
}
