// MapsLauncherRepositoryImpl のユニットテスト。
//
// 設計書: docs/design/issue-3-route-guidance.md 3.4節・5章・6章・7章
//
// 【Redフェーズの前提（実装エージェントへ）】
// - lib/data/navigation/maps_launcher_repository.dart に以下を定義する。
//   abstract class MapsLauncherRepository {
//     Future<GuidanceLaunchResult> launchWalkingNavigation(NearestStation station);
//   }
//   class MapsLauncherRepositoryImpl implements MapsLauncherRepository {
//     MapsLauncherRepositoryImpl({
//       required Future<bool> Function(Uri intentData) tryLaunchAndroidIntent,
//       required Future<bool> Function(Uri webUri) launchWebUrl,
//       required bool isAndroid,
//     });  // すべて名前付き引数
//     static Uri buildNavigationUri(LocationPoint location);
//     static Uri buildWebFallbackUri(NearestStation station);
//     static AndroidIntent buildAndroidIntent(Uri data);
//   }
// - tryLaunchAndroidIntent: 「解決可能かつ起動できた」ならtrue、解決不可ならfalse（例外も可）。
//   falseまたは例外ならWebフォールバックへ進む。
// - pubspec.yaml に android_intent_plus / url_launcher の追加が必要。
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/data/navigation/maps_launcher_repository.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/guidance_launch_result.dart';
import 'package:tobinori/domain/route/nearest_station.dart';

void main() {
  const withLocation = NearestStation(
    name: '渋谷',
    location: LocationPoint(latitude: 35.1, longitude: 139.2),
  );
  const withoutLocation = NearestStation(name: '渋谷');

  late List<Uri> intentCalls;
  late List<Uri> webCalls;

  setUp(() {
    intentCalls = [];
    webCalls = [];
  });

  MapsLauncherRepositoryImpl build({
    bool isAndroid = true,
    Future<bool> Function(Uri)? intent,
    Future<bool> Function(Uri)? web,
  }) {
    return MapsLauncherRepositoryImpl(
      isAndroid: isAndroid,
      tryLaunchAndroidIntent: (uri) {
        intentCalls.add(uri);
        return (intent ?? (_) async => true)(uri);
      },
      launchWebUrl: (uri) {
        webCalls.add(uri);
        return (web ?? (_) async => true)(uri);
      },
    );
  }

  group('buildNavigationUri', () {
    test('google.navigation:q=緯度,経度&mode=w 形式であること', () {
      final uri = MapsLauncherRepositoryImpl.buildNavigationUri(
        const LocationPoint(latitude: 35.1, longitude: 139.2),
      );

      expect(uri.toString(), 'google.navigation:q=35.1,139.2&mode=w');
      expect(uri.scheme, 'google.navigation');
    });
  });

  group('buildWebFallbackUri', () {
    test('座標あり: destinationが「緯度,経度」でtravelmode=walkingであること', () {
      final uri = MapsLauncherRepositoryImpl.buildWebFallbackUri(withLocation);

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['destination'], '35.1,139.2');
      expect(uri.queryParameters['travelmode'], 'walking');
    });

    test('座標なし: destinationが駅名でtravelmode=walkingであること', () {
      final uri =
          MapsLauncherRepositoryImpl.buildWebFallbackUri(withoutLocation);

      expect(uri.queryParameters['destination'], '渋谷');
      expect(uri.queryParameters['travelmode'], 'walking');
    });

    test('日本語・スペース・記号を含む駅名がエンコードされ、デコードすると元に戻ること', () {
      const station = NearestStation(name: '東京 &駅/A#1');

      final uri = MapsLauncherRepositoryImpl.buildWebFallbackUri(station);

      expect(uri.queryParameters['destination'], '東京 &駅/A#1');
      // 生のスペース・#が文字列に残っていない（正しくエンコードされている）。
      final raw = uri.toString();
      expect(raw, isNot(contains(' ')));
      expect(raw, isNot(contains('#')));
      expect(Uri.parse(raw).queryParameters['destination'], '東京 &駅/A#1');
    });
  });

  group('buildAndroidIntent', () {
    test('action・package・dataが設計どおりであること', () {
      final data = MapsLauncherRepositoryImpl.buildNavigationUri(
        const LocationPoint(latitude: 35.1, longitude: 139.2),
      );

      final AndroidIntent intent =
          MapsLauncherRepositoryImpl.buildAndroidIntent(data);

      expect(intent.action, 'action_view');
      expect(intent.package, 'com.google.android.apps.maps');
      expect(intent.data, data.toString());
    });
  });

  group('launchWalkingNavigation: Android・座標あり', () {
    test('インテント解決可なら launchedMapsApp で、Webは呼ばれないこと', () async {
      final repo = build();

      final result = await repo.launchWalkingNavigation(withLocation);

      expect(result, GuidanceLaunchResult.launchedMapsApp);
      expect(intentCalls, [
        MapsLauncherRepositoryImpl.buildNavigationUri(withLocation.location!),
      ]);
      expect(webCalls, isEmpty);
    });

    test('インテント解決不可ならWeb URLを起動し launchedBrowser になること', () async {
      final repo = build(intent: (_) async => false);

      final result = await repo.launchWalkingNavigation(withLocation);

      expect(result, GuidanceLaunchResult.launchedBrowser);
      expect(webCalls,
          [MapsLauncherRepositoryImpl.buildWebFallbackUri(withLocation)]);
    });

    test('解決可否の判定で例外が出ても、Webフォールバックで launchedBrowser になること',
        () async {
      final repo =
          build(intent: (_) async => throw Exception('canResolve error'));

      final result = await repo.launchWalkingNavigation(withLocation);

      expect(result, GuidanceLaunchResult.launchedBrowser);
      expect(webCalls, hasLength(1));
    });

    test('インテント起動が例外でも、Webフォールバックで launchedBrowser になること', () async {
      final repo =
          build(intent: (_) async => throw StateError('ActivityNotFound'));

      final result = await repo.launchWalkingNavigation(withLocation);

      expect(result, GuidanceLaunchResult.launchedBrowser);
      expect(webCalls, hasLength(1));
    });

    test('インテント不可かつWeb起動もfalseなら failed になること', () async {
      final repo = build(intent: (_) async => false, web: (_) async => false);

      expect(await repo.launchWalkingNavigation(withLocation),
          GuidanceLaunchResult.failed);
    });

    test('インテント不可かつWeb起動が例外でも failed になり例外を投げないこと', () async {
      final repo = build(
        intent: (_) async => false,
        web: (_) async => throw Exception('no browser'),
      );

      expect(await repo.launchWalkingNavigation(withLocation),
          GuidanceLaunchResult.failed);
    });
  });

  group('launchWalkingNavigation: 座標なし', () {
    test('インテントを呼ばず、駅名指定のWeb URLで launchedBrowser になること', () async {
      final repo = build();

      final result = await repo.launchWalkingNavigation(withoutLocation);

      expect(result, GuidanceLaunchResult.launchedBrowser);
      expect(intentCalls, isEmpty);
      expect(webCalls, hasLength(1));
      expect(webCalls.single.queryParameters['destination'], '渋谷');
      expect(webCalls.single.queryParameters['travelmode'], 'walking');
    });

    test('日本語・スペース・記号を含む駅名でも駅名指定のWeb URLで起動できること', () async {
      const station = NearestStation(name: '東京 &駅/A#1');
      final repo = build();

      final result = await repo.launchWalkingNavigation(station);

      expect(result, GuidanceLaunchResult.launchedBrowser);
      expect(intentCalls, isEmpty);
      expect(webCalls.single.queryParameters['destination'], '東京 &駅/A#1');
    });

    test('Web起動が失敗(false)なら failed になること', () async {
      final repo = build(web: (_) async => false);

      expect(await repo.launchWalkingNavigation(withoutLocation),
          GuidanceLaunchResult.failed);
      expect(intentCalls, isEmpty);
    });
  });

  group('launchWalkingNavigation: 非Android', () {
    test('座標あり: インテントを呼ばずWeb URLへ直行し、destinationは緯度,経度であること', () async {
      final repo = build(isAndroid: false);

      final result = await repo.launchWalkingNavigation(withLocation);

      expect(result, GuidanceLaunchResult.launchedBrowser);
      expect(intentCalls, isEmpty);
      expect(webCalls.single.queryParameters['destination'], '35.1,139.2');
    });

    test('座標なし: インテントを呼ばずWeb URLへ直行し、destinationは駅名であること', () async {
      final repo = build(isAndroid: false);

      final result = await repo.launchWalkingNavigation(withoutLocation);

      expect(result, GuidanceLaunchResult.launchedBrowser);
      expect(intentCalls, isEmpty);
      expect(webCalls.single.queryParameters['destination'], '渋谷');
    });
  });
}
