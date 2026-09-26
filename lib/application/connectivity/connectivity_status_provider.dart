import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 端末のオンライン・オフライン状態。
///
/// 設計書: docs/design/issue-2-station-search.md 4.2節
enum ConnectivityStatus {
  online,
  offline,
}

/// `Connectivity`のDIポイント（テストでのモック差し替え用）。
final connectivityProvider = Provider<Connectivity>((ref) {
  return Connectivity();
});

/// `connectivity_plus`の接続状態変化を`ConnectivityStatus`に変換して中継するProvider。
///
/// 設計書: docs/design/issue-2-station-search.md 4.2節
/// F-01/F-02/F-03/F-04から共通利用される共有インフラProvider。
final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.onConnectivityChanged.map((results) {
    final isOffline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    return isOffline ? ConnectivityStatus.offline : ConnectivityStatus.online;
  });
});
