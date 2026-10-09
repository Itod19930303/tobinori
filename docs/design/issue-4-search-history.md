# 詳細設計書 - Issue #4 F-04 検索履歴

## 用語メモ

- **Riverpod / Provider**: Flutterの状態管理ライブラリと、その「状態の入れ物」。本プロジェクトは手書き（コード生成なし）で使う。
- **UseCase**: ドメイン層に置く、1機能単位の処理クラス。
- **Repository**: DB・API・端末機能など外部とのやり取りを1か所にまとめるクラス。
- **sqflite**: Flutter用のSQLite（端末内の軽量DB）プラグイン。AndroidではOS同梱のSQLiteを使う。
- **upsert**: 「無ければ追加、有れば更新」を1文で行うSQL。本設計では使わない（4.4節参照）。
- **正規化**: 表記ゆれ（「新宿」と「新宿駅」など）を同じ形にそろえる処理。

## 1. 対象Issue・関連要件

- Issue: #4 F-04 検索履歴（https://github.com/Itod19930303/tobinori/issues/4）
- 関連する機能要件:
  - F-04（requirements.md 4章）: 駅名入力に加え、過去に検索した目的地履歴から選択して再検索できる。
  - 操作フロー: 検索画面に履歴一覧を表示 → タップで再検索、または新規に駅名を入力。
  - 依存: F-02（`routeSearchProvider`）の成功結果を履歴保存のきっかけにする。issue-2設計書 9章 未決定事項4の「連携方法はF-04で確定」を本書で確定する。
- 関連する非機能要件:
  - プライバシー（requirements.md 5章）: 検索履歴は端末内のみに保存し、クラウド同期しない。
  - パフォーマンス: 「調べる→確認する」を最速に。履歴タップ1回で検索まで完了させる。DB処理は検索の応答速度に影響させない。
  - オフライン（architecture.md 8.2）: オフライン中も履歴一覧は閲覧できる。新規検索は不可。
  - アーキテクチャ: sqflite（単一テーブル）、Riverpod（コード生成なし）、build_runner不要（architecture.md 2.2, 2.3, 4章）。

## 2. 画面/UIフロー概要

新規画面は作らない。既存の `SearchScreen` に履歴一覧を組み込む。

```
[SearchScreen]
  OfflineBanner（オフライン時のみ）
  現在地未取得の案内文（該当時のみ）
  DestinationSearchField [____________] [検索]
  ----- 結果エリア（状態で出し分け）-----
  idle / notFound / locationUnavailable / offline / error のとき:
      状態メッセージ（既存のプレースホルダー or エラー文）
      検索履歴ヘッダー「検索履歴」        [すべて削除]
      ○ 新宿駅                              [×]
      ○ 渋谷駅                              [×]
      ...（新しい順・スクロール可）
  loading / success のとき:
      既存どおり（スピナー / 結果カード＋経路案内ボタン）。履歴は出さない
```

操作フロー:

1. 履歴行（一覧では「新宿駅」と `displayName` で表示）をタップすると、入力欄には「駅」なしの `stationName`（「新宿」）が入り、そのまま検索が実行される（確認ステップなし）。
2. 新規入力して検索する流れは従来どおり。
3. 検索が成功すると、その駅名が履歴に保存される（先頭に来る）。
4. 行末の「×」で1件削除、「すべて削除」で確認ダイアログ後に全件削除する。
5. 次の場合、履歴行はグレーアウトしてタップ不可にする。
   - オフライン中
   - 現在地未取得
   - 検索中
   - 条件は `DestinationSearchField` の `enabled` と同一（`canSearch`）。
   - 削除操作は常に可能。

履歴が0件の場合は履歴セクション自体を出さず、既存のプレースホルダー文のみ表示する。

設計判断（結果表示中に履歴を出さない理由）:
- `success` 時は結果カードと経路案内ボタンが画面の主役であり、single-purposeレイアウト（DESIGN.md）を保つため。
- 別の履歴から再検索したい場合は、入力欄に入力する流れとする（未決定事項3参照）。

## 3. クラス設計

### 3.1 UI層（Widget）

- **`SearchScreen`（変更）** `lib/presentation/search/search_screen.dart`
  - `ConsumerWidget` から `ConsumerStatefulWidget` へ変更する。
  - 理由: 履歴タップ時に入力欄のテキストを外から書き換えるため、`TextEditingController` を画面側で保持する。
  - `searchHistoryProvider` は `SearchScreen` では watch しない（履歴の表示は `SearchHistoryList` が watch する）。保存の責務は画面に依存させず、3.2節のとおり `TobinoriApp` 側で Provider を生成して生かす。
  - 結果エリアの出し分けに、上記2章の「履歴を出す状態」の判定を追加する。
  - 履歴行タップ時の処理（`onSelect` で受け取る名前は **`stationName`＝「駅」なしの保存名**。例「新宿」）:
    - フォーカスを外す。
    - コントローラの `text` を `stationName` にする（ユーザーが手入力する形と同じ。一覧の表示は `displayName`＝「新宿駅」だが、入力欄には入れない）。
    - `routeSearchProvider.notifier.search(destinationStationName: stationName)` を呼ぶ。
  - 履歴の削除失敗の通知は `SearchScreen` が一手に担う。`SearchHistoryList` から `onDeleteFailed` を受け取り、`ScaffoldMessenger` で `SnackBar`（「履歴を削除できませんでした」）を表示する。`SearchHistoryList` 自身は `SnackBar` を出さない。
- **`DestinationSearchField`（変更）** `lib/presentation/search/destination_search_field.dart`
  - 任意引数 `TextEditingController? controller` を追加する。
  - 未指定なら従来どおり内部で生成・破棄する（既存呼び出し・既存テストを壊さない）。
  - 指定された場合、そのコントローラの破棄は呼び出し側（`SearchScreen`）が行う。
- **`SearchHistoryList`（新規）** `lib/presentation/search/search_history_list.dart`
  - `ConsumerWidget`。`searchHistoryProvider` を watch する。
  - プロパティ:
    - `bool enabled`: 行タップの可否。
    - `ValueChanged<String> onSelect`: 履歴行タップ時のコールバック。引数は保存されている `stationName`（「駅」なし）。
    - `VoidCallback onDeleteFailed`: 1件削除・全件削除のいずれかが失敗したときに呼ぶ（確定）。SnackBar表示は呼び出し側（`SearchScreen`）の責務で、`SearchHistoryList` は表示しない。
  - 責務:
    - ヘッダー（「検索履歴」と「すべて削除」ボタン）の表示。
    - `ListView` による履歴行の表示。
    - 全件削除の確認ダイアログ（`AlertDialog`: 「検索履歴をすべて削除しますか？」キャンセル／削除）。
  - 状態ごとの表示:
    - `loaded` かつ0件: 何も表示しない（`SizedBox.shrink`）。
    - `loadFailed`: 小さな文言「履歴を読み込めませんでした」のみ。
    - `loading`: 何も表示しない（スピナーは出さない。ローカルDBは高速で、画面のちらつきを避けるため）。
- **`SearchHistoryTile`（新規、`search_history_list.dart` 内のprivate Widgetでも可）**
  - `ListTile` で構成する。
    - 先頭: `Icons.history`
    - タイトル: 表示名（例「新宿駅」）
    - 末尾: 削除用 `IconButton`（`Icons.close`、tooltip「新宿駅を履歴から削除」）
  - アクセシビリティ: 行タップ側にも `Semantics` を付け、ラベルは「新宿駅を検索」（非活性時は `enabled: false` でスクリーンリーダーに無効と伝える）とする。「×」は上記tooltipが読み上げラベルを兼ねる。
  - 色・角丸は `Theme.of(context)` のカラースキームと8px基調に従い、色の直書きはしない。

### 3.2 状態管理層（Riverpod Provider）

- **`searchHistoryRepositoryProvider`**
  - 型: `Provider<SearchHistoryRepository>`
  - 責務: DIポイント。テストでは偽Repositoryで `override` する。
- **`recordSearchHistoryUseCaseProvider`**
  - 型: `Provider<RecordSearchHistoryUseCase>`
- **`searchHistoryProvider`**
  - 型: `StateNotifierProvider<SearchHistoryNotifier, SearchHistoryState>`
  - 状態: `SearchHistoryState { SearchHistoryStatus status, List<SearchHistoryEntry> entries }`
    - `enum SearchHistoryStatus { loading, loaded, loadFailed }`
    - 既存の `RouteSearchState` と同様、sealed classやfreezedは使わず `enum` + データクラス（`==`/`hashCode`/`copyWith` を手書き）とする。
  - `SearchHistoryNotifier` の責務:
    - 生成時に履歴を読み込む。
    - コンストラクタで `ref.listen(routeSearchProvider, ...)` を行い、`success` への遷移を検知して履歴を保存する。この連携はF-04側で閉じ、`RouteSearchNotifier` は一切変更しない。
    - メソッド:
      - `Future<void> load()`: 再読み込み。`loadFailed` からの再試行にも使う。例外はすべて捕捉して `loadFailed` にする（`MissingPluginException` も特別扱いしない。6章14参照）。
    - 読み込みのレース対策（連番トークン）:
      - Notifier が `int _loadSeq` を持ち、`load()` の開始時にインクリメントして自分の番号を控える。
      - `findAll()` 完了時、自分の番号が最新（`_loadSeq` と一致）かつ Notifier が破棄されていない場合のみ state に反映する。古い番号の結果は捨てる。
      - 根拠: 保存後の `load()` と削除後の `load()` が重なり完了順が入れ替わっても、最後に開始した `load()` は必ず直前の書き込み完了後に始まっているため、最終的な表示は最新のDB内容に収束する。
      - `Future<bool> remove(int id)`: 1件削除。成功なら `true`。
      - `Future<bool> clear()`: 全件削除。成功なら `true`。
  - 保存リスナーの条件:
    - `previous?.status != success` かつ `next.status == success` かつ `next.lastQuery` が非null。
    - 保存対象は `next.lastQuery`（検索成功した、trim済みの入力文字列）。
    - 条件に合えば `RecordSearchHistoryUseCase` を呼び、完了後に `load()` する。
    - `unawaited` で呼び、結果表示をDB処理で待たせない。
    - 例外はNotifier内で握りつぶして `debugPrint` するのみ。駅名はログに出さない（5章）。例外の `runtimeType` のみ出力する。
  - Providerの生存範囲（確定）:
    - `autoDispose` は使わない（通常の `StateNotifierProvider`）。一度生成されたらアプリ終了まで生き続け、保存リスナーも切れない。
    - 保存の責務が `SearchScreen` の watch に暗黙依存しないよう、`TobinoriApp` の `initState`（既存の `fetchCurrentLocation()` 呼び出しと同じ箇所）で `ref.read(searchHistoryProvider)` を1回呼び、起動時に必ず生成する。`lib/main.dart` の変更が必要。
    - 表示側は `SearchHistoryList` が watch するだけで、保存とは独立。
    - 注意（テスト）: `SearchScreen` 単体を描画するテスト（`TobinoriApp` を経由しない）では起動時生成が走らない。保存リスナーを確認するテストは `TobinoriApp` を描画するか、`ProviderContainer` で `searchHistoryProvider` を明示的に read すること。
- **（参照のみ）`routeSearchProvider` / `connectivityStatusProvider` / `currentLocationPointProvider`**
  - F-01/F-02のものを参照するだけで、変更しない。

### 3.3 ドメイン層（UseCase/Service）

- **`SearchHistoryEntry`（値オブジェクト）** `lib/domain/history/search_history_entry.dart`
  - `final int id; final String stationName; final DateTime searchedAt;`
  - `String get displayName`: 「駅」で終わっていなければ「駅」を付けた文字列を返す。
  - `==` / `hashCode` / `toString` を手書きする（既存モデルの流儀）。
- **`normalizeStationName`（純粋関数）** `lib/domain/history/station_name_normalizer.dart`
  - シグネチャ: `String normalizeStationName(String raw)`
  - ルール（この順に適用）:
    1. 前後の空白（全角スペース含む）を除去。
    2. 末尾が「駅」なら1文字除去する。ただし除去後が空になる場合（入力が「駅」のみ）は除去しない。
  - 目的: 「新宿」と「新宿駅」を同じ履歴として扱う。`RouteRepositoryImpl` が「駅」を補うため、検索結果は変わらない。
  - 全角/半角や英字大小の正規化は行わない（過剰な処理を避ける。YAGNI）。
- **`RecordSearchHistoryUseCase`** `lib/domain/history/record_search_history_usecase.dart`
  - シグネチャ: `Future<void> call(String rawStationName)`
  - 処理:
    1. 正規化する。
    2. 空文字なら何もしない。
    3. `SearchHistoryRepository.save(name)` を呼ぶ。
  - 件数上限（`kSearchHistoryMaxCount = 20`）の定数はこのファイルまたは同ディレクトリに置き、Repositoryの `save` に引数として渡す。
  - 読み込み・削除・全件削除は単純な委譲のみで業務ロジックが無いため、UseCaseは作らずNotifierがRepositoryを直接呼ぶ（個人開発規模で過剰な抽象化を避ける）。

### 3.4 データ層（Repository）

- **`SearchHistoryRepository`（interface）/ `SearchHistoryRepositoryImpl`** `lib/data/history/search_history_repository.dart`
  - メソッド:
    - `Future<List<SearchHistoryEntry>> findAll()`: `searched_at` の降順（同値なら `id` 降順）で最大 `kSearchHistoryMaxCount` 件を返す。
    - `Future<void> save(String stationName, {required int maxCount})`: 追加または更新（先頭へ移動）し、上限を超えた古い行を削除する。1トランザクションで行う。
    - `Future<void> delete(int id)`
    - `Future<void> deleteAll()`
  - アクセス先: 端末内SQLite（sqflite）。
  - コンストラクタ: `SearchHistoryRepositoryImpl({required Future<Database> Function() openDatabase, DateTime Function()? now})`
    - DBは初回アクセス時に遅延オープンし、インスタンス内で使い回す。
    - 失敗Futureはキャッシュしない。`openDatabase()` が例外で終わった場合は保持しているFuture/参照を破棄し、次のメソッド呼び出し（`load()` 再試行など）で再オープンを試みる。成功したDBのみ使い回す。これにより一時的なDB障害から再起動なしで復帰できる。
    - `now` は検索日時の取得元で、テストで固定時刻を注入できるようにする。
  - すべてのメソッドは失敗時に例外をそのままthrowする。握りつぶすかどうかは呼び出し側の判断とする。
- **DB提供** `lib/data/history/app_database.dart`
  - `Future<Database> openAppDatabase()`: ファイル名 `tobinori.db`、`version: 1`、`onCreate` でテーブル作成。保存先は `getDatabasesPath()` 配下。
  - 将来のテーブル追加・スキーマ変更は `version` を上げて `onUpgrade` で対応する。
- **追加パッケージ**（`pubspec.yaml`）:
  - `sqflite`、`path`（dependencies）
  - `sqflite_common_ffi`（dev_dependencies。VM上のテストでインメモリDBを使うため）

### DBスキーマ

```sql
CREATE TABLE search_history (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  station_name TEXT    NOT NULL UNIQUE,   -- 正規化済みの駅名（末尾「駅」なし）
  searched_at  INTEGER NOT NULL           -- エポックミリ秒（直近の検索成功日時）
);
CREATE INDEX idx_search_history_searched_at ON search_history (searched_at DESC);
```

- 設計判断:
  - 保存するのは駅名と日時のみ。現在地（緯度経度）や経路結果は保存しない（プライバシー最小化、5章）。
  - architecture.md 4章の `destinationStationPlaceId` と `lastRouteSummaryJson` は本Issueでは作らない（未決定事項1・2参照）。必要になれば `version: 2` の `onUpgrade` で列を追加する。
- `save` の実装方針:
  - `UNIQUE` 制約があるため、同名は `INSERT OR REPLACE`（sqfliteの `ConflictAlgorithm.replace`）で上書きし、`searched_at` を更新する。
  - `id` は付け替わるが外部参照が無いため問題ない（「×」押下直前の再保存による削除の空振りは6章16参照）。
  - upsert構文（`ON CONFLICT ... DO UPDATE`）は使わない。minSdk 24（Android 7.0）端末のOS同梱SQLiteは古く、非対応の可能性があるため。
  - 同一トランザクション内で上限超過分を削除する:
    `DELETE FROM search_history WHERE id NOT IN (SELECT id FROM search_history ORDER BY searched_at DESC, id DESC LIMIT ?)`

## 4. 状態遷移

`SearchHistoryStatus` の遷移:

| 状態 | 説明 | 遷移条件 |
|---|---|---|
| `loading` | 初回読み込み中（初期状態） | Notifier生成直後 |
| `loaded` | 読み込み成功（0件含む） | `findAll()` 成功。保存・削除・全件削除成功後の再読み込みも含む |
| `loadFailed` | 読み込み失敗（DBオープン失敗を含む） | `findAll()` またはDBオープンが例外。失敗Futureはキャッシュされないため、次回の `load()`（保存・削除後の再読み込み含む）で再オープンされ、成功すれば `loaded` に戻る |

補足: 複数の `load()` が重なった場合は、最後に開始したものの結果のみ反映する（連番トークン。3.2節）。

履歴データの変化:

| 契機 | 履歴の変化 |
|---|---|
| `routeSearchProvider` が `success` へ遷移 | 保存（既存なら日時更新して先頭へ、新規なら追加）。21件目以降は古い順に削除 |
| `notFound` / `error` / `offline` / `locationUnavailable` | 保存しない（誤入力・失敗を履歴に残さない） |
| 履歴行の「×」 | 該当1件を削除して再読み込み |
| 「すべて削除」確認でOK | 全件削除して再読み込み |

保存タイミングの設計判断:
- 検索成功時のみ保存する。リクエスト送信時に保存すると、誤字入力や存在しない駅名が履歴に残ってしまうため。
- 重複は正規化後の駅名で判定する（「新宿」「新宿駅」は同一）。重複は新規行を増やさず、先頭に移動する。
- 履歴タップによる再検索が成功した場合も同じ経路で保存され、先頭に移動する。

## 5. 外部連携の詳細

- 外部API連携は無い（Routes APIは既存の `RouteRepository` が担当）。
- 端末機能として扱うのは、アプリ専用領域のSQLiteファイルのみ。
- 再検索時は、保存済みの駅名を `RouteSearchNotifier.search(destinationStationName: ...)` にそのまま渡す。`RouteRepositoryImpl` が末尾の「駅」を補うため、API呼び出し内容は新規入力と同じになる。
- プライバシー面:
  - 保存先は端末内のみで、アプリからの送信処理は存在しない。
  - **Auto Backupの扱い（要対応）**: 現在の `android/app/src/main/AndroidManifest.xml` に `android:allowBackup` の指定が無く、既定値 `true` になっている。このままだとOSの自動バックアップによりDBがGoogleアカウントのクラウドへ退避され、「クラウド同期は行わない」(requirements.md 5章) と矛盾する。
    - 対策（本Issueの実装範囲に含める。minSdk は 24 のため下記すべて有効）:
      1. `<application>` に `android:allowBackup="false"` を設定する。
      2. Android 12+（API 31以上）向け: `android:dataExtractionRules="@xml/data_extraction_rules"` を設定し、`android/app/src/main/res/xml/data_extraction_rules.xml` を新規作成する。`<cloud-backup>` と `<device-transfer>` の両方で `<exclude domain="database" path="." />`（sqfliteのDBは `database` ドメイン）を指定する。Android 12以降は `allowBackup` だけに頼らず、この設定でクラウドバックアップ・端末間移行の対象から明示的に外す。
      3. Android 11以下（API 24〜30）向け: `android:fullBackupContent="@xml/backup_rules"` を設定し、`res/xml/backup_rules.xml` で同様に `<exclude domain="database" path="." />` を指定する。`allowBackup="false"` と二重の保険で、Lintの警告（バックアップルール未設定）も避けられる。
    - 影響: 機種変更時や再インストール時に履歴は引き継がれない（要件上も同期なしなので許容。未決定事項5）。
    - 属性は古いAPIでは無視されるだけなので、minSdk 24でも分岐は不要。
  - iOS対応時にも同様の確認が必要（iCloudバックアップ対象外にする設定を検討）。
  - ログ（`debugPrint`）に駅名・履歴内容を出力しない。
  - 保存データは駅名と日時のみ。暗号化はしない（機微度が低く、端末の標準保護に委ねる）。
  - 履歴を消す手段（個別削除・全件削除）をUIで常に提供する。

## 6. 異常系・エッジケース一覧

| # | ケース | 振る舞い |
|---|---|---|
| 1 | DB初期化・読み込み失敗 | `loadFailed`。履歴エリアに小さく「履歴を読み込めませんでした」を表示。検索機能は通常どおり使える |
| 2 | 保存失敗（容量不足・DBロック等） | 握りつぶしてログのみ。ユーザーには通知せず、検索結果の表示には影響させない。履歴に残らないだけ |
| 3 | 削除・全件削除の失敗 | 状態は変えず、`SnackBar`「履歴を削除できませんでした」を表示 |
| 4 | 履歴0件 | 履歴セクションを非表示。プレースホルダー文のみ |
| 5 | 履歴が上限（20件）を超える | 保存時に古い順に削除。表示は常に新しい順 |
| 6 | 同名（「新宿」と「新宿駅」を含む）を再検索 | 行は増えず、先頭に移動 |
| 7 | 履歴タップ時にオフライン | 行は非活性（タップ不可）。`OfflineBanner` が理由を示す。閲覧と削除は可能 |
| 8 | 履歴タップ時に現在地未取得 | 非活性。既存の案内文を表示 |
| 9 | 履歴タップで再検索したが `notFound`/`error` | 既存どおりの通知・表示。履歴は変更しない。入力欄には履歴の駅名が残る |
| 10 | 検索中（`loading`）に履歴行をタップ／履歴の削除 | タップは非活性。削除は可能（検索結果には影響しない） |
| 11 | 検索成功の直後に連続して別の検索が成功 | 保存は検索ごとに独立して実行。再読み込みは最後の結果に収束する |
| 12 | 入力が「駅」だけで成功した | 正規化で空にならないよう「駅」のまま保存（表示は「駅」。稀なケースとして許容） |
| 13 | 同名の別地域駅（例: 府中） | 駅名のみで保持するため区別しない。再検索結果は新規検索と同じ（issue-2 既知の制約） |
| 14 | `MissingPluginException` を含む読み込み例外 | `load()` は全例外を同じ扱いで捕捉して `loadFailed` にし、クラッシュさせない。`MissingPluginException` を特別扱いして握りつぶすことはしない。本番のDB障害とテストでのoverride漏れが同じ見た目になるのを避けるため、(a) ログに例外の `runtimeType` を出す、(b) Widgetテストでは「履歴が正常系のケースで『履歴を読み込めませんでした』が出ていない」ことを確認する（7章）、(c) 下記の対象テストは全て偽Repositoryでoverrideする、の3点で区別する |
| 15 | 非常に長い駅名の履歴 | `ListTile` のタイトルを1行・`TextOverflow.ellipsis` で省略表示 |
| 16 | 「×」押下の直前に同名が再保存され `id` が付け替わった | `delete(id)` は0行削除のno-op（例外にしない）。続く再読み込みで最新の一覧に更新され、ユーザーは再度「×」を押せば消せる。無害なため許容。駅名キーでの削除への変更も検討したが、行を一意に指す `id` のほうが単純で、実害も無いため `id` 削除を維持する |
| 17 | 履歴の駅名で再検索して `notFound` / `error` になった | 履歴は自動削除しない（一時的な障害や現在地由来の失敗の可能性があり、勝手に消さない）。不要ならユーザーが「×」で削除する |
| 18 | Repository `save` の途中失敗（上限削除の失敗など） | 同一トランザクションのため全体ロールバックされ、追加分も残らない。ケース2と同様に握りつぶしてログのみ |

## 7. テスト観点（flutter-test-writerが参照する）

### ユニットテスト

- **`normalizeStationName`**
  - 「新宿」→「新宿」、「新宿駅」→「新宿」。
  - 前後の空白・全角スペースを除去する。
  - 「駅」のみ → 「駅」のまま。
  - 空文字・空白のみ → 空文字。
- **`SearchHistoryEntry`**
  - `displayName` が末尾「駅」の有無に関わらず「〇〇駅」になる。
  - 等価性が成り立つ。
- **`RecordSearchHistoryUseCase`**（偽Repository）
  - 正規化済みの名前と `kSearchHistoryMaxCount` を渡して `save` が1回呼ばれる。
  - 正規化後に空なら `save` が呼ばれない。
  - Repositoryが例外をthrowしたら、そのまま伝播する。
- **`SearchHistoryRepositoryImpl`**（`sqflite_common_ffi` のインメモリDB、`now` を固定）
  - `findAll`: 空DBで空リスト。保存順と逆（新しい順）で返る。
  - `save`: 同名を保存しても1行のまま、`searched_at` が更新され先頭に来る。
  - `save`: 上限（例: 3件に設定して4件目を保存）で最古の行が削除される。
  - `save` のロールバック: テスト内でインメモリDBに「`DELETE` 時に `RAISE(ABORT, ...)` する `TRIGGER`」を作成して上限削除を強制的に失敗させ、`save` が例外をthrowし、かつ追加しようとした行も残っていない（元の内容のまま）ことを確認する。
  - DBオープン失敗後の再試行: `openDatabase` に「1回目は例外、2回目は成功」するファクトリを渡し、1回目の呼び出しは例外、2回目の呼び出しは成功する（失敗Futureがキャッシュされない）ことを確認する。
  - 存在しない `id` の `delete`（再保存で `id` が付け替わったケース）が例外にならず、他の行に影響しない。
  - `delete`: 指定IDのみ削除される。存在しないIDでも例外にならない。
  - `deleteAll`: 全件削除される。
  - 同一ミリ秒で保存した場合も、`id` により安定した順序になる。
- **`SearchHistoryNotifier`**（偽Repository ＋ `routeSearchProvider` を override）
  - 生成時に `loading` → `loaded(entries)`。
  - `findAll` が例外 → `loadFailed`。その後 `load()` 成功で `loaded`。
  - `routeSearchProvider` が `success`（`lastQuery`: "新宿"）へ遷移すると `save` が呼ばれ、再読み込みされる。
  - `notFound` / `error` / `offline` への遷移では `save` が呼ばれない。
  - `save` が例外をthrowしても例外が漏れず、状態が壊れない。
  - `remove` / `clear`: 成功で `true` かつ再読み込み、失敗で `false` かつ状態不変。
  - `success` → `loading` → `success` の再検索で、2回目も保存が呼ばれる。
  - `load()` のレース: 1回目の `findAll()` を後から完了、2回目を先に完了させる（`Completer` で制御）と、最終的な state は2回目（新しい方）の結果になる。
  - 保存→削除の連続（保存の `load()` が遅れて完了）でも最終的な state が削除後の内容に収束する。
  - `loadFailed` 後の `load()` で、Repositoryが復帰していれば `loaded` に戻る。
  - `autoDispose` ではないこと: 購読者がいなくなっても保存リスナーが生きていて、`success` 遷移で `save` が呼ばれる。

### Widgetテスト

#### 既存テストへの影響（override必須の一覧）

`SearchScreen` または `TobinoriApp` を描画しているのは、実コードの調査（`SearchScreen(` / `TobinoriApp(` の検索）で次の3か所（ファイルは2つ）のみ。これらは**全て** `searchHistoryRepositoryProvider` を偽Repositoryでoverrideする。実DBを使うと `MissingPluginException` になり、`loadFailed` として静かに失敗して原因が見えにくくなるため。

| ファイル | 描画対象 | 箇所 |
|---|---|---|
| `test/widget_test.dart` | `TobinoriApp` | 2つの `testWidgets`（46行目付近・64行目付近の `ProviderScope`） |
| `test/presentation/search/search_screen_test.dart` | `SearchScreen` | `pumpSearchScreen` ヘルパー（71行目付近の `ProviderScope`）。全テストがこのヘルパー経由 |

影響が無いことを確認済みのテスト（`SearchScreen` / `TobinoriApp` を描画せず、変更不要）:
- `test/presentation/common/offline_banner_test.dart`（`OfflineBanner` 単体）
- `test/presentation/search/route_guidance_button_test.dart`、`route_result_card_test.dart`、`test/presentation/widgets/location_status_banner_test.dart`（部品単体）
- `test/providers/**` 配下（Provider単体）

共通の偽Repositoryはテスト用ヘルパーに置く（確定）: `test/helpers/fake_search_history_repository.dart` に `FakeSearchHistoryRepository`（初期履歴リストを受け取り、`save` / `delete` / `deleteAll` の呼び出し記録と、失敗させるフラグを持つ）を作り、上記2ファイルと新規Widgetテストが共有する。各ファイルで個別に偽物を作らない。

#### テストケース

- `SearchScreen`: 履歴があるとき、初期表示で履歴が新しい順に表示される。
- `SearchScreen`: 履歴が正常に読み込めているケースでは「履歴を読み込めませんでした」が表示されない（override漏れの検知用）。
- `SearchScreen`: 履歴行（表示は「新宿駅」）をタップすると、入力欄に「駅」なしの `stationName`（「新宿」）が入り、`routeSearchProvider` の検索が `destinationStationName: "新宿"` で1回実行される。
- `SearchScreen`: オフライン中・現在地未取得中・検索中は履歴行がタップできない（検索が呼ばれない）。ただし「×」は押せる。
- `SearchScreen`: `loading`/`success` では履歴が表示されず、`idle`/`notFound`/`error` では表示される。
- `SearchScreen`: 履歴0件のときは履歴ヘッダーも表示されない。
- `SearchScreen`: `loadFailed` のときは「履歴を読み込めませんでした」が表示され、検索は通常どおり行える。
- `TobinoriApp`（`widget_test.dart`）: 検索成功後に、その駅名が履歴に保存される（偽Repositoryに保存された名前を確認）。`SearchScreen` を直接描画するテストでは保存リスナーが起動しないため、この確認は `TobinoriApp` 経由で行う（3.2節）。
- `SearchHistoryList`: 「×」で該当行だけ消える。
- `SearchHistoryList`: 「すべて削除」で確認ダイアログが出る。キャンセルでは消えず、削除で全件消える。
- `SearchHistoryList`: 削除（1件・全件）が失敗したとき `onDeleteFailed` が1回呼ばれる（`SnackBar` は表示しない）。
- `SearchScreen`: 削除失敗時に `SnackBar`「履歴を削除できませんでした」が表示される。
- `SearchHistoryTile`: 行タップ側に `Semantics` ラベル（「新宿駅を検索」）があり、非活性時は無効として扱われる。
- `DestinationSearchField`: `controller` 未指定でも従来どおり動作する。外部コントローラの変更が入力欄に反映される。

### Manifest設定の確認（自動テスト対象外・手動確認可）

Manifest/XMLはFlutterのテストでは検証できないため、実装後に次のいずれかで確認する。
- `flutter build apk --debug` 後、`build/app/intermediates/merged_manifests/` 配下のマージ済みManifestで、`android:allowBackup="false"`、`android:dataExtractionRules`、`android:fullBackupContent` が `<application>` に入っていることを目視する。
- `aapt2 dump xmltree`（または Android Studio の APK Analyzer）で、ビルドしたAPKのManifestに同じ属性があることを確認する。
- `res/xml/data_extraction_rules.xml` と `backup_rules.xml` が存在し、`database` ドメインが `<cloud-backup>` / `<device-transfer>` / `<full-backup-content>` で除外されていること。
- Android Studio の Lint（`flutter analyze` ではなく `./gradlew lint`）でバックアップ関連の警告が出ないこと。
- 余力があれば実機（Android 12以上）で `adb shell bmgr backupnow <パッケージ名>` を実行し、DBがバックアップ対象にならないこと（ログに database が出ない）を確認する。

## 8. 未決定事項・確認したい点

設計側で決めたものは各章に記載済み。以下はプロダクト判断が必要、または確認しておきたい点。

1. **オフライン時の「直近ルート概要キャッシュ」の扱い**
   - architecture.md 4章・8.2 は、`lastRouteSummaryJson` を保存してオフライン時に直近結果を見せる構想を記載している。
   - 本設計では履歴にルートを保存しない（履歴は駅名と日時のみ）。理由:
     - 検索結果は現在地に依存するため、過去のルートは再訪時にほぼ無意味か誤解を招く。
     - 保存データを増やすほどプライバシー面のリスクが増える。
     - requirements.md のF-04は「目的地履歴から再検索」としか書いていない。
   - この方針でよいか確認したい。必要なら別Issueで `version: 2` として追加する。
2. **Place IDの保存**
   - issue-2 未決定事項2（同名駅・Place ID指定）をF-04で再検討する予定だった。
   - 本設計では保存しない。理由: 現在の Routes API リクエストの FieldMask にPlace IDが含まれず、取得には追加API（Places等）が必要になり、確定済み外部連携の範囲を超える。
   - 「府中」などの同名駅が履歴で区別できない点は既知の制約として残る。
3. **履歴の表示条件**
   - 結果表示中（`success`/`loading`）は履歴を隠し、`idle`/`notFound`/`error`等で表示する設計にした。
   - 「結果を見たまま別の履歴にすぐ切り替えたい」ニーズがあれば、入力欄フォーカス時に履歴を重ねて表示する案もある。MVPでは採用しない。意向を確認したい。
4. **履歴の保存件数上限（20件）**
   - architecture.md の「例: 直近50件」より少なく設定した。
   - 理由: 画面が一覧スクロール中心になり「最速」から遠ざかるため。通勤・通学の再検索用途なら20件で十分と判断。
   - 数値は定数1か所で変更できる。
5. **Android Auto Backupの無効化**（`allowBackup="false"` ＋ `dataExtractionRules` / `fullBackupContent`、5章）
   - プライバシー要件（クラウド同期なし）から必須と判断し、本Issueの実装範囲に含めた。
   - 端末買い替え時に履歴を引き継ぎたい場合は、この設定が逆効果になる。引き継ぎは不要という前提でよいか確認したい。
