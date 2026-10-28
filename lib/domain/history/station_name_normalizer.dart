/// 駅名の表記ゆれ（前後空白・末尾「駅」）をそろえる。
///
/// 設計書: docs/design/issue-4-search-history.md 3.3節
String normalizeStationName(String raw) {
  // 全角スペース(U+3000)もtrimの対象。
  var name = raw.trim();
  if (name.endsWith('駅') && name.length > 1) {
    name = name.substring(0, name.length - 1);
  }
  return name;
}
