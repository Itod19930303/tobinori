// RouteRepositoryImpl のユニットテスト。
//
// 設計書: docs/design/issue-2-station-search.md 4.4節・6.1節・8章「テスト観点」
// http.Client をmocktailのMockに差し替え、実際のネットワーク通信に依存せずに検証する。
//
// 【Redフェーズの前提】
// RouteRepositoryImpl.computeRoute() は未実装（UnimplementedErrorをthrowするスタブ）。
// 実装エージェントは本テストが期待するリクエスト/レスポンスの仕様に従って実装すること。
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/data/route/route_repository.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/route_exceptions.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient client;
  late RouteRepositoryImpl repository;

  const origin = LocationPoint(latitude: 35.681236, longitude: 139.767125);
  const destinationStationName = '渋谷';
  const apiKey = 'dummy-api-key';

  setUpAll(() {
    registerFallbackValue(Uri.parse(RouteRepositoryImpl.endpoint));
  });

  setUp(() {
    client = MockHttpClient();
    repository = RouteRepositoryImpl(client: client, apiKey: apiKey);
  });

  http.Response jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
    return http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  final mixedRouteResponseBody = {
    'routes': [
      {
        'duration': '1830s',
        'legs': [
          {
            'steps': [
              {
                'travelMode': 'WALK',
                'staticDuration': '180s',
                'navigationInstruction': {'instructions': '駅まで歩く'},
              },
              {
                'travelMode': 'TRANSIT',
                'staticDuration': '900s',
                'transitDetails': {
                  'stopDetails': {
                    'departureStop': {'name': '渋谷'},
                    'arrivalStop': {'name': '新宿'},
                  },
                  'transitLine': {'name': 'JR山手線'},
                  'headsign': '池袋方面',
                },
              },
              {
                'travelMode': 'TRANSIT',
                'staticDuration': '600s',
                'transitDetails': {
                  'stopDetails': {
                    'departureStop': {'name': '新宿'},
                    'arrivalStop': {'name': '吉祥寺'},
                  },
                  'transitLine': {'name': 'JR中央線'},
                  'headsign': '高尾方面',
                },
              },
              {
                'travelMode': 'WALK',
                'staticDuration': '150s',
                'navigationInstruction': {'instructions': '改札を出て歩く'},
              },
            ],
          },
        ],
      },
    ],
  };

  group('正常系: レスポンスJSONからRouteへのマッピング', () {
    test('徒歩・電車混在、乗換複数回のレスポンスが期待通りのRouteにマッピングされること', () async {
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(mixedRouteResponseBody));

      final route = await repository.computeRoute(
        origin: origin,
        destinationStationName: destinationStationName,
      );

      expect(route, isNotNull);
      expect(route!.totalDuration, const Duration(seconds: 1830));
      // transit区分の出現回数(2) - 1 = 1
      expect(route.transferCount, 1);
      expect(route.steps, hasLength(4));

      expect(route.steps[0].type, RouteStepType.walk);
      expect(route.steps[0].duration, const Duration(seconds: 180));

      expect(route.steps[1].type, RouteStepType.transit);
      expect(route.steps[1].duration, const Duration(seconds: 900));
      expect(route.steps[1].lineName, 'JR山手線');
      expect(route.steps[1].headsign, '池袋方面');
      expect(route.steps[1].departureStopName, '渋谷');
      expect(route.steps[1].arrivalStopName, '新宿');

      expect(route.steps[2].type, RouteStepType.transit);
      expect(route.steps[2].lineName, 'JR中央線');
      expect(route.steps[2].headsign, '高尾方面');
      expect(route.steps[2].departureStopName, '新宿');
      expect(route.steps[2].arrivalStopName, '吉祥寺');

      expect(route.steps[3].type, RouteStepType.walk);
      expect(route.steps[3].duration, const Duration(seconds: 150));
    });

    test('乗換なし（徒歩＋電車1本のみ）の場合、transferCountが0未満にならず0であること', () async {
      final body = {
        'routes': [
          {
            'duration': '600s',
            'legs': [
              {
                'steps': [
                  {
                    'travelMode': 'WALK',
                    'staticDuration': '120s',
                    'navigationInstruction': {'instructions': '駅まで歩く'},
                  },
                  {
                    'travelMode': 'TRANSIT',
                    'staticDuration': '480s',
                    'transitDetails': {
                      'stopDetails': {
                        'departureStop': {'name': '渋谷'},
                        'arrivalStop': {'name': '新宿'},
                      },
                      'transitLine': {'name': 'JR山手線'},
                      'headsign': '池袋方面',
                    },
                  },
                ],
              },
            ],
          },
        ],
      };
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(body));

      final route = await repository.computeRoute(
        origin: origin,
        destinationStationName: destinationStationName,
      );

      expect(route, isNotNull);
      expect(route!.transferCount, 0);
    });
  });

  group('異常系', () {
    test('routesが空配列のレスポンスの場合、nullを返すこと', () async {
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse({'routes': []}));

      final route = await repository.computeRoute(
        origin: origin,
        destinationStationName: destinationStationName,
      );

      expect(route, isNull);
    });

    test('HTTPステータス400（4xx）の場合、RouteApiExceptionをthrowすること', () async {
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => http.Response('{"error": "bad request"}', 400),
      );

      expect(
        () => repository.computeRoute(
          origin: origin,
          destinationStationName: destinationStationName,
        ),
        throwsA(isA<RouteApiException>()),
      );
    });

    test('HTTPステータス403（認証エラー）の場合、RouteApiExceptionをthrowすること', () async {
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => http.Response('{"error": "forbidden"}', 403),
      );

      expect(
        () => repository.computeRoute(
          origin: origin,
          destinationStationName: destinationStationName,
        ),
        throwsA(isA<RouteApiException>()),
      );
    });

    test('HTTPステータス500（5xx）の場合、RouteApiExceptionをthrowすること', () async {
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer(
        (_) async => http.Response('internal server error', 500),
      );

      expect(
        () => repository.computeRoute(
          origin: origin,
          destinationStationName: destinationStationName,
        ),
        throwsA(isA<RouteApiException>()),
      );
    });

    test('タイムアウト時にRouteApiExceptionをthrowすること', () async {
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenThrow(TimeoutException('timeout'));

      expect(
        () => repository.computeRoute(
          origin: origin,
          destinationStationName: destinationStationName,
        ),
        throwsA(isA<RouteApiException>()),
      );
    });

    test('想定外のレスポンス形式（JSONパース失敗）の場合、RouteApiExceptionをthrowすること', () async {
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('not a json', 200));

      expect(
        () => repository.computeRoute(
          origin: origin,
          destinationStationName: destinationStationName,
        ),
        throwsA(isA<RouteApiException>()),
      );
    });
  });

  group('リクエスト内容の検証', () {
    test(
      '送信するJSONボディにorigin（現在地緯度経度）・destination.address（入力駅名+「駅」）・'
      'travelMode: TRANSIT・computeAlternativeRoutes: falseが正しく含まれること',
      () async {
        when(() => client.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            )).thenAnswer((_) async => jsonResponse({'routes': []}));

        await repository.computeRoute(
          origin: origin,
          destinationStationName: destinationStationName,
        );

        final captured = verify(() => client.post(
              any(),
              headers: any(named: 'headers'),
              body: captureAny(named: 'body'),
            )).captured;
        expect(captured, hasLength(1));

        final sentBody =
            jsonDecode(captured.single as String) as Map<String, dynamic>;

        expect(
          sentBody['origin']['location']['latLng']['latitude'],
          origin.latitude,
        );
        expect(
          sentBody['origin']['location']['latLng']['longitude'],
          origin.longitude,
        );
        expect(sentBody['destination']['address'], '$destinationStationName駅');
        expect(sentBody['travelMode'], 'TRANSIT');
        expect(sentBody['computeAlternativeRoutes'], false);
      },
    );

    test('入力駅名が既に「駅」で終わっている場合、重複して「駅」が付与されないこと', () async {
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse({'routes': []}));

      await repository.computeRoute(
        origin: origin,
        destinationStationName: '渋谷駅',
      );

      final captured = verify(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;
      final sentBody =
          jsonDecode(captured.single as String) as Map<String, dynamic>;

      expect(sentBody['destination']['address'], '渋谷駅');
    });

    test('リクエストヘッダーにX-Goog-Api-Keyが正しく設定されること', () async {
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse({'routes': []}));

      await repository.computeRoute(
        origin: origin,
        destinationStationName: destinationStationName,
      );

      final capturedHeaders = verify(() => client.post(
            any(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured;
      final headers = capturedHeaders.single as Map<String, String>;

      expect(headers['X-Goog-Api-Key'], apiKey);
      expect(headers['Content-Type'], contains('application/json'));
    });
  });
}
