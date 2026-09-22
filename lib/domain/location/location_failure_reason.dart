/// 現在地取得に失敗した理由を表す列挙型。
///
/// 設計書: docs/design/issue-1-current-location.md 3.3節
enum LocationFailureReason {
  /// 端末の位置情報サービス（GPS等）が無効
  serviceDisabled,

  /// 権限が拒否された（再度リクエスト可能）
  permissionDenied,

  /// 権限が「今後表示しない」で拒否された（アプリ内から再リクエスト不可）
  permissionDeniedForever,

  /// 取得がタイムアウトした
  timeout,

  /// その他の予期しないエラー
  unknown,
}
