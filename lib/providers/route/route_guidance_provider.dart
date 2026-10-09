import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/data/navigation/maps_launcher_repository.dart';
import 'package:tobinori/domain/route/guidance_launch_result.dart';
import 'package:tobinori/domain/route/nearest_station.dart';
import 'package:tobinori/domain/route/start_route_guidance_usecase.dart';

/// 設計書: docs/design/issue-3-route-guidance.md 3.2節・4章

/// `MapsLauncherRepository`のDIポイント。
final mapsLauncherRepositoryProvider = Provider<MapsLauncherRepository>((ref) {
  return MapsLauncherRepositoryImpl();
});

/// `StartRouteGuidanceUseCase`のDIポイント。
final startRouteGuidanceUseCaseProvider =
    Provider<StartRouteGuidanceUseCase>((ref) {
  return StartRouteGuidanceUseCase(ref.watch(mapsLauncherRepositoryProvider));
});

enum RouteGuidanceStatus { idle, launching, launched, failed }

class RouteGuidanceState {
  const RouteGuidanceState({required this.status});

  final RouteGuidanceStatus status;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RouteGuidanceState && other.status == status;
  }

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => 'RouteGuidanceState(status: $status)';
}

class RouteGuidanceNotifier extends StateNotifier<RouteGuidanceState> {
  RouteGuidanceNotifier(this._ref)
      : super(const RouteGuidanceState(status: RouteGuidanceStatus.idle));

  final Ref _ref;

  Future<void> startGuidance(NearestStation station) async {
    if (state.status == RouteGuidanceStatus.launching) return;

    state = const RouteGuidanceState(status: RouteGuidanceStatus.launching);
    RouteGuidanceStatus next;
    try {
      final result =
          await _ref.read(startRouteGuidanceUseCaseProvider)(station);
      next = result == GuidanceLaunchResult.failed
          ? RouteGuidanceStatus.failed
          : RouteGuidanceStatus.launched;
    } catch (e) {
      debugPrint('経路案内の起動で想定外のエラー: ${e.runtimeType}');
      next = RouteGuidanceStatus.failed;
    }
    if (!mounted) return;
    state = RouteGuidanceState(status: next);
  }
}

final routeGuidanceProvider =
    StateNotifierProvider<RouteGuidanceNotifier, RouteGuidanceState>((ref) {
  return RouteGuidanceNotifier(ref);
});
