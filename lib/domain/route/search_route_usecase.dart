import 'package:tobinori/data/route/route_repository.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/route_exceptions.dart';

/// 現在地と目的駅名から最短経路を検索するユースケース。
///
/// 設計書: docs/design/issue-2-station-search.md 4.3節
class SearchRouteUseCase {
  SearchRouteUseCase(this._repository);

  final RouteRepository _repository;

  Future<Route> call({
    required LocationPoint origin,
    required String destinationStationName,
  }) async {
    final route = await _repository.computeRoute(
      origin: origin,
      destinationStationName: destinationStationName,
    );

    if (route == null) {
      throw const RouteNotFoundException();
    }

    return route;
  }
}
