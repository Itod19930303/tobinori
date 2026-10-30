import 'package:flutter/material.dart';
import 'package:tobinori/domain/location/location_failure_reason.dart';
import 'package:tobinori/domain/location/location_state.dart';

/// 現在地の取得失敗理由に対応するユーザー向けメッセージを返す。
///
/// `LocationStatusBanner`と検索画面（`SearchScreen`）で文言を共有する。
String locationFailureMessage(LocationFailureReason reason) {
  switch (reason) {
    case LocationFailureReason.serviceDisabled:
      return '位置情報サービスがオフになっています。端末の設定から有効にしてください。';
    case LocationFailureReason.permissionDenied:
      return '位置情報の利用が許可されていません。';
    case LocationFailureReason.permissionDeniedForever:
      return '位置情報の利用が許可されていません。アプリの設定から位置情報を許可してください。';
    case LocationFailureReason.timeout:
      return '現在地の取得に時間がかかっています。';
    case LocationFailureReason.unknown:
      return '現在地を取得できませんでした。';
  }
}

/// `LocationState`を受け取り、状態に応じたメッセージと
/// 「現在地を再取得」ボタン（または「設定を開く」ボタン）を表示するWidget。
///
/// 設計書: docs/design/issue-1-current-location.md 3.1節
/// F-02の検索画面が画面最上部に埋め込んで利用する想定。
class LocationStatusBanner extends StatelessWidget {
  const LocationStatusBanner({
    super.key,
    required this.state,
    required this.onRefetch,
    required this.onOpenSettings,
  });

  final LocationState state;
  final VoidCallback onRefetch;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      LocationInitial() || LocationLoading() => const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('現在地を取得しています…'),
            ],
          ),
        ),
      LocationLoaded() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: onRefetch,
                tooltip: '現在地を再取得',
              ),
            ],
          ),
        ),
      LocationFailed(:final reason) => Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text(locationFailureMessage(reason))),
              const SizedBox(width: 8),
              if (reason == LocationFailureReason.permissionDeniedForever)
                ElevatedButton(
                  onPressed: onOpenSettings,
                  child: const Text('設定を開く'),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: onRefetch,
                  tooltip: '現在地を再取得',
                ),
            ],
          ),
        ),
    };
  }
}
