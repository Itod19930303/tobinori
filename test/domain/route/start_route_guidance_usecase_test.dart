// StartRouteGuidanceUseCase のユニットテスト。
//
// 設計書: docs/design/issue-3-route-guidance.md 3.3節・7章
//
// 【Redフェーズの前提】
// - StartRouteGuidanceUseCase(MapsLauncherRepository) / `Future<GuidanceLaunchResult> call(NearestStation)`
// - MapsLauncherRepository は lib/data/navigation/maps_launcher_repository.dart に定義
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/data/navigation/maps_launcher_repository.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/guidance_launch_result.dart';
import 'package:tobinori/domain/route/nearest_station.dart';
import 'package:tobinori/domain/route/start_route_guidance_usecase.dart';

class MockMapsLauncherRepository extends Mock implements MapsLauncherRepository {}

void main() {
  const station = NearestStation(
    name: '渋谷',
    location: LocationPoint(latitude: 35.658, longitude: 139.7016),
  );

  late MockMapsLauncherRepository repository;
  late StartRouteGuidanceUseCase useCase;

  setUpAll(() {
    registerFallbackValue(station);
  });

  setUp(() {
    repository = MockMapsLauncherRepository();
    useCase = StartRouteGuidanceUseCase(repository);
  });

  test('GuidanceLaunchResultは3値を持つこと', () {
    expect(
      GuidanceLaunchResult.values,
      containsAll([
        GuidanceLaunchResult.launchedMapsApp,
        GuidanceLaunchResult.launchedBrowser,
        GuidanceLaunchResult.failed,
      ]),
    );
    expect(GuidanceLaunchResult.values, hasLength(3));
  });

  for (final result in GuidanceLaunchResult.values) {
    test('Repositoryの結果($result)をそのまま返し、駅を渡して1回だけ呼ぶこと', () async {
      when(() => repository.launchWalkingNavigation(any()))
          .thenAnswer((_) async => result);

      final actual = await useCase(station);

      expect(actual, result);
      verify(() => repository.launchWalkingNavigation(station)).called(1);
    });
  }
}
