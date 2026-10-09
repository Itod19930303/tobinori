# 詳細設計書 - Issue #3 F-03 最寄り駅までの経路案内

## 用語メモ

- **インテント（Intent）**: Androidで「他のアプリに何かを依頼する」ための仕組み。ここでは「Googleマップアプリを徒歩ナビ付きで開いて」という依頼に使う。
- **Riverpod / Provider / UseCase / Repository**: Issue #2設計書の用語メモと同じ（状態管理ライブラリ / 状態の入れ物 / 1機能分の処理 / 外部とのやり取りの窓口）。
- **URIスキーム**: `google.navigation:` や `https:` のように、URIの先頭で「どのアプリで開くか」を示す部分。
- **パッケージ可視性（package visibility）**: Android 11以降、アプリは他アプリの有無を無断で調べられない。`AndroidManifest.xml` の `<queries>` 宣言が必要になる。

## 1. 対象Issue・関連要件
- Issue: #3 F-03 最寄り駅までの経路案内（https://github.com/Itod19930303/tobinori/issues/3）
- 関連する機能要件: F-03（requirements.md 4章）
  - 最短ルート結果表示 →「経路案内」操作でGoogleマップアプリを起動（インテント連携）し、徒歩ナビゲーションはGoogleマップ側に委譲する。
  - アプリ内に独自の地図・道順UIは作らない（MVP方針で確定）。
  - 依存: F-02（`Route`を表示している画面にボタンを置く）。F-01の現在地は、Googleマップ側が自前で現在地を使うため本機能では不要（5章参照）。
- 関連する非機能要件:
  - パフォーマンス: 結果表示から1タップでGoogleマップの徒歩ナビに入れること（確認ダイアログ等を挟まない）。
  - オフライン（architecture.md 8.2）: F-02側でオフライン表示に切り替わった場合は結果表示ごとボタンも非表示になる（F-02の挙動を変更しない）。ボタン表示中にオフラインへ遷移した直後のタップに限り、起動を試行する（本機能は接続状態を見て止めない）。実際のナビ可否はGoogleマップ側に委ねる。
  - 対応OS: 現状Android。iOSは将来対応のため、プラットフォーム差分をデータ層に閉じ込める（architecture.md 6.3）。
  - UI: DESIGN.md（Express Blue基調、角丸8px、single-purpose）。ボタンはプライマリ操作として目立たせる。

## 2. 画面/UIフロー概要

新規画面は作らない。既存の `SearchScreen` の結果表示エリア（`RouteResultView`）に「経路案内」ボタンを追加する。

```
[SearchScreen] 検索成功時
  ┌───────────────────────────────┐
  │ 目的駅名入力欄 [______] [検索]      │
  ├───────────────────────────────┤
  │ RouteResultCard                   │
  │  所要時間 / 乗換 / 区間リスト       │
  ├───────────────────────────────┤
  │ [ 最寄り駅（○○駅）まで徒歩で案内 ]  │ ← 新規: RouteGuidanceButton
  └───────────────────────────────┘
        │ タップ
        ▼
  Googleマップアプリ起動（最寄り駅を目的地に徒歩ナビ開始）
```

操作フロー:
1. 検索成功（`RouteSearchStatus.success`）で `RouteResultCard` の下にボタンを表示する。
2. ボタンをタップすると `routeGuidanceProvider` 経由で起動処理を実行する。
3. 成功: Googleマップアプリが前面に出る。トビノリ側は何も表示しない（戻ってきたら結果表示のまま）。
4. Googleマップアプリ未インストール: ブラウザ（Web版Googleマップ）で同じ目的地を開く。
5. 起動自体に失敗: `SnackBar` で「Googleマップを起動できませんでした」を表示する（`notFound`時と同じ一時通知の流儀）。

### 「最寄り駅」の定義（重要・確定）
- 「最寄り駅」＝ **F-02ルートの最初の電車区間の乗車駅（`departureStop`）への徒歩案内** と解釈する。この解釈で確定（レビュー済み）。
- Googleマップ上で別の駅が物理的に最寄りになる可能性はあるが、アプリが表示するルートとの整合性を優先する。
- 現在地から最初の駅までは `Route` の先頭の徒歩区間にあたり、ここをGoogleマップの徒歩ナビに委譲する。
- 目的駅までの電車区間はアプリ内の `RouteResultCard` で確認する、という役割分担になる。

## 3. クラス設計

配置は既存コードの構成（`lib/presentation` `lib/providers` `lib/domain` `lib/data`）に合わせる。

### 3.1 UI層（Widget）

- **`RouteGuidanceButton`**（新規: `lib/presentation/search/route_guidance_button.dart`）
  - 責務: 「経路案内」ボタン。`ConsumerWidget`。
  - プロパティ: `NearestStation station`（案内対象。3.3参照）
  - 挙動:
    - ラベルは「`{駅名}`まで徒歩で案内」のように目的地を明示する（文言・配置はUXレビューで確認。8章）。
    - `Semantics` / ボタンの `semanticLabel`（またはアイコンの `semanticLabel`）に「`{駅名}`まで徒歩で案内」を設定し、スクリーンリーダーで目的地が伝わるようにする。
    - 1タップで起動まで完結させる（確認ダイアログは出さない）。
    - タップで `routeGuidanceProvider.notifier.startGuidance(station)` を呼ぶ。
    - `launching` 中は非活性（連打ガード）。
    - 失敗状態への遷移を `ref.listen` で検知し `SnackBar` を1回だけ表示する（`SearchScreen` の `notFound` 処理と同じ方式）。
  - アイコン: `Icons.directions_walk` 等。DESIGN.mdのプライマリ色（FilledButton）。
- **`RouteResultView`（既存を変更）**
  - `success` で `route.nearestStation != null` のとき、`RouteResultCard` の下に `RouteGuidanceButton` を並べる。
  - `nearestStation == null`（電車区間なし）のときはボタンを表示しない（暫定。8章の未決定事項1）。
- **`RouteResultCard`（変更なし）**
  - 既存の見た目を維持する。ボタンは `RouteResultView` 側で組み合わせる（カードの責務を増やさない）。

### 3.2 状態管理層（Riverpod Provider）

- **`routeGuidanceProvider`**（新規: `lib/providers/route/route_guidance_provider.dart`）
  - 型: `StateNotifierProvider<RouteGuidanceNotifier, RouteGuidanceState>`
  - 状態 `RouteGuidanceState { RouteGuidanceStatus status }`
    - MVPでは失敗理由を区別しない（`failed` 1種）ため、`failureReason` は持たない。詳細理由はログのみ。
    - `enum RouteGuidanceStatus { idle, launching, launched, failed }`
    - 既存方針（Issue #2）に合わせ `freezed` / `sealed class` は使わず、enum＋データクラス（`==`/`hashCode`手書き）にする。
  - メソッド: `Future<void> startGuidance(NearestStation station)`
    - `launching` 中は何もしない（二重起動ガード）。
    - `StartRouteGuidanceUseCase` を呼び、結果で状態を遷移させる。
  - 補足: 失敗通知を同じ値で2回出せるよう、`failed` の後に再タップされたら一度 `launching` を経由する（`ref.listen` が毎回発火する）。
- **`startRouteGuidanceUseCaseProvider`**: `Provider<StartRouteGuidanceUseCase>`（DIポイント）
- **`mapsLauncherRepositoryProvider`**: `Provider<MapsLauncherRepository>`（DIポイント。テストでモックに差し替える）
- 既存Providerへの依存: なし。`connectivityStatusProvider` や `currentLocationPointProvider` は参照しない（オフライン・現在地の有無で起動を止めない）。
  - そのため、ボタン表示中にオフラインへ遷移した直後のタップでも起動を試行する。F-02側でオフライン表示に切り替わった後はボタン自体が非表示（4章・6章 #6）。

### 3.3 ドメイン層（UseCase/Service）

- **`NearestStation`**（新規値オブジェクト: `lib/domain/route/nearest_station.dart`）
  - `final String name; final LocationPoint? location;`
  - `location`（既存の `LocationPoint`）がある場合は `google.navigation` で座標を目的地に指定する。無い場合は `google.navigation` を使わず、最初からWeb URL（駅名指定）で起動する（3.4）。
- **`Route`（既存へ追加）**
  - ゲッター `NearestStation? get nearestStation`
    - `steps` の中で最初の `RouteStepType.transit` の `departureStopName` と `departureStopLocation` から生成する。
    - 電車区間が無い、`departureStopName` が `null`、または空文字（`isEmpty`）なら `null`。
  - **変更範囲（既存コード確認済み。`lib/domain/route/route.dart` / `lib/data/route/route_repository.dart`）**
    - `RouteStep` に `LocationPoint? departureStopLocation` を1項目だけ追加（省略可能な名前付き任意引数。`==`/`hashCode`/`toString` にも追加）。到着駅の座標は不要なので追加しない。
    - `RouteRepositoryImpl._mapStep` の transit 分岐で、既に取得済みの `departureStop` マップから `location.latLng` を読み `LocationPoint` に変換する（追加は数行）。`walk` 分岐は変更なし。
    - `_fieldMask` は変更しない（5.3参照）。
  - 既存F-02のテストに影響するのは `RouteStep` の等価性のみ（追加項目は任意引数なので既存コンストラクタ呼び出しは壊れない）。回帰確認をテスト観点に含める。
- **`StartRouteGuidanceUseCase`**（新規: `lib/domain/route/start_route_guidance_usecase.dart`）
  - シグネチャ: `Future<GuidanceLaunchResult> call(NearestStation station)`
  - 責務: `MapsLauncherRepository.launchWalkingNavigation(station)` を呼ぶだけの薄い層。ドメイン例外や例外ではなく結果enumで返し、UI側のtry/catchを不要にする。
  - 薄い層だが、F-01/F-02の層構成との一貫性を優先して置くことで確定（Notifierから Repository を直接呼ぶ案は採らない）。
- **`GuidanceLaunchResult`**（enum: `lib/domain/route/guidance_launch_result.dart`）
  - `launchedMapsApp`: Googleマップアプリを起動できた
  - `launchedBrowser`: アプリ未導入のためブラウザで開いた
  - `failed`: どちらも起動できなかった
  - `failed` の詳細理由は区別しない（UIの文言は共通のためMVPでは `failed` 1種。詳細はログのみ）。失敗理由の型（`GuidanceFailureReason` 等）は作らない。

### 3.4 データ層（Repository）

- **`MapsLauncherRepository`（インターフェース）/ `MapsLauncherRepositoryImpl`**（新規: `lib/data/navigation/maps_launcher_repository.dart`）
  - シグネチャ: `Future<GuidanceLaunchResult> launchWalkingNavigation(NearestStation station)`
  - アクセス先: 端末のGoogleマップアプリ（Intent / URLスキーム）。
  - 利用パッケージ（`pubspec.yaml` に追加）: `android_intent_plus`、`url_launcher`
  - 分岐の全体像（確定）:
    - `isAndroid == true` かつ `station.location != null` → 下記手順1〜4（インテント優先、失敗時Webへ）。
    - `station.location == null`（座標なし）→ `google.navigation` は使わず、手順3のWeb URL（`destination=<駅名>`、`travelmode=walking`）で最初から起動する。未検証の `google.navigation:q=<駅名>` は採用しない。成功すれば `launchedBrowser`、失敗なら `failed`。
    - `isAndroid == false`（iOS等。本Issueの対象外）→ インテントは試さず、手順3のWeb URLへ直行する。
  - 実装方針（Android・座標あり）:
    1. `android_intent_plus` の `AndroidIntent` で `action: 'action_view'`、`data: 'google.navigation:q=<緯度>,<経度>&mode=w'`、`package: 'com.google.android.apps.maps'` を指定する。
    2. 起動前に `canResolveActivity()` で解決可否を確認する。不可、または `canResolveActivity()` 自体が例外を投げた場合も「解決不可」と同じ扱いで手順3へ（例外は握りつぶしてログのみ）。
       - architecture.md 6.3は `canLaunchUrl` と記載しているが、`google.navigation:` を `package` 指定のインテントで投げるには `android_intent_plus` の `canResolveActivity()` の方が「Googleマップアプリが実際にこのインテントを処理できるか」を直接判定できるため、こちらを採用する（`url_launcher` の `canLaunchUrl` はWebフォールバック側の判定に限る）。
    3. フォールバック: `url_launcher` の `launchUrl(Uri, mode: LaunchMode.externalApplication)` で `https://www.google.com/maps/dir/?api=1&destination=<目的地>&travelmode=walking` を開く（ブラウザ or Googleマップ）。
    4. 手順3も失敗したら `failed`。
  - 目的地の指定:
    - `station.location` あり: インテントは `q=<緯度>,<経度>`、Web URLは `destination=<緯度>,<経度>`。
    - 無し: Web URLのみ `destination=<駅名>`（`Uri` クラス経由で必ずエンコード）。**例外扱い**（座標は常に取れる前提。5.3参照）。同名駅の誤マッチは既知の制約。
  - 出発地は指定しない（Googleマップが端末の現在地を使う）。
  - 実装方針（iOS・将来）: `url_launcher` で `comgooglemaps://?daddr=...&directionsmode=walking`、不可なら手順3のWeb URL。iOSは本Issueの対象外（確定）。実装せず、`Platform` 分岐の置き場所だけ本クラス内に確保する。iOS対応時は `Info.plist` の `LSApplicationQueriesSchemes`（`comgooglemaps`）追加が必要。
  - パッケージのバージョンは実装手順で `flutter pub add` により最新安定版を確認して固定する（設計上の未決定事項ではない）。
  - テスト容易性: `android_intent_plus` / `url_launcher` は静的呼び出しが多くモックしづらい。そのため本クラスのコンストラクタで以下の関数を差し替え可能にする（最小限の関数型注入、独自の抽象クラスは増やさない）。
    - `Future<bool> Function(Uri intentData) tryLaunchAndroidIntent`
    - `Future<bool> Function(Uri webUri) launchWebUrl`
    - `bool isAndroid`
  - URI組み立てのみを行う純粋関数（`buildNavigationUri`（座標必須） / `buildWebFallbackUri`（座標または駅名））を `static` で公開し、単体テスト対象にする。
  - `AndroidIntent` の生成も `static AndroidIntent buildAndroidIntent(Uri data)` に切り出し、`action` / `package` / `data` を単体テストで検証できるようにする（`tryLaunchAndroidIntent` の既定実装はこれを使う）。

### 3.5 その他の変更（ネイティブ設定）
- `android/app/src/main/AndroidManifest.xml` の `<queries>` に `com.google.android.apps.maps` パッケージと `https` スキームの `VIEW` インテントを宣言する（Android 11以降のパッケージ可視性。無いとインストール済みでも「未導入」と判定される恐れ）。実装時に現状のManifestを確認して追記する。
- `INTERNET` 権限はF-02で必要なため既存。追加権限は不要。

## 4. 状態遷移

`RouteGuidanceStatus`:

| 状態 | 説明 | 遷移条件 |
|---|---|---|
| `idle` | 初期状態 | 画面初期表示時 |
| `launching` | 起動処理中（ボタン非活性） | `startGuidance` 呼び出し時（`idle`/`launched`/`failed` から） |
| `launched` | 起動成功（アプリまたはブラウザ） | UseCaseが `launchedMapsApp` / `launchedBrowser` を返した |
| `failed` | 起動失敗。`SnackBar` で通知 | UseCaseが `failed` を返した、または想定外の例外が出た |

- `launched`/`failed` は一時的な結果であり、再度ボタンが押されれば `launching` に戻る。画面上の見た目は `failed` でも変えない（通知のみ）。
- 新しい検索が成功した場合（`routeSearchProvider` 更新）の `routeGuidanceProvider` のリセットは不要。ボタンの引数 `NearestStation` が変わるだけで、状態は結果通知にしか使わないため。
- 検索側の状態（`RouteSearchStatus`）との関係:
  - `success` のときのみボタンが表示される。
  - `offline` へ遷移すると既存実装では `RouteResultView` がプレースホルダー表示になりボタンも消える。MVPではF-02の挙動に従いこの現状維持で確定（F-02の表示仕様は変更しない）。
  - ボタンが表示されている間にオフラインへ遷移した場合、表示が切り替わるまでの直後のタップのみ起動を試行する（接続状態は参照しない）。

## 5. 外部連携の詳細

### 5.1 Googleマップアプリ（Androidインテント）
- URI: `google.navigation:q=<緯度>,<経度>&mode=w`（`mode=w` が徒歩）。座標がある場合のみ使用する。
- 起動先パッケージ: `com.google.android.apps.maps`。
- Googleマップが開き、現在地から目的地への徒歩ナビ画面（またはルート確認画面）が表示される。ナビ開始の自動化はGoogleマップ側の挙動に依存する。

### 5.2 Web版Googleマップ（フォールバック）
- URL: `https://www.google.com/maps/dir/?api=1&destination=<緯度,経度 または 駅名>&travelmode=walking`
- 端末のブラウザ（またはGoogleマップのURLハンドラ）で開く。起点は未指定で、ブラウザ側の現在地利用許可に従う。
- 使う場面: Googleマップアプリ未導入 / インテント失敗 / 座標なし（最初からこちら） / 非Android（iOS等）。

### 5.3 Routes API との関係（座標の取得）
- F-02で既に呼んでいるレスポンスから座標を取る。**追加のAPIリクエストは発生せず、課金も増えない**。
- 既存コードの確認結果（`lib/data/route/route_repository.dart`）:
  - 確認済み: `_fieldMask` は `routes.legs.steps.transitDetails` を丸ごと指定している（子フィールド指定ではない）。Routes APIの仕様上、`transitDetails.stopDetails.departureStop.location.latLng` は追加のマスク変更なしで返却される想定。
  - 確認済み: `_mapStep` は現状 `departureStop` から `name` のみを読み、`location` は読んでいない。よって `_mapStep` への追記は必要。
  - 未確認: 実際のレスポンスに `departureStop.location.latLng` が含まれるか（実機/実APIでのレスポンス確認が必要）。実装時に実レスポンスで確認し、含まれなければフィールドマスクへ `routes.legs.steps.transitDetails.stopDetails` 等の明示を検討する。
- `RouteRepositoryImpl._mapStep` で、`departureStop.location.latLng` を `LocationPoint` に変換して `RouteStep.departureStopLocation` に入れる。
- **座標は常に取れる前提**とする。座標が無い場合は `google.navigation` を使わず、Web URL（駅名指定）で起動する例外扱い（3.4・6章 #8）。

### 5.4 Googleマップ未導入時
- 5.1の `canResolveActivity()` が `false` → 5.2のWeb URLへ。
- Playストアへの誘導は行わない（個人端末前提でインストール済みと想定。architecture.md 6.3の要確認事項）。

## 6. 異常系・エッジケース一覧

| # | ケース | 検知方法 | 振る舞い |
|---|---|---|---|
| 1 | Googleマップアプリ未インストール | `canResolveActivity()` が `false` | ブラウザでWeb版を開く（`launchedBrowser`）。エラー扱いにしない |
| 2 | Web版も開けない（ブラウザ無し等） | `launchUrl` が `false` / 例外 | `failed` →「Googleマップを起動できませんでした」を `SnackBar` で表示 |
| 3 | インテント起動時に例外（`PlatformException` / `ActivityNotFoundException`） | try/catch | Repository内でWebフォールバックへ。それも失敗なら `failed` |
| 4 | `<queries>` 未宣言で誤って「未導入」判定 | 実機確認 | 3.5のManifest宣言で防ぐ。実機（Android 15）で受け入れ確認 |
| 5 | 現在地未取得（`currentLocationPointProvider` が `null`） | - | **経路案内は止めない**。出発地はGoogleマップ側が現在地を使うため不要。ただしそもそも検索成功には現在地が必要で、通常ここには来ない。現在地が取れないときの挙動は「Googleマップ側の挙動に委ねる」 |
| 5b | Googleマップ側の位置情報権限が拒否 / 端末の位置情報サービスOFF | 検知不可 | トビノリでは検知・対処しない。**Googleマップ側の挙動（権限要求・案内画面表示等）に委ねる**。トビノリは目的地をセットして開くまでが責務 |
| 6 | オフライン | - | F-02側でオフライン表示に切り替わった場合は結果表示ごとボタンも消える（現状維持で確定）。ボタン表示中にオフラインへ遷移した直後のタップのみ、接続状態を見ずに起動を試行する（結果はGoogleマップ/ブラウザ側に委ねる。Web起動も失敗すれば `failed`） |
| 7 | 電車区間が無い（徒歩のみ）/ 乗車駅名が無い・空文字 | `route.nearestStation == null` | ボタン非表示（暫定。8章の未決定事項1） |
| 8 | 乗車駅の座標が無い（例外扱い） | `departureStopLocation == null` | `google.navigation` は使わず、最初からWeb URL（`destination=<駅名>`、`travelmode=walking`、URLエンコード済）で起動する（`launchedBrowser`）。同名駅の誤マッチリスクは既知の制約 |
| 8b | 非Android（iOS等。対象外） | `isAndroid == false` | インテントは試さずWeb URLへ直行（座標あり/なしに応じて destination を決める） |
| 8c | `canResolveActivity()` が例外 | try/catch | 解決不可と同じ扱いでWebフォールバック。ログのみ |
| 9 | 駅名に記号・日本語・スペースを含む | - | `Uri.encodeComponent` / `Uri` クラスで必ずエンコードし、不正なURIで失敗させない |
| 10 | ボタン連打 | `launching` 中 | 二重起動しない（Notifierで無視＋ボタン非活性） |
| 11 | 現在地が既に最寄り駅付近（先頭の徒歩区間が0分に近い） | - | 特別扱いしない。そのままGoogleマップに委譲する |
| 12 | Googleマップ側でナビが自動開始されない | 検知不可 | Googleマップ側の仕様。トビノリは目的地をセットして開くまでが責務 |
| 13 | 起動後にトビノリへ戻った | - | 検索結果の表示状態を維持する（再検索しない・状態をリセットしない） |

## 7. テスト観点（flutter-test-writerが参照する）

### ユニットテスト
- **`Route.nearestStation`**
  - 先頭が徒歩・次が電車 → その電車の `departureStopName` / `departureStopLocation` を返す
  - 電車が複数 → 最初の電車区間の乗車駅を返す（2本目ではない）
  - 電車区間なし → `null`
  - 電車区間はあるが `departureStopName` が `null` → `null`
  - 電車区間はあるが `departureStopName` が空文字 → `null`
- **`RouteStep`（拡張後）**: `departureStopLocation` を含む `==` / `hashCode` / `toString`
- **F-02既存テストの回帰**: `RouteStep` 拡張後も既存の `RouteStep` / `Route` / `RouteRepositoryImpl` / `SearchRouteUseCase` テストが修正なしで通る
- **`RouteGuidanceState`**: 同じ `status` なら `==` が true かつ `hashCode` が一致、異なれば false
- **`RouteRepositoryImpl`（F-02テストの追記）**
  - `departureStop.location.latLng` を含むレスポンスで `RouteStep.departureStopLocation` が正しくマッピングされる
  - `location` が無いレスポンスでも例外にならず `null` になる
- **`MapsLauncherRepositoryImpl`**（注入した関数で検証）
  - Android・座標あり・インテント解決可 → `launchedMapsApp`、Webは呼ばれない
  - Android・座標あり・解決不可 → Web URL起動し `launchedBrowser`
  - `canResolveActivity` 相当が例外を投げる → 解決不可と同じくWebフォールバック → `launchedBrowser`
  - インテント起動が例外 → Webフォールバック → `launchedBrowser`
  - Web起動も `false` / 例外 → `failed`
  - 座標なし → インテント関数は一度も呼ばれず、Web URL（`destination=<エンコード済駅名>`、`travelmode=walking`）で起動し `launchedBrowser`（日本語・スペース・記号を含む駅名も）
  - 座標なし・Web起動失敗 → `failed`
  - `isAndroid == false` → インテント関数は呼ばれずWeb URLへ直行（座標あり/なし両方）
  - 座標あり → `google.navigation:q=35.1,139.2&mode=w` 形式（緯度,経度の順）
  - Webフォールバックの `travelmode=walking` と `destination` が正しい（座標あり: `緯度,経度` / 座標なし: 駅名）
- **`buildNavigationUri` / `buildWebFallbackUri`**: 純粋関数として上記のURI内容を直接検証
- **`buildAndroidIntent`**: `action == 'action_view'`、`package == 'com.google.android.apps.maps'`、`data` が `buildNavigationUri` の結果と一致する
- **`StartRouteGuidanceUseCase`**: Repositoryの結果をそのまま返す
- **`RouteGuidanceNotifier`**
  - 成功（`launchedMapsApp`）: `idle → launching → launched`
  - 成功（`launchedBrowser`）: `idle → launching → launched`（ブラウザ起動でも `launched` に遷移する）
  - 失敗: `idle → launching → failed`
  - Repositoryが想定外の例外をthrow → `failed` に落ちクラッシュしない
  - `launching` 中の再呼び出しでRepositoryが2回呼ばれない
  - `failed` の後に再度呼ぶと再び `launching` を経由する

### Widgetテスト
- `RouteResultView`: `success` かつ `nearestStation` がある場合に `RouteGuidanceButton` が表示される
- `RouteResultView`: `nearestStation` が無い場合、ボタンが表示されない
- `RouteResultView`: `idle` / `loading` / `error` / `notFound` / `offline` ではボタンが表示されない
- `RouteGuidanceButton`: ラベルに最寄り駅名が含まれる。セマンティクスラベルにも駅名が含まれる
- `RouteGuidanceButton`: 1タップで `startGuidance` まで到達する（確認ダイアログが出ない）
- `RouteGuidanceButton`: タップでNotifier（モック）の `startGuidance` が正しい `NearestStation` で1回呼ばれる
- `RouteGuidanceButton`: `launching` 中は非活性
- `RouteGuidanceButton`: `failed` への遷移で `SnackBar`（「Googleマップを起動できませんでした」）が表示される
- `RouteGuidanceButton`: `launchedBrowser` / `launchedMapsApp` のときは `SnackBar` を出さない
- `SearchScreen`: 既存の `notFound` の `SnackBar`、オフライン優先表示のテストが壊れていない（回帰）
- 補足: `CircularProgressIndicator` 等の無限アニメーションを避け、`launching` 中の表示は静的（ボタン非活性のみ）にして `pumpAndSettle` で止まる設計にする（`SearchScreen` のコメントにある既知の注意点）

### 実機確認（自動テストの対象外・手動）
- Android 15実機で、Googleマップ導入済み → ナビが起動する
- Googleマップ無効化（または別端末）→ ブラウザで開く
- `<queries>` 設定が効いている（導入済みなのに未導入扱いにならない）
- **座標の有無**: 実APIレスポンスに `departureStop.location.latLng` が常に含まれることを確認する。座標は常に取れる前提で、座標なし時のWeb URL（駅名指定）起動は例外扱い（`google.navigation:q=<駅名>` は採用しないため検証不要）
- 座標なし時のWeb URL（`destination=<駅名>`）で、ブラウザ/Googleマップが妥当な駅を目的地にするか（可能なら座標を意図的に落として確認）
- Googleマップ側の位置情報権限拒否 / 位置情報OFF時にGoogleマップがどう振る舞うか（委ねる方針の確認）

## 8. 未決定事項・確認したい点

1. **徒歩のみ・電車区間なしのルートの扱い**: 目的駅が現在地から徒歩圏内だと `Route` に電車区間が含まれない可能性がある。この場合、本設計では「最寄り駅」が定義できないためボタンを非表示にした。代替案は「目的駅そのものを徒歩ナビの目的地にする」だが、現在の `Route` は目的駅の座標を持たない。この仕様でよいか、代替案を採るか確認したい。
2. **ボタンのラベル文言と配置**: 「{駅名}まで徒歩で案内」を結果カード直下に置く想定。固定表示（画面下部に固定）にするか、カードの下に流れる位置にするかはUXレビューで確認したい。

### 確定済み（レビュー反映。未決定ではない）
- 「最寄り駅」の定義: F-02ルートの最初の電車区間の乗車駅への徒歩案内（2章）。
- オフライン時: F-02の挙動に従い結果表示ごとボタンも消える現状維持。ボタン表示中にオフラインへ遷移した直後のタップのみ起動を試行（1章・4章・6章 #6）。
- 座標なし時: `google.navigation` は使わず最初からWeb URL（駅名指定）で起動（3.4・6章 #8）。
- 非Android（iOS等）: インテントを試さずWeb URL直行（3.4）。
- UseCase層: F-01/F-02との一貫性で置く（3.3）。
- Googleマップ未導入時: architecture.md 6.3どおりブラウザ（Web版）で開く。Playストア誘導はしない（5.4）。
- iOS: 本Issueの対象外（3.4）。
- パッケージバージョン: 実装手順で `flutter pub add` により確認（3.4）。
