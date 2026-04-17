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
- **assets/master/classes/**：クラスのマスターデータ（JSON）
  - 人間系 7 クラス：`fighter-sword.json` / `fighter-axe.json` / `archer.json` / `magician-fire.json` / `magician-water.json` / `healer.json` / `scout.json`
  - 敵固有 5 クラス：`zombie.json` / `wolf.json` / `salamander.json` / `harpy.json` / `dark-lord.json`
  - クラス JSON には `attack_type` / `attack_range` / `is_flying` / `slots.Z` / `slots.V`（pre_delay・post_delay・damage_mult・mp_cost 等）などの「クラスで決まる項目」を集約する
- assets/master/enemies/：敵個体ごとのマスターデータ（JSON、16 種）
  - **個体固有項目のみ**: `id` / `name` / `is_undead` / `is_flying` / `instant_death_immune` / `chase_range` / `territory_range` / `behavior_description` / `projectile_type` / `sprites`
  - クラス項目（`attack_type` / `pre_delay` / `post_delay` 等）は個別 JSON には持たない。クラス JSON から起動時に注入する
  - `hp` / `power` / `skill` 等の直書きステータスは legacy（`apply_enemy_stats()` で上書きされる）
- assets/master/enemies/enemies_list.json：読み込む敵ファイルのパス一覧
- assets/master/stats/class_stats.json：人間クラスのステータス定義
- assets/master/stats/enemy_class_stats.json：敵固有クラスのステータス定義
- assets/master/stats/attribute_stats.json：性別・年齢・体格の補正値・random_max
- assets/master/stats/enemy_list.json：敵 ID → `{stat_type, rank, stat_bonus}` のマッピング
- assets/master/maps/：マップデータ（JSON、マップごとにファイルを分ける）
- assets/master/names.json：名前ストック（性別ごと）
- assets/images/characters/：味方キャラクターの画像（{class}_{sex}_{age}_{build}_{id}/ フォルダ構成）
- assets/images/enemies/：敵キャラクターの画像
- assets/images/items/：アイテム画像（potion_hp.png, potion_mp.png 等）
- assets/images/effects/：エフェクト画像（飛翔体: arrow.png, fire_bullet.png 等 / 渦: whirlpool.png）
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
| DebugWindowの表示/非表示 | F1 | — | 画面中央にデバッグウィンドウをトグル表示（ゲーム進行継続） |
| デバッグ情報コンソール出力 | F2 | — | キャラ・フロア・占有タイル情報を user://debug_floor_info.txt に書き出し |
| ConfigEditor の表示/非表示 | F4 | — | 定数管理UI。タイトル画面・ゲーム中の両方で起動可。ゲーム中は時間停止 |
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

### デバッグウィンドウ（DebugWindow）
- F1 キーで画面中央に表示/非表示トグル。ゲームは進行継続
- 画面幅70%・高さ80%（**背景パネルなし・完全透過**。CanvasLayer layer=15）
- **上半分（55%）**：現在フロアの全パーティー状態をリアルタイム表示（0.2秒ごとに更新）
  - 表示対象：プレイヤーパーティー（青系）→ NPCパーティー（緑系）→ 敵パーティー（赤系）の順
  - 表示条件: いずれか1人が表示フロアにいるパーティーを表示。別フロアのメンバーは名前頭に `[Fx]` を付加
  - 各パーティー：[種別] リーダー名(クラス)  生存:x/y  戦況:xxx 戦力:xx(my/enemy) HP:xx mv=... battle=... ...
  - 各メンバー：★操作中  名前(クラス)[ランク]  HP:x/y  [スタン][ガード]
  - メンバー個別指示概要（battle_formation/combat/target または heal）
  - **メンバーの行動目的（goal）行**: `→DOWN階段(15,3)` / `→攻撃Goblin` / `L追従(DOWN/キュー空/WAIT)` / `[cluster]キュー空(IDLE)` 等。末尾に `_state` ラベル併記（IDLE/MOV/WAIT/ATKp/ATKpost）
  - HP比率で色分け：50%超=白、25-50%=黄、25%以下=赤
  - **上下キーでリーダー行を循環選択**（DebugWindow表示中のみ有効・入力は伝播しない。敵・NPC・プレイヤーの全リーダーが対象）
  - 選択中リーダー行は黄色「▶」マーカーを行頭に表示
  - メンバーは1行に横並び表示（`[Fx]★名前[ランク] HP:x/y [ス][ガ]` 形式・幅超過時は "..." で打ち切り）
  - 各パーティーブロック = ヘッダー行 + メンバー横並び行 + 目的行 の3行固定（ブロック間空白なし）
  - リーダーを選択するとカメラがそのキャラを追跡（`leader_selected` シグナル → `game_map.set_debug_follow_target()`）
  - F1で閉じると選択リセット・カメラは操作キャラの追跡に戻る
- **下半分（45%）**：combat/ai ログ（最新50件・新着が下に追加）
  - combat=黄色、ai=水色（MessageWindow と同じ色分け）
  - `MessageLog.debug_log_added` シグナル経由で受信（エリアフィルタなし・全メッセージ表示）
- MessageWindow には combat/ai メッセージは流れない（system/battle のみ表示）

### メッセージ表記方針
- メッセージウィンドウに表示するバトルメッセージは**自然言語**で記述する（記号的表現を避ける）
  - 良い例：「○○がHPポーションを使い、自身のHPを回復した」
  - 悪い例：「○○がHPポーションを使った（HP+30）」
- 数値は原則として表示しない（ダメージ段階「小/中/大/特大」等の表現を使う）
- アイテム名は統一表記を使う：HPポーション / MPポーション / SPポーション

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

## パーティーシステムのアーキテクチャ

### 全体構造

```
PartyManager（パーティー管理。全パーティー種別で共通）
  ├── PartyLeader（リーダー意思決定の基底クラス）
  │     ├── PartyLeaderPlayer（プレイヤー操作パーティー用）
  │     └── PartyLeaderAI（AI自動判断）
  │           ├── EnemyLeaderAI（敵共通のデフォルト行動）
  │           │     ├── GoblinLeaderAI（種族固有の差分のみオーバーライド）
  │           │     ├── WolfLeaderAI
  │           │     ├── HobgoblinLeaderAI
  │           │     └── （将来の種族追加時もEnemyLeaderAIを継承）
  │           └── NpcLeaderAI（NPC固有のロジック）
  └── Character（味方・NPC・敵の全キャラクター共通）
        ├── PlayerController（プレイヤー操作時）
        └── UnitAI（AI操作時の個体行動。全パーティー種別で共通）
```

### PartyManager（管理層）
- パーティーのメンバーとリーダーを管理する
- `party_type`（`"enemy"` / `"npc"` / `"player"`）に応じてスポーン処理と PartyLeader サブクラスを切り替える
  - `"enemy"`: 敵JSONから読み込み → EnemyLeaderAI（種族別分岐）
  - `"npc"`: CharacterGeneratorでランダム生成 → NpcLeaderAI
  - `"player"`: スポーンなし（setup_adopted）→ PartyLeaderPlayer
- game_map からのデータ（friendly_list / enemy_list / floor_items / vision_system 等）を受け取り、PartyLeader に伝達する
- リーダー管理（初期設定またはリーダー死亡時に再選出）
- パーティー単位の情報共有・再評価通知
- 旧 NpcManager / EnemyManager の処理を統合済み（サブクラス不要）

### PartyLeader（意思決定層の基底クラス）
- パーティー全体の戦略を決定し、各メンバーの UnitAI に指示を伝達する
- `_evaluate_party_strength()`: パーティーの戦力値を算出する共通メソッド（ランク和 × HP充足率。HPポーション回復量を加味）
- `_evaluate_combat_situation()`: 戦況判断の共通ルーチン（リーダーのエリア＋隣接エリアを対象）。全サブクラスで共有する。結果は `_assign_orders()` → `receive_order()` でメンバーに伝達する
- `_evaluate_party_strategy()`: 仮想メソッド。戦略決定（ATTACK / WAIT / FLEE 等）。サブクラスがオーバーライドする
- `_select_target_for()`: 仮想メソッド。ターゲット選択。サブクラスがオーバーライドする
- `_assign_orders()`: 戦略に応じてメンバーの UnitAI に `receive_order()` で指示を伝達する（共通ロジック）
- `_apply_range_check()`: 縄張り・帰還判定（敵パーティーのみ適用。友好パーティーはスキップ）
- UnitAI の生成・管理（`_unit_ais` 辞書）

### PartyLeaderPlayer（プレイヤー操作パーティー用）
- PartyLeader を継承する。プレイヤーの指示（OrderWindow）を戦略・ターゲット選択に変換する
- `_evaluate_party_strategy()`: `global_orders.battle_policy` を戦略に変換する
  - `"attack"` → ATTACK、`"defense"` → WAIT、`"retreat"` → FLEE
- `_select_target_for()`: `global_orders.target` 設定に従う（nearest / weakest / same_as_leader / support）
- プレイヤーの指示を覆さない（戦況判断はメンバーAIの条件評価のみに使う）
- `_evaluate_combat_situation()` の結果を `receive_order()` でメンバーに渡す（AI操作メンバーの特殊攻撃判断等に使用）

### PartyLeaderAI（AI自動判断の基底クラス）
- PartyLeader を継承する。AI がパーティー全体の戦略を自動で判断する
- `_evaluate_party_strategy()`: デフォルト実装（WAIT を返す）
- 再評価タイマーによる定期的な戦略再評価（1.5秒間隔）

### EnemyLeaderAI（敵のデフォルト行動）
- PartyLeaderAI を継承する
- `_evaluate_party_strategy()` のデフォルト実装:
  - friendly（プレイヤー・NPC）が生存している → ATTACK
  - friendly がいない → WAIT
  - FLEE なし（デフォルトでは逃げない）
- `_select_target_for()` のデフォルト実装:
  - 最近傍の friendly を返す
- 種族固有の行動が不要な敵はEnemyLeaderAIをそのまま使用する

### 種族固有リーダーAI（EnemyLeaderAIを継承）
- EnemyLeaderAIを継承し、種族の特徴に応じた差分のみオーバーライドする
- 敵キャラクター一覧の自然言語の特徴（「臆病で逃げる」「狂暴で攻撃的」等）に基づいてClaude Codeが実装する
- 新しい敵種を追加する場合もEnemyLeaderAIを継承し、差分だけ実装する

### NpcLeaderAI（NPC固有のロジック）
- PartyLeaderAI を継承する
- 自律的な探索・フロア移動判断・アイテム自動管理を行う

### UnitAI（個体行動層）
- リーダーからの指示（`receive_order()`）で combat / on_low_hp / move / combat_situation 等を受け取る
- `_determine_effective_action()` で行動を最終決定する（ATTACK/FLEE/WAIT 相当の int を算出）
  - 判定優先順位: パーティー撤退 → 種族自己逃走 → 種族攻撃可否 → 個別低HP → 戦況SAFE判定 → combat 方針
- 種族固有行動は以下のフックメソッドでオーバーライドする（旧 `_resolve_strategy()` を廃止）:
  - `_should_ignore_flee() -> bool`: FLEE を無視する種族（dark_knight 等）が true を返す
  - `_should_self_flee() -> bool`: 自己判断で逃走する種族（goblin 系: HP30%未満）が true を返す
  - `_can_attack() -> bool`: MP 不足等で攻撃不能な種族（mage 系）が false を返す
- ステートマシン・A*経路探索・アクションキュー管理
- 全パーティー種別で同じ UnitAI を使用する

### データの流れ

```
game_map
  └── PartyManager
        ├── PartyLeader（Player または AI）
        │     ├── _evaluate_party_strength()      ← 戦力評価（共通）
        │     ├── _evaluate_combat_situation()  ← 戦況判断（共通）
        │     ├── _evaluate_party_strategy()    ← 戦略決定（サブクラス固有）
        │     └── _assign_orders()              ← 指示伝達（共通）
        │           └── UnitAI.receive_order({
        │                 target, combat, on_low_hp, move,
        │                 battle_formation, leader, party_fleeing,
        │                 combat_situation, hp_potion, sp_mp_potion,
        │                 item_pickup
        │               })
        │                 └── _determine_effective_action() ← 行動最終決定
        └── Character
              ├── PlayerController（プレイヤー操作時）
              └── UnitAI（AI操作時。receive_order の内容から行動を決定）
```

### 実装状況

| クラス | ファイル | 状態 |
|--------|---------|------|
| PartyManager | `party_manager.gd` | ✅ 実装済み。party_type で敵/NPC/プレイヤーを統合管理。旧 NpcManager / EnemyManager を統合済み |
| PartyLeader | `party_leader.gd` | ✅ 実装済み。旧 PartyLeaderAI から共通ロジックを抽出 |
| PartyLeaderAI | `party_leader_ai.gd` | ✅ 実装済み。extends PartyLeader に変更済み |
| EnemyLeaderAI | `enemy_leader_ai.gd` | ✅ 実装済み。extends PartyLeaderAI |
| 種族固有AI | `goblin_leader_ai.gd` 等 | ✅ 実装済み。extends EnemyLeaderAI |
| NpcLeaderAI | `npc_leader_ai.gd` | ✅ 実装済み。extends PartyLeaderAI |
| PartyLeaderPlayer | `party_leader_player.gd` | ✅ 実装済み。hero_manager に接続済み（party_type="player" で PartyLeaderPlayer を生成） |
| `_evaluate_combat_situation()` | `party_leader.gd` | ✅ 実装済み。リーダーのエリア＋隣接エリアの敵との戦力比較で CombatSituation を返す |

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
| ヒーラー | healer | 杖 | 支援：回復(単体・自己含む・全方向)／アンデッド特効 | heal | 防御バフ(単体・自己含む・全方向) |
| 斥候 | scout | ダガー | 近接物理：刺突 | melee | スライディング |

- 攻撃は Z/A の1ボタン。攻撃タイプ（melee/ranged）はクラスのスロット定義から自動判定
- スロット最大4（ZXCV）、ゲームパッド対応を考慮（X/B はガード）
- ヒーラーは通常の攻撃手段を持たない（支援専用）。ただし is_undead=true の敵はZ攻撃のターゲットに含め、回復量をダメージとして適用（アンデッド特効）
- 将来拡張：魔法使いの属性分化（土・風）、支援系第2ジョブ、槍兵・飛翔系・両手武器系、状態異常回復（毒・麻痺実装後）
- スロット4枠を超えるスキルの管理方法（入替・キャラ別・系統別）は将来決定

### Vスロット特殊攻撃仕様
- **突進斬り（fighter-sword）**：向いている方向に最大2マス前進。経路上の敵全員にダメージ。次の空きマスに着地。壁・障害物で止まる。SP消費
  - AI発動条件（指示「強敵なら使う」等を満たした上で追加判定）：隣接8マスの敵が `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` 以上 かつ 前方最大2マスに敵がいて着地可能な空きマスがある
- **振り回し（fighter-axe）**：周囲1マス（斜め含む隣接8マス）の敵全員に通常攻撃相当のダメージ。SP消費
  - AI発動条件：隣接8マスの敵が `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` 以上
- **ヘッドショット（archer）**：`instant_death_immune == false` の敵に即死。ボス級（`instant_death_immune == true`）には無効で通常の3倍ダメージ。SP消費大
- **炎陣（magician-fire）**：自分を中心に半径3マスに設置。設置直後から2〜3秒間燃え続け複数回ヒット。敵のみ判定（巻き添えは将来課題）。MP消費大
- **無力化水魔法（magician-water）**：単体・射程あり・MP消費大。命中した対象の攻撃・移動を2〜3秒間完全停止（回転エフェクト）。全種族共通。被弾時ダメージは受けるが持続時間は変わらない。ボス級には持続時間を短縮（将来調整）
- **防御バフ（healer）**：単体・射程あり・MP消費（`buff_defense` アクション）。**自分自身も対象に含める・方向制限なし（全方向）**。バフ中は半透明の緑色六角形バリアエフェクト（`BuffEffect.gd`）がキャラクターに重ねて表示される。バフ終了時に自動削除。重複付与時はタイマーリセット＋エフェクト再生成
- **スライディング（scout）**：向いている方向に3マス高速移動。移動中は無敵・敵をすり抜け可能。SP消費
  - AI発動条件：隣接8マスの敵が `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` 以上（包囲脱出兼ダメージ）

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
- 加入形態：プレイヤーがリーダーのまま、相手パーティーを丸ごと引き入れる（1種類のみ）

### フロア間メンバー追従
- 移動方針が **`cluster` / `follow` / `same_room`** のメンバーは「リーダー追従系」とみなし、リーダーが別フロアに居る場合は `_generate_stair_queue(dir, ignore_visited=true)` で対応する階段を目指す
- `standby` / `explore` / `guard_room` はリーダーを追わない（自律行動を維持）
- 判定は `unit_ai.gd` の `_generate_move_queue()` 冒頭で行う（PartyLeader の `_assign_orders()` では move_policy を上書きしない）
- 合流済みパーティー（`joined_to_player=true`）は別途 `_generate_floor_follow_queue()` がヒーローを基準に追従する（`_generate_queue` 冒頭の早期分岐）

## ドキュメント運用
- CLAUDE.md：人間・AI共通の概要・方針・ゲーム仕様・フェーズ進捗サマリー。ここでの相談をもとに更新する
- docs/spec.md：AI管理用の詳細仕様・実装メモ。Claude Codeが作成・更新する
- docs/history.md：変更履歴・バグ修正記録。バグの原因と修正内容、設計変更の経緯、廃止した仕様の記録を残す

### CLAUDE.md のフェーズセクション記述ルール
- 完了済みPhaseは1〜2行のサマリーで「何を実現したか」をユーザー視点で書く（ファイル名や関数名は不要）
- 未完了Phaseは詳細を残してよい
- 実装の詳細（変更ファイル・関数名・内部ロジック）はspec.mdに書く
- バグ修正の詳細・設計変更の経緯・廃止した仕様の記録はhistory.mdに書く

### 新しいPhaseを完了したときの更新フロー
1. docs/spec.md に実装詳細を記録する
2. docs/history.md にバグ修正・設計変更・廃止仕様を記録する
3. CLAUDE.md のフェーズセクションに1〜2行のサマリーを追記する
4. CLAUDE.md の仕様セクション（フェーズセクション以外）に影響がある場合は該当箇所も更新する

## ツール運用
- claude.ai（チャット）：仕様の相談・設計の議論を行う。コードの実装・ファイルの編集は行わない
- Claude Code：CLAUDE.mdの更新・仕様書（docs/spec.md）の更新・GDScriptの実装・コミット/プッシュを行う
- 仕様相談はclaude.aiで行い、確定した仕様をもとに Claude Code が CLAUDE.md を更新してから実装する

## 定数管理（Config Editor）

ゲームバランス調整と定数の棚卸しを目的とした開発用UI。

### 起動
- F4キーで開閉（タイトル画面・ゲーム中の両方で動作）
- ゲーム中は他UI（OrderWindow / DebugWindow / PauseMenu / NpcDialogueWindow 等）が開いている時は F4 を無視
- 開いている間は時間停止（`world_time_running = false`）・閉じると元の状態に復帰

### ファイル構成
- `assets/master/config/constants.json` … ユーザー編集中の値（シンプル key:value）
- `assets/master/config/constants_default.json` … デフォルト値＋メタ情報（value / type / category / min / max / step / description）

### トップレベルタブ
- **定数** — `constants.json` / `constants_default.json` を編集
- **味方クラス** — `assets/master/classes/` の人間系 7 ファイルを横断表で編集
- **敵クラス** — `assets/master/classes/` の敵固有 5 ファイル（zombie / wolf / salamander / harpy / dark-lord）を横断表で編集（味方クラスタブと同構造・同描画ロジックを流用）
- **敵一覧** — プレースホルダー（`enemy_list.json` の stat_type / rank / stat_bonus 編集を今後実装）
- **ステータス** — `assets/master/stats/class_stats.json` / `attribute_stats.json` を編集（2サブタブ：クラスステータス・属性補正）
- **アイテム** — プレースホルダー

### 「定数」タブのカテゴリ
コード上のクラス名で分類：

- Character / UnitAI / PartyLeader / NpcLeaderAI / Healer / PlayerController / EnemyLeaderAI / Unknown（未分類検出用）

タブ順は `config_editor.gd` の `TABS` 配列で定義。追加したい場合は配列末尾に追記する。

### 「味方クラス」「敵クラス」タブ
- **味方クラス**：7 クラス（fighter-sword / fighter-axe / archer / magician-fire / magician-water / healer / scout）を横に並べた横断表
- **敵クラス**：5 敵固有クラス（zombie / wolf / salamander / harpy / dark-lord）を横に並べた横断表。味方クラスタブと同構造・同描画関数（`_build_class_tab_common` / `_build_class_grid`）を流用し、対象クラス ID 配列だけ差し替え
- ネストされた `slots.Z.*` / `slots.V.*` は `Z_*` / `V_*` に平坦化して行に表示（保存時に元の階層へ戻す）。`slots.X` / `slots.C` は表示せず、保存時にそのまま維持
- パラメータのグループ分け（`CLASS_PARAM_GROUPS` 配列）：基本 / リソース / 特性 / Zスロット / Vスロット / その他
- 各セルは LineEdit（文字列入力）。保存時に元 JSON の値の型（int / float / bool / string）に合わせて変換。変換失敗時は保存を中止しエラー表示
- 変更されたセルは薄黄色ハイライト、変更があったファイルのみ書き戻す
- 「すべてデフォルトに戻す」「現在値をすべてデフォルト化」は**無効化**（デフォルト値を保持しない方針。復帰は git 履歴で管理）

### 操作
- 各定数を SpinBox（数値）または ColorPicker（色）で編集
- デフォルトと異なる行は背景薄黄色、そのタブ名末尾に `●` 付記
- 下部3ボタン：保存 / すべてデフォルトに戻す / 現在値をすべてデフォルト化
- 破壊的操作（リセット・デフォルト化）は確認ダイアログあり
- タブ切替：マウス、または Ctrl+Tab / Ctrl+Shift+Tab / Ctrl+PageUp / Ctrl+PageDown

### 反映
- 「保存」→ `constants.json` に書き込み → **ゲーム再起動で反映**（即時反映はしない方針）

### 定数追加時の運用ルール（「定数」タブ）
1. `GlobalConstants.gd` に `const`/`var` を追加するときは、`constants_default.json` にも同時に追加する
2. `category` フィールドは既存7タブ（Character / UnitAI / PartyLeader / NpcLeaderAI / Healer / PlayerController / EnemyLeaderAI）のいずれかを指定
3. 上記7タブに属さない場合は `config_editor.gd` の `TABS` 配列にタブを追加することを検討
4. カテゴリ未定義・不明な値の定数は Unknown タブに自動振り分け（起動時に push_warning で警告）
5. 定期的に Claude Code に「外出しされていない定数」の棚卸し指示を出す
   - チェック観点：GlobalConstants 内に直書きされ `constants_default.json` に未登録の定数がないか

### 「味方クラス」編集時の運用ルール
1. クラス JSON に新パラメータを追加するときは、`config_editor.gd` の `CLASS_PARAM_GROUPS` の適切なグループにも追加する
2. 追加し忘れた場合は「その他」グループに自動集約されるため、起動時の push_warning で気付ける
3. Config Editor で編集した結果は `assets/master/classes/*.json` に直接書き戻されるので、そのまま git commit すれば差分管理できる

### 「ステータス」編集時の運用ルール
1. Config Editor は**既存ステータスの値編集のみ**。新ステータス追加はコード変更（CharacterData / 生成ロジック等）を伴うので別タスクで実施
2. クラスステータスは「base / rank」を 2 つの LineEdit 横並びで編集。属性補正は 1 LineEdit / セル
3. `class_stats.json` のクラス順・ステータス順、`attribute_stats.json` のカテゴリ順・ステータス順は元 JSON のキー順を保持（`sort_keys=false`）

### ConfigEditor 対象の `var` 化
- 対象の定数は `const` ではなく `var` で宣言する必要がある（Autoload 起動時に `_load_constants()` が外部 JSON から値を代入するため）
- `const` のまま外部化したい場合は先に `var` へ変換する

## フェーズ
- [x] Phase 1: 主人公1人の移動・画像表示・フィールド表示。グリッド移動・4方向スプライト切替・タイルマップ（FLOOR/WALL）・デッドゾーン方式カメラを実装
- [x] Phase 2: 戦闘基盤。HP等基本ステータス・敵配置（JSON読み込み）・ルールベースAI（A*経路探索・ステートマシン）・近接攻撃・方向ダメージ倍率を実装
- [x] Phase 3: フィールド生成。手作りダンジョンJSON管理・複数部屋＋通路構造・敵パーティー配置を実装
- [x] Phase 4: 攻撃バリエーション。PRE_DELAY→TARGETING→POST_DELAYの攻撃フロー・飛翔体エフェクト・飛行キャラ対応（melee/ranged/dive）を実装
- [x] Phase 5: グラフィック＆UI強化。トップビュー化・タイル画像・OBSTACLE/CORRIDORタイル・部屋単位の視界システム・3カラムUI（左=味方/中央=フィールド/右=敵）・メッセージウィンドウ・エリア名表示を実装
- [ ] Phase 6: 仲間AI・操作切替
  - [x] Phase 6-0: AIを2層構造（リーダーAI＋個体AI）にリファクタリング。7クラスのJSON定義・キャラクター自動生成・画像フォルダ新フォーマット移行を実施
  - [x] Phase 6-1: 仲間NPCの配置と基本AI行動。NpcManager/NpcLeaderAI/NpcUnitAIを実装し、パーティーカラー表示・初期3人パーティーでの開始を実現
  - [x] Phase 6-2: 仲間の加入。Aボタンで隣接NPCに話しかけて仲間にする会話システム（スコア比較方式の承諾判定・共闘/回復ボーナス・敵入室時の会話中断）を実装
  - [x] Phase 6-3: 操作キャラの切替。指示ウィンドウからパーティーメンバーへ操作を切り替え、旧操作キャラはAI制御に戻る仕組みを実装
- [x] Phase 7: 指示システム。全体方針7項目（移動/戦闘方針/ターゲット/低HP/アイテム取得/HPポーション/SP・MPポーション）と個別指示4列（隊形/戦闘/ターゲット/特殊攻撃、ヒーラーは+回復列）をチップ形式UIで実装。AIが指示に従って行動する仕組みを完成
- [x] Phase 8 Step 1: 飛行移動・攻撃タイプ（melee/ranged/dive）・MP・回復/バフ行動（ヒーラー・ダークプリースト）を実装
- [x] Phase 8 Step 2+3: 敵11種の種族別AI（ゴブリン系・ウルフ・ゾンビ・ハーピー・サラマンダー・暗黒系等）とマスターデータを実装。ダンジョンに全種を配置
- [x] Phase 8 バグ修正: 敵JSONの読み込み・ダンジョン構成（12部屋x4フロア+ボス1部屋）を整備
- [x] Phase 9: 操作感・表現強化
  - [x] Phase 9-1: 歩行アニメーション（walk1→top→walk2→topの4フレームループ）・位置補間・先行入力バッファ方式による滑らか移動を実装
  - [x] Phase 9-2: Xbox系ゲームパッド対応（全操作をキーボードとゲームパッドの並列登録）
  - [x] Phase 9-3: 飛翔体グラフィック（矢・火弾・雷弾の画像と飛行方向回転）を実装
  - [x] Phase 9-4: 効果音（Kenney CC0素材。攻撃・命中・被ダメージ・死亡・回復・入室の各SE）を実装
  - [x] Phase 9-5: 衝突判定改善（先着優先方式・abort_move）・スプライト回転アニメーション・味方の押し出しシステムを実装
- [ ] Phase 10: アイテム・装備システム
  - [x] Phase 10-1: アイテムマスターデータ（武器5種・防具4種・消耗品2種）定義・インベントリシステム・部屋制圧方式のドロップシステムを実装
  - [ ] Phase 10-2: 装備システム
    - [x] ドロップ処理（部屋制圧でアイテムが床に散布・踏んで自動取得）・OrderWindowアイテムUI（装備/渡す/3層UI）・操作体系刷新（1ボタン攻撃統合・メニュー共通ナビゲーション）を実装
    - [x] MessageLog（Autoload）新設・DebugWindow移行・全キャラクター常時行動化・会話UIのMessageWindow統合を実装
    - [x] 装備ステータス補正値反映・被ダメージ計算（防御判定・方向判定・耐性）・初期装備付与・装備補正値の仕様統一を実装
    - AI自動装備は将来実装（当面は拾って持つだけ）
    - [x] UI改善（クラス名日本語表示・装備可否色分け・隣接エリア先行可視化等）・主人公をランダム生成に変更
  - [x] Phase 10-3: HP/MP回復ポーション。C/X短押しでアイテム選択UI（使用/装備/渡す）を開く仕組みを実装。ConsumableBar UIで消耗品を常時表示
  - [x] Phase 10-4: OrderWindowに指示テーブル＋ステータス詳細（素値/補正値/最終値）＋装備欄＋所持アイテムを統合表示
- [x] Phase 11: フロア・ダンジョン拡張
  - [x] Phase 11-1: 階段タイル・フロア遷移（5フロア構成）を実装。フロアごとの敵/NPC管理・遅延初期化・各種バグ修正を含む
  - [x] Phase 11-2: 5フロア対応ダンジョン（フロア0:ゴブリン中心〜フロア4:ボス）とゲームクリア判定を実装
  - [x] Phase 11-3: MPバー表示（魔法クラスのみ）・攻撃時MP消費・アイテム一覧のグループ化表示を実装
  - [x] Phase 11-4: プレイヤー操作ヒーラーの回復行動（単体・射程あり・アンデッド特効）とコード描画による回復エフェクトを実装
  - [x] Phase 11-5: ガードシステム（X/Bホールドで正面防御100%成功・移動速度50%・向き固定・guard.pngスプライト）を実装
- [ ] Phase 12: ステージ・バランス調整
  - [x] Phase 12-1: MP/SPシステム（魔法クラス=MP・非魔法クラス=SP・自動回復・SPポーション）を実装
  - [x] Phase 12-2: 水魔法使いクラス（水弾・水流・無力化水魔法）とスタンシステム（行動停止＋スピン表現）・Vスロット基盤を実装
  - [x] Phase 12-3: アイテム画像をゲーム内に反映
  - [x] Phase 12-4: 全7クラスのVスロット特殊攻撃（突進斬り/振り回し/ヘッドショット/炎陣/無力化水魔法/防御バフ/スライディング）を実装。アイテム画像の床・UI表示も対応
  - [x] Phase 12-5: LB/RBでキャラ循環切り替え・C/X短押しでアイテム選択UIを開く操作体系に変更
  - [x] Phase 12-6: 防御バフの緑色六角形バリアエフェクト・LB/RBキャラ切り替え・C/Xアイテム選択UIを実装
  - [x] Phase 12-7: パーティーメンバーと未加入NPCのフロア遷移（個別階段使用・ランク和ベースの適正フロア判断）を実装。関連バグ修正を含む
  - [x] Phase 12-8: OrderWindow右キー動作修正・NPC会話専用ウィンドウ新設・各フロア階段3か所配置・別フロアキャラのブロック問題修正
  - [x] Phase 12-9: 左パネル12人対応・パーティー上限12人ガード・NPC配置をフロア0に集約（4部屋11人）
  - [x] Phase 12-10: attack.pngスプライト対応（攻撃中の専用画像）・プレイヤー/NPC全14キャラにimage_setを固定割り当て
  - [x] Phase 12-11: NPCの多層階探索（同フロア敵全滅で探索モード移行・視界ベース階段探索・フロア遷移後の自律行動）を修正
  - [x] Phase 12-12: アンデッド5種（skeleton/skeleton-archer/lich/demon/dark-lord）追加。ヒーラーのアンデッド特効・雷弾飛翔体・魔王のワープ＋炎陣を実装
  - [x] Phase 12-13: ダンジョン全面再生成（5フロア141体）・アウトラインシェーダー・射程オーバーレイ・各種バグ修正
  - [x] Phase 12-14: ステータス名統一（power/skill）・ガード防御改修・NPC会話をAボタン方式に変更・「一緒に行く」合流処理修正
  - [x] Phase 12-15: ステータス生成を設定ファイル方式に移行。全ステータス0-100スケール統一・vitality/energy追加・move_speed/obedience変換を実装
  - [x] Phase 12-16: クリティカルヒット（skill/3%の確率でダメージ2倍・二重エフェクト）を実装
  - [x] Phase 12-17: 敵16種のステータス生成を設定ファイル方式（enemy_class_stats.json/enemy_list.json）で実装
  - [x] Phase 12-18: フロア遷移時のfreedクラッシュ・新フロア敵未起動・LB/RBキャラ切り替え不具合・アウトライン残留バグを修正
  - [x] Phase 12-19: 装備補正値の仕様統一・敵ヒーラーの回復対象バグ・シェーダーmodulate無視バグ・freedキャストクラッシュを修正。旧敵画像を削除
- [x] Phase 13: タイトル画面・メインメニュー（セーブ3スロット・名前入力・オプション）・ポーズメニュー・セーブシステムを実装
- [x] Phase 13-1: MessageWindowをアイコン行方式に刷新。戦闘メッセージを自然言語化し、攻撃側/被攻撃側の顔アイコン＋左右上半身画像を表示
- [x] Phase 13-2: ダメージ倍率調整・NPC探索分散・部屋制圧に敵走離脱を追加・メッセージのグループ表示・リーダー方角インジケーターを実装
- [x] Phase 13-3: MessageWindowのスムーズスクロール（0.15秒補間・SubViewportによる上端クリッピング）を実装
- [x] Phase 13-4: ダンジョン全49部屋に非矩形形状（L字・T字・八角形等10種のパターン）と障害物タイルを配置
- [x] Phase 13-5: OrderWindow全体方針を6行個別設定に刷新・個別指示テーブル4列化（非ヒーラー:ターゲット/隊形/戦闘/特殊攻撃、ヒーラー:+回復）・選択肢をチップ形式で横並び表示
- [x] Phase 13-6: Phase 13-5の指示仕様をAIロジックに反映（ポーション自動使用・アイテムナビゲーション・follow追従・support援護ターゲット等）
- [x] Phase 13-7: 移動前に向きだけ変える回転操作を実装（移動方向が現在の向きと異なる場合、まず回転してから移動）
- [x] Phase 13-8: 未加入NPCパーティーのアイテム自動装備・ポーション自動受け渡しを実装。会話選択肢を「仲間にする/キャンセル」の2択に変更
- [x] Phase 13-9: OrderWindowステータス表示を2列化（左:攻撃系/右:防御系）・ヘッダーに名前+クラス+ランクを統合
- [x] Phase 13-9（戦闘方針・集結隊形）: 全体方針にbattle_policy（攻撃/防衛/撤退）を追加。gather隊形（パーティー重心付近に集結）を実装
- [x] Phase 13-10: 敵の縄張り・追跡システムを実装。chase_range/territory_rangeで追跡範囲を制限し、範囲外では帰還行動に切り替え
- [x] Phase 13-10 後続修正: ヒーラーの回復指示デフォルトを瀕死度優先に変更・非ヒーラー行の回復列にグレー「-」表示
- [x] Phase 13-11: フロア0をゴブリンのみに変更・NPCデフォルト指示をプレイヤーと整合・戦闘中のbattle_formation優先・follow追従ロジック改善
- [x] Phase 13-12: バグ修正完了（フロア2以降の敵が攻撃しない問題・未加入NPCがアイテムを素通りする問題）
- [x] 味方キャラ同士が重なる・味方を迂回できない問題を修正（`_link_all_character_lists` を全フロア走査に変更・フロア遷移/合流時の `_all_members` 更新漏れを修正・A* 1歩目の味方迂回フォールバック追加）
- [x] パーティーシステムリファクタリング: 敵リーダーAI継承構造リファクタリング（EnemyLeaderAI）・PartyLeader基底クラス抽出・NpcManager/EnemyManager廃止しPartyManagerに統合・パーティー戦力評価メソッド追加
- [x] ダンジョン再構成: 5フロア×20部屋構成に拡張。各フロア下り階段3部屋・上り階段3部屋（上り階段部屋は敵初期配置なし）。主人公1人スタート・NPC 8パーティー（1人×5+2人×2+3人×1=計12人）を全てフロア0に配置
- [x] 安全部屋の追加: フロア0中央に「安全の広間」（15×11、`is_safe_room`）を配置。上下左右4部屋と通路で接続。敵は通路までは来れるが部屋内に進入できない（MapData.is_safe_tile で敵AIのA*経路探索から除外）。主人公とNPC全8パーティーがここからスタート
- [x] UI・演出ブラッシュアップ（2026-04-16）:
  - ヒットエフェクトを3層プロシージャル（リング波紋＋光条＋パーティクル散布・加算合成）に刷新
  - OrderWindow レイアウト再構成（タイトル削除・ステータスヘッダー復活・ランク色付き・装備/所持アイテム2列化・全身画像拡大1:1維持・ログ行廃止）
  - OrderWindow チップ選択の左右キーは全列循環・上下移動時は列種類（pos）で対応づけ
  - メッセージウィンドウ刷新（右スティック上下でピクセル単位スムーズスクロール・R3/Homeで拡大トグル・背景半透明化・文字色分け segments 対応）
  - 状態ラベル4段階化（healthy/wounded/injured/critical）。スプライト色・テキスト色・HPゲージ色・DebugWindow を状態ラベル閾値に統一
  - 攻撃フロー改善（他ボタンで攻撃キャンセル＋機能切替・射程内対象なし時の自動キャンセル・ヒーラー360度射程オーバーレイ対応）
  - 安全部屋専用タイル画像（safe_floor.png）
  - `Character.joined_to_player` フラグ追加（パーティー所属判定用）
  - アイテム名称統一（HPポーション/MPポーション/SPポーション）
- [x] 近接3クラス（剣士/斧戦士/斥候）の特殊攻撃AI発動条件（隣接敵数・突進斬りの経路判定）を実装
- [x] 攻撃クールダウン（pre_delay / post_delay）の全面見直し：クラスJSONのスロット単位（Z/V）に一元化、プレイヤー/AIで同じ slots 参照、PRE_DELAY 中から射程オーバーレイ表示、game_speed 適用
- [x] HP状態ラベルの色と点滅を全UI要素で統一。色定数を `GlobalConstants` に集約（SPRITE/GAUGE/TEXT の3パレット）。wounded 以降はスプライト・顔アイコンで3Hz点滅。ゲージ・文字は静的
- [x] Config Editor（開発用定数エディタ）を実装。F4 でタイトル画面・ゲーム中ともトグル起動。5定数（Phase A）を外部 JSON（`assets/master/config/constants.json` / `constants_default.json`）化し、7 + Unknown タブでカテゴリ分け表示・保存・デフォルト復帰・デフォルト化に対応
- [x] Config Editor にトップレベルタブ構造（定数/味方クラス/敵/ステータス/アイテム）を導入し、「味方クラス」タブで 7 クラス JSON を横断表で編集できるよう実装（`slots.Z/V` 平坦化・LineEdit セル・元値型に合わせた書き戻し・キー順保持）
- [x] Config Editor「ステータス」タブを実装。`class_stats.json`（クラス × ステータス × base/rank の 2 LineEdit セル）と `attribute_stats.json`（属性補正表 + random_max 表）を直接編集可能
- [x] 敵データの構造整理：敵固有 5 クラス（zombie / wolf / salamander / harpy / dark-lord）の JSON を `assets/master/classes/` に新規作成。個別敵 JSON 16 ファイルから `attack_type` / `attack_range` / `pre_delay` / `post_delay` / `heal_mp_cost` / `buff_mp_cost` を除去し、クラス経由で注入する仕組みに統一。`healer.json` の top-level `heal_mp_cost` / `buff_mp_cost` も削除し、`slots.Z.mp_cost` / `slots.V.mp_cost` を正規化
- [x] Config Editor「敵クラス」タブを実装。味方クラスタブの描画関数を流用し、対象クラス ID 配列を差し替えて 5 敵固有クラスを横断表編集可能に。トップタブを「敵」→「敵クラス」「敵一覧」の 2 タブに分割
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
- 部屋に配置された enemy_party の全員が**死亡 or 敵走離脱**したら「制圧完了」
- 制圧時、敵パーティーの所持アイテムが**部屋の床タイルにランダムに散らばる**（1マスに1個）
- 出現は1回きり（敵が戻っても再出現しない）
- **制圧判定の詳細**（`party_manager._check_room_suppression()`）：
  - 死亡 → 制圧対象
  - 部屋の外にいる かつ パーティー戦略が FLEE → 離脱扱い・制圧対象
  - 部屋の外にいる かつ FLEE 以外（追跡中など） → 制圧対象にしない
  - 部屋の中で生存 → 制圧対象にしない
  - 判定タイミング：メンバー死亡時（`_on_member_died`）
  - 二重発火防止：`party_wiped` 発火後に `_room_id` を空文字にクリア
- item_get 効果音を再生、メッセージウィンドウに通知（例：「アイテムが散らばった！」）
- 表示：アイテム種類別アイコン（`assets/images/items/{item_type}.png`。画像なし時は黄色マーカーにフォールバック）
- **取得方法**：同じマスに移動したら自動取得。拾ったキャラ個人の inventory に未装備品として入る
- プレイヤー操作キャラはフィルタなし（踏めば何でも拾う）
- AIキャラは item_pickup 指示に従う（指示システム節を参照）
- 敵パーティーの所持アイテムはClaude Codeがダンジョン生成時に種族構成を考慮して割り当て
- 複数パーティーによる協力撃破の分配は将来実装

### 消耗品
- HPポーション・MPポーション・SPポーション（上級ポーションは設けない）
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

### 戦況判断（CombatSituation）
- `_evaluate_combat_situation()` が「リーダーのエリア＋隣接エリア」にいる敵との戦力比から判定する
- 通路にもエリアID（`c{フロア番号}_{連番}`。例：`c1_1`）が付与されており、`部屋 ←→ 通路 ←→ 部屋` が隣接として扱われる
- これにより部屋の境界付近で戦っても戦況がぶれない
- 自軍側も同じ「対象エリア」に絞ってランク和・戦力を算出する
- **同陣営の他パーティー**（`is_friendly` が同じ別パーティー）が対象エリア内にいる場合、その生存メンバーのランク和・戦力も自軍側に加算する
  - プレイヤー＋未加入NPC連合、敵パーティー同士の合流など
  - 敵同士でも同じルールなので、敵が密集しているエリアでは敵が強気になり、プレイヤー側が有利な時ほど敵は逃げやすくなる
- HP充足率（HpStatus）は自パーティーのみで計算（他パーティーのポーション所持は把握不可のため）
- 戦力比 = 自軍戦力 / 敵戦力（`_evaluate_party_strength_for()` で算出）

| 戦況 | 戦力比 | NPC行動への影響 | アイテム拾い |
|------|--------|----------------|-------------|
| SAFE | 敵なし | 通常探索 | item_pickup 指示に従う |
| OVERWHELMING | ≥ 2.0 | 通常攻撃（余裕あり） | しない |
| ADVANTAGE | ≥ 1.2 | 通常攻撃 | しない |
| EVEN | ≥ 0.8 | 通常攻撃 | しない |
| DISADVANTAGE | ≥ 0.5 | 通常攻撃（特殊攻撃は指示「強敵なら使う」で発動） | しない |
| CRITICAL | < 0.5 | 撤退（部屋から離脱） | しない |

- アイテム取得ナビゲーションは `_is_combat_safe()` で判定（戦況 SAFE のときのみ item_pickup 指示に従う）
- SAFE 時の1マス移動完了ごとにアイテムチェックを実行（移動中に隣接のアイテムを見逃さない）
- 撤退後に敵がいなくなると SAFE に戻り、探索・アイテム取得に復帰する
- 目標フロアの再計算で HP チェックが×なら上の階に撤退する

### 戦力比（PowerBalance）
- ランク和のみで比較（HP を含めない純粋な戦力比較）
- 自軍側ランク和 = 自パーティーのエリア内生存メンバー ＋ **同陣営の他パーティーのエリア内生存メンバー**のランク和（加算）
- 敵がいない場合は OVERWHELMING

| 段階 | 自軍ランク和 / 敵ランク和 |
|------|--------------------------|
| OVERWHELMING | ≥ 2.0 |
| SUPERIOR | ≥ 1.2 |
| EVEN | ≥ 0.8 |
| INFERIOR | ≥ 0.5 |
| DESPERATE | < 0.5 |

### HP充足率（HpStatus）
- 自軍パーティー全体のHP充足率（ポーション込み）

| 段階 | 充足率 |
|------|--------|
| FULL | ≥ 0.75 |
| STABLE | ≥ 0.5 |
| LOW | ≥ 0.25 |
| CRITICAL | < 0.25 |

### 特殊攻撃の指示と発動条件

| 指示 | 発動条件 |
|------|---------|
| 積極的に使う | MP/SP が足りていれば常に使う |
| 強敵なら使う | PowerBalance が INFERIOR 以下かつ MP/SP が足りている |
| 劣勢なら使う | HpStatus が LOW 以下かつ MP/SP が足りている |
| 使わない | 使わない |

### ゲーム内閾値一覧

主要な閾値は `GlobalConstants` に定数として定義する。コード内に数値をハードコードしない。

#### HP系
| 用途 | 定数名 | 値 |
|------|-------|-----|
| 状態ラベル "healthy" の境界（HP%≥この値） | `CONDITION_HEALTHY_THRESHOLD` | 0.5 |
| 状態ラベル "wounded" の境界（HP%≥この値） | `CONDITION_WOUNDED_THRESHOLD` | 0.35 |
| 状態ラベル "injured" の境界（HP%≥この値、未満は "critical"） | `CONDITION_INJURED_THRESHOLD` | 0.25 |
| 瀕死判定（HPポーション自動使用・on_low_hp 発動・heal "aggressive" モード対象） | `NEAR_DEATH_THRESHOLD` | 0.25 |
| ヒーラー回復モード "lowest_hp_first" / "leader_first"（リーダー判定） | `HEALER_HEAL_THRESHOLD` | 0.5 |
| 種族固有自己逃走（ゴブリン系 `_should_self_flee`） | `SELF_FLEE_HP_THRESHOLD` | 0.3 |

#### MP/SP系
| 用途 | 定数名 | 値 |
|------|-------|-----|
| MP/SPポーション自動使用（sp_mp_potion="use" 設定時） | `POTION_SP_MP_AUTOUSE_THRESHOLD` | 0.5 |

#### パーティー系
| 用途 | 定数名 | 値 |
|------|-------|-----|
| パーティー逃走（ゴブリン/ウルフ：生存メンバー率がこれ未満で FLEE 戦略） | `PARTY_FLEE_ALIVE_RATIO` | 0.5 |
| 特殊攻撃の発動状況判定（隣接8マスの敵数） | `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` | 2 |
| NPC フロア遷移の最低 HP 閾値（最低 HP 率がこれを下回ると適正フロア-1） | `NPC_HP_THRESHOLD` | 0.5 |
| NPC フロア遷移の最低エネルギー（MP/SP）閾値 | `NPC_ENERGY_THRESHOLD` | 0.3 |

#### 戦況系
本セクション上部の「戦況判断（CombatSituation）」「戦力比（PowerBalance）」「HP充足率（HpStatus）」表の閾値は、それぞれ以下の定数で定義されている:
- `COMBAT_RATIO_OVERWHELMING / ADVANTAGE / EVEN / DISADVANTAGE` (2.0 / 1.2 / 0.8 / 0.5)
- `POWER_BALANCE_OVERWHELMING / SUPERIOR / EVEN / INFERIOR` (2.0 / 1.2 / 0.8 / 0.5)
- `HP_STATUS_FULL / STABLE / LOW` (0.75 / 0.5 / 0.25)

#### ヒーラー回復モードの選定ロジック
| モード | 対象 |
|--------|------|
| `aggressive`（積極回復） | HP率 < `NEAR_DEATH_THRESHOLD` (0.25) のうち最もHP率が低い1人 |
| `lowest_hp_first`（瀕死度優先） | HP率 < `HEALER_HEAL_THRESHOLD` (0.5) のうち最もHP率が低い1人 |
| `leader_first`（リーダー優先） | リーダーが HP率 < `HEALER_HEAL_THRESHOLD` (0.5) なら最優先、それ以外は `aggressive` と同じ |
| `none`（回復しない） | 対象なし（null を返す） |

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
| 状態ラベル | `get_condition()` | HP割合に基づく4段階ラベル（healthy/wounded/injured/critical）。AI の戦力評価で敵のHP推定に使用。閾値は GlobalConstants で管理 |

### 状態ラベルの色と点滅
- 閾値は `GlobalConstants.CONDITION_HEALTHY_THRESHOLD` (0.5) / `CONDITION_WOUNDED_THRESHOLD` (0.35) / `CONDITION_INJURED_THRESHOLD` (0.25)
- 色は `GlobalConstants` に 3 系統のパレットで集約（SPRITE / GAUGE / TEXT）。各 UI は用途に応じてパレットを使い分ける
- 点滅は **スプライト・顔アイコン（左右パネル）のみ** に適用。wounded / injured / critical の 3 段階で 3Hz 点滅（`CONDITION_PULSE_HZ`）。ゲージ・文字・DebugWindow は静的色

| ラベル | HP閾値 | スプライト・アイコン | HPゲージ | テキスト | DebugWindow HP | 点滅 |
|---|---|---|---|---|---|---|
| healthy  | ≥50% | 白 | 緑 | 緑 | 白 | なし |
| wounded  | ≥35% | 黄 | 黄 | 黄 | 黄 | **あり** |
| injured  | ≥25% | 橙 | 橙 | 橙 | 橙 | **あり** |
| critical | <25% | 赤 | 赤 | 赤 | 赤 | **あり** |

- 色定数：`CONDITION_COLOR_{SPRITE|GAUGE|TEXT}_{HEALTHY|WOUNDED|INJURED|CRITICAL}`（全12定数）
- ヘルパー：`condition_sprite_modulate(cond)`（点滅あり）/ `condition_sprite_color(cond)`（静的）/ `condition_gauge_color(cond)` / `condition_text_color(cond)` / `ratio_to_condition(ratio)`
- 点滅実装：`_pulse_color(base)` が `sin(t*TAU*3)` で「色 ↔ 暗い同色（各成分×0.7）」を lerp

- 魔法命中精度は `skill` と共通（`power` 系は攻撃・回復とも同じ命中扱い）
- 回復魔法は必ず命中するため、ヒーラー（attack_type="heal"）には OrderWindow の魔法技量行を表示しない
- 耐性素値はクラスごとに設定（例：戦士クラスは物理耐性高め、魔法使いは魔法耐性高め）
- 耐性はステータス決定構造の加算式で決定（他のステータスと同じフロー）
- 軽減方式：逓減カーブ（軽減率 = 能力値 / (能力値 + 100)。100で50%、200で67%）
- OrderWindow では数値のみ表示（%表記はしない）

### MP/SPシステム
- **魔法クラス**（`magician-fire` / `magician-water` / `healer`）：`mp` / `max_mp` を使用
- **非魔法クラス**（`fighter-sword` / `fighter-axe` / `archer` / `scout`）：`sp` / `max_sp` を使用
- バー表示（左パネル）：MPは濃い青・SPは水色系。それぞれのクラスで対応するバーのみ表示。Vスロット特殊攻撃のコスト未満になるとバー色が紫系に変化（MP=濃い紫・SP=明るい紫）
- 通常攻撃（Z）：全クラス微量消費（自動回復と相殺される程度）
- 特殊攻撃（V）：魔法クラスはMP消費大・非魔法クラスはSP消費大
- ヒーラーのZ（回復）はMP消費大（例外扱い）
- 自動回復：MP・SP ともに時間経過でゆっくり回復
- 回復アイテム：MPポーション（魔法クラス用）・SPポーション（非魔法クラス用）に分離
- 敵キャラクターは当面 SP/MP システムを持たない（AI の行動クールタイムで代替）

### 命中・被ダメージ計算

**着弾判定**（命中精度）：攻撃が狙った対象に向かうか。`skill` が低いと別の敵・味方に誤射する可能性。

**攻撃タイプ別ダメージ倍率**（`GlobalConstants.ATTACK_TYPE_MULT`）:
- melee: × 0.3
- ranged: × 0.2
- dive: × 0.3
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
- **クラスと個体の区別**：各敵は `enemy_list.json` の `stat_type` で「敵クラス」を参照する。「攻撃タイプ」や「攻撃間隔」はクラス側（`assets/master/classes/*.json`）で決まる
- 人間系クラス（fighter-sword / fighter-axe / archer / magician-fire / healer）は味方と共通の定義を流用。敵固有クラスは `zombie` / `wolf` / `salamander` / `harpy` / `dark-lord` の 5 種類
- **`behavior_description` は個体側の属性**：同じクラスでも個体ごとに異なる個性（例：ゴブリンの「臆病」、ホブゴブリンの「狂暴」）を表現する
- `is_flying` / `is_undead` / `instant_death_immune` / `chase_range` / `territory_range` / `projectile_type` も個体側

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
- 味方（クラス持ち）は `assets/master/classes/*.json` の **スロット単位**（`slots.Z` / `slots.V`）で `pre_delay` / `post_delay` を定義。プレイヤーも AI も `slots` から同じ値を参照する
- 敵は `assets/master/enemies/*.json` の**トップレベル** `pre_delay` / `post_delay`（スロット構造なし）
- pre_delay / post_delay は `game_speed` の影響を受ける（移動系と同じ。×2.0 で攻撃テンポも2倍）

### 攻撃フロー（PRE_DELAY → TARGETING → POST_DELAY）
- Z/A **短押し** → PRE_DELAY モードへ（pre_delay 消化中は時間進行・ターゲット候補を表示・**射程オーバーレイも表示**）
- PRE_DELAY 中は射程が見えるが、ターゲット選択（LB/RB や確定）はできない
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

## 敵キャラクターのステータス直接参照の禁止
- 敵キャラクターの正確なステータス（hp, max_hp, power, skill 等）をAIの判断ロジックで直接参照してはならない
  - 参照してよい情報：ランク、クラス（種族）、condition（状態ラベル）、位置、向き、is_alive、is_flying、is_undead など外見で判断できる情報
  - 理由：ゲーム仕様上、敵のステータスは不可視。将来的に情報制限を導入する前提で設計する
  - HP の推定は状態ラベル（condition: healthy/wounded/injured/critical）経由で行う
  - 戦力評価は `_evaluate_party_strength_for()` を使う
  - 種族固有リーダーAI（GoblinLeaderAI 等）でも同じルールを守ること
  - 自パーティーのメンバーのステータスは直接参照してよい

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
- ログ参照の改善（OrderWindowのログをより使いやすく）：現在は最新50件をそのまま表示するだけ。フィルタリング・検索・スクロール操作の改善を検討
- パーティーシステムの残作業：
  - [x] 戦況判断ルーチン（`_evaluate_combat_situation()`）の実装（PartyLeader の共通メソッド。同エリア敵との戦力比較で CombatSituation を返す）
  - [x] NpcLeaderAI の撤退ロジック追加（CombatSituation.CRITICAL 時に FLEE に切り替え。SAFE 復帰で EXPLORE に戻る）
  - [x] special_skill 指示のAI接続（strong_enemy / disadvantage 等の条件判定。PowerBalance / HpStatus で判定。_generate_special_attack_queue で発動）
- NpcLeaderAI のアイテム収集方針の動的切り替え：目標フロアに到達している場合（余裕がある状態）、item_pickup を "passive"（近くなら拾う）から "aggressive"（積極的に拾う）に切り替える。装備強化のために能動的にアイテムを回収する行動

## 参照ファイル
- docs/spec.md：詳細仕様書（実装前に参照すること）
