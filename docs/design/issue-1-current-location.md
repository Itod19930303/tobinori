# 詳細設計書 - Issue #1 F-01 現在地取得

## 用語メモ

この設計書で出てくる専門用語を先にまとめておく。

- **Riverpod**: Flutterアプリの「状態管理」用のライブラリ。アプリ内のデータ（例: 現在地の取得結果）を、画面のどこからでも安全に参照・更新できるようにする仕組み。
- **Provider**: Riverpodが提供する「データの置き場所」の単位。例えば「現在地取得の状態」を保持するProviderを1つ作り、画面側はそれを見に行く（watchする）だけでよい。
- **embed（埋め込む）**: 別の画面・部品の中に組み込んで使うこと。この設計書では「F-01で作る部品を、F-02の検索画面に埋め込んで使う」という意味で使っている。
- **UseCase**: 「何をするか」という業務ロジックをまとめたクラス。画面（UI）やデータ取得の詳細（Repository）とは分けて置く。
- **Repository**: 外部（GPS・API・DB等）から実際にデータを取ってくる役割のクラス。
- **sealed class**: 「このクラスの種類（サブクラス）は決まった数種類しかない」とDartに教えるための書き方。状態を「取得中」「成功」「失敗」のように限られたパターンで表したいときに使う。

## 1. 対象Issue・関連要件

- Issue: #1 F-01 現在地取得（<https://github.com/Itod19930303/tobinori/issues/1>）
- 関連する機能要件: F-01（`docs/requirements.md` 4章）
  - 何ができるか: アプリ起動時にGPSで現在地を自動取得する
  - 誰が使うか: 全ユーザー
  - 画面/操作フロー概要:
    1. アプリ起動
    2. 位置情報の権限確認・取得
    3. 現在地情報を検索の起点として保持
  - F-02（目的駅検索）は、本Issueで取得する現在地情報を検索の起点として利用する（依存関係あり）
- 関連する非機能要件（`docs/requirements.md` 5章）
  - パフォーマンス: 「調べる→確認する」を最速にするため、起動直後にGPS取得を開始し体感待ち時間を減らす（`docs/architecture.md` 8.1）
  - 可用性・オフライン対応: オフライン時は明示的な状態表示を行う方針。本Issueでは主に「GPS取得自体の失敗」として同様の考え方を踏襲する（ネットワーク接続の可否そのものは、F-02のRoutes API呼び出し側で扱う）
  - 対応OS: Android 7.0（API24）以降を目安とし、`geolocator`パッケージを利用する（`docs/architecture.md` 6.2）

## 2. 画面/UIフロー概要

F-01は、専用の画面を持たない。

代わりに、アプリ起動直後に現在地取得処理をバックグラウンドで開始し、その結果（取得中／取得成功／各種失敗）をRiverpodの状態として保持する。

UI上の見え方は、F-02で設計される検索画面（未着手）の中に組み込む想定のため、本Issueでは「他機能が埋め込める最小限の状態表示Widget」までを設計範囲とする。

```
アプリ起動（main.dart / ルートWidgetのinitState相当）
   │
   ▼
CurrentLocationNotifier.fetchCurrentLocation() を自動実行
   │
   ├─ 位置情報サービスOFF ───────────────→ LocationFailed(serviceDisabled)
   ├─ 権限未許可 → 権限リクエスト → 拒否 ──→ LocationFailed(permissionDenied)
   ├─ 権限を「今後表示しない」で拒否済み ──→ LocationFailed(permissionDeniedForever)
   ├─ 取得タイムアウト ──────────────────→ LocationFailed(timeout)
   ├─ その他の例外 ──────────────────────→ LocationFailed(unknown)
   └─ 取得成功 ──────────────────────────→ LocationLoaded(LocationPoint)
   │
   ▼
currentLocationProvider の状態が更新される
   │
   ▼
F-02側の検索画面が currentLocationProvider を見に行く（watchする）
   ├─ LocationLoaded なら、検索起点として利用する
   └─ LocationFailed / Loading なら、本Issueで定義する
      LocationStatusBanner 等で状態を明示表示し、再試行の導線を出す
```

- 起動トリガーの実装箇所: 特定の画面ではなく、アプリのルートWidget（`main.dart`が生成する`ConsumerStatefulWidget`、例: `TobinoriApp`）の`initState`相当のタイミングで、`ref.read(currentLocationProvider.notifier).fetchCurrentLocation()`を1回だけ呼び出す。
  - こうすることで、どの画面がホーム画面になっても取得タイミングが画面実装に依存しない。
- 失敗時の見た目（バナー文言・レイアウト）は、デザインシステム（DESIGN.md）に沿ったコンポーネントとして本Issueで最小限実装する。ただし検索画面への実際の組み込みはF-02側のIssueで行う。

### 確定事項（F-02連携仕様）

以下は、ユーザーとの対話で確定した、F-02（検索画面）との連携仕様。F-02の詳細設計時もこの内容を前提とする。

- **検索ボタンの活性/非活性条件**
  - 駅名入力などの検索条件入力操作そのものは、`currentLocationProvider`の状態に関わらず常に操作可能とする（ブロックしない）。
  - 一方、「検索」ボタン（経路検索の実行トリガー）は、`currentLocationProvider`が`LocationLoaded`になるまでは非活性（押下不可）とする。
  - `LocationInitial`・`LocationLoading`・`LocationFailed`のいずれの間も、検索ボタンは無効化する。
  - F-02側の実装では、`currentLocationProvider`（または`currentLocationPointProvider`が非`null`かどうか）を、検索ボタンの`onPressed`の有効/無効判定に利用する想定。
- **`LocationStatusBanner`の設置場所**: 検索画面（F-02）の画面最上部に設置する。
- **現在地の手動再取得**: `LocationStatusBanner`上のボタンから、現在地を手動で再取得できる（詳細は3.1節）。

## 3. クラス設計

想定ディレクトリ構成（`docs/architecture.md`のレイヤー構成に準拠）:

```
lib/
  presentation/
    widgets/
      location_status_banner.dart
  providers/
    location/
      current_location_provider.dart
  domain/
    location/
      location_point.dart
      location_failure_reason.dart
      location_state.dart
      get_current_location_usecase.dart
  data/
    location/
      location_repository.dart
```

### 3.1 UI層（Widget）

**`LocationStatusBanner`**

- 責務: `LocationState`を受け取り、状態に応じたメッセージと「現在地を再取得」ボタン（または設定画面を開くボタン）を表示する、見た目だけを担当するWidget。
  - 検索画面（F-02）の最上部に設置される想定（確定事項、2章参照）。
- 表示仕様（状態ごと）:
  - `LocationInitial`（起動直後、`fetchCurrentLocation()`呼び出し前）
    - `LocationLoading`と同一のローディング表示にする。
    - 3.2節の通り、自動取得は起動直後に1回だけ即座にトリガーされる設計のため、UI上で`LocationInitial`が見える時間は実質ごく短い想定。それでも「取得中である」ことを一貫してユーザーに示すため、`LocationLoading`と区別せず同じローディングUIを描画する（＝`LocationStatusBanner`内部では、`LocationInitial`と`LocationLoading`を同じ分岐で扱う）。
    - 再取得ボタンは非表示（またはタップ不可）にする。
  - `LocationLoading`
    - ローディングインジケータを表示する。
    - 再取得ボタンは非表示（またはタップ不可）にする（取得処理が既に進行中のため、多重実行を避ける）。
  - `LocationLoaded`
    - 従来は何も表示しない設計だったが、確定事項により「現在地を再取得」ボタン（小さいアイコンボタン、例: リフレッシュアイコン）を常時表示する形に変更する。
    - バナー本体のメッセージ文言は表示しない、またはごく控えめな表示（例: アイコンボタンのみ）とする。`SizedBox.shrink()`（＝何も表示しない書き方）は使用しない。
  - `LocationFailed(reason)`
    - 失敗理由に応じたメッセージを表示する。
    - `permissionDeniedForever`の場合は「設定を開く」ボタンを表示する。
    - それ以外（`serviceDisabled`/`permissionDenied`/`timeout`/`unknown`）の場合は「現在地を再取得」ボタンを表示する。
- ボタンの統合方針
  - 「再試行」ボタンと「現在地を再取得」ボタンは機能的に同一（`fetchCurrentLocation()`相当を呼び出し、状態を`LocationLoading`に戻す）。
  - そのためUI上は1つのボタン（ラベル/アイコンは共通、例: リフレッシュアイコン＋「現在地を再取得」）として統合する。
  - `LocationLoaded`後・`LocationFailed`後のどちらの状態でも押下可能にする。
- 主要なプロパティ:
  - `LocationState state`: 表示対象の状態。
  - `VoidCallback onRefetch`: 「現在地を再取得」ボタン押下時のコールバック。`LocationLoaded`・`LocationFailed`（`permissionDeniedForever`を除く）の両状態で使う共通コールバック。押下すると`fetchCurrentLocation()`が呼ばれ、状態が`LocationLoading`に戻る。
  - `VoidCallback onOpenSettings`: `permissionDeniedForever`時の「設定を開く」ボタン押下時のコールバック。`openAppSettings()`を呼び出す。
- 備考:
  - F-02の検索画面が、このWidgetを画面最上部に埋め込んで利用する想定（他機能から参照されるUI部品）。
  - 検索ボタンの活性/非活性制御そのものは`LocationStatusBanner`の責務ではない。F-02側の検索画面Widgetが`currentLocationProvider`（または`currentLocationPointProvider`）を直接watchして判定する（2章の確定事項参照）。

### 3.2 状態管理層（Riverpod Provider）

すべて手書き（コード生成なし）のRiverpodで実装する（`docs/architecture.md` 2.2）。

- `locationRepositoryProvider`
  - 型: `Provider<LocationRepository>`
  - 内容: `LocationRepository()`を返すだけの単純なDIポイント（＝依存先のインスタンスを差し替えやすくするための置き場所）。
- `getCurrentLocationUseCaseProvider`
  - 型: `Provider<GetCurrentLocationUseCase>`
  - 内容: `GetCurrentLocationUseCase(ref.watch(locationRepositoryProvider))`
- `currentLocationProvider`
  - 型: `StateNotifierProvider<CurrentLocationNotifier, LocationState>`
  - 保持する状態: `LocationState`（3.3参照の`LocationState`。sealed classで「取得前／取得中／成功／失敗」の4パターンを表す）
  - 責務: アプリ全体で共有する「現在地取得状態」の唯一の正解データ（Source of Truth）。
    - F-02はこのProviderをwatchするだけで、現在地を検索起点として利用できる（＝本Issueが提供する他機能向けインターフェース）。
  - 公開メソッド:
    - `Future<void> fetchCurrentLocation()`: 現在地取得を実行し状態を更新する。以下の3箇所から呼ばれる共通メソッド（呼び出し元によって処理を分岐させない）。
      1. アプリ起動時（ルートWidgetから自動的に1回）
      2. `LocationStatusBanner`の「現在地を再取得」ボタン押下時（`LocationFailed`状態からの再試行）
      3. `LocationStatusBanner`の「現在地を再取得」ボタン押下時（`LocationLoaded`状態からの手動再取得。確定事項、2章・3.1節参照）
- `currentLocationPointProvider`（F-02向けの利便性Provider）
  - 型: `Provider<LocationPoint?>`
  - 内容: `currentLocationProvider`の状態が`LocationLoaded`の場合はその`LocationPoint`を、それ以外は`null`を返す派生Provider。
  - F-02側で「取得済みの現在地だけを素直に使いたい」ケース向けの薄いラッパー。

**`CurrentLocationNotifier`**（`StateNotifier<LocationState>`）

- コンストラクタ: `CurrentLocationNotifier(this._useCase) : super(const LocationInitial())`
- `Future<void> fetchCurrentLocation()`の処理内容:
  1. `state = const LocationLoading()`
  2. `_useCase.call()`を実行
  3. 成功時: `state = LocationLoaded(point)`
  4. 失敗時: `state = LocationFailed(reason)`

### 3.3 ドメイン層（UseCase/Service）

- `LocationPoint`（値オブジェクト、`domain/location/location_point.dart`）
  - フィールド: `final double latitude; final double longitude;`
  - `==`/`hashCode`をオーバーライドした不変クラス（`const`コンストラクタ）。
  - F-02・F-03から参照される共通の位置情報の型として、`domain`層に置き他機能からimportしやすくする。
- `LocationFailureReason`（enum、`domain/location/location_failure_reason.dart`）
  - 値: `serviceDisabled`, `permissionDenied`, `permissionDeniedForever`, `timeout`, `unknown`
- `LocationState`（sealed class、`domain/location/location_state.dart`）
  - Dart 3のsealed classによるパターンマッチを利用し、freezed等の追加コード生成パッケージは導入しない。
  - `LocationInitial`（起動直後、未取得）
  - `LocationLoading`（取得処理中）
  - `LocationLoaded`（`final LocationPoint point`を保持）
  - `LocationFailed`（`final LocationFailureReason reason`を保持）
- `GetCurrentLocationUseCase`（`domain/location/get_current_location_usecase.dart`）
  - メソッド: `Future<LocationResult> call()`
    - 戻り値: `LocationResult`は、UseCase内で`LocationRepository`の結果（後述）をそのまま返す薄いラッパー。
    - F-01時点では追加の業務ロジックはほぼ持たない。ただし将来的な加工処理（例: 精度に基づくフィルタリング等）を挟められるよう、Provider層が直接Repositoryを呼ばずUseCaseを経由する構成にする（`docs/architecture.md`のレイヤー構成を踏襲）。
    - `LocationResult`は`domain/location/location_point.dart`と同居させる小さなsealed class（`LocationSuccess(LocationPoint point)` / `LocationFailureResult(LocationFailureReason reason)`）とする。`LocationState`とは別に定義し、UseCaseの戻り値とProviderの状態を分離することで、UI都合の`LocationInitial`/`LocationLoading`をドメイン層に持ち込まないようにする。

### 3.4 データ層（Repository）

- `LocationRepository`（`data/location/location_repository.dart`）
  - 抽象インターフェースは設けず、具象クラス1つのみとする（個人開発規模のため過度な抽象化を避ける方針）。
    - テスト時は`geolocator_platform_interface`が提供する`GeolocatorPlatform.instance`の差し替えでモック化する。詳細は8章。
  - アクセス先: 端末GPS（`geolocator`パッケージ経由）
  - メソッド: `Future<LocationResult> getCurrentLocation()`
    - 内部処理フロー:
      1. `Geolocator.isLocationServiceEnabled()`で位置情報サービスの有効性を確認する。無効なら`LocationFailureResult(serviceDisabled)`を返す。
      2. `Geolocator.checkPermission()`で権限状態を確認する。
      3. `denied`の場合は`Geolocator.requestPermission()`で権限をリクエストする。それでも`denied`なら`LocationFailureResult(permissionDenied)`。
      4. `deniedForever`の場合は`LocationFailureResult(permissionDeniedForever)`を返す（この場合はOS側のリクエストダイアログが出せないため、UI側で設定アプリへの導線を出す）。
      5. `whileInUse`/`always`の場合、`Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)))`で現在地を取得する。
      6. タイムアウト（`TimeoutException`）時は`LocationFailureResult(timeout)`を返す。
      7. その他の例外は`LocationFailureResult(unknown)`を返す。
      8. 成功時は`Position`の`latitude`/`longitude`から`LocationPoint`を生成し、`LocationSuccess(point)`を返す。
  - 設定アプリを開くための補助メソッド: `Future<void> openAppSettings()`（`Geolocator.openAppSettings()`のラッパー。`permissionDeniedForever`時にUI側から呼び出す）

## 4. 状態遷移

`LocationState`（Provider/UI向け状態）の遷移:

```
LocationInitial
   │ fetchCurrentLocation()
   ▼
LocationLoading
   ├─ 成功 ──────────────→ LocationLoaded(point)
   │                              │ 「現在地を再取得」ボタン押下（LocationStatusBanner、確定事項）
   │                              ▼
   │                         LocationLoading（以降同様のループ）
   └─ 失敗 ──────────────→ LocationFailed(reason)
                                  │ 「現在地を再取得」ボタン押下（LocationStatusBanner。permissionDeniedForever時は「設定を開く」ボタンのためこの遷移は発生しない）
                                  ▼
                             LocationLoading
```

- `LocationLoaded`から自動的に定期再取得は行わない（MVPでは「起動時に1回取得し検索起点として保持」で足りるため）。
  - ただし確定事項として、`LocationStatusBanner`上の「現在地を再取得」ボタンによるユーザーの明示操作からは`LocationLoaded`→`LocationLoading`への遷移が可能（3.1節・3.2節参照）。
- `LocationFailed`の`reason`によってUI側の導線が変わる（6章参照）。
  - `permissionDeniedForever`の場合のみ「現在地を再取得」ボタンではなく「設定を開く」ボタンが表示され、押下してもこのProviderの状態遷移（`fetchCurrentLocation()`呼び出し）は発生しない（OS設定アプリへの遷移のみ）。
- **検索ボタンの活性/非活性**（F-02側の挙動、確定事項）: `LocationLoaded`のときのみ検索ボタンが活性化する。`LocationInitial`/`LocationLoading`/`LocationFailed`の間は非活性。

## 5. 外部連携の詳細

- 利用パッケージ: `geolocator`（`docs/architecture.md` 6.2で確定）
- **対象プラットフォームのスコープ**: 本Issueの実装対象は**Androidのみ**とする。
  - `docs/architecture.md` 2.1に「iOS対応は将来（1年以内目安）」と明記されており、現時点でiOSはリリース対象外のため、本設計書でもiOS向けの設定（`Info.plist`への`NSLocationWhenInUseUsageDescription`追加等）は実装スコープに含めない。
  - これは記載漏れではなく、上記方針を踏まえた意図的なスコープ限定である。iOS対応着手時には、本設計書を改訂した上で`Info.plist`設定・`geolocator`のiOS固有挙動（後述の未決定事項参照）の追加設計を行う。
- Android側の設定: `AndroidManifest.xml`に`ACCESS_FINE_LOCATION`権限を追加する（実装時にプロジェクト作成後に対応。`docs/architecture.md` 6.2に対応する設定）
- リクエスト内容: 明示的なHTTPリクエストは発生しない（端末OSのGPS/位置情報プロバイダへの問い合わせ）。`Geolocator.getCurrentPosition`の`LocationSettings`で`accuracy: LocationAccuracy.high`、`timeLimit: Duration(seconds: 10)`を指定する（確定事項。理由は6章・8章参照）。
- レスポンス構造とドメインモデルへのマッピング: `geolocator`の`Position`（`latitude`, `longitude`, `accuracy`, `timestamp`等を保持）のうち、F-01スコープでは`latitude`/`longitude`のみを`LocationPoint`にマッピングする（`accuracy`や`timestamp`など他フィールドは現時点で未使用。将来必要になった場合に`LocationPoint`を拡張する）。

## 6. 異常系・エッジケース一覧

以下は5章のスコープに合わせ、**Androidの権限モデル（`whileInUse`/`always`/`denied`/`deniedForever`等）を前提**とした一覧である。iOS対応時は権限モデル・ダイアログ挙動がAndroidと異なる（例: 初回拒否後に再度OSダイアログを出せない条件がAndroidと異なる等）ため、本表は見直しが必要になる想定。

| ケース | 振る舞い |
|---|---|
| 位置情報サービス（端末のGPS/位置情報設定）がOFF | `LocationFailed(serviceDisabled)`。バナーで「位置情報サービスがオフになっています」等を表示し、端末設定を開く導線（`Geolocator.openLocationSettings()`）を提示 |
| 権限を初回ダイアログで拒否 | `LocationFailed(permissionDenied)`。バナーで再試行ボタンを表示し、押下時に`fetchCurrentLocation()`を再実行（OSの権限ダイアログを再度表示できる） |
| 権限を「今後表示しない」で拒否（Android: 2回目拒否時に自動的にこの状態になる） | `LocationFailed(permissionDeniedForever)`。バナーで「アプリの設定から位置情報を許可してください」と表示し、`openAppSettings()`でOS設定画面へ遷移させる導線を提示（アプリ内から権限ダイアログは再表示できないため） |
| GPS信号が弱く取得が完了しない（屋内・地下等） | `LocationSettings.timeLimit`（10秒。確定事項。屋内やビル陰でのGPS初回捕捉＝コールドスタートに時間がかかるケースを考慮し、打ち切り→再試行の往復を減らすため8秒から変更）でタイムアウトさせ`LocationFailed(timeout)`。バナーで「現在地の取得に時間がかかっています」等を表示し「現在地を再取得」ボタンを提供 |
| 上記以外の予期しない例外（プラットフォーム例外等） | `LocationFailed(unknown)`。汎用的な「現在地を取得できませんでした」文言＋「現在地を再取得」ボタン |
| アプリ起動直後、取得完了前にF-02の検索画面が先に表示されるケース | `currentLocationProvider`が`LocationLoading`のため、F-02側は検索起点が未確定であることを`LocationStatusBanner`（画面最上部）で明示する。検索条件の入力操作自体はブロックしないが、検索ボタンは`LocationLoaded`になるまで非活性にする（確定事項、2章・4章参照） |
| `LocationLoaded`後にユーザーが手動で現在地を更新したい場合（取得後に移動した等） | `LocationStatusBanner`の「現在地を再取得」ボタン押下により`fetchCurrentLocation()`が再実行され、状態が`LocationLoading`に戻る（確定事項）。再取得中は検索ボタンが再び非活性になる |
| ネットワークが完全にオフラインの状態でGPS取得を行う | GPSは衛星測位のため基本的にネットワーク接続なしでも取得可能。ただしAndroidの位置情報精度モード（ネットワークベース測位を含む設定）次第では取得に時間がかかる場合があり、その場合も上記の`timeout`扱いに収斂させる。F-02のRoutes API呼び出し可否とは独立した問題として扱う |

## 7. テスト観点（flutter-test-writerが参照する）

### ユニットテスト

- `LocationRepository.getCurrentLocation()`
  - 正常系: 権限が`whileInUse`/`always`で、位置情報取得に成功した場合に`LocationSuccess`かつ正しい緯度経度の`LocationPoint`が返ること
  - 異常系: 位置情報サービスが無効の場合に`LocationFailureResult(serviceDisabled)`を返すこと（`requestPermission`が呼ばれないこと＝早期リターンの確認も含む）
  - 異常系: 権限`denied`→リクエスト後も`denied`の場合に`LocationFailureResult(permissionDenied)`を返すこと
  - 異常系: 権限が`deniedForever`の場合に`requestPermission`を呼ばずに`LocationFailureResult(permissionDeniedForever)`を返すこと
  - 異常系: `getCurrentPosition`が`TimeoutException`を投げた場合に`LocationFailureResult(timeout)`を返すこと
  - 異常系: `getCurrentPosition`がその他の例外を投げた場合に`LocationFailureResult(unknown)`を返すこと
  - `GeolocatorPlatform.instance`をモック実装（`geolocator_platform_interface`のテストユーティリティ、または`mocktail`で`GeolocatorPlatform`を実装したモック）に差し替えてテストする
- `LocationRepository.openAppSettings()`
  - `Geolocator.openAppSettings()`が1回呼ばれること（モック化した`GeolocatorPlatform.instance`に対する呼び出し検証。`permissionDeniedForever`時にUIから呼ばれる補助メソッドのため、戻り値の分岐処理は持たず呼び出しの委譲のみを検証すれば十分）
- `GetCurrentLocationUseCase.call()`
  - `LocationRepository`の戻り値（`LocationSuccess`/`LocationFailureResult`）をそのまま返すこと（モックRepositoryを注入して検証）
- `CurrentLocationNotifier`
  - 正常系: `fetchCurrentLocation()`呼び出し時に状態が`LocationInitial` → `LocationLoading` → `LocationLoaded(point)`の順で遷移すること
  - 異常系: UseCaseが失敗を返した場合に`LocationLoading` → `LocationFailed(reason)`の順で遷移し、`reason`が正しく伝播すること
  - 再取得系: 状態が`LocationLoaded`のときに`fetchCurrentLocation()`を再度呼び出すと、`LocationLoading`を経て新しい`LocationLoaded(point)`（または`LocationFailed(reason)`）に遷移すること（確定事項の「現在地を再取得」操作に対応する遷移の検証）
  - 再取得系: 状態が`LocationFailed(reason)`のときに`fetchCurrentLocation()`を再度呼び出すと、`LocationLoading`を経て新しい状態に遷移すること
  - モック化した`GetCurrentLocationUseCase`を注入してテストする
- `currentLocationPointProvider`
  - `currentLocationProvider`が`LocationLoaded`のときに対応する`LocationPoint`を返すこと
  - `currentLocationProvider`が`LocationInitial`/`LocationLoading`/`LocationFailed`のときに`null`を返すこと
- 検索ボタンの活性/非活性判定（F-02側で実装される想定だが、本Issueが提供する状態を前提とするため観点として記載する）
  - `currentLocationProvider`（または`currentLocationPointProvider`）が`LocationLoaded`（非`null`）のときのみ検索ボタンが活性であると判定できること
  - `LocationInitial`/`LocationLoading`/`LocationFailed`のいずれの場合も検索ボタンが非活性であると判定できること

### Widgetテスト

- `LocationStatusBanner`
  - `LocationLoaded`状態の場合、「現在地を再取得」ボタン（アイコンボタン）が表示されること（確定事項によりSizedBox.shrinkではなくなったことの確認）
  - `LocationInitial`状態の場合、`LocationLoading`と同一のローディング表示（インジケータ等）がされること（3.1節の仕様通り、両者が同じ見た目になることを確認）。「現在地を再取得」ボタンは非表示またはタップ不可であること
  - `LocationLoading`状態の場合、ローディング表示（インジケータ等）が表示されること。「現在地を再取得」ボタンは非表示またはタップ不可であること
  - `LocationFailed(serviceDisabled)`/`(permissionDenied)`/`(timeout)`/`(unknown)`それぞれで、対応するメッセージ文言と「現在地を再取得」ボタンが表示されること
  - `LocationFailed(permissionDeniedForever)`の場合、対応するメッセージ文言と「設定を開く」ボタンが表示され、「現在地を再取得」ボタンは表示されないこと
  - `LocationLoaded`状態で「現在地を再取得」ボタンをタップすると`onRefetch`コールバックが呼ばれること
  - `LocationFailed`（`permissionDeniedForever`を除く）状態で「現在地を再取得」ボタンをタップすると`onRefetch`コールバックが呼ばれること
  - `LocationFailed(permissionDeniedForever)`状態で「設定を開く」ボタンをタップすると`onOpenSettings`コールバックが呼ばれ、`onRefetch`は呼ばれないこと
- 検索画面（F-02側の実装だが、本Issueの状態提供を前提にした観点として記載）
  - `currentLocationProvider`が`LocationLoaded`以外（`LocationInitial`/`LocationLoading`/`LocationFailed`）のとき、検索ボタンWidgetの`onPressed`が`null`（＝非活性）であること
  - `currentLocationProvider`が`LocationLoaded`のとき、検索ボタンWidgetの`onPressed`が非`null`（＝活性）であること
  - `LocationStatusBanner`が検索画面の最上部（他の検索UI要素より前）に配置されていること

## 8. 未決定事項・確認したい点

### 確定した事項（参考記録）

以下はユーザーとの対話で確定済みのため、本Issueおよびflutter-test-writer/flutter-feature-implementationの前提として扱う（詳細は各該当節を参照）。

1. **F-01取得中/失敗中にF-02の検索操作をブロックするか**（確定）
   - 駅名入力などの検索条件入力操作自体はブロックしない。
   - 一方、「検索」ボタンは`currentLocationProvider`が`LocationLoaded`になるまで非活性にする（`LocationInitial`/`LocationLoading`/`LocationFailed`の間は非活性）。
   - 2章・4章・7章参照。
2. **`LocationStatusBanner`の実際の設置場所**（確定）: 検索画面（F-02）の最上部に設置する。2章・3.1節参照。
3. **位置情報取得のタイムアウト秒数**（確定）: 8秒の仮置きから10秒に変更する。
   - 理由: 屋内やビル陰でのGPS初回捕捉（コールドスタート）に時間がかかるケースを考慮し、タイムアウトによる失敗→再試行の往復を減らすため。
   - 5章・6章参照。
4. **`LocationLoaded`後の明示的な再取得UI**（確定）
   - `LocationStatusBanner`（または検索画面上）に「現在地を再取得」ボタン（小さいアイコンボタン程度）を追加する。
   - `LocationLoaded`・`LocationFailed`のどちらの状態でも押下可能とし、押下すると`fetchCurrentLocation()`相当の処理を呼び出し状態を`LocationLoading`に戻す。
   - 既存の`LocationFailed`時の「再試行」ボタンと機能的に近いため、UI上は1つのボタン（`onRefetch`コールバック）に統合する（`permissionDeniedForever`時の「設定を開く」ボタンのみ別動作として維持）。
   - 3.1節・3.2節・4章参照。

### 未決定のまま残る事項

5. **`accuracy`（取得精度）の扱い**: `geolocator`の`Position`は精度（メートル単位）も取得できるが、本設計では未使用としている。今後、著しく精度が低い場合にユーザーへ注意喚起するか等は要件化されていないため対象外とした（現状維持、変更なし）。
6. **iOS対応時の`AppleSettings`検討**: `geolocator`はiOS向けに`AppleSettings`（`activityType`等のiOS固有オプション）を提供している。本Issueでは5章の通りAndroidのみを対象とするため未設計だが、iOS対応着手時には`LocationSettings`の生成箇所（3.4節`LocationRepository.getCurrentLocation()`）でプラットフォーム分岐が必要になる可能性がある点を留意事項として残す。
7. **`docs/architecture.md`の「LocationProvider」という呼称との対応関係**: `docs/architecture.md` 1章の構成図では機能を指して「LocationProvider」という名称が使われているが、本設計書では実装クラスとして`LocationRepository`（データ層）・`currentLocationProvider`（Riverpod Provider）に分割して設計している。architecture.mdの「LocationProvider」はレイヤー構成上の概念的な呼称（＝「位置情報を提供する機能一式」の意）であり、本設計書の`LocationRepository`＋`currentLocationProvider`の組み合わせがそれに相当する、という対応関係を確認事項として明記しておく（実装時にクラス名の揺れが生じないようにするため）。
