# プロジェクト概要
リアルタイムタクティクスRPG（仮題未定）

## ジャンル・コンセプト
- リアルタイム進行（ターン制なし）
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
    front.png    (1024x1024, 全身正面・UI表示用)
    face.png     (256x256, frontから顔切り出し・左パネル表示用)

assets/images/enemies/
  {enemy_type}_{sex}_{age}_{build}_{id}/
    top.png / walk1.png / walk2.png / ready.png / front.png / face.png  （味方と同じ6ファイル構成・walk1/walk2は省略可）
```
- 味方: class = fighter-sword, fighter-axe, archer, magician-fire, healer, scout
- 敵: enemy_type = goblin, goblin-archer, goblin-mage, hobgoblin, dark-knight, dark-mage, dark-priest, wolf, zombie, harpy, salamander 等
- sex: male, female
- age: young, adult, elder
- build: slim, medium, muscular
- id: 01〜99
- view名にアンダーバー不使用
- 歩行アニメ: `walk1 → top → walk2 → top` の4枚ループ。walk1/walk2がない場合はtop固定（フォールバック）
- 攻撃アニメーション（attack1.png / attack2.png）は将来実装。当面は攻撃モーション中も ready → top の切り替えのまま
- 画像がない敵はJSONのフラットパス指定またはプレースホルダー色にフォールバック

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
- JSONに画像ファイルパスを含めて一元管理
- work/：作業用ファイル置き場（コードから参照しない。AI生成の元画像・参考資料など）
- ※ work/ 配下はGodotのインポート対象外。フォルダ構成は自由に変更してよい

## マップデータ仕様
- タイルデータ（壁・床）、プレイヤーパーティー初期配置、敵パーティー初期配置をひとまとめに管理
- プレイヤー・敵ともにパーティー単位で配置情報を記述（将来の複数パーティー対応を考慮）
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

| 操作 | キーボード | ゲームパッド |
|------|-----------|-------------|
| 移動 | 矢印キー | 左スティック or 十字キー |
| 近接攻撃（ホールド） | Z | A（Xbox） |
| 遠距離攻撃（ホールド） | X | X（Xbox） |
| ターゲット循環（ホールド中） | 矢印キー | LB / RB |
| 指示／ステータスウィンドウ | Tab | Select / Back |
| アイテム使用（ホールド） | 未定 | LT ホールド＋ABXY |
| ゲーム終了 | Esc（当面） | ポーズメニュー内で選択（将来実装） |
| ポーズメニュー | 未定（将来実装） | Start |
| AIデバッグパネル ON/OFF | F1 | — |
| シーン再スタート | F5 | — |

### 指示／ステータスウィンドウ（OrderWindow）
- 専用ボタンでいつでも開閉可能（ポーズなし・時間進行継続）
- リーダー操作中：指示の変更可
- 非リーダー操作中：閲覧のみ（変更不可）
- 構成：上部=キャラ一覧＋指示内容、下部=選択キャラのステータス詳細・装備・所持アイテム
- ステータス表示：素値・補正値・最終値の3列（例：攻撃力　15　+5　→　20）
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

### 初期6クラス
| クラス | ファイル名表記 | 武器タイプ | Z（通常） | X（ため） | C（第3） |
|--------|--------------|-----------|----------|----------|---------|
| 剣士 | fighter-sword | 剣 | 近接物理：斬撃 | 強斬撃 | — |
| 斧戦士 | fighter-axe | 斧 | 近接物理：振り下ろし | 大振り | — |
| 弓使い | archer | 弓 | 遠距離物理：速射 | 狙い撃ち | — |
| 魔法使い(火) | magician-fire | 杖 | 遠距離魔法：火弾(単体) | 火炎(単体高威力) | 火炎範囲 |
| ヒーラー | healer | 杖 | 支援：回復(単体小) | 回復(単体大) | 防御バフ(単体) |
| 斥候 | scout | ダガー | 近接物理：刺突 | 急所狙い | — |

- スロット最大4（ZXCV）、ゲームパッド対応を考慮
- ヒーラーは攻撃手段を持たない（支援専用）
- 将来拡張：魔法使いの属性分化（水・土・風）、支援系第2ジョブ、槍兵・飛翔系・両手武器系、状態異常回復（毒・麻痺実装後）
- スロット4枠を超えるスキルの管理方法（入替・キャラ別・系統別）は将来決定

## キャラクター生成システム

- プレイヤー（主人公）含め全キャラクターがランダム生成
- グラフィック（画像セット）をあらかじめ複数用意。各セットに性別・年齢・体格・対応クラスが紐づく
- ゲーム開始時にグラフィックからランダム選出
- 名前は性別ごとのストック（assets/master/names.json）からランダム割り当て。グラフィックとは独立
- ランク（S/A/B/C）はグラフィックとは無関係にランダム割り当て
- 当面は同一人種の人間のみ

### ステータス決定構造
```
最終ステータス = クラス基準値 × ランク補正 × 体格補正 × 性別補正 × 年齢補正
```

| 要素 | 補正幅 | 方向性 |
|------|--------|--------|
| ランク（S〜C） | 約2倍差 | 見た目に非依存。純粋な強さ |
| 体格 | 約2倍差 | サブクラス的に機能。筋肉質=高火力低回避、小柄=低火力高回避 |
| 性別 | ±20% | 男性=近接攻撃力・HP高め、女性=速度・回避・魔法系高め |
| 年齢 | ±20% | 若年=速度・回避高め、壮年=バランス、老年=魔法・耐性高め |

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
    - カメラはデッドゾーン方式（画面の70%）
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
    - Z：近接攻撃（マンハッタン距離1、旧スペースキーから移行）
    - X：遠距離攻撃（射程5タイル、ユークリッド距離）
    - C/V：空（将来用）
  - ターゲット選択モード（Phase 6-1で**ホールド方式**に変更済み）
    - 攻撃キーをホールドしている間がターゲット選択モード（離して発動）
    - ホールド開始時点から pre_delay カウントを開始
    - ターゲットリストをリアルタイム更新（敵の出入りに対応）
    - 矢印キーで循環選択：前方±45°の敵を距離順 → それ以外を距離順
    - キーを離す：フォーカスあり→攻撃発動、キャンセルor敵なし→ノーコストキャンセル
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
    - [x] タイル画像の追加（tile_floor.png / tile_wall.png / tile_rubble.png / tile_corridor.png、なければフォールバック色）
    - [x] RUBBLEタイル追加（type=2、地上は歩行不可・飛行は通過可能）
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
    - [x] AIデバッグパネル（RightPanel下半分）：現在エリアの敵の戦略・ターゲット・キューをリアルタイム表示。F1でON/OFF。デフォルトON（リリース版ではOFF予定）
    - [x] メッセージウィンドウ（MessageWindow.gd）：将来のシステムメッセージ用に保持（現在呼び出し元なし）
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
    - [x] DialogueTrigger.gd：NPC 自発（wants_to_initiate=true）のみ自動トリガーに変更。プレイヤー起点は矢印キーバンプ経由
    - [x] DialogueTrigger.try_trigger_for_member()：矢印キーバンプ用の直接トリガーメソッド
    - [x] PlayerController.gd：npc_bumped シグナル追加（矢印キーで NPC 方向に入力すると発火）
    - [x] game_map._on_npc_bumped()：npc_bumped を受け取り DialogueTrigger.try_trigger_for_member() を呼ぶ
    - [x] DialogueWindow.gd：会話UI（メンバー一覧・選択肢・↑↓/Z/Esc操作）
    - [x] NpcLeaderAI：wants_to_initiate() / will_accept() / get_party_strength() 追加
    - [x] player_controller.gd：is_blocked フラグ追加（会話中は移動・攻撃入力を無効化）
    - [x] vision_system.gd：remove_npc_manager() 追加
    - [x] game_map.gd：_setup_dialogue_system() / 合流処理 / 敵入室による会話中断
    - [x] game_map.gd：会話中は対象 NpcManager の process_mode を DISABLED に設定（NPC 停止）
    - [x] player_controller.gd：_get_valid_targets() で is_friendly チェック追加（合流後の仲間を攻撃対象から除外）
    - [x] dialogue_window.gd：画面下部ポップアップ方式・GRID_SIZE 連動フォントサイズに変更
    - 会話トリガー条件
      - 部屋内の敵が全滅していること
      - プレイヤーと NPC メンバーが隣接（マンハッタン距離1）
      - 通路（エリアIDなし）では会話しない
      - プレイヤー起点：矢印キーで NPC 方向に入力（バンプ検出）
      - NPC 自発：wants_to_initiate=true のとき毎フレーム自動チェック
    - 会話UI
      - NPCパーティーの情報を表示（名前・クラス・ランク・状態）
      - プレイヤーから話しかけた場合の選択肢
        - 「仲間になってほしい」：NPC がプレイヤー傘下に加入、プレイヤーがリーダー維持
        - 「一緒に連れて行ってほしい」：プレイヤーが NPC 傘下に加入、NPC リーダーがリーダー
        - （立ち去る）
      - NPC 側からの申し出（wants_to_initiate=true）：承諾/断る の2択
      - NPCの申し出ロジック：重傷者が過半数（HP<50%）なら申し出
      - NPCリーダーAIの承諾/拒否：プレイヤー総合力 × 1.5 < NPC 総合力なら拒否
    - 合流処理
      - 合流メンバーを party に追加・常時表示
      - VisionSystem・npc_managers から除外（再会話防止）
      - 「連れて行ってほしい」はNPCリーダーをアクティブキャラとして左パネルでハイライト
      - プレイヤーの操作キャラ（hero）は変わらない
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
  - 全体方針プリセット（6種）→ 5項目を一括設定
    - 攻撃: aggressive / surround / same_room / nearest / keep_fighting
    - 防衛: support / surround / cluster / same_as_leader / retreat
    - 待機: standby / surround / cluster / nearest / retreat
    - 追従: support / surround / cluster / same_as_leader / retreat
    - 撤退: standby / surround / cluster / nearest / flee
    - 探索: aggressive / surround / explore(リーダー)・same_room(他) / nearest / retreat
  - 指示ウィンドウ（OrderWindow）
    - 全体方針行: ←→ でプリセット選択、Z で全メンバーに一括適用
    - メンバーテーブル: ↑↓ で行移動、←→ で列移動、Z で値を切替
    - 左パネルに5項目略称を2行で常時表示（行1: 移動+戦闘+標的 / 行2: 隊形+低HP）
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
  - 飛行移動：飛行キャラ（is_flying=true）は WALL・RUBBLE・地上キャラ占有タイルを通過可能
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
  - dungeon_handcrafted.json を再作成（6部屋・11種の敵・3人スタートパーティー）
    - 起動デフォルト：Claude Code 手作りダンジョン（dungeon_handcrafted.json）を直接読み込む。F5 でシーン再スタート
    - 入口部屋に hero + archer + healer の3人パーティー
    - 敵パーティー：goblin・goblin-archer・wolf・zombie・hobgoblin・goblin-mage・dark-knight・dark-mage・dark-priest・salamander
    - NPCパーティー：ゾンビの霊廟に fighter-sword + healer の2人
  - game_map.gd：handcrafted ダンジョン読み込みロジックを復元
- [ ] Phase 9: 操作感・表現強化
  - [x] Phase 9-1: 歩行アニメーション・滑らか移動
    - move_to(pos, duration) に持続時間パラメータを追加。視覚位置を _visual_from→_visual_to へ duration 秒かけて線形補間
    - 衝突判定・grid_pos は即時更新のまま（グリッド単位を維持）
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
    - attack_melee (Z) → Joypad Button 0（A）
    - attack_ranged (X) → Joypad Button 2（X）
    - open_order_window → Joypad Button 4（Back/Select）のみ。キーボード Tab は _input() で KEY_TAB 直接マッチ
    - game_quit → キーボード Esc は _input() で KEY_ESCAPE 直接マッチ。Start ボタンは将来のポーズメニュー用に予約
    - 移動（ui_up/down/left/right）は Godot デフォルトで D-pad・左スティック対応済み
    - デバッグ機能（F1/F5）はキーボードのみ
    - game_map.gd: ゲームパッドは _process() で is_action_just_pressed ポーリング、キーボード Tab/Esc は _input() で physical_keycode 直接マッチ
    - 全カスタム描画 Control ノードに focus_mode = FOCUS_NONE を設定（Tab の UI フォーカスナビゲーション干渉を防止）
    - LB（Joypad Button 9）後退サイクルバグ修正：_refresh_targets() がキャンセル状態を毎フレームリセットしていた問題を修正（was_cancel フラグで保持）
  - [ ] Phase 9-3: 飛翔体グラフィック
    - 飛翔体画像を assets/images/projectiles/ に配置
      - arrow.png（矢：弓使い・ゴブリンアーチャー）
      - magic_bullet.png（魔法弾：魔法使い・ゴブリンメイジ・ダークメイジ）
      - flame.png（炎：サラマンダー）
    - 飛行方向に合わせて rotation で回転。軌道は直線
    - ヒーラー・ダークプリーストの回復・バフは飛翔体なし（別途エフェクト）
    - 当面は magic_bullet.png と flame.png は同じ画像でも可
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
    - ドロップシステム：PartyManager に `party_wiped(items, killer)` シグナル追加、全滅時に発火
    - ゲーム側（game_map）でシグナルを受け、killer の所属パーティーリーダーの inventory に未装備品として追加。item_get 効果音＋メッセージウィンドウ通知
    - グレードフィールドは持たない（補正値の強さがグレードを表す）
    - 複数パーティーによる協力撃破の分配は将来実装
  - [ ] Phase 10-2: 装備システム
    - 装備の着脱・ステータスへの補正値反映
    - クラスと装備の対応制限を実装（アイテムシステム節を参照）
    - 被ダメージ計算に防御判定・防御強度・耐性を反映（戦闘仕様節を参照）
  - [ ] Phase 10-3: 消耗品の使用
    - HP回復ポーション・MP回復ポーション
    - ゲームパッド：LT ホールド＋ABXY で選択・使用（最大4スロット）
    - キーボード操作は実装時に決定
  - [x] Phase 10-4: 指示／ステータスウィンドウ統合
    - 既存の OrderWindow を拡張（order_window.gd）
    - 上部：キャラ一覧テーブル（全体方針プリセット＋5指示項目）
    - 下部：選択中キャラのステータス詳細・装備スロット（空）・所持アイテム（空）
    - ステータス表示：素値・補正値・最終値の3列（例：攻撃力　15　+0　→　15）
    - 開発中は全ステータス項目を表示（HP/MP/攻撃力/防御力/攻撃タイプ/射程/溜め硬直/ランク/飛行/統率力/従順度）
    - 開いている間も時間進行継続（ポーズなし）
    - リーダー操作中：指示の変更可。非リーダー操作中：閲覧のみ（タイトルに「閲覧のみ」表示）
    - 操作列（キャラ切替）はリーダー以外でも常に有効
    - 誰を操作中でも Tab / Select でウィンドウを開ける（旧：リーダーのみ）
    - ステータス欄左側に front.png（なければ face.png、なければプレースホルダー）を表示
    - カーソル位置記憶：ウィンドウ閉じて再度開いたとき前回位置から再開
    - 全体方針→個別方針カーソル移動時は1列目（操作）から開始
    - バグ修正：`_get_char_front_texture()` が sprite_front ファイル不在のとき sprite_face にフォールバックするよう修正（CharacterGenerator 生成キャラは常に sprite_front パスが設定されるため、ファイル存在チェックが必要だった）
- [ ] Phase 11: フロア・ダンジョン拡張
  - [ ] Phase 11-1: 階段実装・フロア遷移
    - 階段を踏んだキャラのみ移動（パーティー分断あり）
    - 操作キャラが別フロアに移動したらカメラはそのキャラを追う
    - 残ったメンバーは AI 行動継続
    - 上のフロアへの移動も可能（往来自由）
    - 倒した敵はフロアをまたいでも復活しない
    - 敵も階段を使って別フロアに移動できる（原則は部屋を守るため自発的には移動しない）
    - フロアは縦方向につながったひとつの大きなダンジョンとして扱う（フロア単位の独立概念なし）
  - [ ] Phase 11-2: 10フロア対応・ダンジョン事前生成方式への移行
    - ダンジョンは10フロア構成を標準とする
    - 深いフロアほど強い敵を配置・アイテムの補正値も高くなる
    - 配布時は Claude Code で事前に100〜1000個のダンジョンJSONを生成してストック、プレイ時にランダム選択
    - F5 は単純なシーン再スタート（`get_tree().reload_current_scene()`）
    - 開発中は手作りダンジョン（dungeon_handcrafted.json）を使用
- [ ] Phase 12: ステージ・バランス調整
- [ ] Phase 13: Steam配布準備

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
| ヒーラー | 杖 | ローブ | ✕ |

- 戦士クラス（剣士・斧戦士）は盾を左手に持つ（グラフィック統一）
- 杖は魔法使い・ヒーラーで共用。magic_power として魔法攻撃力・回復力の両方に効く

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
- **武器**：attack_power・accuracy を補正（魔法系武器は magic_power・accuracy）。加えて block_power も持つ
- **防具（鎧・服・ローブ）**：physical_resistance・magic_resistance を補正
- **盾**：physical_resistance・magic_resistance を補正。加えて block_power も持つ
- 補正がかからないもの：defense_accuracy（防御精度）・move_speed・leadership・obedience・max_hp・max_mp

### ダメージ計算への装備補正反映
- 攻撃力    = キャラ素値 + 武器 attack_power
- 命中精度  = キャラ素値 + 武器 accuracy
- 魔法威力  = キャラ素値 + 杖 magic_power
- 物理耐性  = キャラ素値 + 防具 physical_resistance + 盾 physical_resistance
- 魔法耐性  = キャラ素値 + 防具 magic_resistance + 盾 magic_resistance
- 防御強度  = キャラ素値 + 武器 block_power + 盾 block_power
- OrderWindow のステータス表示は素値・補正値・最終値の3列（例：攻撃力 15 +3 → 18）

### アイテム生成
- 補正値はランダム生成（フロア深度に応じた範囲内）
- 名前はClaude Codeがダンジョン生成時に補正値の強さ・フロア深度を考慮して作成
- グレードフィールドは持たない（補正値の強さがグレードを表す）
- アイテムマスターは `assets/master/items/` に種類ごとに定義

### 敵キャラクターとアイテムの関係
- 敵は装備の概念を持たない（現状のステータスがそのまま戦闘能力）
- 敵パーティーの所持アイテムはドロップ用にパーティー単位で保持するのみ

### アイテムのドロップ
- 敵パーティー全滅時、最後にトドメを刺したキャラの所属パーティーのリーダーが全アイテムを自動取得（未装備品としてリーダーの inventory に追加）
- item_get 効果音を再生
- メッセージウィンドウに取得通知（例：「〇〇が3点のアイテムを入手した」）
- 敵パーティーの所持アイテムはClaude Codeがダンジョン生成時に種族構成を考慮して割り当て
- 複数パーティーによる協力撃破の分配は将来実装

### 消耗品
- HP回復ポーション・MP回復ポーション
- ウィンドウを開かずにフィールドから使用可能
- ゲームパッド：LTホールド＋ABXYで選択・使用（最大4スロット）
- キーボード：未定（後で検討）

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
| MP | `max_mp` / `mp` | マジックポイント（魔法使用時に消費） |
| 攻撃力 | `attack_power` | 物理攻撃のダメージ（近接・遠距離共通） |
| 命中精度 | `accuracy` | 物理攻撃の命中（近接・遠距離共通）。装備実装時に有効化 |
| 魔法威力 | `magic_power` | 魔法ダメージ・回復量の共通値（攻撃魔法・回復魔法の両方に効く） |
| 物理攻撃耐性 / 魔法攻撃耐性 / その他耐性 | （将来実装） | 割合軽減(%)。防具による補正あり |
| 防御精度 | `defense_accuracy` | 防御判定の成功しやすさ。キャラ固有の素値（装備による変化なし） |
| 防御強度 | （装備側） | 防御成功時に無効化できるダメージ量。武器・盾に付くパラメータ |
| 移動速度 | `move_speed` | 単位：秒/タイル（標準0.4） |
| 統率力（leadership） | `leadership` | リーダー側。クラス・ランクから算出して確定後不変。当面は値のみ保持 |
| 従順度（obedience） | `obedience` | 個体側（0.0〜1.0）。クラス・種族・ランクから算出して確定後不変。当面は値のみ保持 |

- 魔法命中精度は `accuracy` と共通（magic_power 系は攻撃・回復とも同じ命中扱い）
- 回復魔法は必ず命中するため、ヒーラー（attack_type="heal"）には OrderWindow の命中精度行を表示しない

### 命中・被ダメージ計算

**着弾判定**（命中精度）：攻撃が狙った対象に向かうか。命中精度が低いと別の敵・味方に誤射する可能性。

**被ダメージ計算フロー**（着弾後）:
1. **防御判定**（防御精度で成功/失敗。背面攻撃は判定スキップ）
   - 成功：攻撃方向に応じた武器・盾の防御強度の合計をダメージからカット
   - 失敗：カットなし
2. **耐性適用**（物理 or 魔法耐性で割合軽減）
   - 残ダメージ × (1 - 耐性%)
3. **最終ダメージ確定**（最低1）

**攻撃方向と使用可能な防具**（戦士クラス：盾は左手）:
| 攻撃方向 | 使用可能な防具 |
|---------|--------------|
| 正面 | 盾＋武器 |
| 左側面 | 盾 |
| 右側面 | 武器 |
| 背面 | なし（防御判定スキップ） |

- 盾を持たないクラスは全方向で武器のみで防御判定
- 左右の判定：攻撃者がキャラの正面から見て左右どちらにいるかで決定（実装時に詳細化）
- ダメージの方向倍率（旧1.0/1.5/2.0倍）は廃止。攻撃方向は防御可否のみに影響する

### 飛行キャラクター
- キャラクターデータに `is_flying` フラグを追加
- WALL・RUBBLE・地上キャラ占有タイルを通過可能（飛行同士はブロックし合う）
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
| ハーピー | 降下（dive） | 飛行（WALL・RUBBLE・地上キャラを無視して移動）。飛行中は地上からの近接攻撃を受けない。地上の敵に隣接して降下攻撃を行う（攻撃中も飛行扱いを維持） |
| サラマンダー | 遠距離（炎＝魔法効果） | 遠距離から火を吐く |
| ダークナイト | 近接 | 人間型の強敵 |
| ダークメイジ | 遠距離（魔法） | 人間型。後方から魔法攻撃 |
| ダークプリースト | 支援（回復・バリア） | 人間型。後方で仲間を回復・強化 |

### 攻撃仕様
- 攻撃タイプ（CharacterData.attack_type）
  - melee（近接）: 隣接した地上の敵を攻撃。カウンター有効。飛行→飛行NG、地上→飛行NG
  - ranged（遠距離）: 射程内の全対象に飛翔体で攻撃。カウンター無効
  - dive（降下）: 飛行キャラが地上の隣接対象に降下攻撃。カウンター有効
- 種類：単体（当面。将来は範囲も追加）
- 属性タイプ：physical／magic（当面はphysicalのみ）
- クールタイム：事前（ため・詠唱）・事後（硬直）の両方あり
- キャラクターデータにpre_delay・post_delayとして持つ

### ターゲット選択中のpre_delay進行
- 攻撃ボタン（Z/X）ホールド開始時点からpre_delayのカウントを開始する
- ホールド中も時間が進行し、pre_delayが消化される
- キーリリース時に残りのpre_delayがあればFIRINGステートで消化してから発動。残り0以下なら即発動
- これによりプレイヤーが慌てずにターゲットを選べる（素早く選べば待ち時間なし）

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

## GDScript 警告の運用方針
- `warnings/inference_on_variant=1`（project.godot に設定済み）により、Variant 推論警告はエラー扱いせず警告として表示する
- 警告はビルドを通すが、放置はしない。コミットの節目に以下のコマンドで一覧を確認し、まとめて修正する：
  ```
  godot --headless --check-only 2>&1
  ```
- 典型的な修正パターン：`:=` による型推論 → `var x: 型 =` または戻り値に `as 型` を付けて明示

## 将来実装項目（未フェーズ）
- お金の概念・商店：アイテムシステム完成後に改めて設計
- 複数パーティーによるアイテム分配：現在は最後にトドメを刺したパーティーの総取り
- BGM
- ポーズメニュー（ゲーム終了・オプション設定などを含むメニュー）：Startボタンで開く。現在はStartボタン未割り当て

## 参照ファイル
- docs/spec.md：詳細仕様書（実装前に参照すること）
