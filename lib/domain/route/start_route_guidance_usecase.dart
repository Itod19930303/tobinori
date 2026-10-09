import 'package:tobinori/data/navigation/maps_launcher_repository.dart';
import 'package:tobinori/domain/route/guidance_launch_result.dart';
import 'package:tobinori/domain/route/nearest_station.dart';

/// 最寄り駅までの徒歩案内（Googleマップ起動）を開始するUseCase。
///
/// 設計書: docs/design/issue-3-route-guidance.md 3.3節
class StartRouteGuidanceUseCase {
  StartRouteGuidanceUseCase(this._repository);

  final MapsLauncherRepository _repository;

  Future<GuidanceLaunchResult> call(NearestStation station) {
    return _repository.launchWalkingNavigation(station);
  }
}
