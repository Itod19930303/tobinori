import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_point.dart';

/// 端末GPSから現在地を取得するRepository。
///
/// 設計書: docs/design/issue-1-current-location.md 3.4節
/// 個人開発規模のため抽象インターフェースは設けず、具象クラス1つのみとする。
class LocationRepository {
  /// 現在地を取得する。
  ///
  /// 内部処理フローは設計書3.4節の通り。
  Future<LocationResult> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationFailureResult(
        LocationFailureReason.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return const LocationFailureResult(
          LocationFailureReason.permissionDenied,
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return const LocationFailureResult(
        LocationFailureReason.permissionDeniedForever,
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LocationSuccess(
        LocationPoint(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
      );
    } on TimeoutException {
      return const LocationFailureResult(LocationFailureReason.timeout);
    } catch (_) {
      return const LocationFailureResult(LocationFailureReason.unknown);
    }
  }

  /// OSの設定アプリ（アプリの権限設定画面）を開く。
  ///
  /// `permissionDeniedForever`時にUI側から呼び出される補助メソッド。
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }
}
