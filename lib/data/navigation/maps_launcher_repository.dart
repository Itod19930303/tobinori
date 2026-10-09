import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/route/guidance_launch_result.dart';
import 'package:tobinori/domain/route/nearest_station.dart';
import 'package:url_launcher/url_launcher.dart';

/// Googleマップ（アプリ／Web）を徒歩ナビ付きで起動するRepository。
///
/// 設計書: docs/design/issue-3-route-guidance.md 3.4節
abstract class MapsLauncherRepository {
  Future<GuidanceLaunchResult> launchWalkingNavigation(NearestStation station);
}

class MapsLauncherRepositoryImpl implements MapsLauncherRepository {
  /// 関数・[isAndroid]はテスト用に差し替え可能。省略時は実機用の既定実装を使う。
  MapsLauncherRepositoryImpl({
    Future<bool> Function(Uri intentData)? tryLaunchAndroidIntent,
    Future<bool> Function(Uri webUri)? launchWebUrl,
    bool? isAndroid,
  })  : _tryLaunchAndroidIntent =
            tryLaunchAndroidIntent ?? _defaultTryLaunchAndroidIntent,
        _launchWebUrl = launchWebUrl ?? _defaultLaunchWebUrl,
        _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  static const _mapsPackage = 'com.google.android.apps.maps';

  final Future<bool> Function(Uri intentData) _tryLaunchAndroidIntent;
  final Future<bool> Function(Uri webUri) _launchWebUrl;
  final bool _isAndroid;

  /// `google.navigation:q=緯度,経度&mode=w`
  static Uri buildNavigationUri(LocationPoint location) {
    return Uri.parse(
      'google.navigation:q=${location.latitude},${location.longitude}&mode=w',
    );
  }

  static Uri buildWebFallbackUri(NearestStation station) {
    final location = station.location;
    final destination = location != null
        ? '${location.latitude},${location.longitude}'
        : station.name;
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
      'travelmode': 'walking',
    });
  }

  static AndroidIntent buildAndroidIntent(Uri data) {
    return AndroidIntent(
      action: 'action_view',
      data: data.toString(),
      package: _mapsPackage,
    );
  }

  static Future<bool> _defaultTryLaunchAndroidIntent(Uri data) async {
    final intent = buildAndroidIntent(data);
    if (await intent.canResolveActivity() != true) return false;
    await intent.launch();
    return true;
  }

  static Future<bool> _defaultLaunchWebUrl(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<GuidanceLaunchResult> launchWalkingNavigation(
    NearestStation station,
  ) async {
    final location = station.location;
    if (_isAndroid && location != null) {
      try {
        if (await _tryLaunchAndroidIntent(buildNavigationUri(location))) {
          return GuidanceLaunchResult.launchedMapsApp;
        }
      } catch (e) {
        debugPrint('Googleマップのインテント起動に失敗: ${e.runtimeType}');
      }
    }

    try {
      if (await _launchWebUrl(buildWebFallbackUri(station))) {
        return GuidanceLaunchResult.launchedBrowser;
      }
    } catch (e) {
      debugPrint('Web版Googleマップの起動に失敗: ${e.runtimeType}');
    }
    return GuidanceLaunchResult.failed;
  }
}
