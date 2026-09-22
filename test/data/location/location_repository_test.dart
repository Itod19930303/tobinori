// LocationRepository のユニットテスト。
//
// 設計書: docs/design/issue-1-current-location.md 3.4節・7章
// GeolocatorPlatform.instance をmocktailのMockに差し替え、
// geolocatorパッケージの実プラットフォーム呼び出しに依存せずに検証する。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tobinori/data/location/location_repository.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_point.dart';

class MockGeolocatorPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {}

class FakeLocationSettings extends Fake implements LocationSettings {}

Position _dummyPosition({
  double latitude = 35.681236,
  double longitude = 139.767125,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  late MockGeolocatorPlatform geolocatorPlatform;
  late LocationRepository repository;

  setUpAll(() {
    registerFallbackValue(FakeLocationSettings());
  });

  setUp(() {
    geolocatorPlatform = MockGeolocatorPlatform();
    GeolocatorPlatform.instance = geolocatorPlatform;
    repository = LocationRepository();
  });

  group('LocationRepository.getCurrentLocation()', () {
    test(
      '位置情報サービスが有効・権限がwhileInUseで取得に成功した場合、'
      'LocationSuccessかつ正しい緯度経度のLocationPointを返すこと',
      () async {
        when(() => geolocatorPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => true);
        when(() => geolocatorPlatform.checkPermission())
            .thenAnswer((_) async => LocationPermission.whileInUse);
        when(() => geolocatorPlatform.getCurrentPosition(
              locationSettings: any(named: 'locationSettings'),
            )).thenAnswer(
          (_) async => _dummyPosition(latitude: 35.0, longitude: 139.0),
        );

        final result = await repository.getCurrentLocation();

        expect(result, isA<LocationSuccess>());
        expect(
          (result as LocationSuccess).point,
          const LocationPoint(latitude: 35.0, longitude: 139.0),
        );
      },
    );

    test(
      '権限がalwaysで取得に成功した場合も、LocationSuccessを返すこと',
      () async {
        when(() => geolocatorPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => true);
        when(() => geolocatorPlatform.checkPermission())
            .thenAnswer((_) async => LocationPermission.always);
        when(() => geolocatorPlatform.getCurrentPosition(
              locationSettings: any(named: 'locationSettings'),
            )).thenAnswer((_) async => _dummyPosition());

        final result = await repository.getCurrentLocation();

        expect(result, isA<LocationSuccess>());
      },
    );

    test(
      '位置情報サービスが無効の場合、LocationFailureResult(serviceDisabled)を返し、'
      'requestPermissionは呼ばれないこと（早期リターン）',
      () async {
        when(() => geolocatorPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => false);

        final result = await repository.getCurrentLocation();

        expect(result, isA<LocationFailureResult>());
        expect(
          (result as LocationFailureResult).reason,
          LocationFailureReason.serviceDisabled,
        );
        verifyNever(() => geolocatorPlatform.checkPermission());
        verifyNever(() => geolocatorPlatform.requestPermission());
      },
    );

    test(
      '権限がdenied→requestPermission後もdeniedの場合、'
      'LocationFailureResult(permissionDenied)を返すこと',
      () async {
        when(() => geolocatorPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => true);
        when(() => geolocatorPlatform.checkPermission())
            .thenAnswer((_) async => LocationPermission.denied);
        when(() => geolocatorPlatform.requestPermission())
            .thenAnswer((_) async => LocationPermission.denied);

        final result = await repository.getCurrentLocation();

        expect(result, isA<LocationFailureResult>());
        expect(
          (result as LocationFailureResult).reason,
          LocationFailureReason.permissionDenied,
        );
        verify(() => geolocatorPlatform.requestPermission()).called(1);
      },
    );

    test(
      '権限がdeniedForeverの場合、requestPermissionを呼ばずに'
      'LocationFailureResult(permissionDeniedForever)を返すこと',
      () async {
        when(() => geolocatorPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => true);
        when(() => geolocatorPlatform.checkPermission())
            .thenAnswer((_) async => LocationPermission.deniedForever);

        final result = await repository.getCurrentLocation();

        expect(result, isA<LocationFailureResult>());
        expect(
          (result as LocationFailureResult).reason,
          LocationFailureReason.permissionDeniedForever,
        );
        verifyNever(() => geolocatorPlatform.requestPermission());
      },
    );

    test(
      'getCurrentPositionがTimeoutExceptionを投げた場合、'
      'LocationFailureResult(timeout)を返すこと',
      () async {
        when(() => geolocatorPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => true);
        when(() => geolocatorPlatform.checkPermission())
            .thenAnswer((_) async => LocationPermission.whileInUse);
        when(() => geolocatorPlatform.getCurrentPosition(
              locationSettings: any(named: 'locationSettings'),
            )).thenThrow(TimeoutException('timeout'));

        final result = await repository.getCurrentLocation();

        expect(result, isA<LocationFailureResult>());
        expect(
          (result as LocationFailureResult).reason,
          LocationFailureReason.timeout,
        );
      },
    );

    test(
      'getCurrentPositionがその他の例外を投げた場合、'
      'LocationFailureResult(unknown)を返すこと',
      () async {
        when(() => geolocatorPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => true);
        when(() => geolocatorPlatform.checkPermission())
            .thenAnswer((_) async => LocationPermission.whileInUse);
        when(() => geolocatorPlatform.getCurrentPosition(
              locationSettings: any(named: 'locationSettings'),
            )).thenThrow(Exception('unexpected platform error'));

        final result = await repository.getCurrentLocation();

        expect(result, isA<LocationFailureResult>());
        expect(
          (result as LocationFailureResult).reason,
          LocationFailureReason.unknown,
        );
      },
    );
  });

  group('LocationRepository.openAppSettings()', () {
    test('Geolocator.openAppSettings()が1回呼ばれること', () async {
      when(() => geolocatorPlatform.openAppSettings())
          .thenAnswer((_) async => true);

      await repository.openAppSettings();

      verify(() => geolocatorPlatform.openAppSettings()).called(1);
    });
  });
}
