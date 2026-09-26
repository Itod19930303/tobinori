/// 経路検索に関するドメイン例外。
///
/// 設計書: docs/design/issue-2-station-search.md 4.3節・7章

/// 該当する駅・ルートが見つからなかった場合の例外。
///
/// `RouteRepository.computeRoute()`が`null`を返した場合に
/// `SearchRouteUseCase`がthrowする（設計書4.4節）。
class RouteNotFoundException implements Exception {
  const RouteNotFoundException([
    this.message = '該当する駅が見つかりませんでした',
  ]);

  final String message;

  @override
  String toString() => 'RouteNotFoundException: $message';
}

/// Routes API呼び出し失敗（通信エラー・タイムアウト・5xx・想定外レスポンス形式）を表す例外。
///
/// 設計書: docs/design/issue-2-station-search.md 4.4節・7章
class RouteApiException implements Exception {
  const RouteApiException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'RouteApiException: $message${cause != null ? ' (cause: $cause)' : ''}';
}
