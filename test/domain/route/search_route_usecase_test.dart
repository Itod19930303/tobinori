// SearchRouteUseCase のユニットテスト。
//
// 設計書: docs/design/issue-2-station-search.md 4.3節・8章「テスト観点」
//
// 【Redフェーズの前提】
// SearchRouteUseCase.call() は未実装（UnimplementedErrorをthrowするスタブ）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/data/route/route_repository.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/route_exceptions.dart';
import 'package:tobinori/domain/route/search_route_usecase.dart';

class MockRouteRepository extends Mock implements RouteRepository {}

void main() {
  late MockRouteRepository repository;
  late SearchRouteUseCase useCase;

  const origin = LocationPoint(latitude: 35.681236, longitude: 139.767125);
  const destinationStationName = '渋谷';

  const route = Route(
    totalDuration: Duration(minutes: 30),
    transferCount: 1,
    steps: [
      RouteStep(type: RouteStepType.walk, duration: Duration(minutes: 3)),
      RouteStep(
        type: RouteStepType.transit,
        duration: Duration(minutes: 15),
        lineName: 'JR山手線',
        headsign: '池袋方面',
        departureStopName: '渋谷',
        arrivalStopName: '新宿',
      ),
    ],
  );

  setUp(() {
    repository = MockRouteRepository();
    useCase = SearchRouteUseCase(repository);
  });

  test('正常系: Repositoryが Route を返した場合、そのまま返却すること', () async {
    when(() => repository.computeRoute(
          origin: origin,
          destinationStationName: destinationStationName,
        )).thenAnswer((_) async => route);

    final result = await useCase.call(
      origin: origin,
      destinationStationName: destinationStationName,
    );

    expect(result, route);
  });

  test('異常系: Repositoryがnullを返した場合、RouteNotFoundExceptionをthrowすること', () async {
    when(() => repository.computeRoute(
          origin: origin,
          destinationStationName: destinationStationName,
        )).thenAnswer((_) async => null);

    expect(
      () => useCase.call(
        origin: origin,
        destinationStationName: destinationStationName,
      ),
      throwsA(isA<RouteNotFoundException>()),
    );
  });

  test(
    '異常系: RepositoryがRouteApiExceptionをthrowした場合、そのまま（または'
    'RouteApiExceptionとして）伝播すること',
    () async {
      when(() => repository.computeRoute(
            origin: origin,
            destinationStationName: destinationStationName,
          )).thenThrow(const RouteApiException('通信に失敗しました'));

      expect(
        () => useCase.call(
          origin: origin,
          destinationStationName: destinationStationName,
        ),
        throwsA(isA<RouteApiException>()),
      );
    },
  );
}
