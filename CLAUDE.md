# プロジェクト概要
半リアルタイムタクティクスRPG
ゲームタイトル：Rally the Parties

## ジャンル・コンセプト
- 半リアルタイム進行（ターン制なし）。`world_time_running` フラグで AI タイマーを制御
  - プレイヤー行動中（移動・攻撃前後）：時間進行（AI・タイマーが動く）
  - プレイヤー待機中・ターゲット選択中・アイテムUI中：時間停止（AI・タイマーが止まる）
- 2Dグリッドマップ（将来的に自由移動へ拡張予定、次バージョン以降）
- 視点：トップビュー（キャラ画像1枚・GRID_SIZEサイズ・rotationで方向対応）

## キャラクター・パーティーシステム
- 主人公1人からスタートし、ダンジョン内でNPCと出会い仲間に加入
- プレイヤーは主人公または仲間の誰かを選んで直接操作
- 操作切替時：旧キャラはAIに切替、新キャラをプレイヤーが操作
- 非操作キャラはAIが自動行動
- 1パーティー構成（将来：複数パーティー連携を想定、設計は今から考慮）

## 仲間への指示システム
- 攻撃：近くの敵を積極的に攻撃
- 防衛：その場を守る・反撃中心
- 待機：動かない
- 追従：操作キャラのそばにいる
- 撤退：安全な場所に下がる

## 技術スタック
- エンジン：Godot 4.x
- 言語：GDScript
- 配布先：Steam（将来）

## アセット方針
- キャラクター画像：AI生成（プロトタイプは仮素材・差し替え前提）
- 配布前に商用利用可能な素材に差し替える
- 装備差分はSAM2で抽出、Godotでレイヤー合成（将来実装）
- 画風統一：イラスト調（アニメとリアルの中間）、ダークファンタジー寄り

### 画像フォーマット（Phase 6-0〜）
```
assets/images/characters/
  {class}_{sex}_{age}_{build}_{id}/
    top.png      (1024x1024, フィールド表示用・rotationで方向対応)
    walk1.png    (1024x1024, 歩行パターン1・左足を出した状態)
    walk2.png    (1024x1024, 歩行パターン2・右足を出した状態)
    ready.png    (1024x1024, 構えポーズ・ターゲット選択中・攻撃モーション中)
    guard.png    (1024x1024, ガード姿勢・X/Bホールド中。なければready.png→top.pngにフォールバック)
    front.png    (1024x1024, 全身正面・UI表示用)
    face.png     (256x256, frontから顔切り出し・左パネル表示用)

assets/images/enemies/
  {enemy_type}_{sex}_{age}_{build}_{id}/
    top.png / walk1.png / walk2.png / ready.png / front.png / face.png  （味方と同じ構成・walk1/walk2/guard.pngは省略可）
```
- 味方: class = fighter-sword, fighter-axe, archer, magician-fire, magician-water, healer, scout
  - ヒーラーは白系・魔法使い(水)は青〜水色系の画風（magician-fireの赤系・healerの白系と区別）
- 敵: enemy_type = goblin, goblin-archer, goblin-mage, hobgoblin, dark-knight, dark-mage, dark-priest, wolf, zombie, harpy, salamander, skeleton, skeleton-archer, lich, demon, dark-lord 等
- sex: male, female
- age: young, adult, elder
- build: slim, medium, muscular
- id: 01〜99
- view名にアンダーバー不使用
- 歩行アニメ: `walk1 → top → walk2 → top` の4枚ループ。walk1/walk2がない場合はtop固定（フォールバック）
- 攻撃アニメーション（attack1.png / attack2.png）は将来実装。当面は攻撃モーション中も ready → top の切り替えのまま
- 画像がない敵はJSONのフラットパス指定またはプレースホルダー色にフォールバック

### タイル画像フォーマット
```
assets/images/tiles/
  {category}_{id}/
    floor.png      (部屋の床タイル)
    wall.png       (壁タイル)
    obstacle.png   (障害物タイル。カテゴリに応じて瓦礫・溶岩溜まり等)
    corridor.png   (通路タイル。省略時はfloor.pngにフォールバック)
```
- category: stone, dirt, lava 等（当面は stone のみ）
- id: 5桁ゼロ埋め（00001〜99999）
- ダンジョンデータのフロアごとに tile_set を指定（未指定時は "stone_00001"）
- 旧 RUBBLE → OBSTACLE にリネーム（タイル種別定数・コメント等）
- 高解像度画像（1024x1024）は左上1/4を切り出して1セルに表示（_crop_single_tile）

## 使用アセットとライセンス
| アセット | 用途 | ライセンス | 帰属表示 |
|---------|------|-----------|---------|
| Kenney Particle Pack | ヒットエフェクト（hit_01〜06.png） | CC0（パブリックドメイン） | 不要 |
| Kenney RPG Audio | slash / axe / dagger / arrow_shoot / room_enter / item_get | CC0（パブリックドメイン） | 不要 |
| Kenney Impact Sounds | hit_physical / hit_magic / take_damage / stairs | CC0（パブリックドメイン） | 不要 |
| Kenney Sci-fi Sounds | magic_shoot / flame_shoot / death | CC0（パブリックドメイン） | 不要 |
| Kenney Interface Sounds | heal | CC0（パブリックドメイン） | 不要 |

## 画像生成フロー
- 正面画像：Nano Banana（プロンプトテンプレートは work/prompt_template.md に保存）
- トップビュー変換：QIE（Qwen Image Edit）+ LoRA
- 背景除去：RemBG
- 将来の装備差分：SAM2で領域抽出 → Godotでレイヤー合成

## ファイル構成
- assets/master/characters/：味方キャラクターのマスターデータ（JSON）
- assets/master/enemies/：敵キャラクターのマスターデータ（JSON、種類ごとにファイルを分ける）
- assets/master/enemies/enemies_list.json：読み込む敵ファイルのリスト
- assets/master/maps/：マップデータ（JSON、マップごとにファイルを分ける）
- assets/master/names.json：名前ストック（性別ごと）
- assets/images/characters/：味方キャラクターの画像（{class}_{sex}_{age}_{build}_{id}/ フォルダ構成）
- assets/images/enemies/：敵キャラクターの画像
- assets/images/items/：アイテム画像（potion_hp.png, potion_mp.png 等）
- assets/images/projectiles/：飛翔体画像（arrow.png, fire_bullet.png 等）
- JSONに画像ファイルパスを含めて一元管理
- work/：作業用ファイル置き場（コードから参照しない。AI生成の元画像・参考資料など）
- ※ work/ 配下はGodotのインポート対象外。フォルダ構成は自由に変更してよい

## マップデータ仕様
- タイルデータ（壁・床）、プレイヤーパーティー初期配置、敵パーティー初期配置をひとまとめに管理
- プレイヤー・敵ともにパーティー単位で配置情報を記述（将来の複数パーティー対応を考慮）
- マップにIDを付与して複数用意し、プレイヤーがゲーム開始時に選択できる形にする（将来実装）
- 同じマップを繰り返しプレイ可能（敵配置・装備補正値は固定）
- 将来：マップごとのクリア率・クリア時間などの統計を記録
```json
{
  "map_id": "dungeon_01",
  "width": 20,
  "height": 15,
  "tiles": [...],
  "player_parties": [
    {
      "party_id": 1,
      "members": [
        { "character_id": "hero", "x": 2, "y": 2 }
      ]
    }
  ],
  "enemy_parties": [
    {
      "party_id": 1,
      "members": [
        { "enemy_id": "goblin", "x": 10, "y": 5 },
        { "enemy_id": "goblin", "x": 11, "y": 5 },
        { "enemy_id": "goblin", "x": 10, "y": 6 }
      ]
    }
  ]
}
```

## グリッド・表示設定
- GRID_SIZEを定数で一元管理（GlobalConstants.gd / Autoload）
- 起動時に画面サイズから動的計算：`GRID_SIZE = viewport_height / TILES_VERTICAL`
- TILES_VERTICAL = 11（縦11タイル固定）→ 1920x1080時に約98px
- キャラクター表示サイズ：GRID_SIZE x GRID_SIZE（正方形。トップビュー用）
- ウィンドウサイズ：1920x1080（project.godot で設定）
- ウィンドウ設定：ボーダーレス（開発中はウィンドウモード、配布時にフルスクリーン予定）

## アニメーション仕様
- 判定・座標管理：グリッド単位（マス）で行う。衝突判定・攻撃当たり判定もすべてグリッド座標
- 表示：tween補間なし。1マス移動する間に `walk1 → top → walk2 → top` の4枚を順番に切り替えて表示
- 移動中のみアニメーション再生、静止中は top に戻る
- 攻撃アニメ：当面は ready（振り上げ）→ top（振り下ろし）の切り替え。将来 attack1/attack2 に差し替え予定

## キー操作・ゲームパッド対応（開発中）

基準：Xbox系コントローラー（Steam標準）。デバッグ機能（F1/F5など）はキーボードのみ。

### フィールド操作

| 操作 | キーボード | ゲームパッド | 備考 |
|------|-----------|-------------|------|
| 移動 | 矢印キー | 左スティック or 十字キー | |
| 攻撃（短押し：Z/A → PRE_DELAY → TARGETING → Z/A 確定） | Z | A | クラスの攻撃タイプで近接/遠距離を自動切替。ターゲット選択中は時間停止 |
| ガード（ホールド） | X | B | ホールド中ガード姿勢。正面攻撃のブロック量3倍・移動速度50%・向き固定 |
| アイテム選択UI（短押し） | C | X | 所持アイテム一覧を開く（使用/装備/渡す）。UI中は時間停止 |
| 特殊攻撃 | V | Y | Vスロット特殊攻撃（Phase 12-4で全クラス実装済み） |
| キャラクター切り替え | 未定 | LB / RB | パーティーメンバーを表示順で循環切り替え（通常時・パーティーリーダーが主人公のときのみ有効） |
| アイテムUI中のカーソル移動 | 矢印キー | LB / RB | アイテムUI中のみ有効（LBで前、RBで次） |
| ターゲット循環（TARGETING中） | 矢印キー | LB / RB | ターゲット選択中のみ有効 |
| 指示／ステータスウィンドウ | Tab | Select / Back | |
| ポーズメニュー開閉 | Esc | Start | |
| AIデバッグパネル ON/OFF | F1 | — | |
| デバッグ情報コンソール出力 | F2 | — | キャラ・フロア・占有タイル情報を user://debug_floor_info.txt に書き出し |
| シーン再スタート | F5 | — | |

### メニュー内共通操作

OrderWindow・サブメニュー・アイテム一覧・アクションメニュー・相手選択で共通。

| 操作 | キーボード | ゲームパッド |
|------|-----------|-------------|
| 項目選択 | 上下キー | 上下キー / 左スティック |
| 決定 | Z または 右キー | A または 右キー |
| 戻る | X または 左キー | B または 左キー |

- 全階層で左右キーが使える（右=決定、左=戻る）
- OrderWindowトップレベルで「戻る」を押すとウィンドウを閉じる（Tab/Selectと同じ）
- テーブル内の指示値切替（移動/隊形/戦闘/ターゲット/低HP/アイテム取得の各列）は左右キーで値を切替。「決定/戻る」は名前列・全体方針行・ログ行でのみ適用

### 指示／ステータスウィンドウ（OrderWindow）
- 専用ボタンでいつでも開閉可能（ポーズなし・時間進行継続）
- リーダー操作中：指示の変更可。非リーダー操作中：閲覧のみ（変更不可）
- テーブルの列構成：名前 / 移動 / 隊形 / 戦闘 / ターゲット / 低HP / アイテム取得
- 名前列で Z を押すとサブメニュー表示：操作切替 / アイテム
  - 操作切替：そのキャラを操作キャラにする（常時有効）
  - アイテム：そのキャラの所持アイテム一覧を表示（未装備品のみ。装備中品はステータス欄で確認）
    - アイテムを選んで Z → アクションメニュー：
      - 装備する：選択キャラのクラスで装備可能な場合のみ表示。上書き時、旧装備は未装備品として手元に残る。誰を操作中でも全メンバー変更可
      - 渡す → 渡す相手をメンバー一覧から選択：リーダー操作中のみ表示
      - スロットに割り当て：消耗品の場合（将来実装。Phase 10-3）
    - アイテムが0件の場合は「アイテムなし」と表示
- ステータス表示を2列化（縦幅を縮小）。素値・最終値の2列
- 最下行に「ログ」行を追加（「閉じる」行は廃止）
  - メンバー行にカーソル → 下部はステータス表示
  - ログ行にカーソル → 下部はメッセージログ表示（最新50件を保持）
  - ログ行で Z → スクロールモード（上下でスクロール、Esc/Z で戻る）
  - ログ閲覧中もゲーム進行はポーズしない
- 開発中は全ステータス項目を表示。配布前に再検討する

## アーキテクチャ方針
- キャラクターにPlayerController / AIControllerを差し替え可能な設計
- Partyクラスを最初から用意し、将来の複数パーティー連携に備える
- 仕様書はClaude Codeが作成・更新、人間が確認する運用

## AIアーキテクチャ（2層構造）

### リーダーAI（パーティー単位）
- パーティー全体の戦略を決定（攻撃/防衛/撤退など）
- 各メンバーに指示を出す（攻撃対象・ポジション・行動方針）
- リーダーのキャラ種やクラスによって戦略傾向が異なる
- 将来的にプレイヤーの指示システム（Phase 7）と同じインターフェースになる

### 個体AI（キャラ単位）
- リーダーの指示を受けて実際の行動を決定
- 従順度パラメータで指示への忠実さが変わる（ゾンビ=低、ゴブリン=中、人間NPC=高）
- BaseAIの既存機能（ステートマシン・A*・キュー管理）をそのまま活用
- クラスやキャラ種に応じた行動（射程維持、逃走条件など）

### パーティーマネージャー
- EnemyManagerの役割を汎用化（敵・NPC・プレイヤーパーティーで共通）
- リーダー管理（初期設定またはリーダー死亡時に再選出）
- パーティー単位の情報共有・再評価通知
- 混成パーティー対応（異なるキャラ種が同じパーティーに混在）

## ゲームデザイン方針
- レベルアップなし。装備と仲間の強化が成長の主軸
- 武器はキャラ職業（クラス）に紐づく（剣士は剣のみなど）
- アイテムはフロア深度に応じた補正値でランダム生成。名前はClaude Codeがダンジョン生成時に作成（詳細は「アイテムシステム」節を参照）
- 敵リポップなし
- アイテム入手：過去の冒険者の装備をモンスターがため込んでいる設定
- ダンジョン攻略は国からの要請、複数パーティーが競争・協力して攻略
- 攻略成功で褒美・名誉が得られる

## クラスシステム

### クラス一覧
| クラス | ファイル名表記 | 武器タイプ | Z/A（攻撃） | 攻撃タイプ | V/Y（特殊攻撃） |
|--------|--------------|-----------|------------|----------|-----------------|
| 剣士 | fighter-sword | 剣 | 近接物理：斬撃 | melee | 突進斬り |
| 斧戦士 | fighter-axe | 斧 | 近接物理：振り下ろし | melee | 振り回し |
| 弓使い | archer | 弓 | 遠距離物理：速射 | ranged | ヘッドショット |
| 魔法使い(火) | magician-fire | 杖 | 遠距離魔法：火弾 | ranged | 炎陣 |
| 魔法使い(水) | magician-water | 杖 | 遠距離魔法：水弾 | ranged | 無力化水魔法 |
| ヒーラー | healer | 杖 | 支援：回復(単体)／アンデッド特効 | heal | 防御バフ(単体) |
| 斥候 | scout | ダガー | 近接物理：刺突 | melee | スライディング |

- 攻撃は Z/A の1ボタン。攻撃タイプ（melee/ranged）はクラスのスロット定義から自動判定
- スロット最大4（ZXCV）、ゲームパッド対応を考慮（X/B はガード）
- ヒーラーは通常の攻撃手段を持たない（支援専用）。ただし is_undead=true の敵はZ攻撃のターゲットに含め、回復量をダメージとして適用（アンデッド特効）
- 将来拡張：魔法使いの属性分化（土・風）、支援系第2ジョブ、槍兵・飛翔系・両手武器系、状態異常回復（毒・麻痺実装後）
- スロット4枠を超えるスキルの管理方法（入替・キャラ別・系統別）は将来決定

### Vスロット特殊攻撃仕様
- **突進斬り（fighter-sword）**：向いている方向に最大2マス前進。経路上の敵全員にダメージ。次の空きマスに着地。壁・障害物で止まる。SP消費
- **振り回し（fighter-axe）**：周囲1マス（斜め含む隣接8マス）の敵全員に通常攻撃相当のダメージ。SP消費
- **ヘッドショット（archer）**：`instant_death_immune == false` の敵に即死。ボス級（`instant_death_immune == true`）には無効で通常の3倍ダメージ。SP消費大
- **炎陣（magician-fire）**：自分を中心に半径3マスに設置。設置直後から2〜3秒間燃え続け複数回ヒット。敵のみ判定（巻き添えは将来課題）。MP消費大
- **無力化水魔法（magician-water）**：単体・射程あり・MP消費大。命中した対象の攻撃・移動を2〜3秒間完全停止（回転エフェクト）。全種族共通。被弾時ダメージは受けるが持続時間は変わらない。ボス級には持続時間を短縮（将来調整）
- **防御バフ（healer）**：単体・射程あり・MP消費（`buff_defense` アクション）。バフ中は半透明の緑色六角形バリアエフェクト（`BuffEffect.gd`）がキャラクターに重ねて表示される。バフ終了時に自動削除。重複付与時はタイマーリセット＋エフェクト再生成
- **スライディング（scout）**：向いている方向に3マス高速移動。移動中は無敵・敵をすり抜け可能。SP消費

### 魔法使い（水）の仕様
- クラスID：`magician-water`
- 武器：杖 / 防具：ローブ / 盾：なし（`magician-fire` と同じ装備構成）
- 画風：青〜水色系（`magician-fire` の赤系・`healer` の白系と区別）
- Z/A：通常水弾（遠距離魔法・ダメージのみ）
- V/Y：無力化水魔法（上記Vスロット仕様参照）

## キャラクター生成システム

- プレイヤー（主人公）含め全キャラクターがランダム生成
- グラフィック（画像セット）をあらかじめ複数用意。各セットに性別・年齢・体格・対応クラスが紐づく
- ゲーム開始時にグラフィックからランダム選出
- 名前は性別ごとのストック（assets/master/names.json）からランダム割り当て。グラフィックとは独立
- ランク（A/B/C）はグラフィックとは無関係にランダム割り当て（人間キャラクターは A 上限。S はダークロード等のボス専用）
- 当面は同一人種の人間のみ

### ステータス決定構造
```
最終値 = class_base + rank × class_rank_bonus + sex_bonus + age_bonus + build_bonus + randi() % (random_max + 1)
rank値: C=0, B=1, A=2, S=3
小数を含む場合は加算後に roundi() で整数化
```

- すべての数値ステータス（vitality・energy・power・skill・physical_resistance・magic_resistance・defense_accuracy）は **0〜100 の範囲**に収まるよう設定
- 数値は設定ファイルで管理（`character_generator.gd` の `CLASS_STAT_BASES` 定数は廃止済み）

### ステータス設定ファイル
- **`assets/master/stats/class_stats.json`**：クラスごとの base（ランクC時の基本値）と rank（1段階ごとの加算値）を定義
  - 対象ステータス: vitality / energy / power / skill / defense_accuracy / physical_resistance / magic_resistance / move_speed / leadership / obedience
- **`assets/master/stats/attribute_stats.json`**：性別・年齢・体格の補正値と各ステータスの random_max（0〜N の乱数幅）を定義
- `CharacterGenerator._load_stat_configs()` が初回 `_calc_stats()` 呼び出し時にロードして静的キャッシュに保持

### vitality / energy の格納先
- `vitality`（0-100）→ `character_data.max_hp`（`hp` はゲーム開始時に `max_hp` で初期化）
- `energy`（0-100）→ 魔法クラス（magician-fire / magician-water / healer）は `max_mp`、非魔法クラスは `max_sp` に格納（`mp` / `sp` はゲーム開始時に上限値で初期化）
- クラスJSON（`assets/master/classes/*.json`）の `"mp"` / `"max_sp"` フィールドは廃止（energy で代替）

### move_speed の変換
- 0〜100 スコアで生成し `_convert_move_speed(score)` で秒/タイルに変換して `character_data.move_speed` に格納
- 変換式: `seconds = max(0.1, 0.8 - score × 0.006)`（要調整）
  - score=0 → 0.80s/タイル（最遅）、score=50 → 0.50s/タイル、score=100 → 0.20s/タイル

### obedience の変換
- 0〜100 の整数スコアで生成し `/ 100.0` で 0.0〜1.0 に変換して格納

| 要素 | 設定方法 | 方向性 |
|------|---------|--------|
| ランク（S〜C） | class_stats.json の rank × rank値（C=0, S=3） | クラスごとに rank 補正量を設定 |
| 性別（sex_bonus） | attribute_stats.json の sex セクション | 男性=威力・物理耐性高め、女性=技量・魔法耐性・統率力高め |
| 年齢（age_bonus） | attribute_stats.json の age セクション | 若年=威力・移動速度高め、壮年=バランス、老年=技量・魔法耐性高め |
| 体格（build_bonus） | attribute_stats.json の build セクション | 筋肉質=威力・物理耐性高め、細身=技量高め |
| ランダム（random_max） | attribute_stats.json の random_max セクション | ステータスごとに乱数幅を設定（0〜N） |

## NPC仕様

- ダンジョン内にNPCがパーティー単位で配置される
- 単独NPCも、スタート時から複数人でパーティーを組んでいるNPCもいる
- 行動生成は敵と同様にパーティー単位
- NPCは仲間に加入できる（加入の仕組みはPhase 6-2で実装予定）
- 加入形態は2種類：プレイヤーがリーダー維持で相手を引き入れる／相手パーティーのリーダーに自分が加わる

## ドキュメント運用
- CLAUDE.md：人間・AI共通の概要・方針・フェーズ進捗。ここでの相談をもとに更新する
- docs/spec.md：AI管理用の詳細仕様・実装メモ。Claude Codeが作成・更新する

## ツール運用
- claude.ai（チャット）：仕様の相談・設計の議論を行う。コードの実装・ファイルの編集は行わない
- Claude Code：CLAUDE.mdの更新・仕様書（docs/spec.md）の更新・GDScriptの実装・コミット/プッシュを行う
- 仕様相談はclaude.aiで行い、確定した仕様をもとに Claude Code が CLAUDE.md を更新してから実装する

## フェーズ
- [x] Phase 1: 主人公1人の移動・画像表示・フィールド表示
  - [x] Phase 1-1: キャラクター基盤（移動入力・グリッド座標管理）
  - [x] Phase 1-2: グラフィック表示（スプライト・4方向切替）
    - 1キャラクター4枚（前・後・左・右）、512x1024px
    - ファイル名規則：`キャラ名_front.png` など
    - 移動方向に応じて画像切替、静止中は最後の向きを維持
    - 向き管理：enum Direction {DOWN, UP, LEFT, RIGHT}（トップビュー基準：DOWN=画面下、UP=画面上）
    - GRID_SIZEを定数管理、表示スケールを自動計算
  - [x] Phase 1-3: フィールド・マップ基盤（タイルマップ・Zオーダー）
    - タイル種類：FLOOR（床）/ WALL（壁）の2種類
    - タイルサイズ：GRID_SIZE（64px）の正方形
    - マップサイズ：20x15タイル
    - マップ構造：外周がWALL、内側がすべてFLOORの四角い部屋
    - マップデータ：0=FLOOR、1=WALLの2次元配列で管理
    - グラフィック：当面は単色（床=グレー、壁=暗いグレー）、将来タイル画像に差し替え可能な設計
    - キャラクターはWALLタイルに移動不可
    - キャラクターのZオーダー：タイルより手前に表示
  - [x] Phase 1-4: カメラ・スクロール（追従・範囲制限）
    - カメラはデッドゾーン方式（画面の40%）
    - デッドゾーン内はカメラ固定、超えたらブロック単位でカメラ移動
    - なめらかスクロールはアニメーション実装時に追加予定
    - マップ外（壁の外側）は黒で表示
    - カメラはマップ端で止める（実装上の処理として）
    - 視界システム・探索状態管理は将来のフェーズで追加予定
  - [x] Phase 1-5: 統合・動作確認
- [x] Phase 2: 戦闘基盤（HP・攻撃・当たり判定）
  - テスト構成：味方はプレイヤー操作の主人公1人、敵はゴブリン3体（同一パーティー）
  - 敵・味方のパーティークラス共通化は検証後に判断
  - クリア条件は未実装（動作確認のみ）
  - [x] Phase 2-1: キャラクターステータス基盤
    - HP・攻撃力・防御力などの基本パラメータ
    - キャラクターデータに自然言語の行動説明フィールドを追加
    - 死亡処理
  - [x] Phase 2-2: 敵の配置
    - マップデータ（dungeon_01.json）からタイル・プレイヤー・敵の配置を読み込む
    - 敵パーティーをパーティー単位で配置（将来の複数パーティー対応を考慮）
    - enemy_parties の各パーティーごとに別々の EnemyManager を生成（複数パーティー対応）
    - プレイヤーが近づいたらアクティブ化
  - [x] Phase 2-3: ルールベースAI行動生成（LLMから変更）
    - BaseAI（基底クラス）：ステートマシン・A*経路探索・キュー管理・定期再評価（1.5秒）
    - GoblinAI（ゴブリン専用）：HP30%未満または仲間50%以下で逃走、それ以外は攻撃
    - 戦略・ターゲットが変わらずキューが十分残っていれば再評価をスキップ
    - 仲間が倒されたときに即座に再評価（notify_situation_changed）
    - LLMClient / DungeonGenerator はコード上残存しているが現在は未使用（将来削除対象）
    - 全パーティー合算の `_all_enemies` を BaseAI が参照し、パーティーをまたいだ敵同士の重複を防止
    - `_find_adjacent_goal` に `_is_passable` による占有チェックを追加、A* のゴールタイル特例廃止により同一パーティー内の敵重複も解消
  - [x] Phase 2-4: 移動・攻撃の実装
    - 敵の移動：A*経路探索で0.4秒/タイルで移動（ターゲット追従・毎タイル再計算）
    - 占有チェック：Character.get_occupied_tiles() で抽象化（複数マスキャラ対応済み）
    - 敵の攻撃：ATTACKING_PRE（溜め）→ 攻撃実行 → ATTACKING_POST（硬直）
    - プレイヤーの攻撃：スペースキーで向いている方向の隣接敵を攻撃
    - 方向ダメージ倍率：正面1.0 / 側面1.5 / 背面2.0
    - ステータスHUD：画面左上にプレイヤー・各敵のHP・状態をリアルタイム表示
- [x] Phase 3: フィールド生成
  - ダンジョン構造
    - 現在3フロア生成（トークン制限のため。将来的に増加予定）
    - 1フロアに5部屋程度、部屋サイズ：幅10〜20、高さ10〜20タイル
    - 部屋は通路でつながり、フロア内で分岐あり
    - 各部屋に敵パーティーを配置（入口部屋を除く）
    - 現在は1フロア目（CURRENT_FLOOR=0）のみ表示。フロア遷移は Phase 7 以降
  - ダンジョンデータの管理方針（現在の運用）
    - Claude Code が dungeon_handcrafted.json を手作りで作成・管理する（ゲーム内LLM生成は廃止済み）
    - データ形式：`dungeon.floors[]` の配列でフロアを記述
      - 各フロア：`floor`番号・`entrance_room`・`rooms[]`・`corridors[]`・`stairs[]`
      - 各部屋：`id`・`x`・`y`・`width`・`height`・`type`・`enemy_party`・`is_entrance`
      - 通路：`from`・`to`（部屋IDで指定）
      - 階段：`room`（部屋ID）・`direction`（down／up）
    - タイルの実データはDungeonBuilderがGodot側で展開
  - 起動・読み込みの仕組み
    - 起動時は dungeon_handcrafted.json を直接読み込む
    - F5キー：シーンを再スタート（`get_tree().reload_current_scene()`）
    - 読み込み失敗時は dungeon_01.json にフォールバック
  - ※ LLMClient / DungeonGenerator のコードはゲーム内に残存しているが現在は未使用（将来削除対象）
  - 将来の拡張予定
    - フロア数を増やす（フロアを分割して複数回生成する方法を検討。一括生成はトークン上限が課題）
    - 階段の実装（フロア遷移）→ フロア移動が必要になったタイミングで優先実装
    - ステータス表示の改善（現フロアのキャラのみ表示。フロア遷移実装後に対応）
    - 部屋typeにboss・treasureを追加
    - 混成パーティー対応（goblin×3＋hobgoblin×1など）
    - エリア名生成の強化（dungeon_handcrafted.json の JSON 編集で対応）
      - 敵の種類・構成を考慮した部屋名（例：ゴブリンが多い部屋→「ゴブリンの巣窟」）
      - フロアごとにテーマを統一した命名（例：1階：廃墟、2階：地下牢、3階：祭壇）
      - ボス部屋・宝部屋には特別な名前を付ける
      - 通路も雰囲気に合わせた名前を生成（例：「嘆きの回廊」）
- [x] Phase 4: 攻撃バリエーション
  - 攻撃スロット
    - Z/A：攻撃（クラスの attack_type で近接/遠距離を自動切替。短押し：通常攻撃 / 長押し：ため攻撃）
    - X/B：ガード（ホールド中ガード姿勢。正面ブロック3倍・移動速度50%・向き固定）
    - C/X：アイテム使用（Phase 10-3で実装）
    - V/Y：特殊攻撃（将来実装）
  - 攻撃フロー（Phase adae62c で大幅改修済み）
    - Z/A **短押し** → PRE_DELAY（pre_delay 消化・時間進行・ターゲット候補を表示）
    - PRE_DELAY 完了 → TARGETING（ターゲット選択・時間停止）
    - TARGETING 中：矢印キー / LB/RB で循環選択（前方±45° を距離順、次いでそれ以外）
    - Z/A で確定 → 射程チェック → 攻撃実行 → POST_DELAY（硬直・時間進行）
    - X/B でノーコストキャンセル（TARGETING 中のみ）
    - 空振りなし（発動時は必ずヒット）
  - 飛翔体エフェクト
    - 図形（仮素材）で直線飛行、斜め方向対応
    - 速度：2000px/秒（移動での回避不可）
    - 発射時に命中確定（常にヒット）
  - [x] 飛行キャラ対応
    - 近接攻撃：地上→飛行は不可、飛行→地上は可能、飛行同士は不可
    - 遠距離攻撃：双方向で有効
- [x] Phase 5: グラフィック＆UI強化
  - グラフィック
    - [x] トップビューへの変更（キャラ画像1枚・GRID_SIZEサイズ・回転で方向対応）
    - [x] タイル画像の追加（タイルセット方式: {category}_{id}/floor.png 等。なければフォールバック色）
    - [x] OBSTACLEタイル（旧RUBBLE、type=2、地上は歩行不可・飛行は通過可能）
    - [x] CORRIDORタイル追加（type=3、歩行・飛行とも通過可能。DungeonBuilderが通路に使用）
    - [x] モード表示：ターゲット確定=白輝き（Color(1.5,1.5,1.5)）、ヒット=HitEffect（AnimatedSprite2D）
    - [x] ターゲット選択モード：sprite_top_ready に対応（未設定時は sprite_top をそのまま使用）
    - [x] 攻撃モーション中（ATTACKING_PRE/POST）：is_attacking フラグで構え画像に切替（EnemyAI制御）
    - [x] キャラ状態：HP比率で色変化（白→黄→オレンジ→赤点滅）
    - [x] GRID_SIZE動的計算（起動時に縦11タイル固定でGRID_SIZEを決定・1920x1080基準で約98px）
  - 視界システム
    - [x] 部屋単位の視界管理（VisionSystem.gd）
    - [x] 訪問済みエリア管理（パーティー単位・将来の仲間視界共有に対応）
    - [x] 未訪問エリアのタイル・敵は非表示（背景の黒のまま）
    - [x] 一度訪問したエリアはずっと表示（暗くしない）
    - [x] 部屋に入った瞬間に訪問済みに更新・敵アクティブ化
    - [x] 右パネルの敵情報は現在いるエリアのみ表示
  - UI
    - [x] 3カラムレイアウト（左パネル=味方・中央=フィールド・右パネル=敵）
    - [x] 左パネル（LeftPanel.gd）：フェイスアイコン・名前・HPバー・MPバー・状態
      - フェイスアイコンは face.png（なければ front.png）を TextureRect ノードで表示
    - [x] 右パネル（RightPanel.gd）：可視敵の種類・数・ランク（ランク色分け）
    - [x] ~~AIデバッグパネル（RightPanel下半分）~~：Phase 10-2準備で廃止。代わりにMessageWindowのデバッグメッセージ（F1でON/OFF）に移行
    - [x] メッセージウィンドウ（MessageWindow.gd）：フィールド画面下部に5行固定表示。MessageLog（Autoload）で共有バッファ管理。メッセージ種別（system=白/combat=黄/ai=水色）で色分け。F1でデバッグメッセージ（combat/ai）のON/OFF切替。**デバッグモード中（F1 ON）はエリア外（他部屋・他フロア）の戦闘ログもエリアフィルターを無視して表示**（通常時は非表示のまま）
    - [x] エリア名表示（AreaNameDisplay.gd）：エリア入室時にフィールド上部中央にエリア名を常時表示（名前なしエリアは非表示）
- [ ] Phase 6: 仲間AI・操作切替
  - [x] Phase 6-0: 準備（クラス・ステータス・グラフィック仕様の反映＋AIリファクタリング）
    - [x] AIアーキテクチャをリーダーAI＋個体AIの2層構造にリファクタリング
      - BaseAI/GoblinAI → PartyLeaderAI + UnitAI に再編
      - EnemyManager → PartyManager に汎用化
      - 既存ゴブリン3体の動作を維持しながら段階的に移行
    - [x] クラスシステム・キャラクター生成・NPC仕様をコードに反映
      - assets/master/classes/{class_id}.json（6クラス）作成
      - CharacterGenerator.gd 実装（グラフィックセット走査・ステータス計算・名前生成）
      - CharacterData に class_id / image_set / sprite_face / sex / age / build フィールド追加
    - [x] 画像フォルダ構成を新フォーマットに移行（味方20セット・敵22セット配置済み）
      - CharacterGenerator に scan_enemy_graphic_sets() / apply_enemy_graphics() を追加
      - PartyManager._spawn_member() が apply_enemy_graphics() を呼び出し、敵に画像を自動割り当て
      - 敵フォルダのパース: "_male_" / "_female_" 境界で enemy_type を検出（"-" を含む型名に対応）
    - [x] names.json作成（男性・女性それぞれ20名）
    - [x] 敵ランクをS/A/B/Cの4段階に統一
  - [x] Phase 6-1: 仲間NPCの配置と基本AI行動
    - [x] 手作りダンジョン（dungeon_handcrafted.json）の仕組みを導入
      - 起動時は dungeon_handcrafted.json を直接読み込む
    - [x] MapData に npc_parties フィールド追加
    - [x] DungeonBuilder が npc_party を rooms から収集
    - [x] NpcManager.gd：CharacterGenerator でランダム生成・is_friendly=true・緑プレースホルダー
    - [x] NpcLeaderAI.gd：敵リストから最近傍をターゲット。生存敵あり→ATTACK、なし→WAIT
    - [x] NpcUnitAI.gd：従順度1.0・A*経路探索
    - [x] Character.is_friendly フラグ追加（プレースホルダー色を緑に設定）
    - [x] Character.party_color / is_leader フラグ追加（パーティーカラーリング・リーダー二重リングで所属表示）
    - [x] NpcManager.set_party_color()：NPC パーティーに色を割り当て、合流時に白リングに統一
    - [x] PartyManager.activate()：VisionSystem 経由ではなく直接 AI を起動するパブリックメソッド
    - [x] VisionSystem：add_npc_manager() 追加・NPC の表示制御・AI アクティブ化
    - [x] game_map：_setup_npcs()・handcrafted読み込み・visionへのNPC登録
    - [x] game_map：_link_all_character_lists() 追加・敵＋NPC 合算リストを全マネージャーに配布（NPC-敵重複防止）
    - [x] player_controller.blocking_characters に NPC メンバーを追加（プレイヤー-NPC 重複防止）
    - [x] party_manager.gd：ノード名衝突修正（マネージャー名をプレフィックスに追加）
    - [x] unit_ai.gd：freed オブジェクトキャストクラッシュ修正（is_instance_valid チェック追加）
    - [x] dungeon_handcrafted.json：入口部屋（R01）に player_party を追加（fighter-sword / archer / healer の 3 人スタート）
    - [x] game_map._setup_initial_allies()：初期パーティーの追加メンバーを NpcManager 経由でスポーン → activate() で即時 AI 起動 → 合流処理
  - [x] Phase 6-2: 仲間の加入の仕組み
    - [x] DialogueTrigger.gd：隣接チェック・エリア敵全滅チェック・NPC自発申し出検出
    - [x] DialogueTrigger.gd：NPC 自発申し出は無効（`wants_to_initiate()` は常に false）。プレイヤー起点の A ボタン隣接検出経由のみ（Phase 12-14 でバンプ方式から変更）
    - [x] DialogueTrigger.try_trigger_for_member()：プレイヤー起点会話用の直接トリガーメソッド
    - [x] PlayerController.gd：npc_bumped シグナル追加（A ボタン押下時に隣接 NPC を検索して発火）
    - [x] PlayerController.gd：healed_npc_member シグナル追加（ヒーラーが未加入 NPC を回復したときに発火）
    - [x] game_map._on_npc_bumped()：npc_bumped を受け取り DialogueTrigger.try_trigger_for_member() を呼ぶ
    - [x] game_map._on_npc_healed()：healed_npc_member を受け取り対象 NpcManager に notify_healed() を呼ぶ
    - [x] game_map._check_fought_together()：Character.dealt_damage_to / took_damage_from シグナルのイベント駆動で呼ばれる。NPC がプレイヤーと同フロア・同エリアで敵と戦闘したとき has_fought_together をセット（旧：_update_fought_together_flags() ポーリング方式から変更）
    - [x] ~~DialogueWindow.gd~~：会話UIはMessageWindowに統合済み（Phase 10-2準備で移行）
    - [x] NpcLeaderAI：will_accept() をスコア比較方式に刷新。has_fought_together / has_been_healed フラグ・定数を追加
    - [x] NpcLeaderAI：will_accept() に適正フロア足切り条件を追加（current_floor < _get_target_floor() なら即拒否）。適正フロア算出ロジックを _get_target_floor() に切り出し、_get_explore_move_policy() と共通化
    - [x] player_controller.gd：is_blocked フラグ追加（会話中は移動・攻撃入力を無効化）
    - [x] vision_system.gd：remove_npc_manager() 追加
    - [x] game_map.gd：_setup_dialogue_system() / 合流処理 / 敵入室による会話中断
    - [x] game_map.gd：会話中は対象 NpcManager の process_mode を DISABLED に設定（NPC 停止）
    - [x] player_controller.gd：_get_valid_targets() で is_friendly チェック追加（合流後の仲間を攻撃対象から除外）
    - [x] ~~dialogue_window.gd~~：MessageWindowに統合済み（選択肢をインライン表示）
    - 会話トリガー条件（`try_trigger_for_member()` 内で判定）
      - プレイヤーと NPC メンバーが隣接（マンハッタン距離1）
      - 通路（エリアIDなし）では会話しない（is_area_enemy_free が false を返すため）
      - プレイヤー起点：A ボタン押下時に隣接 NPC を検索して発火（Phase 12-14 で矢印キーバンプ方式から変更）
      - NPC 自発：現在は無効（`wants_to_initiate()` が常に false を返す）
    - 会話トリガー失敗時のメッセージ（`DialogueTrigger.dialogue_blocked` シグナル → `game_map._on_dialogue_blocked()`）
      - 話しかけたメンバーのエリアに敵がいる → 「○○は戦いに集中している」（MessageLog システムメッセージ）
      - 同パーティーの別メンバーが戦闘中エリアにいる → 「○○の仲間が戦闘中のため話せない」（MessageLog システムメッセージ）
    - 会話UI（NpcDialogueWindow）
      - 画面中央に半透明パネル。NPC メンバーの顔画像・名前・クラス名＋ランクを表示
      - プレイヤー起点の選択肢：「仲間にする」（→確認ダイアログ）・「一緒に行く」・「キャンセル」の3択
      - 「仲間にする」→ CONFIRM 状態で「本当に仲間にしますか？（はい/いいえ）」
      - 承諾判定（join_us のみ）：スコア比較方式。join_them は常に承諾
        - プレイヤー側スコア = リーダーの統率力 + パーティーランク和×10 + 共闘ボーナス(5) + 回復ボーナス(5)
        - NPC 側スコア = (100 - 従順度平均×100) + NPCランク和×10
        - ランク数値: C=3, B=4, A=5, S=6
      - 結果（合流・拒否・中断）は MessageLog に記録
    - 合流処理
      - 合流メンバーを party に追加・常時表示
      - VisionSystem・npc_managers から除外（再会話防止）
      - 「仲間にする」: hero がリーダー維持。`_merge_npc_into_player_party()` で NPC 全員を追加
      - 「一緒に行く」: NPC リーダーが party リーダー。`_merge_player_into_npc_party()` で既存メンバーの is_leader を false に。hero は引き続き操作キャラ（ハイライト変わらず）。nm.set_joined_to_player(true) で NPC メンバーが hero を追従
    - 会話中断：敵が部屋に入ってきたら game_map._process() が検出して即中断
  - [x] Phase 6-3: 操作キャラの切替
    - 指示ウィンドウ内の「操作」列でパーティーメンバーへの操作切替
    - 切替先キャラのフィールドにカメラを即座に移動
    - 旧操作キャラは AI 制御（UnitAI）に戻る（is_player_controlled フラグで制御）
    - Character.is_player_controlled フラグ追加：UnitAI._process でチェックして処理スキップ
    - Character.join_index 追加：Party.add_member() が付与し、表示ソートに使用
    - Party.sorted_members()：リーダー先頭＋加入順で並べた表示用リストを返す
    - 左パネル・指示ウィンドウとも sorted_members() で表示順を統一（リーダー固定）
    - 操作中のキャラは左パネルで青ハイライト、指示ウィンドウで緑「[操作中]」表示
    - リーダーは変わらない（指示ウィンドウは Tab でいつでも開閉可。非リーダー操作中は閲覧のみ）
- [x] Phase 7: 指示システム（刷新済み）
  - Tab キーで指示ウィンドウ開閉（いつでも開閉可。非リーダー操作中は閲覧のみ）
  - 指示データ構造（Character.current_order: Dictionary）
    - move:             explore=探索 / same_room=同室追従 / cluster=密集 / guard_room=部屋を守る / standby=待機
    - battle_formation: surround=包囲 / front=前衛 / rear=後衛 / same_as_leader=リーダーと同じ
    - combat:           aggressive=積極攻撃 / support=援護 / standby=待機
    - target:           nearest=最近傍 / weakest=最弱 / same_as_leader=リーダーと同じ
    - on_low_hp:        keep_fighting=戦い続ける / retreat=後退 / flee=逃走
    - item_pickup:      aggressive=積極取得 / passive=経路上なら取得 / avoid=全アイテムを避ける
  - item_pickup の詳細
    - aggressive: 周囲に敵がいなければ積極的に拾いに行く。対象は「自クラスで装備可能な武器・防具・盾」「HPポーション（全クラス）」「MPポーション（魔法使い・ヒーラーのみ）」に限定。それ以外は passive 扱い（経路上なら拾う）
    - passive: 移動経路上にあれば拾う（寄り道しない）。フィルタなし
    - avoid: 全アイテムを避ける（拾わない。アイテムのあるマスを避けて移動）
  - 全体方針プリセット（6種）→ 6項目を一括設定
    - 攻撃: cluster / surround / aggressive / nearest / keep_fighting / aggressive
    - 防衛: cluster / surround / support / same_as_leader / retreat / passive
    - 待機: cluster / surround / standby / nearest / retreat / avoid
    - 追従: cluster / surround / support / same_as_leader / retreat / passive
    - 撤退: cluster / surround / standby / nearest / flee / avoid
    - 探索: explore(リーダー)・same_room(他) / surround / aggressive / nearest / retreat / aggressive
  - 指示ウィンドウ（OrderWindow）
    - 全体方針行: ←→ でプリセット選択、Z で全メンバーに一括適用
    - メンバーテーブル: ↑↓ で行移動、←→ で列移動、Z で値を切替
    - 左パネルに6項目略称を2行で常時表示（行1: 移動+戦闘+標的 / 行2: 隊形+低HP+取得）
  - UnitAI への反映
    - combat=aggressive → Strategy.ATTACK（積極的に追従・攻撃）
    - combat=support/standby → Strategy.WAIT（待機、隊形維持）
    - on_low_hp=flee かつ HP50%未満 → Strategy.FLEE（逃走優先）
    - on_low_hp=retreat かつ HP50%未満 → Strategy.WAIT + move=cluster（リーダー周辺に退避）
    - パーティーレベルの FLEE（GoblinLeaderAI 等）は常に最優先
    - move: 隊形制約を満たしていなければ move_to_formation / move_to_explore でリーダーへ移動
      - explore: VisionSystem で未訪問エリアを検出して移動（全訪問済みならランダム巡回）
      - same_room: MapData.get_area() でリーダーと同じ部屋IDを維持
      - cluster: マンハッタン距離5以内を維持
      - guard_room: 初回設定時の部屋を記憶して守る
      - standby: その場待機（隣接の敵のみ攻撃）
    - battle_formation=rear: A*で背後に回り込む（ASTAR_FLANK）
    - target=same_as_leader: リーダーと同じターゲットを攻撃
  - 統率力・従順度パラメータを CharacterData に追加（当面は値のみ保持）
  - 操作キャラ切替（Phase 6-3）との連携済み：切替後の新操作キャラには current_order が適用される
  - hero 自律行動対応：`_hero_manager`（NpcManager）を game_map で生成し、操作外れ時に UnitAI が current_order を反映して動作する
- [x] Phase 8 Step 1: 未実装行動の追加
  - 飛行移動：飛行キャラ（is_flying=true）は WALL・OBSTACLE・地上キャラ占有タイルを通過可能
  - 攻撃タイプ（melee / ranged / dive）を CharacterData に追加し UnitAI が参照
    - melee: 地上のみ隣接攻撃（飛行→地上OK、地上→飛行NG、飛行→飛行NG）
    - ranged: 射程内の全対象を飛翔体で攻撃（飛行レイヤー無関係）
    - dive: 飛行キャラが地上の隣接対象に降下攻撃（方向倍率なし・DiveEffect表示）
    - カウンター有効：melee・dive　カウンター無効：ranged（カウンター自体は将来実装）
  - MP フィールド追加（character_data.max_mp / character.mp）
  - 回復行動（ヒーラー・ダークプリースト）：HP50%以下の味方を優先して回復、MP消費
  - バフ行動（ダークプリースト）：バフが切れた味方に防御力アップを付与、MP消費
  - harpy.json / dark_priest.json 作成、enemies_list.json に追加
- [x] Phase 8 Step 2+3: 種族別AIルーチンの追加・ダンジョン生成への組み込み
  - UnitAI に `_get_move_interval()`・`_on_after_attack()` 仮想メソッド追加（速度変更・MP消費フック）
  - 種族別 LeaderAI: HobgoblinLeaderAI（混成パーティー管理）/ WolfLeaderAI（群れ戦術）/ DefaultLeaderAI（汎用）
  - 種族別 UnitAI: HobgoblinUnitAI / GoblinArcherUnitAI / GoblinMageUnitAI / ZombieUnitAI / WolfUnitAI / HarpyUnitAI / SalamanderUnitAI / DarkKnightUnitAI / DarkMageUnitAI / DarkPriestUnitAI
  - 特徴実装: ゾンビ低速2倍・直進経路 / 狼高速1.5倍・側面回り込み / 近距離後退（弓・サラマンダー）/ MP消費（メイジ系）
  - 欠けていたJSONマスターデータ8種作成（hobgoblin / goblin_archer / goblin_mage / zombie / wolf / salamander / dark_knight / dark_mage）
  - enemies_list.json に11種全て追加
  - party_manager._create_leader_ai() ファクトリを11種に対応（match文で正確にルーティング）
  - dungeon_handcrafted.json を11種対応に更新（種族特性・フロア別配置ガイドラインを手作り反映）
  - 旧 dungeon_handcrafted.json 削除（後続バグ修正で再作成・内容を刷新）
- [x] Phase 8 バグ修正
  - party_manager._spawn_member()：enemy_id のハイフンをアンダーバーに変換してJSONファイルを正しく読み込む（例: "goblin-mage" → goblin_mage.json）
  - dark_priest.json：id を "dark_priest" → "dark-priest" に修正（画像フォルダ名 `dark-priest_...` と一致させる）
  - dungeon_handcrafted.json を再作成（現行は12部屋×4フロア＋ボス1部屋の5フロア構成）
    - 起動デフォルト：Claude Code 手作りダンジョン（dungeon_handcrafted.json）を直接読み込む。F5 でシーン再スタート
    - 入口部屋に hero + archer + healer の3人パーティー
    - 敵パーティー：goblin・goblin-archer・wolf・zombie・hobgoblin・goblin-mage・dark-knight・dark-mage・dark-priest・salamander
  - game_map.gd：handcrafted ダンジョン読み込みロジックを復元
- [x] Phase 9: 操作感・表現強化
  - [x] Phase 9-1: 歩行アニメーション・滑らか移動
    - move_to(pos, duration) に持続時間パラメータを追加。視覚位置を _visual_from→_visual_to へ duration 秒かけて線形補間
    - 衝突判定・grid_pos は半マス到達（進捗50%）で更新。移動中は旧位置+移動先の両方を占有タイルとして返す
    - スプライトフレームを補間進捗 t=0→1 で駆動: 0%〜25%=walk1, 25%〜50%=top, 50%〜75%=walk2, 75%〜100%=top
    - walk1/walk2 がない場合は top 固定にフォールバック
    - is_moving() メソッドを追加（_visual_duration > 0 の間 true）
    - GlobalConstants に game_speed: float = 1.0 を追加（将来の設定画面から変更）
    - UnitAI: MOVE_INTERVAL=1.2s（旧0.4s）、WAIT_DURATION=3.0s に変更。_get_move_interval() で game_speed 除算
    - PlayerController: タイマー方式を廃止し先行入力バッファ方式（_move_buffer）に変更
      - アニメーション中は is_moving() で移動をブロック、方向入力をバッファに上書き記録
      - キーを離したらバッファをクリア（ZERO 上書き）→ 1回押しで2マス進む問題を修正
      - アニメーション完了後にバッファ→現在入力の優先順で次移動を実行（長押し連続移動に対応）
      - これにより斜め移動（補間途中から別方向補間）・長押し停止の両問題を解消
    - MOVE_INTERVAL=0.30s（PlayerController 用。game_speed で除算）
    - テスト用: hero.json の sprite を assets/images/characters/test/ フォルダに一時切替済み
    - game_map.gd: character_id=="hero" の場合は CharacterData.create_hero()（hero.json）を使用するよう修正
  - [x] Phase 9-2: ゲームパッド対応
    - Xbox系コントローラー（Steam標準）を基準に InputMap へ並列登録
    - attack (Z) → Joypad Button 0（A）（Phase 10-2 で attack_melee から改名・1ボタン統合）
    - menu_back (X) → Joypad Button 1（B）（メニュー戻る。フィールドでは当面未使用）
    - open_order_window → Joypad Button 4（Back/Select）のみ。キーボード Tab は _input() で KEY_TAB 直接マッチ
    - ポーズメニュー開閉 → キーボード Esc は game_map._input() で KEY_ESCAPE 直接マッチ。Start ボタン（JOY_BUTTON_START）は pause_menu.gd の PROCESS_MODE_ALWAYS _input() でトグル処理
    - 移動（ui_up/down/left/right）は Godot デフォルトで D-pad・左スティック対応済み
    - デバッグ機能（F1/F5）はキーボードのみ
    - game_map.gd: ゲームパッドは _process() で is_action_just_pressed ポーリング、キーボード Tab/Esc は _input() で physical_keycode 直接マッチ
    - 全カスタム描画 Control ノードに focus_mode = FOCUS_NONE を設定（Tab の UI フォーカスナビゲーション干渉を防止）
    - LB（Joypad Button 9）後退サイクルバグ修正：_refresh_targets() がキャンセル状態を毎フレームリセットしていた問題を修正（was_cancel フラグで保持）
  - [x] Phase 9-3: 飛翔体グラフィック
    - 飛翔体画像を assets/images/projectiles/ に配置
      - arrow.png（矢：弓使い・ゴブリンアーチャー・スケルトンアーチャー）
      - fire_bullet.png（火属性魔法弾：魔法使い(火)・ゴブリンメイジ・ダークメイジ・サラマンダー）
      - thunder_bullet.png（雷属性魔法弾：デーモン専用・is_magic=true）
    - 判定ロジック：`attack_type=="ranged"` かつ `is_magic==false → arrow.png`、`is_magic==true → fire_bullet.png`（thunder_bullet はキャラクター固有指定で上書き）
    - 飛行方向に合わせて rotation で回転（下向き正方向の画像を `-PI/2` オフセットで補正）。軌道は直線
    - ヒーラー・ダークプリーストの回復・バフは飛翔体なし（別途エフェクト）
    - 画像がない場合は黄色の円（フォールバック）を表示
  - [x] Phase 9-4: 効果音
    - 素材：Kenney CC0 アセット4パック（RPG Audio / Impact Sounds / Sci-fi Sounds / Interface Sounds）
    - SoundManager.gd（Autoload）で一元管理。AudioStreamPlayer×8 のプールでポリフォニー対応
    - ファイルが存在しない場合は無音スキップ（将来の差し替えも容易）
    - 実装済み効果音と再生箇所：
      - slash / axe / dagger：近接攻撃時（player_controller._execute_melee / unit_ai._execute_attack）
      - arrow_shoot：弓発射時（archer / goblin-archer の ranged 攻撃）
      - magic_shoot：魔法弾発射時（magician-fire / goblin-mage / dark-mage 等）
      - flame_shoot：炎発射時（salamander の ranged 攻撃）
      - hit_physical / hit_magic：命中時（攻撃側のタイプで自動判定）
      - take_damage：character.take_damage() で再生
      - death：character.die() で再生
      - heal：character.heal() / unit_ai heal アクションで再生
      - room_enter：vision_system で新エリア入室時に再生
      - item_get / stairs：将来実装時に SoundManager.play(SoundManager.ITEM_GET/STAIRS) で呼ぶ
    - BGMは当面なし
  - [x] Phase 9-5: 衝突判定改善・移動回転アニメーション
    - **衝突判定の改善**
      - `_can_move_to()` を `grid_pos` のみで判定（pending 位置は不使用）。半マス到達で grid_pos が更新されるため、物理的な進入を基準とする先着優先方式
      - `static var _all_chars: Array` レジストリを character.gd に追加。移動進捗50%（コミット時）に他キャラの grid_pos と比較し、競合があれば `abort_move()` で移動をキャンセル（押し戻し効果）
      - unit_ai: MOVING ステートで移動先の競合チェックを追加（AI 側の abort 対応）
      - `is_pending()` / `get_pending_grid_pos()` / `abort_move()` メソッドを character.gd に追加
    - **向き変更ディレイ（移動ブロック時）**
      - `player_controller.gd`：`TURN_DELAY = 0.15s` / `game_speed` で除算。移動ブロック時に向きが変わる場合のみ発動
      - ディレイ中は `GlobalConstants.world_time_running = true`（世界時間を進行させる）
      - ディレイ完了時に `character.complete_turn()` を呼んで向きを確定
    - **スプライト回転アニメーション**
      - `character.gd`：`start_turn_animation(target, duration, last_dir)` / `complete_turn()` / `_calc_turn_delta_rad()` 追加
      - Tween で最短経路の回転アニメーション。180°は `last_dir.x` で時計回り/反時計回りを決定
      - `_turn_target_facing: Direction` / `_turn_tween: Tween` フィールド追加
      - **通常移動時も適用**：`move_to()` が `_apply_direction_rotation()` の代わりに `start_turn_animation()` を呼ぶ。移動時間と同じ duration で回転アニメーション
- [ ] Phase 10: アイテム・装備システム
  - [x] Phase 10-1: アイテムデータ基盤
    - **ステータス統合（フィールドリネーム）**
      - `attack` → `attack_power`（物理近接/遠距離の攻撃力）
      - `heal_power` → `magic_power`（魔法攻撃力＋回復力を統合）
      - `accuracy: float = 0.0` 追加（現時点は未使用・装備実装時に有効化）
      - `inventory: Array = []` を CharacterData に追加（アイテムインスタンスの辞書リスト）
      - `last_attacker: Character` を Character に追加（ドロップ帰属の追跡用）
      - `attack_type` に "magic" を追加（goblin-mage / dark-mage / salamander / dark-priest）
    - assets/master/items/ にアイテム種類ごとのマスターデータを定義（sword.json, axe.json, bow.json, dagger.json, staff.json, armor_plate.json, armor_cloth.json, armor_robe.json, shield.json, potion_hp.json, potion_mp.json）
    - dungeon_handcrafted.json の各 enemy_party に `items` 配列を追加（Claude Code が内容を決定）
    - ドロップシステム（部屋制圧方式）：部屋の enemy_party 全員が死亡 or 離脱で制圧完了→アイテムが床にランダム散らばり
    - グレードフィールドは持たない（補正値の強さがグレードを表す）
    - 複数パーティーによる協力撃破の分配は将来実装
  - [ ] Phase 10-2: 装備システム
    - [x] ドロップ処理（部屋制圧方式）
      - party_wiped シグナルを `(items, room_id)` 方式に変更（party_manager.gd）
      - 部屋の enemy_party 全員が死亡 or 離脱で制圧完了
      - game_map._floor_items（Vector2i→Dict）に1マス1個でランダム散布
      - _check_item_pickup()：同じマスに移動で自動取得、inventory へ追加
      - プレイヤー操作キャラはフィルタなし。AIキャラは item_pickup 指示に従う（avoid=スキップ）
      - アイテムを床に黄色マーカーで描画（ビジョン外は非表示）
    - [x] OrderWindow 改修（アイテムUI）
      - サブメニュー項目を「操作切替 / アイテム」に刷新（旧「操作」列廃止）
      - アイテム画面：未装備品一覧 → アクションメニュー（装備する / 渡す）→ 受け渡し相手選択 の3層UI
      - 装備する：CLASS_EQUIP_TYPES で装備可能なアイテムのみ表示。上書き時、旧装備は未装備品に残る
      - 渡す：リーダー操作中のみ表示。渡す相手をメンバー一覧から選択
      - 装備欄：equipped_weapon / armor / shield を実際に表示（旧スタブ廃止）
      - 所持アイテム欄：装備中アイテムを除外した未装備品のみ表示
    - [x] 操作体系の刷新
      - attack_melee → attack にリネーム（Z + Joypad Button 0/A）
      - attack_ranged 削除。攻撃タイプ（melee/ranged）はクラスの slots.Z.action から自動判定
      - menu_back 新規追加（X + Joypad Button 1/B）
      - player_controller.gd：AttackSlot.X・_slot_x・DEFAULT_SLOT_X 削除、1ボタン統合
      - メニュー内ナビゲーション：右キー/Z=決定、左キー/X/Esc=戻る（order_window・dialogue_window 共通）
      - 名前列：Z=サブメニュー開く、右キー=隣の列へ移動、左キー=ウィンドウ閉じる
      - ログ行：右キー/Z=ログ開始、左キー/X/Esc=ウィンドウ閉じる
    - [x] MessageWindow拡張・AIデバッグパネル廃止（Phase 10-2 準備）
      - RightPanel からAIデバッグ表示（下半分）を削除。敵情報表示のみ残す
      - MessageLog（Autoload）を新設。メッセージ種別（system=白/combat=黄/ai=水色）と色分け、デバッグフィルタ
      - MessageWindow をフィールド画面下部5行固定表示にリファクタリング。自動スクロール
      - OrderWindow のログ行が MessageLog の共有バッファを参照するよう統合
      - F1キーを MessageLog のデバッグメッセージ表示トグルに転用（デフォルトON）
      - 各リーダーAI（Goblin/Wolf/Hobgoblin/Default/NPC）に戦略変更時のログ出力を追加
        - ログフォーマット：`[AI] {名前}: {旧}→{新}（{理由}）`（例：`[AI] ゴブリン: 待機→攻撃（敵発見）`）
        - プレイヤー操作中のメンバーがいるパーティーはログ抑制
        - 合流前の一時パーティー（初期仲間・hero_manager）はsuppress_ai_logフラグでログ抑制
      - character.gd に戦闘計算ログ出力（暫定フォーマット）を追加
      - Strategy enum に EXPLORE を追加（パーティーレベル専用。UnitAI には ATTACK+move=explore に変換）
      - NPC パーティーのデフォルト戦略を WAIT → EXPLORE に変更（敵なし時は探索行動）
      - 敵パーティーのデフォルト戦略は WAIT のまま（アクティブ化時に ATTACK に遷移）
    - [x] 全キャラクター常時行動化（Phase 10-2 準備）
      - NPC パーティーをゲーム開始時に即座にアクティブ化（VisionSystem 配布後）
      - 敵パーティーはプレイヤー or NPC が部屋に入ったらアクティブ化（friendly_areas で判定）
      - 画面外のNPCは非表示のまま自律行動（VisionSystem の既存 visited_areas で表示制御）
      - デバッグログ（combat/ai）をプレイヤーのいるエリアに限定（MessageLog エリアフィルタ）
    - [x] 会話UIをMessageWindowに統合（Phase 10-2 準備）
      - DialogueWindow を廃止。会話の選択肢をMessageWindow下部にインライン表示
      - NPC パーティー情報（名前・ランク・クラス・状態）をメッセージとして表示
      - 会話の結果（合流・拒否・中断）もメッセージとして表示
    - [x] 装備ステータス補正値反映
      - 装備変更時に Character.refresh_stats_from_equipment() でパラメータに反映（attack_power / magic_power）
      - 攻撃コードは装備補正込みのパラメータを参照するため変更不要
      - 戦闘計算ログは武器名・装備補正の内訳を表示しない（補正済みパラメータを表示）
    - [x] 被ダメージ計算に防御判定・防御強度・耐性を反映（Phase 10-2 準備で実装済み）
    - [x] 方向判定：atan2 で4象限（正面/背面/左側面/右側面）、近接・遠距離共通（Phase 10-2 準備で実装済み）
    - [x] 耐性（physical_resistance / magic_resistance）をキャラクターデータに追加（Phase 10-2 準備で実装済み）
      - クラスごとの素値を設定、他パラメータと同じ生成フローで決定
      - 能力値（整数）で管理し、軽減率への変換は内部で行う: 軽減率 = 能力値 / (能力値 + 100)
    - [x] 初期装備の付与（Phase 10-2 準備で実装済み。dungeon_handcrafted.json の items → 装備スロットにセット）
    - [x] 装備補正値を新仕様に統一（dungeon_handcrafted.json 全装備を更新）
      - 初期装備（プレイヤー・NPC）は全補正値0（補正なし）
      - 武器の `skill` 補正を廃止（仕様通り skill は装備で変化しない）
      - 剣・斧・短剣: `power` + `block_right_front` / 弓・杖: `power` + `block_front`
      - 盾: `block_left_front` のみ（旧 `physical_resistance` を削除）
      - 防具: `physical_resistance` + `magic_resistance` の両方を持つように修正
      - 最深層（フロア4）の敵パーティーはアイテムなし（クリア直結のためドロップ不要）
      - 敵ドロップ補正値はフロア深度に応じてスケール
    - AI自動装備は将来実装（当面は拾って持つだけ）
    - [x] UI改善・バグ修正
      - 左パネル・OrderWindow にクラス名（日本語）・ランクを表示
      - 左パネルの個別指示表示を OrderWindow の COL_LABELS と完全一致する表記に統一（例：同じ部屋 / 積極攻撃 / 最近傍）
      - 会話選択の決定を Z/A のみ、キャンセルを X/B のみに限定（左右キー無効化・移動との競合防止）
      - CharacterGenerator で名前・画像セットの重複防止（使用済みリスト追跡・枯渇時フォールバック）
      - アイテム一覧の装備可否色分け（不可=灰色）・補正値の日本語表記統一（アイテム一覧・装備欄の両方）
      - GlobalConstants に CLASS_NAME_JP / STAT_NAME_JP テーブルを追加
      - 主人公を hero.json 固定からランダム生成に変更（他キャラと同様に CharacterGenerator 使用）
      - dungeon_handcrafted.json の主人公定義を character_id:"hero" → class_id:"fighter-sword" に変更
      - 耐性を能力値（整数）に変更。軽減率 = 能力値 / (能力値 + 100) の逓減カーブで内部変換
      - カメラのデッドゾーン比率を 0.70 → 0.40 に変更（先読みマージン拡大・出会いがしら軽減）
      - 隣接エリアの先行可視化（通路の端に立つと次の部屋が見える。VisionSystem でタイル隣接チェック）
      - 移動時の grid_pos 更新を半マス到達（進捗50%）に遅延。占有タイルは旧位置+移動先の両方をカバー
  - [x] Phase 10-3: 消耗品の使用（Phase 12-5 で操作体系を変更）
    - HP回復ポーション・MP回復ポーション
    - C/X **短押し** → アイテム選択UI（ITEM_SELECT→ACTION_SELECT→TRANSFER_SELECT）
      - 未装備品＋消耗品を一覧表示（装備中アイテムは除外）。消耗品は同種をグループ化
      - アクション: 使用する / 装備する / 渡す（リーダーのみ）/ キャンセル
      - 「渡す」→ TRANSFER_SELECT（パーティーメンバーを選択）
      - Z/A または C/X で決定、B（menu_back）で前の画面へ戻る
      - LB/RB でカーソル循環（通常時のキャラ切り替えは無効）
      - UI 中は時間停止
    - 使用条件：HPポーション→HP満タンでない、MPポーション→MP満タンでない
    - 使用後：inventoryから削除。MessageLogにシステムメッセージ
    - **ConsumableBar UI**（ConsumableBar.gd）：画面上部・部屋名ラベルの左側に常時表示
      - `GlobalConstants.ConsumableDisplayMode` enum: NORMAL / ITEM_SELECT / ACTION_SELECT / TRANSFER_SELECT（パースエラー回避のため GlobalConstants に定義）
      - NORMAL 時：消耗品を種類ごとにアイコン＋「×個数」で横並び表示。消耗品ゼロなら非表示
      - ITEM_SELECT 時：アイテム一覧をアイコン付きで表示。V スロットのクールダウン残秒も表示
      - 操作キャラ切替・アイテム取得・C/X操作・使用後に自動更新
    - バグ修正：アイテム選択UIから装備中の武器・防具・盾を除外（`is_same()` で判定）
  - [x] Phase 10-4: 指示／ステータスウィンドウ統合
    - 既存の OrderWindow を拡張（order_window.gd）
    - 上部：キャラ一覧テーブル（全体方針プリセット＋5指示項目）
    - 下部：選択中キャラのステータス詳細・装備スロット（空）・所持アイテム（空）
    - ステータス表示：素値・補正値・最終値の3列（例：攻撃力　15　+0　→　15）
    - 開発中は全ステータス項目を表示（HP/MP/攻撃力/防御力/攻撃タイプ/射程/溜め硬直/ランク/飛行/統率力/従順度）
    - 開いている間も時間進行継続（ポーズなし）
    - リーダー操作中：指示の変更可。非リーダー操作中：閲覧のみ（タイトルに「閲覧のみ」表示）
    - 誰を操作中でも Tab / Select でウィンドウを開ける（旧：リーダーのみ）
    - ステータス欄左側に front.png（なければ face.png、なければプレースホルダー）を表示
    - カーソル位置記憶：ウィンドウ閉じて再度開いたとき前回位置から再開
    - 全体方針→個別方針カーソル移動時は1列目（名前）から開始
    - バグ修正：`_get_char_front_texture()` が sprite_front ファイル不在のとき sprite_face にフォールバックするよう修正（CharacterGenerator 生成キャラは常に sprite_front パスが設定されるため、ファイル存在チェックが必要だった）
- [x] Phase 11: フロア・ダンジョン拡張
  - [x] Phase 11-1: 階段実装・フロア遷移
    - 階段タイル（STAIRS_DOWN=4, STAIRS_UP=5）を TileType に追加。GlobalConstants に定数追加
    - DungeonBuilder が JSON の `stairs` 配列（type/x/y 形式）から階段タイルを配置
    - MapData.find_stairs(type) で階段座標を全検索
    - VisionSystem をフロアインデックスごとに訪問済みエリア・可視タイルを管理（switch_floor()）
    - game_map.gd: 全フロアの MapData を起動時に一括構築（_all_map_data[]）
    - game_map.gd: フロアごとに EnemyManager・NpcManager を管理（_per_floor_enemies[], _per_floor_npcs[]）
    - 未訪問フロアは初訪問時に敵・NPC をセットアップ（遅延初期化）
    - _check_stairs_step(): hero が静止・階段タイルを踏んでいれば _transition_floor() を呼ぶ
    - _transition_floor(): フロア番号更新・hero 位置更新・VisionSystem 切替・カメラリミット更新
    - 階段タイルは茶色/黄土色で塗り、▼/▲ シンボルを重ねて表示
    - 遷移クールダウン 1.5 秒（連続遷移防止）
    - 倒した敵はフロアをまたいでも復活しない（EnemyManager が永続保持）
    - dungeon_handcrafted.json: 5フロア構成（各フロア12部屋・3列×4行レイアウト・部屋サイズ10×8。フロア4のみボス1部屋）
    - 敵は階段を使わない（hero・パーティーメンバー・未加入 NPC のみ遷移する）
    - [x] Phase 11-1 バグ修正（フロア遷移後の不具合）
      - クロスフロアすり抜け・不可視攻撃バグの3点修正
        1. `_setup_floor_enemies/npcs()` で敵・NPC スポーン時に `current_floor` をセット
        2. `_transition_floor()` で `blocking_characters` を新フロアの敵・NPC に再構築
        3. `party_leader_ai._assign_orders()` で別フロアのターゲットを null に排除
      - NPC アクティブ化を訪問済みエリアのみに限定（起動時・フロア遷移時の両方）
        - `vision_system.gd`: 未訪問エリアの NPC を `friendly_areas` から除外
        - `game_map.gd`: 未訪問エリアの NPC は activate() しない
      - 矢印キー長押しで階段を通り抜けてしまう問題を修正
        - `player_controller.gd`: 階段タイル静止中は移動バッファをブロック
        - `stair_just_transitioned` フラグで遷移直後（新フロアの階段タイル上）はブロック解除
        - `_transition_floor()` でフラグをセット
      - F2 デバッグキーを追加（`user://debug_floor_info.txt` に出力。MessageWindow でパスを通知）
      - カメラ X 方向デッドゾーンを 0.40 → 0.20 に変更（進行方向の視野を改善）
      - DungeonBuilder に `MAP_BORDER = 6` を追加（四方6タイルの境界壁。コンテンツを offset で移動）
        - キャラがカメラリミット付近に物理的に到達できなくなり、マップ端での画面端寄りを解消
  - [x] Phase 11-2: 5フロア対応・ゲームクリア実装
    - dungeon_handcrafted.json を5フロア構成に（各フロア12部屋・3列×4行・部屋10×8タイル・階段3か所）
      - フロア0（地下1層）: 12部屋。入口1・NPC4・敵7（ゴブリン中心）。下り階段3か所
      - フロア1（地下2層）: 12部屋。ゴブリン＋アンデッド（zombie/skeleton）混成。上り3・下り3階段
      - フロア2（地下3層）: 12部屋。アンデッド＋狼＋ハーピー＋暗黒系。上り3・下り3階段
      - フロア3（地下4層）: 12部屋。暗黒騎士団・デーモン・リッチ・サラマンダー。上り3・下り3階段
      - フロア4（地下5層・最下層）: 1部屋（深淵の玉座）。ボス構成（dark-lord・dark-knight×2・dark-mage・dark-priest・demon）。上り階段3か所のみ
    - フロアが深いほど敵が強くドロップアイテムの補正値も高い
    - ゲームクリア判定: 最終フロア（インデックス4）の全敵パーティー全滅で `_trigger_game_clear()` 発火
      - プレイヤー入力を無効化（`player_controller.is_blocked = true`）
      - MessageLog にシステムメッセージ「ダンジョンを制覇した！…」を表示
      - F5 リスタートは引き続き有効（`game_map._input()` の KEY_F5 直接マッチのため）
    - Phase 11-2 バグ修正
      - 魔法敵（ゴブリンメイジ・ダークメイジ・サラマンダー等）が攻撃しない問題: `party_leader_ai.gd` の `magic_power > 0` 条件が魔法攻撃キャラを WAIT に固定していたのを `heal_mp_cost > 0 or buff_mp_cost > 0` に修正
      - 敵の初動が遅い問題: `unit_ai.gd` の move アクション開始時タイマーを `_get_move_interval()` から `0.0` に変更（最初の1歩の待ち時間を解消）
      - 敵・NPCの移動速度が遅い問題: `MOVE_INTERVAL` を `1.2` → `0.40` 秒/タイルに変更（プレイヤー速度 0.30 s/タイルに近づけた）
  - [x] Phase 11-3: MPバー表示・MP消費・アイテム一覧グループ化
    - 左パネルの MP バー: max_mp > 0 のキャラのみ青いバーと「MP X/Y」テキストを表示
    - `player_controller.gd`: `_execute_melee` / `_execute_ranged` でスロットの `mp_cost` を消費（`character.use_mp()`）
    - `magician-fire.json` / `healer.json` に `"mp"` フィールドと各スロットの `"mp_cost"` を追加。healer には `heal_mp_cost` / `buff_mp_cost` も追加
    - OrderWindow アイテム一覧: 同名アイテムを「剣 ×2」形式でグループ表示（`_cached_grouped` キャッシュ追加、カーソルはグループ単位で操作）
  - [x] Phase 11-4: ヒーラー操作時の回復実装・回復エフェクト
    - プレイヤー操作ヒーラーの回復行動
      - `_get_valid_targets()`: `action=="heal"` または `"buff_defense"` のとき `is_friendly==true` のキャラ（自分除く）を対象にする
      - ターゲット並び順: 距離順 → HP割合低い順（`_get_sorted_targets()` で heal/buff_defense 専用ソート）
      - `_enter_targeting()` に MP不足チェックを追加（`mp_cost > character.mp` ならターゲット選択モードに入れない）
      - `_execute_heal()`: `magic_power × heal_mult` で回復量を計算・`character.heal()` でHP回復・MP消費
      - `_execute_buff()`: `apply_defense_buff()` でバフ付与・MP消費
    - 回復射程仕様
      - ヒーラーの回復は単体・射程あり（`healer.json` の各スロット `range` フィールドで管理。弓・炎と同じ仕組みで射程制限）
      - `healer.json` の `attack_range`（AI用）および全スロット `range` を 1 → 4 に更新
      - 将来の範囲魔法: 範囲内の味方全員を対象（実装時に `ranged_area` 相当の heal 版アクションを追加する設計）
    - 回復エフェクト（案A採用: コード描画）
      - `scripts/heal_effect.gd` 新規作成（Kenney素材に波紋系が存在しないため案A採用）
      - キャスト側（ヒーラー）: `mode="cast"` → 白金系（`Color(1.0, 0.95, 0.6)`）の波紋リング3本が外へ広がる
      - ターゲット側（回復される側）: `mode="hit"` → 緑〜白系のリングが内へ縮まる + 中央グロー
      - 再生時間 0.6 秒（HitEffect の約 0.375 秒より遅め）、半径 `GRID_SIZE × 0.55`（HitEffect より大きめ）
      - `_spawn_heal_effect(pos, mode)` を `player_controller.gd` に追加し、キャスト・ターゲット両方に発火
      - HEAL SE は `character.heal()` 内の既存処理をそのまま使用
  - [x] Phase 11-5: ガードシステム
    - X/B ボタン（`menu_back` アクション）ホールドでガード発動
      - `player_controller._process_normal()`: `Input.is_action_pressed("menu_back")` で `character.is_guarding` をセット/解除
      - 攻撃キー入力時はガードを先に解除してからターゲット選択モードへ移行
      - `is_blocked = true`（メニュー等）のとき `character.is_guarding = false` に強制解除
    - ガード中の向き維持
      - `character.move_to()`: `is_guarding = true` のとき facing を更新しない（guard_facing を維持）
      - 後ずさり・横歩きに対応（`_apply_direction_rotation()` もスキップ）
    - ガード中の移動速度
      - `player_controller._try_move()`: duration を2倍（通常の50%速度）
    - ガードグラフィック
      - `character_data.sprite_top_guard: String = ""`（`sprites.top_guard` キーからロード）
      - `character_generator.gd`: `data.sprite_top_guard = folder + "/guard.png"`（味方・敵共通）
      - `character._tex_guard`: 起動時に事前ロード（`_load_walk_sprites()` 内）
      - `_update_ready_sprite()` 優先順: `guard.png`（ガード中）> `ready.png`（ターゲット/攻撃中）> `top.png`（通常）
      - guard.png がなければ ready.png にフォールバック、それもなければ top.png
      - ガード中は歩行アニメをスキップ（`is_guarding` チェックを `is_targeting_mode or is_attacking` と並列追加）
    - ガードダメージ軽減
      - `character.take_damage()`: `is_guarding == true` かつ `dir_result == "front"` のとき
        - 防御判定を自動成功（ダイスロールなし）
        - `blocked = _calc_block_power_front_guard()`（block_right_front + block_left_front + block_front の合計。判定100%成功）
      - 正面以外（側面・背面・方向不明）はガード効果なし（通常の防御判定）
    - 画像フォーマット仕様追加
      - `guard.png`（256×256 または 1024×1024、ガード姿勢・盾構え）
      - 配置先: `assets/images/characters/{set}/guard.png`（味方）/ `assets/images/enemies/{set}/guard.png`（敵）
      - なければフォールバックで ready.png → top.png を使用（敵は当面 guard.png なし）
- [ ] Phase 12: ステージ・バランス調整
  - [x] Phase 12-1: MP/SPシステム実装
    - **CharacterData に追加したフィールド**
      - `max_sp: int = 0`（非魔法クラス専用スタミナ上限）
      - `instant_death_immune: bool = false`（ボス級は true）
      - `friendly_fire: bool = false`（将来実装・当面 false 固定）
    - **Character ランタイムフィールド**
      - `sp: int` / `max_sp: int` を追加（`_init_stats()` で初期化）
      - 自動回復：`_recover_mp_sp(delta)` を `_process()` から毎フレーム呼ぶ（速度 `MP_SP_RECOVERY_RATE = 3.0` /秒・端数蓄積方式）
      - `use_sp(cost)` メソッド追加（`use_mp()` と同じ仕組み）
      - `use_consumable()` に `restore_sp` 対応を追加
    - **非魔法クラス JSON に追加**（`fighter-sword` / `fighter-axe` / `archer` / `scout`）
      - `"max_sp": 60` をクラス定義に追加
      - Z スロットに `"sp_cost": 2` を追加（通常攻撃の微量消費。回復速度と相殺される程度）
    - **player_controller.gd**：`_execute_melee()` / `_execute_ranged()` で `sp_cost` を `use_sp()` で消費
    - **左パネル（left_panel.gd）**
      - `MAGIC_CLASS_IDS = ["magician-fire", "magician-water", "healer"]` 定数追加
      - 魔法クラスは MPバー（濃い青 `Color(0.2, 0.5, 1.0)`）を表示
      - 非魔法クラスは SPバー（水色 `Color(0.4, 0.8, 1.0)`）を表示（`max_sp > 0` のとき）
    - **OrderWindow**：魔法クラスは「MP」行・非魔法クラスは「SP」行を表示（クラスIDで判定）
    - **SPポーション**（`assets/master/items/potion_sp.json` 新規作成）
      - `category: consumable` / `effect.restore_sp: 20`
      - `consumable_bar.gd` に `potion_sp` の水色アイコン色を追加
    - **ダンジョン**：fighter-sword・archer の初期装備に `potion_sp`（活力薬）を追加。goblin-archer パーティーのドロップにも追加
  - [x] Phase 12-2: 水魔法使いクラス・スタンシステム実装
    - **`magician-water` クラス追加**（`assets/master/classes/magician-water.json` 新規作成）
      - Z: 水弾（ranged magic, range 5, mp_cost 3, damage_mult 0.8）
      - X: 水流（ranged magic, range 5, mp_cost 10, damage_mult 1.5）
      - V: 無力化水魔法（water_stun, magic, range 4, mp_cost 15, stun_duration 4.0s）
      - `max_sp: 0`・`mp: 60`
    - **スタンシステム（Character）**
      - `is_stunned: bool` / `stun_timer: float` フィールド追加
      - `apply_stun(duration)` メソッド：スタン付与・MessageLog に通知。重複スタンは残り時間を延長
      - `_process()` でタイマー消化・解除時に `_sprite.rotation = 0` リセット
      - スタン中は `_sprite.rotation += delta * 4.0` で視覚的なスピン表現
      - `_update_modulate()` でスタン中はシアン点滅に上書き
    - **UnitAI スタン対応**
      - `_process()` 冒頭で `is_stunned == true` の場合は行動キューをクリア・IDLE に戻して早期 return
    - **Projectile 水弾対応**
      - `_WATER_BULLET_PATH` 定数追加（`water_bullet.png`・画像なければ水色フォールバック）
      - `_is_water: bool` / `_stun_duration: float` フィールド追加
      - `setup()` に `stun_duration` / `is_water` オプション引数追加
      - `_on_arrive()` で `_stun_duration > 0` の場合 `target.apply_stun()` を呼ぶ
      - フォールバック色：水=水色・火=オレンジ・矢=黄色
    - **V スロット（player_controller）**
      - `special_skill` InputAction 追加（V キー + Y ボタン）
      - `_slot_v: Dictionary` / `_using_v_slot: bool` フィールド追加
      - `_load_class_slots()` で V スロットをロード
      - `_get_slot()` で `_using_v_slot == true` のとき `_slot_v` を返す
      - `_is_slot_held()` で `_using_v_slot` に応じて `special_skill` / `attack` アクションを判定
      - `_execute_water_stun()` メソッド追加：MP消費・水弾発射（stun_duration 付き）
      - `_get_valid_targets()` で `water_stun` を `ranged` と同様に射程内の敵を対象
    - **SPポーションアイコン色変更**：`consumable_bar.gd` の `potion_sp` 色を水色 → 緑（`Color(0.2, 0.8, 0.3)`）に変更
    - **ボス系敵に `instant_death_immune: true` 追加**：dark_knight / dark_mage / dark_priest / hobgoblin
    - **ダンジョン**：ゾンビの霊廟（r1_4）の NPC パーティーに `magician-water` メンバー追加（杖・ローブ・MPポーション×2 装備）
  - [x] Phase 12-3: アイテム画像反映
  - [x] Phase 12-4: Vスロット特殊スキル実装（7クラス）
    - **共通基盤（`player_controller.gd`）**
      - `V_SLOT_COOLDOWN = 2.0` / `_v_slot_cooldown: float` 追加。`_process()` でカウントダウン
      - `_has_v_slot_resources()`: MP/SP不足チェック
      - `_start_v_cooldown()`: クールダウン開始＋ConsumableBar 更新
      - `_execute_v_instant(action)`: インスタント系ディスパッチャ（クールダウン先行開始）
      - インスタント系（sliding/whirlwind/rush/flame_circle）: `is_action_just_pressed` で発動
      - ターゲット系（headshot/water_stun/buff_defense）: `is_action_just_pressed` で PRE_DELAY → TARGETING フローへ
      - `_enter_targeting()` に SP コストチェックを追加
      - `_execute_pending()` で headshot 対応・V スロット実行後にクールダウン開始
      - `_get_valid_targets()` に headshot を ranged 相当として追加
    - **`character.gd`**: `is_sliding: bool = false` 追加。`take_damage()` でスライディング中はスキップ
    - **`scripts/flame_circle.gd`** 新規作成: 炎陣エフェクト・tick ダメージノード
    - **`consumable_bar.gd`**: `v_slot_cooldown: float` 追加・`_on_draw()` に "V: X秒" 表示を追加
    - **スキル実装（`player_controller.gd`）**
      - `_execute_sliding()`: 3マスダッシュ（await）・壁で止まる・キャラクター通り抜け可・is_blocked=true
      - `_execute_whirlwind()`: 周囲8マス AoE・即時ダメージ・is_attacking フラグ（await で解除）
      - `_execute_rush()`: 前方2マス前進（await）・経路の敵にダメージ・壁で止まる・is_blocked=true
      - `_execute_headshot()`: ターゲット選択後に実行。immune=false→99999ダメージ（実質即死）、immune=true→×3ダメージ
      - `_execute_flame_circle()`: FlameCircle ノードを map_node に追加・2.5秒間・0.5秒ごとに magic ダメージ
      - `_find_character_at(pos)`: 指定グリッド座標のキャラクターを返すユーティリティ
    - **クラス JSON 更新**
      - `scout.json`: V=スライディング（sp_cost: 20）
      - `fighter-axe.json`: V=振り回し（sp_cost: 15, damage_mult: 1.0）
      - `fighter-sword.json`: V=突進斬り（sp_cost: 15, damage_mult: 1.2）
      - `archer.json`: V=ヘッドショット（sp_cost: 25, range: 6, damage_mult: 3.0）
      - `magician-fire.json`: V=炎陣（mp_cost: 20, range: 3, damage_mult: 0.8, duration: 2.5s, tick_interval: 0.5s）
      - `magician-water.json`: V=無力化水魔法（Phase 12-2 から変更なし）
      - `healer.json`: C スロットを null に変更、V=防御バフ（buff_defense・mp_cost: 8・range: 4）
    - **床アイテムマーカー（`game_map.gd`）**
      - `item.get("image", "")` が空のとき `item_type` から `assets/images/items/{item_type}.png` を導出
      - `_load_item_texture()` 経由でテクスチャロード。画像なし時は黄色マーカーにフォールバック（既存挙動）
      - 対応画像: `sword.png` / `axe.png` / `dagger.png` / `bow.png` / `staff.png` / `armor_plate.png` / `armor_cloth.png` / `armor_robe.png` / `shield.png` / `potion_hp.png` / `potion_mp.png` / `potion_sp.png`
    - **OrderWindow アイテム一覧オーバーレイ（`_draw_item_list_overlay`）**
      - `_item_tex_cache: Dictionary` と `_load_item_tex(item)` を追加（同パス導出ロジック）
      - 各アイテム行の左端に `row_h - 6` サイズのアイコンを描画。テクスチャなし時はグレーブロック
      - テキストはアイコン幅＋4px 右にオフセット
    - **OrderWindow 装備欄（`_draw_status_section`・装備スロット部）**
      - 武器・防具・盾スロット行の値列左端に `stat_h - 2` サイズのアイコンを描画
    - **OrderWindow 所持アイテム欄（`_draw_status_section`・インベントリ部）**
      - 未装備品リスト各行の左端にアイコンを描画
  - [x] Phase 12-5: 操作体系変更・LB/RBキャラ切り替え・C/X短押しアイテム選択UI
  - [x] Phase 12-6: 防御バフのバリアエフェクト実装
    - `scripts/buff_effect.gd` 新規作成（コード描画・永続エフェクト）
      - 半透明の緑色六角形（塗り＋枠線）を `draw_polygon()` + `draw_polyline()` で描画
      - 外周リングを `draw_arc()` で重ねる（半径 GRID_SIZE × 0.74）
      - ゆっくり回転（60°/秒・`ROT_SPEED = PI/3`）
      - 自身では削除しない（`character.gd` が寿命を管理）
    - `character.gd` 修正
      - `_buff_effect: Node2D` フィールド追加
      - `apply_defense_buff()`: エフェクトを生成して `add_child()`。重複付与時は再生成でリセット
      - `_remove_buff_effect()` ヘルパー追加
      - バフタイマー消化時（`defense_buff_timer <= 0`）に `_remove_buff_effect()` を呼ぶ
    - **LB/RB（通常時）**：パーティーメンバーを表示順で循環切り替え。`switch_char_requested` シグナルで `game_map._on_switch_character_requested()` を呼び出し。`player_controller.party_leader` がパーティーリーダーのときのみ有効（NPC パーティーに合流してリーダーを譲った場合は無効）
    - **C/X短押し**：アイテム選択UIを開く（ITEM_SELECT→ACTION_SELECT→TRANSFER_SELECT）。UI中は時間停止・LB/RBでカーソル循環
    - **ConsumableBar**：`GlobalConstants.ConsumableDisplayMode` enum で UI フェーズを管理。`is_selecting` / `select_index` は後方互換用（旧C/Xホールド方式の残留フィールド）
    - **project.godot**：`switch_char_prev`（LB/Button9）・`switch_char_next`（RB/Button10）を追加。旧 `slot_prev`/`slot_next` を空に（未使用）
    - **game_map.gd**：`player_controller.switch_char_requested` シグナルを接続。`_party_sorted_members` を初期設定時およびキャラ切り替え後に更新
  - [x] Phase 12-7: パーティーメンバー・未加入 NPC のフロア遷移
    - **パーティーメンバーの階段使用**
      - `unit_ai.gd`: `_generate_queue()` 冒頭で hero と別フロアの仲間を検出 → `_generate_floor_follow_queue()` で適切な階段タイルへ A* 誘導
      - `game_map.gd`: `_check_party_member_stairs()` で仲間が階段タイルに静止したら `_transition_member_floor()` を呼んで遷移
      - `_transition_member_floor()`: hero の隣接空きタイルに着地・NpcManager の `map_data` 更新・`blocking_characters` 再構築
      - `_member_stair_cooldown` 変数でパーティー遷移クールダウンを hero の `_stair_cooldown` とは独立管理
    - **未加入 NPC のフロアランク判断**
      - `global_constants.gd`: `FLOOR_RANK = {0:0, 1:8, 2:13, 3:18, 4:24}` / `NPC_HP_THRESHOLD = 0.5` / `NPC_ENERGY_THRESHOLD = 0.3` 追加
      - `npc_leader_ai.gd`: `_get_explore_move_policy()` 追加（全メンバーの RANK_VALUES（C=3, B=4, A=5, S=6）の**和**と `FLOOR_RANK` を比較して適正フロアを決定。HP最低値・エネルギー平均値が閾値未満なら-1補正。`_calc_recoverable_hp()` / `_calc_recoverable_energy()` ヘルパー追加）
      - `party_leader_ai.gd`: `_get_explore_move_policy()` 仮想メソッド追加・EXPLORE 戦略の `move_policy` 設定をこのメソッド経由に変更
      - `unit_ai.gd`: `"stairs_down"` / `"stairs_up"` move_policy で `_generate_stair_queue()` を生成
      - `game_map.gd`: `_check_npc_member_stairs()` で全フロアの NPC を監視・`_transition_npc_floor()` で NPC パーティーを遷移
    - **共通基盤**
      - `unit_ai.gd`: `set_map_data()` 追加・`_is_passable()` に別フロアキャラを除外するクロスフロアフィルターを追加
      - `party_leader_ai.gd`: `set_map_data()` 追加（UnitAI に伝播）
      - `party_manager.gd`: `set_map_data()` 追加（LeaderAI に伝播）
      - `game_map.gd`: `_rebuild_blocking_characters()` 追加（`_transition_floor()` でも流用）・`_find_free_adjacent_to()` 追加・`_member_to_npc_manager` マッピング追加
      - `global_constants.gd`: `CLASS_NAME_JP` に `"magician-water"` を追加
  - [x] Phase 12-7 バグ修正
    - **NPC パーティーがプレイヤーを追従する問題**
      - 原因：`party_leader_ai._assign_orders()` で formation_ref の決定ロジックが未加入 NPC パーティーにも `_player` を渡していた
      - 修正：`joined_to_player` フラグを `PartyLeaderAI` / `PartyManager` に追加。合流済みの場合のみ `formation_ref = _player` に設定。未加入 NPC リーダーは `formation_ref = null`（自由行動）
      - `game_map._merge_npc_into_player_party()` で `nm.set_joined_to_player(true)` を呼んでフラグを伝播
    - **仲間の「同じ部屋」指示が機能しない問題**
      - 原因：`unit_ai._formation_satisfied()` の "same_room" 判定で、通路タイル（area_id が空文字）の場合に常に true を返していた
      - 修正：自分またはリーダーが通路にいる場合はマンハッタン距離 ≤3 のフォールバック判定に切り替え
      - `_target_in_formation_zone()` の "same_room" でも同様の修正を適用
    - **ヒーラーが他パーティーの NPC に回復・バフをかける問題**
      - 原因：`UnitAI._find_heal_target()` / `_find_buff_target()` が `_all_members` 全体を対象にしていた
      - 修正：`_party_peers: Array[Character]` フィールドを追加し、`PartyLeaderAI.setup()` が `unit_ai.set_party_peers(members)` を呼ぶ。heal/buff ターゲット候補を自パーティーメンバー＋hero に限定
    - **アイテムが未訪問フロアに出現する問題**
      - 原因：`_floor_items` が `{Vector2i: item}` のフラット辞書であり、全フロアのアイテムが混在していた
      - 修正：`_floor_items` を `{floor_idx: {Vector2i: item}}` のネスト構造に変更。`_setup_floor_enemies()` のラムダで floor_idx をキャプチャ。`_check_item_pickup()` と描画処理も `ch.current_floor` / `_current_floor_index` を参照するよう更新
    - **キャラクターが A* 経路探索で階段タイルを通り抜ける問題**
      - 原因：`unit_ai._astar()` が階段タイルを中間ノードとして通過可能として扱っていた
      - 修正：`_astar()` で階段タイルを中間ノードとしてスキップ（`move_policy` が "stairs_down"/"stairs_up" の場合、またはゴールが階段タイルの場合は除外しない）
      - `_find_adjacent_goal()` で階段でないタイルを優先候補として選択（`best_on_stair` フラグで管理）
      - `_find_explore_target()` で階段タイルをフィルタリング（非階段タイルが存在する場合のみ）
      - `_generate_queue()` 冒頭で `move_policy` が階段系以外にもかかわらず階段上にいる場合は隣接の非階段タイルへ移動するフォールバック
      - `_find_non_stair_adjacent()` / `_is_stair_tile()` ヘルパー追加
    - **未加入 NPC のフロア遷移：意図しない方向への遷移を防止**
      - `game_map._check_npc_member_stairs()` で NpcManager の `get_explore_move_policy()` を確認し、`"stairs_down"` / `"stairs_up"` の意図がない場合は遷移をスキップ
- [x] Phase 12-8: OrderWindowバグ修正・NPC会話専用ウィンドウ・階段複数設置
  - [x] **OrderWindow 名前列フォーカス時の右キー動作修正**
    - 修正前：名前列（_col_cursor=0）で右キーを押すとサブメニューが開いていた
    - 修正後：右キーは常に列移動のみ（col 0→1→…→6→0 の循環）。サブメニューを開くのは Z/A のみ
    - `order_window.gd` の `ui_right` ハンドラを簡略化（分岐削除）
  - [x] **NPC会話専用ウィンドウ（`scripts/npc_dialogue_window.gd`）新設**
    - CanvasLayer（layer=20）・`process_mode = PROCESS_MODE_ALWAYS`
    - 表示中はゲームを一時停止（`get_tree().paused = true`）、閉じたら再開
    - **レイアウト**
      - 画面中央に半透明の暗幕＋パネル
      - 上部：NPC メンバーの `face.png`（なければ `front.png`、なければグレーブロック）を横並び表示。その下に名前・クラス名（日本語）＋ランク `[S]/[A]/[B]/[C]`（S/A=赤・他=オレンジで色分け）
      - 下部：選択肢（MAIN 状態）または確認ダイアログ（CONFIRM 状態）
    - **操作フロー**
      - MAIN 状態：「仲間にする」（デフォルト）/ 「断る」を↑↓で選択、Z/A で決定、X/B で閉じる
      - 「仲間にする」→ CONFIRM 状態へ遷移：「本当に仲間にしますか？」＋「はい」「いいえ」（デフォルト：いいえ）
      - 「はい」→ `choice_confirmed("join_us")` シグナル発火
      - 「いいえ」・X/B → MAIN 状態に戻る
      - 「断る」・X/B → `dismissed()` シグナル発火
    - シグナル：`choice_confirmed(choice_id: String)` / `dismissed()`
  - [x] **game_map.gd 変更**
    - `var npc_dialogue_window: NpcDialogueWindow` フィールド追加
    - `_setup_dialogue_system()`: MessageWindow の dialogue シグナル接続を NpcDialogueWindow に変更
    - `_on_dialogue_requested()`: MessageWindow.start_dialogue() → NpcDialogueWindow.show_dialogue() に置き換え。MessageLog に会話開始メッセージのみ記録
    - `_on_dialogue_choice()`: CHOICE_JOIN_THEM（連れて行って）を廃止し join_us のみ対応。結果を MessageLog に記録
    - `_on_dialogue_dismissed()`: MessageLog に「誘いを断った」を記録してから `_close_dialogue()` を呼ぶ
    - `_close_dialogue()`: `message_window.end_dialogue()` → `npc_dialogue_window.hide_dialogue()` に変更
    - MessageWindowの会話モードはNPC会話には使用しない（MessageLogへの記録のみ継続）
    - LB/RB キャラ切替後に `order_window.set_controlled()` を呼んで指示ウィンドウに反映
  - [x] **`dungeon_handcrafted.json` 階段配置**（フロアあたり3か所。フロア間で同一座標に対応する上り/下りを設置）
    - フロア0：下り3か所（r1_8/r1_11/r1_12）
    - フロア1：上り3か所（r2_1/r2_5/r2_8）・下り3か所（r2_10/r2_11/r2_12）
    - フロア2：上り3か所（r3_1/r3_5/r3_8）・下り3か所（r3_10/r3_11/r3_12）
    - フロア3：上り3か所（r4_1/r4_5/r4_8）・下り3か所（r4_10/r4_11/r4_12）
    - フロア4：上り3か所（r5_1 内に3つ）
    - 入口部屋（r1_1）には階段を置かない
  - [x] Phase 12-8 バグ修正
    - **別フロアのキャラクターが移動をブロックする問題**
      - 原因：`_rebuild_blocking_characters()` が全フロアの敵・NPC を無差別に追加していた（`current_floor` フィルターなし）。無効参照（freed キャラ）も 18 件混入
      - 修正：`_rebuild_blocking_characters()` で敵・NPC を1体ずつ `current_floor` フィルタリング＋ `is_instance_valid` チェック。`_can_move_to()` / `_try_move()` / `_get_valid_targets()` にも同フロアフィルターを追加（二重防衛）
      - デバッグログ出力先：`%APPDATA%\Godot\app_userdata\trpg\debug_floor_info.txt`（F2 キー）
    - **敵がプレイヤー（英雄）以外を攻撃しない問題**
      - 原因①：全敵リーダー AI（goblin/wolf/hobgoblin/default）の `_select_target_for()` が `return _player` 固定だった
      - 原因②：`set_friendly_list()` を呼ぶ時点で `_leader_ai == null`（`activate()` 前）なのでリストが破棄されていた
      - 修正①：`PartyLeaderAI` に `_friendly_list` と `_find_nearest_friendly()` / `_has_alive_friendly()` を追加。各敵リーダー AI の `_evaluate_party_strategy()` / `_select_target_for()` をこれらを使うよう変更
      - 修正②：`PartyManager` に `_friendly_list` フィールドを追加して保存し、`_start_ai()` 内で `_leader_ai` 生成直後に `set_friendly_list()` を渡す
      - `game_map._link_all_character_lists()` でパーティーメンバー＋未加入 NPC を `all_friendlies` としてまとめ、全敵マネージャーに配布
- [x] Phase 12-9: 左パネル改修・パーティー上限・NPC配置集約
  - [x] **左パネルから MAP 表示を削除・12人対応**
    - `left_panel.gd`：`minimap_h`（下25%）を廃止し全高さをキャラクター表示に使用
    - `MAX_CARD_HEIGHT = 100`（1人あたりカード最大高さ）を定数追加。人数が少なくても大きくなりすぎない
    - `GlobalConstants.MAX_PARTY_MEMBERS = 12` を追加
  - [x] **パーティー満員ガード（NpcDialogueWindow）**
    - `_State.PARTY_FULL` 状態を追加。`show_party_full(nm)` メソッドで表示
    - 「これ以上仲間にできません（最大 N 人）」とNPC顔画像を表示し、Z/A・X/B で閉じる
    - `party_full_closed` シグナルを追加。`game_map._on_party_full_closed()` でログ記録・ダイアログを閉じる
    - `game_map._on_dialogue_requested()` で `party.members.size() >= MAX_PARTY_MEMBERS` をチェックし満員時は会話ウィンドウの代わりに満員メッセージを表示
  - [x] **NPC配置をフロア0に集約（4部屋・11人）**
    - `dungeon_handcrafted.json` 修正：フロア0の r1_3〜r1_6 をすべて NPC 専用部屋（敵なし）に変更
    - r1_2（ゴブリンの集会所）のみ敵部屋として残す
    - NPC 配置（計11人・クラスバランスを考慮）：
      - r1_3「傭兵の集会所」: archer + fighter-axe（2人）
      - r1_4「廃教会」: fighter-sword + healer + magician-water（3人、既存）
      - r1_5「冒険者の野営地」: scout + magician-fire + archer（3人）
      - r1_6「探索者の拠点」: fighter-sword + healer + scout（3人）
    - 各 NPC は初期装備持ち（プレイヤー初期装備相当の弱め装備）
- [x] Phase 12-10: attack.png スプライト対応・image_set 固定割り当て
  - [x] **`attack.png` スプライト対応**
    - `character_data.gd`：`sprite_top_attack: String = ""` フィールド追加（`sprites.top_attack` キーからロード）
    - `character_generator.gd`：`generate_character()` / `apply_enemy_graphics()` で `sprite_top_attack = folder + "/attack.png"` を設定
    - `character.gd`：`_tex_attack: Texture2D = null` フィールド追加。`_load_walk_sprites()` でロード
    - `character.gd`：`_update_ready_sprite()` に `is_attacking` 専用分岐を追加。優先順: `guard.png`（ガード中）> `attack.png`（攻撃中）> `ready.png`（ターゲット選択中）> `top.png`（通常）
  - [x] **`apply_image_set_override()` 追加と image_set 固定割り当て**
    - `character_generator.gd`：`apply_image_set_override(data, folder_name)` 静的メソッド追加。フォルダ名からスプライトパスを一括設定し `_used_image_sets` に登録
    - `npc_manager.gd`：`setup()` で `image_set` フィールドを読み取り `_spawn_member()` に渡す。`_spawn_member()` に `image_set_override: String = ""` 引数追加
    - `dungeon_handcrafted.json`：プレイヤーパーティー3人・NPC11人の全14キャラに `image_set` を固定割り当て
      - hero (fighter-sword) → `fighter-sword_male_young_slim_00001`
      - player archer → `archer_female_young_slim_00006`
      - player healer → `healer_female_young_slim_00010`
      - r1_3 archer → `archer_male_young_slim_00005`、r1_3 fighter-axe → `fighter-axe_female_young_slim_00004`
      - r1_4 fighter-sword → `fighter-sword_female_young_slim_00002`、r1_4 healer → `healer_male_young_slim_00009`、r1_4 magician-water → `magician-water_female_young_slim_00014`
      - r1_5 scout → `scout_female_young_slim_00012`、r1_5 magician-fire → `magician-fire_male_young_slim_00007`、r1_5 archer → `archer_male_young_slim_00005`
      - r1_6 fighter-sword → `fighter-sword_female_young_slim_00002`、r1_6 healer → `healer_male_young_slim_00009`、r1_6 scout → `scout_male_young_slim_00011`
- [x] Phase 12-11: NPC 多層階探索・行動バグ修正
  - [x] **NPC が同フロア敵全滅後に探索モードへ移行しない問題**
    - 原因：`npc_leader_ai._evaluate_party_strategy()` が `_enemy_list`（全フロア）を無差別にチェックしていたため、他フロアに敵が生存している限り常に `ATTACK` を返していた
    - 修正：自パーティーの `current_floor` を取得し、**同フロアの敵のみ** ATTACK トリガーにする。他フロアの敵は無視
  - [x] **NPC がパーティー強度十分でも階段を使わず他の部屋を探索する問題**（修正済み・値は後続でさらに更新）
    - Phase 12-11 時点での修正：`global_constants.gd` の `FLOOR_RANK` を平均スコアベースの `{0:5, 1:12, 2:20, 3:30, 4:45}` に変更
    - **スコアロジック全面改修（Phase 12-11 後）**：平均スコアから和スコアに変更 + 動的スコア（HP/MP/SP）を追加。FLOOR_RANK を和ベースの `{0:200, 1:280, 2:420, 3:580, 4:780}` に更新。`NPC_HP_THRESHOLD = 0.5`・`NPC_ENERGY_THRESHOLD = 0.3` を追加
    - **スコア方式をランク和に変更（最終版）**：`power + physical_resistance + ...` の stat 和を廃止し、RANK_VALUES（C=3, B=4, A=5, S=6）の合計に変更。FLOOR_RANK を `{0:0, 1:8, 2:13, 3:18, 4:24}` に更新（各フロアの敵パーティー構成を参照した現実的な値）
  - [x] **NPC がフロア遷移後にプレイヤーと同フロアに降りてくるまで動かない問題**
    - 原因：`unit_ai._generate_queue()` のフロア追従チェックが `_member.is_friendly` で判定していたため、未加入 NPC が hero と別フロアにいると「hero を追って戻れ」という指示になり階段付近で停止していた。hero が降りてきた瞬間に動き出すという現象
    - 修正：`unit_ai.gd` に `_follow_hero_floors: bool = false` フラグを追加。フロア追従は `_follow_hero_floors == true` のときのみ発動
    - `party_leader_ai.setup()` で `joined_to_player` の値を各 UnitAI に初期値として渡す
    - `party_leader_ai.set_follow_hero_floors()` を追加（全 UnitAI に一括伝播）
    - `party_manager.set_joined_to_player()` が `set_follow_hero_floors()` 経由で UnitAI まで伝播するよう変更
    - 結果：合流済みパーティーメンバーのみフロア追従、未加入 NPC は各フロアで自律行動を継続
  - [x] **NPC がフロア遷移後にすり抜けられる問題**
    - 原因：`_transition_npc_floor()` で NPC が現フロアに到着した際、`npc_managers` には追加されているが `_rebuild_blocking_characters()` が呼ばれておらず `player_controller.blocking_characters` が未更新だった
    - 修正：`_transition_npc_floor()` の `new_floor == _current_floor_index` ブロックに `_rebuild_blocking_characters()` 呼び出しを追加
- [x] Phase 12-12: アンデッド・新敵種実装
  - CharacterData に `is_undead: bool = false` フィールド追加
  - skeleton / skeleton-archer / lich / demon / dark-lord の JSON マスターデータ作成・enemies_list.json に追加
  - **アンデッド特効（ヒーラー）**
    - `_get_valid_targets()` に is_undead=true の敵を追加（heal アクション時）
    - `_execute_heal()` でターゲットがアンデッドの場合は `character.heal()` ではなく `take_damage()` を呼ぶ（回復量をダメージとして適用）
  - **thunder_bullet 飛翔体**（デーモン専用）
    - `Projectile` に `_THUNDER_BULLET_PATH` 定数追加（`assets/images/projectiles/thunder_bullet.png`）
    - demon.json の `projectile_type: "thunder_bullet"` でキャラクター固有指定。画像なし時は紫色フォールバック
  - **炎陣（FlameCircle）のAI呼び出し対応**
    - `FlameCircle` を AI 側（DarkLordUnitAI）からも生成できるようスタティックメソッドまたはシグナル経由で map_node に追加できる設計に変更
    - dark-lord の攻撃アクションとして炎陣を使用
  - **ワープ移動（DarkLordUnitAI専用）**
    - `DarkLordUnitAI.gd` 新規作成
    - 3秒間隔（`game_speed` 除算）でランダムな空きタイルにワープ（`character.sync_position()` で瞬間移動）
    - ワープ直後に炎陣を設置する行動パターン
  - **リッチの交互魔法弾**
    - LichUnitAI が攻撃ごとに fire_bullet / water_bullet を交互に切り替えて発射
  - dungeon_handcrafted.json のフロア4ボス構成に dark-lord を追加
- [x] Phase 12-13: バグ修正・ダンジョン再構成
  - **dungeon_handcrafted.json を全面再生成（12部屋×4フロア＋ボス1部屋）**
    - フロア0〜3：12部屋（3列×4行・部屋サイズ10×8タイル）・階段3か所
    - フロア0：入口1・NPC4部屋（11名）・敵7部屋（ゴブリン中心・22体）
    - フロア1：ゴブリン＋アンデッド（zombie/skeleton/lich）混成・36体
    - フロア2：アンデッド＋狼＋ハーピー＋暗黒系・38体
    - フロア3：暗黒騎士団・デーモン・リッチ・サラマンダー・45体
    - フロア4：ボス1部屋（深淵の玉座）・dark-lord等6体（変更なし）
    - アイテム補正値はフロア深度に応じてスケール（フロア0: atk 2-5、フロア4: atk 15-22）
  - **アウトラインシェーダー復活**（`assets/shaders/outline.gdshader`）
    - ターゲット選択中の敵にシェーダーで白いアウトラインを描画
    - 8方向隣接サンプリングによるキャンバスアイテムシェーダー
    - `uniform bool outline_enabled`・`textureSize(TEXTURE, 0)` を使用
    - **注意**：canvas_item の `fragment()` 内では `return` 使用不可（Godot 4 制限）→ bool フラグ + 三項演算子（`?:`）で代替
    - `ShaderMaterial` は `_setup_sprite()` 時点で即生成（eager）。GDScript 側は `true`/`false` で渡す
  - **ターゲット選択時の射程オーバーレイ復活・方向フィルタ追加**（`game_map._draw()`）
    - ターゲット選択中に射程範囲を赤でオーバーレイ表示
    - melee: 前方±90°（dot ≥ 0.0）のマスのみ表示
    - ranged/heal/buff 系: 前方±45°（dot ≥ 0.707）のマスのみ表示
    - `_was_targeting: bool` フラグで選択モード切替時に `queue_redraw()` を発火
  - **ConsumableBar.DisplayMode パースエラー修正**
    - Godot 4 のパース順問題で `ConsumableBar.DisplayMode` が外部から参照できないエラー
    - `GlobalConstants` に `enum ConsumableDisplayMode { NORMAL, ITEM_SELECT, ACTION_SELECT, TRANSFER_SELECT }` を移動
    - `consumable_bar.gd` / `player_controller.gd` を `GlobalConstants.ConsumableDisplayMode.X` 参照に統一
  - **gitignore 修正**：`dungeon_generated.json` をgit追跡対象に変更（gitignoreから除外）
  - **ConsumableBar アイテム画像表示修正**
    - ダンジョン JSON のアイテム定義には `image` フィールドがないため、NORMAL モード・ITEM_SELECT モードの両方で `img_path` が空になっていた
    - `consumable_bar.gd` の両描画関数に `img_path` が空のとき `"assets/images/items/" + itype + ".png"` を導出するフォールバックを追加
    - `order_window.gd` の `_load_item_tex()` には既にフォールバックあり（変更不要）
  - **`assets/images/items/daggar.png` → `dagger.png` にリネーム**（typo修正）
- [x] Phase 12-14: ステータス統合・ガード改修・NPC会話UI刷新
  - **フィールド名統一**
    - `attack_power` / `magic_power` → `power`（物理クラスは物理威力・魔法クラスは魔法威力として共用）
    - `accuracy` → `skill`（物理技量/魔法技量として共用）
    - 敵 JSON 全16ファイル・クラス JSON・アイテム JSON・ダンジョン JSON の全 items.stats を一括変換
    - 参照箇所一括更新（player_controller / unit_ai / party_leader_ai / order_window / left_panel 等）
    - 旧キー（`attack_power`/`magic_power`）は `character_data.gd` でフォールバック互換を維持
  - **OrderWindow UI ラベル変更**
    - `power`: 物理クラス=「物理威力」、魔法クラス=「魔法威力」
    - `skill`: 物理クラス=「物理技量」、魔法クラス=「魔法技量」（heal クラスは非表示）
    - `defense_accuracy`: 「防御技量」
  - **「特殊スキル」→「特殊攻撃」全置換**（コード・UI・MessageLog）
  - **ガード防御改修**（`character.take_damage()` / `_calc_block_power_front_guard()`）
    - 正面攻撃（±45°）: 防御判定100%成功・防御強度分カット（旧 ×3 乗算廃止）
    - 側面・背面: 通常防御判定（変更なし）
  - **NPC会話トリガー変更**（`player_controller.gd`）
    - バンプ検出方式を廃止。移動方向ではなく A ボタンで隣接 NPC に話しかける方式に変更
    - `_find_adjacent_npc()` 追加・攻撃入力時に隣接 NPC チェックを挿入
    - 断られた NPC は `mark_refused()` で再申し出を永続停止（`NpcLeaderAI._was_refused` フラグ）
  - **NPC会話選択肢の刷新**（`npc_dialogue_window.gd`）
    - プレイヤー起点: 「仲間にする」「一緒に行く」「キャンセル」の3択（NPC 自発は現在無効）
    - 「仲間にする」→ CONFIRM 状態（「本当に仲間にしますか？」）経由で確定
    - 「一緒に行く」→ 直接 `choice_confirmed("join_them")` を発火
    - 会話UI開き直後2フレームの入力スキップ（ボタンリーク修正）
  - **「一緒に行く」合流処理修正**（`game_map._merge_player_into_npc_party()`）
    - 操作キャラ（hero）のハイライトを維持（NPC リーダーへの誤切り替えを防止）
    - `nm.set_joined_to_player(true)` 追加（NPC メンバーが hero を追従するように）
    - `player_controller.party_leader` を NPC リーダーに更新
    - `_switch_character()` の判定を `character.is_leader` ベースに変更（シンプル化）
- [x] Phase 12-15: ステータス生成システムの完成（設定ファイル方式・全ステータス0-100レンジ化）
  - **設定ファイル方式へ移行**（`CLASS_STAT_BASES` ハードコード定数を廃止）
    - `assets/master/stats/class_stats.json`：クラスごとの base / rank を定義
    - `assets/master/stats/attribute_stats.json`：sex / age / build 補正値・random_max を定義
    - `CharacterGenerator._load_stat_configs()` が初回呼び出し時にロード・静的キャッシュ
  - **ステータスキー追加**
    - `vitality`（0-100）→ `character_data.max_hp` に格納
    - `energy`（0-100）→ 魔法クラス（magician-fire / magician-water / healer）は `max_mp`、非魔法クラスは `max_sp` に格納
    - class_json の `"mp"` / `"max_sp"` フィールドは廃止（energy で代替）
  - **全ステータス 0-100 スケールに統一**（HP/MP/SP を含む全ステータスが同一スケール）
  - **CharacterGenerator に `MAGIC_CLASS_IDS` 定数追加**（energy の格納先判定）
  - **`move_speed` の変換**：0-100 スコア → `_convert_move_speed()` で秒/タイルに変換して格納
  - **`obedience` の変換**：0-100 整数スコア → `/ 100.0` で 0.0〜1.0 に変換して格納、表示は `× 100` で 0-100 整数に戻す
- [x] Phase 12-17: 敵ステータス生成システム実装（設定ファイル方式・0-100スケール化）
  - **`assets/master/stats/enemy_class_stats.json`** 新規作成：敵専用ステータスタイプ5種（zombie / wolf / salamander / harpy / dark-lord）の base / rank を定義
  - **`assets/master/stats/enemy_list.json`** 新規作成：全16敵種の `stat_type`（参照するステータステーブル）/ `rank`（デフォルトランク）/ `stat_bonus`（加算補正・100でクランプ）を定義
    - 人間クラスを流用する敵（goblin=fighter-axe、dark-knight=fighter-sword 等）は `class_stats.json` を参照
    - 敵専用タイプ（zombie / wolf / salamander / harpy / dark-lord）は `enemy_class_stats.json` を参照
    - アンデッド系（skeleton / skeleton-archer / lich）は `physical_resistance: 30` の stat_bonus で物理耐性を底上げ
  - **`character_generator.gd`** 変更
    - `ENEMY_CLASS_STATS_JSON_PATH` / `ENEMY_LIST_JSON_PATH` 定数追加
    - `_enemy_list_cache` / `_enemy_list_loaded` 静的変数追加
    - `_load_stat_configs()` に enemy_class_stats.json のロード＋`_class_stats_cache` へのマージを追加（`_calc_stats()` が人間クラス・敵専用タイプ両方を参照できるように）
    - `_load_enemy_list()` 追加（enemy_list.json の遅延ロード）
    - `apply_enemy_stats(data)` 追加：enemy_list.json を参照して stat_type/rank/stat_bonus を取得 → `_calc_stats()` でステータス生成 → データに格納。敵は energy → max_sp（MP/SP区別なし）
  - **`party_manager._spawn_member()`**：`apply_enemy_graphics()` の直後に `apply_enemy_stats()` を追加
- [x] Phase 12-16: クリティカルヒット実装
  - **判定ロジック**（`character.gd` の `take_damage()`）
    - クリティカル率 = 攻撃側の `skill ÷ 3`%（例: skill=30 → 10%、skill=60 → 20%）
    - クリティカル時: `multiplier *= 2.0`（ダメージ2倍）
    - MessageLog へのメッセージ通知なし
  - **エフェクト**：クリティカル時は `_spawn_hit_effect(actual)` を2回呼んで二重エフェクトで強調
  - **SE・グラフィック**：既存の HitEffect / SE をそのまま流用
- [x] Phase 12-18: バグ修正（フロア遷移クラッシュ・敵未起動・キャラ切替・アウトライン）
  - **NPC フロア遷移時の freed hero クラッシュ（`game_map.gd`）**
    - `_transition_npc_floor()` で hero が死亡済み（freed）の状態で `dialogue_trigger.setup(hero, ...)` を呼ぶとクラッシュ
    - 修正：`is_instance_valid(hero)` チェックを追加してから setup を呼ぶ
  - **`party.members` の freed キャラへの as キャストクラッシュ（`game_map.gd`）**
    - 死亡したキャラクターが `party.members` に残留し、`as Character` キャストでクラッシュ
    - 修正：ループを `for member_var: Variant` に変更し、`is_instance_valid()` チェックを先に実施（4箇所）
  - **フロア遷移後の敵が動かない問題（`game_map.gd`）**
    - `_link_all_character_lists()` が起動時にしか呼ばれず、新フロアの EnemyManager が `set_friendly_list()` を受け取れないため WAIT のまま
    - 修正：`_transition_floor()` 内で `_link_all_character_lists()` を呼ぶ
  - **`VisionSystem._process` で freed な party メンバーへの as キャストクラッシュ（`vision_system.gd`）**
    - 死亡キャラが `_party.members` に残り、VisionSystem の3か所でクラッシュ
    - 修正：`for m: Variant in _party.members` ＋ `is_instance_valid(m)` チェックを3箇所に追加
  - **LB/RB キャラ切り替えが2人目操作後に効かなくなる問題（`player_controller.gd`）**
    - `_switch_character()` が `character.is_leader`（現在操作キャラのリーダーフラグ）を判定していたため、非リーダーキャラに切り替えると以降全切り替えが不可に
    - 修正：`player_is_leader: bool = true` フラグを追加し、NPC パーティーに合流してリーダーを譲った場合のみ `false` に設定する方式に変更
    - `_merge_player_into_npc_party()` で `player_controller.player_is_leader = false` をセット
  - **攻撃キャンセル後にアウトラインが操作キャラに残るバグ（`player_controller.gd`）**
    - `_exit_targeting()` の末尾で `character.set_outline(Color.WHITE, 1.0)` を呼んでいたが、操作キャラは元々アウトラインなしのデザインのため、キャンセルのたびに白アウトラインが付与されていた
    - あわせて `_exit_targeting()` / `_confirm_target()` のアウトラインクリアを `Character._all_chars`（全キャラ静的レジストリ）の走査に変更し、`_valid_targets` から漏れたアウトラインも確実に除去
    - 修正：不要な `character.set_outline(Color.WHITE, 1.0)` 呼び出しを削除
- [x] Phase 12-19: バグ修正（装備仕様統一・回復AI・シェーダー・freed キャスト）
  - **装備補正値を新仕様に統一（`dungeon_handcrafted.json`）**
    - 初期装備（プレイヤー・NPC）を全補正値0に変更
    - 武器の `skill` 補正を廃止。`character.gd` の `refresh_stats_from_equipment()` から skill 加算を削除
    - `order_window.gd` の skill 行の装備補正表示を 0 固定に変更
    - 全装備を仕様準拠の stats キーに更新（block_right_front/block_front/block_left_front/physical_resistance/magic_resistance）
    - 最深層（フロア4）の敵パーティーからアイテムを削除（クリア直結のため不要）
  - **敵ヒーラーがプレイヤーを回復するバグ（`unit_ai.gd`）**
    - `_find_heal_target()` / `_find_buff_target()` が `is_friendly == true` でフィルタしていたため、敵ヒーラーが hero を回復対象にしていた
    - 修正：`ch.is_friendly != my_friendly` に変更し、同じ陣営のキャラのみを対象にする
  - **回復スキルを持たない敵が回復行動を生成するバグ（`unit_ai.gd`）**
    - `_generate_heal_queue()` に `heal_mp_cost <= 0` のガードがなく、ゴブリン等（heal_mp_cost=0）が回復行動を実行していた
    - 修正：`cost <= 0` の場合は早期リターンを追加（`_generate_buff_queue()` と同じ形式）
  - **アウトラインシェーダーが modulate（HP色変化）を無視するバグ（`outline.gdshader`）**
    - `COLOR = texture(TEXTURE, UV)` で生テクスチャ色を書き込み、Godot が渡す modulate を上書きしていた
    - 修正：`COLOR`（modulate 情報）を保持し、テクスチャ色に乗算するよう変更
  - **hero 死亡後のフロア初期化クラッシュ（`game_map.gd`）**
    - NPC/仲間のフロア遷移時に hero が freed の状態で `_setup_floor_enemies()` → `em.setup(members, hero, ...)` が呼ばれクラッシュ
    - 修正：`_setup_floor_enemies()` / `_setup_floor_npcs()` の先頭に `is_instance_valid(hero)` ガードを追加
  - **`party.sorted_members()` の freed キャラへの as キャストクラッシュ（`party.gd`）**
    - 死亡キャラが `members` に残留し、`m as Character` でクラッシュ
    - 修正：キャスト前に `is_instance_valid(m)` チェックを追加
  - **古い敵画像フォルダ（3/30 作成・22フォルダ）を削除**
    - コード・マスターデータから未参照の旧画像を整理。新画像（4/7 作成・16種）のみ残す
- [x] Phase 13: タイトル・セーブ・メニューシステム
  - [x] **セーブシステム基盤**
    - `scripts/save_data.gd`（class_name SaveData）：slot_index / exists / hero_name_male / hero_name_female / current_floor / clear_count / playtime / to_dict() / from_dict() / format_playtime()
    - `scripts/save_manager.gd`（Autoload: SaveManager）：get_save_data() / write_save() / has_any_save() / start_session() / get_active_save() / flush_playtime() / update_floor() / record_clear()
    - `project.godot`：SaveManager を autoload に追加
  - [x] **タイトル画面**（`scripts/title_screen.gd` / `scenes/title_screen.tscn`）
    - 背景画像（assets/images/ui/title_bg.png、なければグラデーションフォールバック）
    - "Rally the Parties" ゴールド文字＋サブタイトル「リアルタイムタクティクスRPG」
    - "Press any button / key" 点滅（0.55s間隔）
    - 任意キー/ボタン押下 → main_menu.tscn へ遷移
    - `project.godot` メインシーンを game_map.tscn → title_screen.tscn に変更
  - [x] **メインメニュー**（`scripts/main_menu.gd` / `scenes/main_menu.tscn`）
    - 状態機械：MAIN / SLOT_SELECT_NEW / OVERWRITE_CONFIRM / NAME_INPUT / SLOT_SELECT_CONT / OPTIONS
    - 「続きから始める」はセーブがある場合のみ表示
    - セーブスロット3枠：フロア・クリア回数・プレイ時間・主人公名を表示
    - 上書き確認ダイアログ
    - 名前入力（LineEdit ×2：男性名・女性名）。空白時はランダム生成（character_name はゲーム開始後に適用）
    - オプション画面：音量（←→）・ゲーム速度（←→）・主人公名（表示のみ）・ゲーム終了・← 戻る
  - [x] **ポーズメニュー**（`scripts/pause_menu.gd`）
    - `process_mode = PROCESS_MODE_ALWAYS`・`get_tree().paused = true/false`
    - Startボタン（JOY_BUTTON_START）でトグル開閉（open のみ PROCESS_MODE_ALWAYS で処理）
    - 状態機械：MAIN / OPTIONS / RETURN_CONFIRM
    - 項目：オプション・タイトルへ戻る（確認あり・flush_playtime() 後に title_screen.tscn へ遷移）・ゲームに戻る
    - オプション：音量・ゲーム速度（ゲーム終了は表示しない）
  - [x] **game_map.gd 修正**
    - `_setup_hero()` 後に SaveManager.get_active_save() から性別に応じた主人公名を character_data.character_name に適用
    - `_trigger_game_clear()` で SaveManager.record_clear() を呼ぶ
    - `_transition_floor()` で SaveManager.update_floor(new_floor) を呼ぶ
    - `_input()` の KEY_ESCAPE をポーズメニュー開閉に変更（旧 get_tree().quit() を廃止）
    - `_setup_pause_menu()` で PauseMenu をインスタンス化・add_child
  - [x] **SoundManager.set_volume()** 追加（linear_to_db 変換して Master バスに適用）
- [ ] Phase 14: Steam配布準備

## 装備システム

### 装備種類と補正パラメータ

| 装備 | 威力 | 右手防御強度 | 左手防御強度 | 両手防御強度 | 物理耐性 | 魔法耐性 |
|------|------|------------|------------|------------|---------|---------|
| 剣・斧・短剣 | 0〜30 | 0〜30 | — | — | — | — |
| 弓・杖 | 0〜30 | — | — | 0〜30 | — | — |
| 盾 | — | — | 0〜30 | — | — | — |
| 鎧 | — | — | — | — | 0〜30 | 0〜15 |
| 服 | — | — | — | — | 0〜15 | 0〜15 |
| ローブ | — | — | — | — | 0〜15 | 0〜30 |

- 射程補正は将来実装予定（弓・杖に追加予定）
- 空白のパラメータは補正対象外
- 補正対象の各パラメータは独立してランダムに決定する（0〜上限値の連続値）

### 装備の名前生成
- 補正値を決定した後、その特徴を反映した名前をClaude Codeがマップ生成時に付ける
- 命名の基準：
  - 威力が防御強度の2倍以上 → 攻撃系の名前（例：「鋭利な剣」「業物」）
  - 防御強度が威力の2倍以上 → 防御系の名前（例：「守りの剣」「頑丈な剣」）
  - それ以外 → バランス系の名前（例：「均整の剣」「騎士の剣」）
  - 防具は物理耐性と魔法耐性の比率で同様に命名
- 名前と補正値は両方プレイヤーに表示する

### 装備の生成タイミングと強さ
- 敵配置時に装備を生成・確定する
- 敵パーティーの強さ（フロア深度・敵ランク）に応じて補正値の期待値が上がる

## アイテムシステム

### 装備品
| カテゴリ | 種類 |
|---------|------|
| 武器 | 剣・斧・弓・ダガー・杖 |
| 防具 | 鎧・服・ローブ・盾 |

### クラスと装備の対応
| クラス | 武器 | 防具 | 盾 |
|--------|------|------|-----|
| 剣士 | 剣 | 鎧 | ○ |
| 斧戦士 | 斧 | 鎧 | ○ |
| 弓使い | 弓 | 服 | ✕ |
| 斥候 | ダガー | 服 | ✕ |
| 魔法使い(火) | 杖 | ローブ | ✕ |
| 魔法使い(水) | 杖 | ローブ | ✕ |
| ヒーラー | 杖 | ローブ | ✕ |

- 戦士クラス（剣士・斧戦士）は盾を左手に持つ（グラフィック統一）
- 杖は魔法使い・ヒーラーで共用。`power` として魔法攻撃力・回復力の両方に効く

### アイテム所持の仕組み
- アイテムはキャラクター個人が所持する（パーティー単位のインベントリではない）
- 各アイテムは「装備中」と「未装備」の2状態を持つ
- 装備スロット：武器1 / 防具1 / 盾1（戦士クラスのみ）の3スロット
- **装備は外せない**（別アイテムで上書きのみ）。上書き時、旧装備は未装備品としてそのキャラの手元に残る
- OrderWindow 下部：装備スロット欄に装備中アイテムを表示、所持アイテム一覧に未装備品と消耗品のみ表示（重複表示しない）
- 未装備品はリーダー権限でパーティー内の他キャラに受け渡し可能

### 初期装備
- `dungeon_handcrafted.json` の `player_party` / `npc_parties` メンバーに `items` フィールドで初期装備を記述する
- 各クラスに応じた装備を持たせる（fighter-sword: 剣+鎧+盾、fighter-axe: 斧+鎧+盾、archer: 弓+服、scout: ダガー+服、magician-fire: 杖+ローブ、healer: 杖+ローブ）
- 初期装備は弱め（各補正値1〜3程度）
- 敵ドロップ品は部屋の奥に行くほど強くなる

### 装備の補正値
- **武器（剣・斧・短剣）**：`power`・`block_right_front` を補正
- **武器（弓・杖）**：`power`・`block_front` を補正（射程補正は将来実装）
- **盾**：`block_left_front` を補正
- **防具（鎧）**：`physical_resistance`（0〜30）・`magic_resistance`（0〜15）を補正
- **防具（服）**：`physical_resistance`（0〜15）・`magic_resistance`（0〜15）を補正
- **防具（ローブ）**：`physical_resistance`（0〜15）・`magic_resistance`（0〜30）を補正
- 補正がかからないもの：defense_accuracy（防御技量）・move_speed・leadership・obedience・max_hp・max_mp

### ダメージ計算への装備補正反映
- 物理威力／魔法威力 = キャラ素値 + 武器 power
- 物理耐性  = キャラ素値 + 防具 physical_resistance
- 魔法耐性  = キャラ素値 + 防具 magic_resistance
- 右手防御強度 = キャラ素値（block_right_front）+ 武器 block_right_front（剣・斧・短剣のみ）
- 左手防御強度 = キャラ素値（block_left_front）+ 盾 block_left_front
- 両手防御強度 = キャラ素値（block_front）+ 武器 block_front（弓・杖のみ）
- OrderWindow のステータス表示：保有または装備補正がある防御強度フィールドのみ「右手防御強度」「左手防御強度」「両手防御強度」として表示（素値・補正値の2列）

### アイテム生成
- 補正値はランダム生成（フロア深度に応じた範囲内）
- 名前はClaude Codeがダンジョン生成時に補正値の強さ・フロア深度を考慮して作成
- グレードフィールドは持たない（補正値の強さがグレードを表す）
- アイテムマスターは `assets/master/items/` に種類ごとに定義

### 敵キャラクターとアイテムの関係
- 敵は装備の概念を持たない（現状のステータスがそのまま戦闘能力）
- 敵パーティーの所持アイテムはドロップ用にパーティー単位で保持するのみ

### アイテムのドロップ（部屋制圧方式）
- 部屋に配置された enemy_party の全員が**死亡 or その部屋から離脱**したら「制圧完了」
- 制圧時、敵パーティーの所持アイテムが**部屋の床タイルにランダムに散らばる**（1マスに1個）
- 出現は1回きり（敵が戻っても再出現しない）
- item_get 効果音を再生、メッセージウィンドウに通知（例：「アイテムが散らばった！」）
- 表示：アイテム種類別アイコン（`assets/images/items/{item_type}.png`。画像なし時は黄色マーカーにフォールバック）
- **取得方法**：同じマスに移動したら自動取得。拾ったキャラ個人の inventory に未装備品として入る
- プレイヤー操作キャラはフィルタなし（踏めば何でも拾う）
- AIキャラは item_pickup 指示に従う（指示システム節を参照）
- 敵パーティーの所持アイテムはClaude Codeがダンジョン生成時に種族構成を考慮して割り当て
- 複数パーティーによる協力撃破の分配は将来実装

### 消耗品
- HP回復ポーション・MP回復ポーション
- C/X短押しでフィールドからアイテム選択UIを開いて使用（ウィンドウ不要）
- 固定スロット管理なし。inventory内のアイテムを一覧表示（消耗品はグループ化）
- LB/RB（通常時）：パーティーメンバーを表示順で循環切り替え
- LB/RB（アイテムUI中）：アイテムカーソル循環
- LB/RB（TARGETING中）：ターゲット循環
- 左パネルのアクティブキャラ欄に `[C] アイテム名` を常時表示

## 戦闘仕様

### 視界システム
- Phase 5で部屋単位に実装済み
  - 現在いる部屋の敵のみ見える・アクティブ化（VisionSystem.gd）
  - 通路では敵が非表示（CORRIDORタイルにはエリアIDなし）
  - 部屋に入った瞬間に敵がアクティブ化、メッセージウィンドウに通知
- 将来：通常時は前方のみ、警戒時（攻撃を受けた・仲間がやられたなど）は全方位
- 不意打ちなどの演出に活用予定

### 情報管理
- 敵はパーティー単位で情報を共有（個別管理ではない）

### HP・状態
- 当面：敵味方ともに正確な数値を共有
- 将来：視界内の敵は大まかな状態のみ（healthy／wounded／critical）

### キャラクターステータス
| ステータス | フィールド名（実装） | 説明 |
|-----------|-------------------|------|
| HP | `max_hp` / `hp` | ヒットポイント |
| MP | `max_mp` / `mp` | マジックポイント。魔法クラス（magician-fire/magician-water/healer）専用 |
| SP | `max_sp` / `sp` | スタミナポイント。非魔法クラス（fighter-sword/fighter-axe/archer/scout）専用 |
| 物理威力／魔法威力 | `power` | 攻撃ダメージ・回復量の共通値。UI表示ラベルはクラスに応じて「物理威力」（物理クラス）または「魔法威力」（魔法クラス）に切り替え |
| 物理技量／魔法技量 | `skill` | 命中精度・クリティカル率の基礎値。UI表示ラベルはクラスに応じて「物理技量」または「魔法技量」に切り替え |
| 物理攻撃耐性 | `physical_resistance` | 物理ダメージ軽減の能力値（整数）。軽減率 = 値/(値+100)。クラスごとに素値を設定＋装備補正 |
| 魔法攻撃耐性 | `magic_resistance` | 魔法ダメージ軽減の能力値（整数）。軽減率 = 値/(値+100)。クラスごとに素値を設定＋装備補正 |
| 防御技量 | `defense_accuracy` | 防御判定の成功しやすさ。キャラ固有の素値（装備による変化なし） |
| 防御強度 | `block_right_front` / `block_left_front` / `block_front` | 防御成功時に無効化できるダメージ量。クラス固有値（装備補正なし）。方向別に3フィールド。OrderWindowで保有フィールドのみ「右手防御強度」「左手防御強度」「両手防御強度」として表示 |
| 移動速度 | `move_speed` | 単位：秒/タイル（標準0.4） |
| 統率力（leadership） | `leadership` | リーダー側。クラス・ランクから算出して確定後不変。当面は値のみ保持 |
| 従順度（obedience） | `obedience` | 個体側（0.0〜1.0）。クラス・種族・ランクから算出して確定後不変。当面は値のみ保持 |
| 即死耐性 | `instant_death_immune` | bool。デフォルト false。ボス級は true（ヘッドショット無効・無力化水魔法短縮） |
| アンデッド | `is_undead` | bool。デフォルト false。skeleton / skeleton-archer / lich が true。ヒーラーの回復魔法が特効（回復量をダメージとして適用）。物理耐性極高・魔法はある程度有効 |
| 巻き添え | `friendly_fire` | bool。デフォルト false（将来実装。範囲攻撃が味方・他パーティーにも当たる仕様） |

- 魔法命中精度は `skill` と共通（`power` 系は攻撃・回復とも同じ命中扱い）
- 回復魔法は必ず命中するため、ヒーラー（attack_type="heal"）には OrderWindow の魔法技量行を表示しない
- 耐性素値はクラスごとに設定（例：戦士クラスは物理耐性高め、魔法使いは魔法耐性高め）
- 耐性はステータス決定構造の加算式で決定（他のステータスと同じフロー）
- 軽減方式：逓減カーブ（軽減率 = 能力値 / (能力値 + 100)。100で50%、200で67%）
- OrderWindow では数値のみ表示（%表記はしない）

### MP/SPシステム
- **魔法クラス**（`magician-fire` / `magician-water` / `healer`）：`mp` / `max_mp` を使用
- **非魔法クラス**（`fighter-sword` / `fighter-axe` / `archer` / `scout`）：`sp` / `max_sp` を使用
- バー表示（左パネル）：MPは濃い青・SPは水色系。それぞれのクラスで対応するバーのみ表示
- 通常攻撃（Z）：全クラス微量消費（自動回復と相殺される程度）
- 特殊攻撃（V）：魔法クラスはMP消費大・非魔法クラスはSP消費大
- ヒーラーのZ（回復）はMP消費大（例外扱い）
- 自動回復：MP・SP ともに時間経過でゆっくり回復
- 回復アイテム：MPポーション（魔法クラス用）・SPポーション（非魔法クラス用）に分離
- 敵キャラクターは当面 SP/MP システムを持たない（AI の行動クールタイムで代替）

### 命中・被ダメージ計算

**着弾判定**（命中精度）：攻撃が狙った対象に向かうか。`skill` が低いと別の敵・味方に誤射する可能性。

**攻撃タイプ別ダメージ倍率**（`GlobalConstants.ATTACK_TYPE_MULT`）:
- melee: × 0.5
- ranged: × 0.2
- dive: × 0.5
- magic: × 0.2
- ベースダメージ = `power × type_mult × damage_mult`（damage_mult はスロット定義値。通常攻撃は 1.0）

**クリティカルヒット**:
- クリティカル率 = skill ÷ 3 %（例: skill=30 → 10%、skill=60 → 20%）
- クリティカル時: ベースダメージ × 2.0（power ステータス自体は変化しない）
- エフェクト・SE は既存アセット流用（HitEffect + hit_physical/hit_magic SE）

**被ダメージ計算フロー**（着弾後）:
1. **ベースダメージ算出**（`power × type_mult × damage_mult`）
2. **クリティカル判定**（skill からクリティカル率を算出。クリティカル時はベースダメージ × 2.0）
3. **防御判定**（3フィールド方式。各フィールドは独立してロール。背面攻撃は常にスキップ）
   - `block_right_front`：正面・右側面で有効　`block_left_front`：正面・左側面で有効　`block_front`：正面のみ有効
   - 成功したフィールドの合計値をダメージからカット
4. **耐性適用**（物理 or 魔法耐性の能力値から軽減率を算出して軽減。軽減率 = 能力値 / (能力値 + 100)）
   - 残ダメージ × (1 - 耐性%)
5. **最終ダメージ確定**（最低1）

**防御強度フィールドと有効方向**:

| フィールド | 有効方向 | 保有クラス例 |
|-----------|---------|------------|
| `block_right_front` | 正面・右側面 | 剣士・斧戦士・斥候・ハーピー・ダークロード |
| `block_left_front`  | 正面・左側面 | 剣士・斧戦士・ハーピー・ダークロード |
| `block_front`       | 正面のみ   | 弓使い・魔法使い・ヒーラー・ゾンビ・ウルフ・サラマンダー |

- 各フィールドは独立して `defense_accuracy` でロール（パーセント成功判定）
- 成功したフィールドの値の合計をダメージからカット
- 背面攻撃は常にすべてのフィールドをスキップ
- ガード中の正面攻撃：判定100%成功・全フィールドの合計をカット
- 方向判定ロジック：防御側の向き（facing）を基準に、攻撃者の相対位置から atan2 で角度を計算し4象限（90°ずつ）で判定
  - 正面 ±45° → 正面、背面 ±45° → 背面、それ以外 → 左側面 or 右側面
  - 近接攻撃・遠距離攻撃で共通のロジックを使用
- ダメージの方向倍率（旧1.0/1.5/2.0倍）は廃止。攻撃方向は防御可否のみに影響する

### 飛行キャラクター
- キャラクターデータに `is_flying` フラグを追加
- WALL・OBSTACLE・地上キャラ占有タイルを通過可能（飛行同士はブロックし合う）
- 攻撃の可否（攻撃タイプ別）

| 攻撃側 \ 対象 | 地上 | 飛行 |
|-------------|------|------|
| melee（地上） | 可 | 不可 |
| melee（飛行） | 不可 | 不可 |
| ranged | 可 | 可 |
| dive（飛行→地上） | 可 | — |

- 遠距離攻撃（ranged）：双方向で有効
- 降下攻撃（dive）：飛行キャラが地上の隣接対象のみ攻撃可。攻撃中も飛行扱いを維持

### 敵キャラクター一覧
| 敵 | 攻撃タイプ | 特徴 |
|----|-----------|------|
| ゴブリン | 近接 | 集団行動。臆病で強い相手からすぐ逃げる |
| ホブゴブリン | 近接 | ゴブリンの強化版。数体を手下にする。狂暴で攻撃的 |
| ゴブリンアーチャー | 遠距離（弓） | 遠距離から弓で攻撃 |
| ゴブリンメイジ | 遠距離（魔法） | 遠距離から魔法で攻撃 |
| ゾンビ | 近接（つかみ） | 低速。近くの人間に向かってくる |
| ウルフ | 近接（かみつき＝つかみ効果） | 集団行動。高速移動 |
| ハーピー | 降下（dive） | 飛行（WALL・OBSTACLE・地上キャラを無視して移動）。飛行中は地上からの近接攻撃を受けない。地上の敵に隣接して降下攻撃を行う（攻撃中も飛行扱いを維持） |
| サラマンダー | 遠距離（炎＝魔法効果） | 遠距離から火を吐く |
| ダークナイト | 近接 | 人間型の強敵 |
| ダークメイジ | 遠距離（魔法） | 人間型。後方から魔法攻撃 |
| ダークプリースト | 支援（回復・バリア） | 人間型。後方で仲間を回復・強化 |
| スケルトン | 近接 | アンデッド（is_undead=true）。physical_resistance極高で物理攻撃ほぼ無効・魔法はある程度有効・ヒーラーの回復魔法が特効 |
| スケルトンアーチャー | 遠距離（弓） | アンデッド（is_undead=true）。スケルトンと同じ耐性特性。遠距離から弓で攻撃 |
| リッチ | 遠距離（魔法・火水交互） | アンデッド（is_undead=true）。火弾と水弾を交互に放つ。スケルトンと同じ耐性特性 |
| デーモン | 遠距離（魔法・thunder_bullet） | 飛行（is_flying=true）。雷属性魔法弾を使う強敵 |
| 魔王（ダークロード） | 遠距離（炎陣・範囲）＋ワープ移動 | ラスボス専用（フロア4のみ）。instant_death_immune=true。3秒間隔（game_speed除算）でランダムワープ移動。炎陣をAI側から呼び出して範囲攻撃 |

### 攻撃仕様
- 攻撃タイプ（CharacterData.attack_type）
  - melee（近接）: 隣接した地上の敵を攻撃。カウンター有効。飛行→飛行NG、地上→飛行NG
  - ranged（遠距離）: 射程内の全対象に飛翔体で攻撃。カウンター無効
  - dive（降下）: 飛行キャラが地上の隣接対象に降下攻撃。カウンター有効
- 種類：単体（当面。将来は範囲も追加）
- 属性タイプ：physical／magic（当面はphysicalのみ）
- クールタイム：事前（ため・詠唱）・事後（硬直）の両方あり
- キャラクターデータにpre_delay・post_delayとして持つ

### 攻撃フロー（PRE_DELAY → TARGETING → POST_DELAY）
- Z/A **短押し** → PRE_DELAY モードへ（pre_delay 消化中は時間進行・ターゲット候補を表示）
- PRE_DELAY 完了後 TARGETING モードへ自動遷移（時間停止・LB/RB または矢印キーで循環選択）
- TARGETING 中に Z/A → 射程チェック → 攻撃実行 → POST_DELAY（硬直・時間進行）→ NORMAL
- TARGETING 中に X/B → ノーコストキャンセル → NORMAL（時間停止に戻る）
- V スロットのターゲット系（headshot/water_stun/buff_defense）も同フロー（V キーで起動）
- pre_delay 中にターゲットが射程外に逃げても TARGETING で自動キャンセル（空振りなし）

### 方向と防御
- 攻撃方向によるダメージ倍率は廃止。方向は防御判定の可否にのみ影響する（詳細は「命中・被ダメージ計算」節を参照）

### LLMへ渡すデータ構造（参考仕様・未使用）
> **注意**: Phase 2-3 でルールベースAIに移行済み。以下は当初設計の参考仕様として残す。

```json
{
  "party": {
    "members": [
      {
        "id": "goblin_1",
        "position": {"x": 10, "y": 5},
        "facing": "left",
        "hp": 30,
        "condition": "healthy",
        "status": "ready"
      }
    ]
  },
  "visible_characters": [
    {
      "type": "player",
      "position": {"x": 5, "y": 3},
      "facing": "right",
      "hp": 80,
      "condition": "healthy"
    }
  ],
  "current_actions": { },
  "remaining_queue": [ ]
}
```

### LLMの返答形式（参考仕様・未使用）
> **注意**: Phase 2-3 でルールベースAIに移行済み。以下は当初設計の参考仕様として残す。

- パーティー単位で行動シーケンスを返す
- 移動は絶対座標ではなく目標キャラクターへの相対位置で指定
```json
{
  "actions": [
    {
      "id": "goblin_1",
      "sequence": [
        { "action": "move", "target": "player", "relative_position": "right_side" },
        { "action": "attack", "target": "player", "attack_type": "physical" },
        { "action": "move", "target": "player", "relative_position": "up_side" }
      ]
    }
  ]
}
```
- relative_positionの種類：down_side／up_side／left_side／right_side／adjacent

### LLM呼び出し方針（参考仕様・未使用）
> **注意**: Phase 2-3 でルールベースAIに移行済み。以下は当初設計の参考仕様として残す。

- LLMは非同期で常に動かし続ける
- キューが残り少なくなったタイミングでリクエスト送信
- 返ってきたシーケンスは既存キューと実行中アクションを即座に置き換えて開始する（追加方式ではなく置き換え方式）
- moveアクションの目標座標は毎タイル移動後に再計算してターゲットを追従する
- 攻撃を受けたなど状況が大きく変わった場合は強制再生成（`notify_situation_changed()`、現在は未接続）
- LLMには現在の状況に加えて実行中・キュー残りのアクションも渡す

## リポジトリ
- GitHub: https://github.com/komuro72/trpg
- ブランチ: master

## 作業ルール
- セッション終了時（「今日はここまで」など）にコミットを依頼された場合は、`git commit` に加えて `git push` まで行う
  - 理由：毎日新しいセッションで作業しており、別PCで作業再開することもあるため
- **画像ファイルを追加・更新したら、必ずその都度コミット＋プッシュまで行う**
  - 理由：画像はバイナリファイルのため差分が見えにくく、別PCで作業再開したときに古いままになりやすい
  - 対象：`assets/images/` 配下の全ファイル（キャラクター・敵・タイル・UI・飛翔体・エフェクトなど）
  - `.import` ファイルも一緒にコミットする（Godot がリソース解決に使用するため）
- Claude Code が新規ファイル・新規ディレクトリを作成した場合は、必ずコミット時に `git add` でステージングする
  - 対象：スクリプト（.gd）・シェーダー（.gdshader）・JSON・画像・シーン（.tscn）など Claude Code が作成した全ファイル
  - Godot が自動生成する `.import` / `.uid` ファイルはコミット不要（`.gitignore` 対象外だが追跡しない）
  - 新規ディレクトリ配下のファイルは `git status` で untracked になるため見落としやすい。意識的に確認する

## GDScript 警告の運用方針
- `warnings/inference_on_variant=1`（project.godot に設定済み）により、Variant 推論警告はエラー扱いせず警告として表示する
- 警告はビルドを通すが、放置はしない。コミットの節目に以下のコマンドで一覧を確認し、まとめて修正する：
  ```
  godot --headless --check-only 2>&1
  ```
- 典型的な修正パターン：`:=` による型推論 → `var x: 型 =` または戻り値に `as 型` を付けて明示

## 将来実装項目（未フェーズ）
- お金の概念・商店：アイテムシステム完成後に改めて設計
- 複数パーティーによるアイテム分配：現在は部屋制圧時にフィールドに散らばったアイテムを早い者勝ちで取得
- BGM
- 巻き添え（`friendly_fire`）：範囲攻撃（炎陣など）が味方・他パーティーにも当たる仕様。`CharacterData.friendly_fire: bool`（当面 false 固定）で管理し、将来切り替え可能にする
- 大型ボスの即死耐性設計：`instant_death_immune: bool`（ボス級は true）。ヘッドショット無効・無力化水魔法持続短縮。敵 JSON でフラグを設定できる設計にする

## 参照ファイル
- docs/spec.md：詳細仕様書（実装前に参照すること）
