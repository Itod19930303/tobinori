/// 経路案内（Googleマップ起動）の結果。
///
/// 設計書: docs/design/issue-3-route-guidance.md 3.3節
enum GuidanceLaunchResult {
  /// Googleマップアプリを起動できた
  launchedMapsApp,

  /// アプリ未導入等のためブラウザで開いた
  launchedBrowser,

  /// どちらも起動できなかった
  failed,
}
