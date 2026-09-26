// connectivityStatusProvider のユニットテスト。
//
// 設計書: docs/design/issue-2-station-search.md 4.2節・8章「テスト観点」
// ConnectivityPlatform.instance をmocktailのMockに差し替え、
// connectivity_plusパッケージの実プラットフォーム呼び出しに依存せずに検証する。
//
// 【Redフェーズの前提】
// connectivityStatusProvider は未実装（builder内でUnimplementedErrorをthrowするスタブ）。
import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';

class MockConnectivityPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements ConnectivityPlatform {}

void main() {
  late MockConnectivityPlatform platform;
  late StreamController<List<ConnectivityResult>> controller;

  setUp(() {
    platform = MockConnectivityPlatform();
    ConnectivityPlatform.instance = platform;
    controller = StreamController<List<ConnectivityResult>>.broadcast();
    when(() => platform.onConnectivityChanged)
        .thenAnswer((_) => controller.stream);
  });

  tearDown(() async {
    await controller.close();
  });

  test(
    'connectivity_plusのストリームがオフライン（[none]）を通知した場合に'
    'ConnectivityStatus.offlineになること',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final statuses = <ConnectivityStatus>[];
      container.listen<AsyncValue<ConnectivityStatus>>(
        connectivityStatusProvider,
        (previous, next) => next.whenData(statuses.add),
        fireImmediately: true,
      );

      controller.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);

      expect(statuses, contains(ConnectivityStatus.offline));
    },
  );

  test(
    'オフライン通知の後にオンライン（[wifi]等）が通知された場合、'
    'ConnectivityStatus.onlineへ戻ること',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final statuses = <ConnectivityStatus>[];
      container.listen<AsyncValue<ConnectivityStatus>>(
        connectivityStatusProvider,
        (previous, next) => next.whenData(statuses.add),
        fireImmediately: true,
      );

      controller.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      controller.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);

      expect(statuses, [
        ...statuses.takeWhile((s) => s != ConnectivityStatus.online),
        ConnectivityStatus.online,
      ]);
      expect(statuses.last, ConnectivityStatus.online);
    },
  );

  test('モバイル回線（[mobile]）の場合もConnectivityStatus.onlineになること', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final statuses = <ConnectivityStatus>[];
    container.listen<AsyncValue<ConnectivityStatus>>(
      connectivityStatusProvider,
      (previous, next) => next.whenData(statuses.add),
      fireImmediately: true,
    );

    controller.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);

    expect(statuses, contains(ConnectivityStatus.online));
  });
}
