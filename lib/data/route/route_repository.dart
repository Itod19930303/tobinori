import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/route.dart';
import 'package:tobinori/domain/route/route_exceptions.dart';

/// Google Maps Platform Routes API（`computeRoutes`）へのアクセスを担うRepository。
///
/// 設計書: docs/design/issue-2-station-search.md 4.4節・6.1節
abstract class RouteRepository {
  /// 現在地（[origin]）から[destinationStationName]までの最短経路（1件）を取得する。
  ///
  /// 該当する経路が存在しない場合は`null`を返す（ドメイン例外への変換は
  /// `SearchRouteUseCase`側で行う）。
  /// 通信失敗・タイムアウト・想定外レスポンス形式の場合は[RouteApiException]をthrowする。
  Future<Route?> computeRoute({
    required LocationPoint origin,
    required String destinationStationName,
  });
}

/// [RouteRepository]のGoogle Maps Platform Routes APIを利用した実装。
///
/// 設計書: docs/design/issue-2-station-search.md 4.4節・6.1節
class RouteRepositoryImpl implements RouteRepository {
  RouteRepositoryImpl({required http.Client client, required String apiKey})
      : _client = client,
        _apiKey = apiKey;

  static const endpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  static const timeout = Duration(seconds: 5);

  static const _fieldMask =
      'routes.duration,routes.legs.steps.transitDetails,'
      'routes.legs.steps.travelMode,routes.legs.steps.staticDuration,'
      'routes.legs.steps.navigationInstruction';

  final http.Client _client;
  final String _apiKey;

  @override
  Future<Route?> computeRoute({
    required LocationPoint origin,
    required String destinationStationName,
  }) async {
    final address = destinationStationName.endsWith('駅')
        ? destinationStationName
        : '$destinationStationName駅';

    final requestBody = jsonEncode({
      'origin': {
        'location': {
          'latLng': {
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          },
        },
      },
      'destination': {'address': address},
      'travelMode': 'TRANSIT',
      'computeAlternativeRoutes': false,
      'languageCode': 'ja',
      'unitSystem': 'METRIC',
    });

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _apiKey,
      'X-Goog-FieldMask': _fieldMask,
    };

    final http.Response response;
    try {
      response = await _client
          .post(Uri.parse(endpoint), headers: headers, body: requestBody)
          .timeout(timeout);
    } on TimeoutException catch (e) {
      throw RouteApiException('Routes APIへのリクエストがタイムアウトしました', e);
    } catch (e) {
      throw RouteApiException('Routes APIへのリクエストに失敗しました', e);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RouteApiException(
        'Routes APIがエラーレスポンスを返しました（status: ${response.statusCode}）',
      );
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw RouteApiException('Routes APIのレスポンス形式が不正です', e);
    }

    try {
      final routes = decoded['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        return null;
      }

      final firstRoute = routes.first as Map<String, dynamic>;
      final totalDuration = _parseDuration(firstRoute['duration'] as String);

      final legs = firstRoute['legs'] as List<dynamic>? ?? const [];
      final steps = <RouteStep>[];
      for (final leg in legs) {
        final legMap = leg as Map<String, dynamic>;
        final stepList = legMap['steps'] as List<dynamic>? ?? const [];
        for (final step in stepList) {
          steps.add(_mapStep(step as Map<String, dynamic>));
        }
      }

      final transitCount =
          steps.where((step) => step.type == RouteStepType.transit).length;
      final transferCount = transitCount - 1 < 0 ? 0 : transitCount - 1;

      return Route(
        totalDuration: totalDuration,
        transferCount: transferCount,
        steps: steps,
      );
    } on RouteApiException {
      rethrow;
    } catch (e) {
      throw RouteApiException('Routes APIのレスポンス形式が不正です', e);
    }
  }

  RouteStep _mapStep(Map<String, dynamic> step) {
    final travelMode = step['travelMode'] as String?;
    final duration = _parseDuration(step['staticDuration'] as String);

    if (travelMode == 'TRANSIT') {
      final transitDetails = step['transitDetails'] as Map<String, dynamic>?;
      final stopDetails =
          transitDetails?['stopDetails'] as Map<String, dynamic>?;
      final departureStop =
          stopDetails?['departureStop'] as Map<String, dynamic>?;
      final arrivalStop =
          stopDetails?['arrivalStop'] as Map<String, dynamic>?;
      final transitLine =
          transitDetails?['transitLine'] as Map<String, dynamic>?;

      return RouteStep(
        type: RouteStepType.transit,
        duration: duration,
        lineName: transitLine?['name'] as String?,
        headsign: transitDetails?['headsign'] as String?,
        departureStopName: departureStop?['name'] as String?,
        arrivalStopName: arrivalStop?['name'] as String?,
      );
    }

    return RouteStep(type: RouteStepType.walk, duration: duration);
  }

  Duration _parseDuration(String value) {
    final seconds = int.parse(value.substring(0, value.length - 1));
    return Duration(seconds: seconds);
  }
}
