import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/data/location/location_repository.dart';
import 'package:tobinori/domain/location/get_current_location_usecase.dart';
import 'package:tobinori/domain/location/location_point.dart';
import 'package:tobinori/domain/location/location_state.dart';

/// 設計書: docs/design/issue-1-current-location.md 3.2節
/// すべて手書き（コード生成なし）のRiverpodで実装する。

/// `LocationRepository`のDIポイント。
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository();
});

/// `GetCurrentLocationUseCase`のDIポイント。
final getCurrentLocationUseCaseProvider =
    Provider<GetCurrentLocationUseCase>((ref) {
  return GetCurrentLocationUseCase(ref.watch(locationRepositoryProvider));
});

/// アプリ全体で共有する「現在地取得状態」のSource of Truth。
final currentLocationProvider =
    StateNotifierProvider<CurrentLocationNotifier, LocationState>((ref) {
  return CurrentLocationNotifier(ref.watch(getCurrentLocationUseCaseProvider));
});

/// `currentLocationProvider`が`LocationLoaded`の場合のみ`LocationPoint`を返す
/// 派生Provider（F-02向けの利便性Provider）。
final currentLocationPointProvider = Provider<LocationPoint?>((ref) {
  final state = ref.watch(currentLocationProvider);
  return switch (state) {
    LocationLoaded(:final point) => point,
    _ => null,
  };
});

/// 現在地取得状態を管理するStateNotifier。
class CurrentLocationNotifier extends StateNotifier<LocationState> {
  CurrentLocationNotifier(this._useCase) : super(const LocationInitial());

  final GetCurrentLocationUseCase _useCase;

  /// 現在地取得を実行し状態を更新する。
  ///
  /// アプリ起動時の自動実行、再取得ボタン押下時のいずれからも呼ばれる共通メソッド。
  Future<void> fetchCurrentLocation() async {
    state = const LocationLoading();
    final result = await _useCase.call();
    state = switch (result) {
      LocationSuccess(:final point) => LocationLoaded(point),
      LocationFailureResult(:final reason) => LocationFailed(reason),
    };
  }
}
