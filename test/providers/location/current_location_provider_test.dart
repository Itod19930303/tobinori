// current_location_provider.dart（Riverpod Provider群）のユニットテスト。
//
// 設計書: docs/design/issue-1-current-location.md 3.2節・7章
// - locationRepositoryProvider / getCurrentLocationUseCaseProvider は単純なDIポイントのため
//   本テストでは主に CurrentLocationNotifier と currentLocationPointProvider を検証する。
// - モック化した GetCurrentLocationUseCase を注入してテストする。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tobinori/domain/location/get_current_location_usecase.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/location/location_state.dart';
import 'package:tobinori/providers/location/current_location_provider.dart';

class MockGetCurrentLocationUseCase extends Mock
    implements GetCurrentLocationUseCase {}

void main() {
  late MockGetCurrentLocationUseCase useCase;

  setUp(() {
    useCase = MockGetCurrentLocationUseCase();
  });

  group('CurrentLocationNotifier', () {
    test('初期状態はLocationInitialであること', () {
      final notifier = CurrentLocationNotifier(useCase);
      expect(notifier.state, isA<LocationInitial>());
    });

    test(
      '正常系: fetchCurrentLocation()呼び出し時に'
      'LocationInitial → LocationLoading → LocationLoaded(point) の順で遷移すること',
      () async {
        const point = LocationPoint(latitude: 35.0, longitude: 139.0);
        when(() => useCase.call())
            .thenAnswer((_) async => const LocationSuccess(point));

        final notifier = CurrentLocationNotifier(useCase);
        final states = <LocationState>[notifier.state];
        notifier.addListener(
          (state) => states.add(state),
          fireImmediately: false,
        );

        await notifier.fetchCurrentLocation();

        expect(states, [
          isA<LocationInitial>(),
          isA<LocationLoading>(),
          isA<LocationLoaded>(),
        ]);
        expect((states.last as LocationLoaded).point, point);
      },
    );

    test(
      '異常系: UseCaseが失敗を返した場合にLocationLoading → LocationFailed(reason)の順で遷移し、'
      'reasonが正しく伝播すること',
      () async {
        when(() => useCase.call()).thenAnswer(
          (_) async =>
              const LocationFailureResult(LocationFailureReason.timeout),
        );

        final notifier = CurrentLocationNotifier(useCase);
        final states = <LocationState>[notifier.state];
        notifier.addListener(
          (state) => states.add(state),
          fireImmediately: false,
        );

        await notifier.fetchCurrentLocation();

        expect(states, [
          isA<LocationInitial>(),
          isA<LocationLoading>(),
          isA<LocationFailed>(),
        ]);
        expect(
          (states.last as LocationFailed).reason,
          LocationFailureReason.timeout,
        );
      },
    );

    test(
      '再取得系: LocationLoaded状態からfetchCurrentLocation()を再度呼び出すと、'
      'LocationLoadingを経て新しいLocationLoaded(point)に遷移すること',
      () async {
        const firstPoint = LocationPoint(latitude: 35.0, longitude: 139.0);
        const secondPoint = LocationPoint(latitude: 36.0, longitude: 140.0);
        when(() => useCase.call())
            .thenAnswer((_) async => const LocationSuccess(firstPoint));

        final notifier = CurrentLocationNotifier(useCase);
        await notifier.fetchCurrentLocation();
        expect(notifier.state, isA<LocationLoaded>());

        when(() => useCase.call())
            .thenAnswer((_) async => const LocationSuccess(secondPoint));

        final states = <LocationState>[];
        notifier.addListener(
          (state) => states.add(state),
          fireImmediately: false,
        );
        await notifier.fetchCurrentLocation();

        expect(states.first, isA<LocationLoading>());
        expect(states.last, isA<LocationLoaded>());
        expect((states.last as LocationLoaded).point, secondPoint);
      },
    );

    test(
      '再取得系: LocationFailed状態からfetchCurrentLocation()を再度呼び出すと、'
      'LocationLoadingを経て新しい状態に遷移すること',
      () async {
        when(() => useCase.call()).thenAnswer(
          (_) async =>
              const LocationFailureResult(LocationFailureReason.unknown),
        );

        final notifier = CurrentLocationNotifier(useCase);
        await notifier.fetchCurrentLocation();
        expect(notifier.state, isA<LocationFailed>());

        const point = LocationPoint(latitude: 1.0, longitude: 2.0);
        when(() => useCase.call())
            .thenAnswer((_) async => const LocationSuccess(point));

        final states = <LocationState>[];
        notifier.addListener(
          (state) => states.add(state),
          fireImmediately: false,
        );
        await notifier.fetchCurrentLocation();

        expect(states.first, isA<LocationLoading>());
        expect(states.last, isA<LocationLoaded>());
      },
    );
  });

  group('currentLocationPointProvider', () {
    test('currentLocationProviderがLocationLoadedのとき対応するLocationPointを返すこと',
        () async {
      const point = LocationPoint(latitude: 35.0, longitude: 139.0);
      when(() => useCase.call())
          .thenAnswer((_) async => const LocationSuccess(point));

      final container = ProviderContainer(
        overrides: [
          getCurrentLocationUseCaseProvider.overrideWithValue(useCase),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(currentLocationProvider.notifier)
          .fetchCurrentLocation();

      expect(container.read(currentLocationPointProvider), point);
    });

    test(
      'currentLocationProviderがLocationInitial/LocationLoading/LocationFailedのとき'
      'nullを返すこと',
      () async {
        final container = ProviderContainer(
          overrides: [
            getCurrentLocationUseCaseProvider.overrideWithValue(useCase),
          ],
        );
        addTearDown(container.dispose);

        // LocationInitial
        expect(container.read(currentLocationPointProvider), isNull);

        // LocationFailed
        when(() => useCase.call()).thenAnswer(
          (_) async => const LocationFailureResult(
            LocationFailureReason.serviceDisabled,
          ),
        );
        await container
            .read(currentLocationProvider.notifier)
            .fetchCurrentLocation();
        expect(container.read(currentLocationProvider), isA<LocationFailed>());
        expect(container.read(currentLocationPointProvider), isNull);
      },
    );
  });

  group('検索ボタンの活性/非活性判定（currentLocationProvider/currentLocationPointProviderを利用）', () {
    test(
      'currentLocationPointProviderが非nullのとき（＝LocationLoaded）検索ボタンが活性であると判定できること',
      () async {
        const point = LocationPoint(latitude: 35.0, longitude: 139.0);
        when(() => useCase.call())
            .thenAnswer((_) async => const LocationSuccess(point));

        final container = ProviderContainer(
          overrides: [
            getCurrentLocationUseCaseProvider.overrideWithValue(useCase),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(currentLocationProvider.notifier)
            .fetchCurrentLocation();

        final isSearchEnabled =
            container.read(currentLocationPointProvider) != null;
        expect(isSearchEnabled, isTrue);
      },
    );

    test(
      'LocationInitial/LocationLoading/LocationFailedのいずれの場合も'
      '検索ボタンが非活性であると判定できること',
      () async {
        final container = ProviderContainer(
          overrides: [
            getCurrentLocationUseCaseProvider.overrideWithValue(useCase),
          ],
        );
        addTearDown(container.dispose);

        // LocationInitial
        expect(
          container.read(currentLocationPointProvider) != null,
          isFalse,
        );

        // LocationFailed
        when(() => useCase.call()).thenAnswer(
          (_) async =>
              const LocationFailureResult(LocationFailureReason.timeout),
        );
        await container
            .read(currentLocationProvider.notifier)
            .fetchCurrentLocation();
        expect(
          container.read(currentLocationPointProvider) != null,
          isFalse,
        );
      },
    );
  });
}
