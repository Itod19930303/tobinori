// GetCurrentLocationUseCase のユニットテスト。
//
// 設計書: docs/design/issue-1-current-location.md 3.3節・7章
// - LocationRepositoryの戻り値（LocationSuccess/LocationFailureResult）をそのまま返すこと
//   （モックRepositoryを注入して検証）
//
// 注意: LocationRepositoryは抽象インターフェースを持たない具象クラス1つのみとする設計
// （3.4節）のため、ここではmocktailでLocationRepository自体をモック化する。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/data/location/location_repository.dart';
import 'package:tobinori/domain/location/get_current_location_usecase.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_point.dart';

class MockLocationRepository extends Mock implements LocationRepository {}

void main() {
  late MockLocationRepository repository;
  late GetCurrentLocationUseCase useCase;

  setUp(() {
    repository = MockLocationRepository();
    useCase = GetCurrentLocationUseCase(repository);
  });

  group('GetCurrentLocationUseCase.call()', () {
    test('Repositoryが成功結果を返した場合、そのままLocationSuccessを返すこと', () async {
      const point = LocationPoint(latitude: 35.681236, longitude: 139.767125);
      when(() => repository.getCurrentLocation())
          .thenAnswer((_) async => const LocationSuccess(point));

      final result = await useCase.call();

      expect(result, isA<LocationSuccess>());
      expect((result as LocationSuccess).point, equals(point));
      verify(() => repository.getCurrentLocation()).called(1);
    });

    test('Repositoryが失敗結果を返した場合、そのままLocationFailureResultを返すこと', () async {
      when(() => repository.getCurrentLocation()).thenAnswer(
        (_) async =>
            const LocationFailureResult(LocationFailureReason.timeout),
      );

      final result = await useCase.call();

      expect(result, isA<LocationFailureResult>());
      expect(
        (result as LocationFailureResult).reason,
        LocationFailureReason.timeout,
      );
      verify(() => repository.getCurrentLocation()).called(1);
    });
  });
}
