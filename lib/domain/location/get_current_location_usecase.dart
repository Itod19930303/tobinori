import 'package:tobinori/data/location/location_repository.dart';
import 'package:tobinori/domain/location/location_point.dart';

/// 現在地取得のユースケース。
///
/// 設計書: docs/design/issue-1-current-location.md 3.3節
/// F-01時点では追加の業務ロジックはほぼ持たず、Repositoryの結果を薄くラップする。
class GetCurrentLocationUseCase {
  GetCurrentLocationUseCase(this._repository);

  final LocationRepository _repository;

  Future<LocationResult> call() {
    return _repository.getCurrentLocation();
  }
}
