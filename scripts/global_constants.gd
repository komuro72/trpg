## グローバル定数（Autoload: GlobalConstants）
## グリッドサイズ・UIレイアウト定数を管理する

extends Node

## 縦方向のタイル数（固定・GRID_SIZE計算の基準）
## 1920x1080 基準で GRID_SIZE ≈ 96px になるよう設定（1080 / 11 ≈ 98px）
const TILES_VERTICAL: int = 11

## 左右パネルの幅（タイル数単位）
const PANEL_TILES: int = 3

## グリッド1マスのピクセルサイズ（起動時に動的計算 / デフォルト64）
var GRID_SIZE: int = 64

## ゲーム速度倍率（1.0 = 標準速度）
## 将来の設定画面からここを変更することで全体の速度が変わる
## 移動間隔は各定数 ÷ game_speed で決まる（2.0 = 2倍速、0.5 = 半速）
var game_speed: float = 1.0


## 時間進行フラグ（PlayerController が制御）
## true の間: キャラクターのタイマー（MP/SP回復・スタン・バフ）・AI の _process が進行する
## false の間: 上記が停止する（プレイヤーがターゲット選択中など）
## 影響しないもの: テキスト表示・ヒット/バフエフェクト・Projectile
var world_time_running: bool = false

## クラスIDから日本語名への変換テーブル
const CLASS_NAME_JP: Dictionary = {
	"fighter-sword":   "剣士",
	"fighter-axe":     "斧戦士",
	"archer":          "弓使い",
	"magician-fire":   "魔法使い(火)",
	"magician-water":  "魔法使い(水)",
	"healer":          "ヒーラー",
	"scout":           "斥候",
}

## パーティー最大人数（これを超えて仲間にはできない）
const MAX_PARTY_MEMBERS: int = 12

## 攻撃タイプ別ダメージ倍率（power × type_mult × damage_mult = ベースダメージ）
## 各要素は Config Editor で編集可能な個別 var として定義し、
## _ready() 時に ATTACK_TYPE_MULT 辞書に集約する（既存の .get() アクセス互換性維持）
## [ConfigEditor 対象]
var ATTACK_TYPE_MULT_MELEE:  float = 0.3
var ATTACK_TYPE_MULT_RANGED: float = 0.2
var ATTACK_TYPE_MULT_DIVE:   float = 0.3
var ATTACK_TYPE_MULT_MAGIC:  float = 0.2
## 集約後の辞書（Character / PlayerController / UnitAI から参照）
var ATTACK_TYPE_MULT: Dictionary = {}

## フロア難易度ランク（各フロアの基準ランク和。NPC の下層降下判定で使用）
## NPC の戦力（rank_sum + tier_sum × ITEM_TIER_STRENGTH_WEIGHT × HP率）がこの値以上になると
## 対応するフロアに進む。装備 tier 戦力反映後は同じ基準値でも降下しやすくなる可能性あり
## 設計当初の値（純粋 rank_sum ベース）：F1=8 / F2=13 / F3=18 / F4=24
## [ConfigEditor 対象・NpcLeaderAI カテゴリ]
var FLOOR_0_RANK_THRESHOLD: int = 0
var FLOOR_1_RANK_THRESHOLD: int = 8
var FLOOR_2_RANK_THRESHOLD: int = 13
var FLOOR_3_RANK_THRESHOLD: int = 18
var FLOOR_4_RANK_THRESHOLD: int = 24

## 退避閾値比率：現フロアの基準ランク和の何倍未満で 1 階上に退避するか
## 0.5 = 半分未満で退避（設計当初のハードコード値）
## [ConfigEditor 対象・NpcLeaderAI カテゴリ]
var FLOOR_RETREAT_RATIO: float = 0.5

## NpcLeaderAI の battle_policy 自動書き換えクールダウン（秒）
## 2026-04-21 追加（ステップ 2：CRITICAL 時 battle_policy 自動書き換え）
## 戦況 CRITICAL/SAFE が境界値で振動したときに battle_policy が頻繁に変わるのを抑制する。
## retreat ⇔ attack の切替からこの秒数が経過していないと再書き換えを行わない。
## [ConfigEditor 対象・NpcLeaderAI カテゴリ]
var NPC_POLICY_CHANGE_COOLDOWN: float = 3.0

## アイテム取得範囲（item_pickup=passive 設定時の取得判定距離・マンハッタン距離）
const ITEM_PICKUP_RANGE: int = 2
## 瀕死判定閾値（HP率がこれ以下で「瀕死」と判定。ヒールポーション自動使用・on_low_hp発動・heal "aggressive" モード対象選定に使用）
## [ConfigEditor 対象]
var NEAR_DEATH_THRESHOLD: float = 0.25
## ヒーラー回復閾値（heal "lowest_hp_first" / "leader_first" モードの対象判定。HP率がこれ未満のメンバーが回復対象）
## [ConfigEditor 対象]
var HEALER_HEAL_THRESHOLD: float = 0.5
## SP/MPポーション自動使用閾値（sp_mp_potion="use" 設定時、SP率/MP率がこれ未満で自動使用）
## [ConfigEditor 対象]
var POTION_SP_MP_AUTOUSE_THRESHOLD: float = 0.5
## 種族固有自己逃走HP閾値（goblin系の _should_self_flee がこの値未満で true を返す）
## [ConfigEditor 対象]
var SELF_FLEE_HP_THRESHOLD: float = 0.3

## FLEE 時の逃走先決定ロジック（2026-04-21 ステップ 3 追加）
## `UnitAI._calc_threat_cost()` / `_astar_with_cost()` / 逃走先推奨決定で使用
## 詳細仕様：CLAUDE.md「FLEE 時の逃走先決定ロジック」セクション
## [ConfigEditor 対象・UnitAI カテゴリ]
var FLEE_THREAT_RANGE: int              = 5      ## 敵から何マス以内を危険とみなすか
var FLEE_THREAT_WEIGHT: float           = 3.0    ## 危険マス 1 つあたりのコスト加算量
var FLEE_AREA_DISTANCE_WEIGHT: float    = 10.0   ## 出口 → 避難先の部屋単位 BFS 距離係数
var FLEE_NON_RECOMMENDED_PENALTY: float = 15.0   ## リーダー推奨外出口のペナルティ
var FLEE_REEVAL_MIN_INTERVAL: float     = 0.3    ## エリア変化による強制再評価の最小インターバル（秒）
## パーティー逃走の生存率閾値（goblin/wolf リーダー：生存メンバー率がこれ未満で FLEE 戦略に切り替え）
## [ConfigEditor 対象] 外部 JSON (assets/master/config/constants.json) から読み込み
var PARTY_FLEE_ALIVE_RATIO: float = 0.5
## 特殊攻撃の状況判定で使う「隣接敵数の最小値」
## 近接3クラス（剣士・斧戦士・斥候）の発動条件: 隣接8マスの敵がこの数以上
## [ConfigEditor 対象]
var SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES: int = 2
## 炎陣（magician-fire）の発動判定範囲。自分中心の半径マス数
## この範囲内の敵数が SPECIAL_ATTACK_FIRE_ZONE_MIN_ENEMIES 以上で発動検討
## [ConfigEditor 対象]
var SPECIAL_ATTACK_FIRE_ZONE_RANGE: int = 2
## 炎陣（magician-fire）の発動に必要な範囲内の敵数
## [ConfigEditor 対象]
var SPECIAL_ATTACK_FIRE_ZONE_MIN_ENEMIES: int = 2
## 劣勢判定閾値（特殊攻撃「劣勢なら使う」用の参考値。現在は HpStatus enum で代替されており未使用）
const DISADVANTAGE_THRESHOLD: float = 0.6

## NPC が階段の位置を最初から知っているか（true: 地図持ち / false: 探索して発見）
## false の場合、訪問済みエリアにある階段のみ目標にし、未発見なら通常 explore にフォールバック
const NPC_KNOWS_STAIRS_LOCATION: bool = false

## 階段タイル種別定数（MapData.TileType と対応）
const TILE_STAIRS_DOWN: int = 4
const TILE_STAIRS_UP:   int = 5

## アイテム補正キーの日本語名
## アイテム一覧 / 装備スロット行 / ステータス装備差分で使用（OrderWindow）
const STAT_NAME_JP: Dictionary = {
	"power":               "威力",
	"skill":               "技量",
	"physical_resistance": "物理耐性",
	"magic_resistance":    "魔法耐性",
	"block_right_front":   "右手防御",
	"block_left_front":    "左手防御",
	"block_front":         "両手防御",
	"range_bonus":         "射程",
}


## ConsumableBar の表示モード（player_controller / consumable_bar の両方から参照）
## ConsumableBar クラス内の enum は外部からアクセス時にパースエラーが出ることがあるため
## Autoload の GlobalConstants に定義して回避する
enum ConsumableDisplayMode { NORMAL, ITEM_SELECT, ACTION_SELECT, TRANSFER_SELECT }

## 状態ラベル（condition）の HP% 閾値（4段階）
## Character.get_condition() が返す文字列の判定基準
## 戦力評価で敵のHP推定に使用する（_estimate_hp_ratio_from_condition）
## [ConfigEditor 対象]
var CONDITION_HEALTHY_THRESHOLD:  float = 0.5   ## HP50%以上 → "healthy"
## [ConfigEditor 対象]
var CONDITION_WOUNDED_THRESHOLD:  float = 0.35  ## HP35%以上50%未満 → "wounded"
## [ConfigEditor 対象]
var CONDITION_INJURED_THRESHOLD:  float = 0.25  ## HP25%以上35%未満 → "injured"
## HP25%未満 → "critical"

## 状態ラベル色（全要素統一・2026-04-17〜）
## スプライト・顔アイコンは wounded 以降で点滅（condition_sprite_modulate）
## ゲージ・テキストは静的（condition_gauge_color / condition_text_color）
## [ConfigEditor 対象]
var CONDITION_PULSE_HZ: float = 3.0

## スプライト・顔アイコンの modulate 色（白 / 黄 / 橙 / 赤）
## [ConfigEditor 対象・すべて]
var CONDITION_COLOR_SPRITE_HEALTHY:  Color = Color.WHITE
var CONDITION_COLOR_SPRITE_WOUNDED:  Color = Color(1.00, 0.85, 0.20)
var CONDITION_COLOR_SPRITE_INJURED:  Color = Color(1.00, 0.65, 0.25)
var CONDITION_COLOR_SPRITE_CRITICAL: Color = Color(1.00, 0.35, 0.35)

## HP ゲージ色（緑 / 黄 / 橙 / 赤）
## [ConfigEditor 対象・すべて]
var CONDITION_COLOR_GAUGE_HEALTHY:  Color = Color(0.25, 0.80, 0.30)
var CONDITION_COLOR_GAUGE_WOUNDED:  Color = Color(0.95, 0.80, 0.15)
var CONDITION_COLOR_GAUGE_INJURED:  Color = Color(0.95, 0.55, 0.15)
var CONDITION_COLOR_GAUGE_CRITICAL: Color = Color(0.90, 0.20, 0.20)

## 状態ラベルテキスト色（緑 / 黄 / 橙 / 赤）
## [ConfigEditor 対象・すべて]
var CONDITION_COLOR_TEXT_HEALTHY:  Color = Color(0.40, 0.90, 0.40)
var CONDITION_COLOR_TEXT_WOUNDED:  Color = Color(1.00, 0.85, 0.20)
var CONDITION_COLOR_TEXT_INJURED:  Color = Color(1.00, 0.60, 0.20)
var CONDITION_COLOR_TEXT_CRITICAL: Color = Color(1.00, 0.35, 0.35)


## HP 比率 → 状態ラベル文字列（"healthy"/"wounded"/"injured"/"critical"）
func ratio_to_condition(ratio: float) -> String:
	if ratio >= CONDITION_HEALTHY_THRESHOLD:
		return "healthy"
	elif ratio >= CONDITION_WOUNDED_THRESHOLD:
		return "wounded"
	elif ratio >= CONDITION_INJURED_THRESHOLD:
		return "injured"
	return "critical"


## スプライト・顔アイコン用 modulate 色を返す（wounded 以降は 3Hz 点滅）
## healthy → WHITE 固定  /  wounded・injured・critical → 色 ↔ 暗い同色 を sin で lerp
func condition_sprite_modulate(cond: String) -> Color:
	match cond:
		"healthy":
			return CONDITION_COLOR_SPRITE_HEALTHY
		"wounded":
			return _pulse_color(CONDITION_COLOR_SPRITE_WOUNDED)
		"injured":
			return _pulse_color(CONDITION_COLOR_SPRITE_INJURED)
		_:
			return _pulse_color(CONDITION_COLOR_SPRITE_CRITICAL)


## スプライト系パレットの静的色（点滅なし・PartyStatusWindow 用）
func condition_sprite_color(cond: String) -> Color:
	match cond:
		"healthy": return CONDITION_COLOR_SPRITE_HEALTHY
		"wounded": return CONDITION_COLOR_SPRITE_WOUNDED
		"injured": return CONDITION_COLOR_SPRITE_INJURED
	return CONDITION_COLOR_SPRITE_CRITICAL


## HP ゲージ色（静的・点滅なし）
func condition_gauge_color(cond: String) -> Color:
	match cond:
		"healthy": return CONDITION_COLOR_GAUGE_HEALTHY
		"wounded": return CONDITION_COLOR_GAUGE_WOUNDED
		"injured": return CONDITION_COLOR_GAUGE_INJURED
	return CONDITION_COLOR_GAUGE_CRITICAL


## 状態ラベルテキスト色（静的・点滅なし）
func condition_text_color(cond: String) -> Color:
	match cond:
		"healthy": return CONDITION_COLOR_TEXT_HEALTHY
		"wounded": return CONDITION_COLOR_TEXT_WOUNDED
		"injured": return CONDITION_COLOR_TEXT_INJURED
	return CONDITION_COLOR_TEXT_CRITICAL


## 点滅ヘルパー：ベース色と暗い同色（各成分 ×0.7）を 3Hz で lerp
func _pulse_color(base: Color) -> Color:
	var t := Time.get_ticks_msec() / 1000.0
	var dark := Color(base.r * 0.7, base.g * 0.7, base.b * 0.7, base.a)
	var pulse := (sin(t * TAU * CONDITION_PULSE_HZ) + 1.0) * 0.5
	return base.lerp(dark, pulse)

## 戦況判断（_evaluate_strategic_status）の戦力比閾値
## 自軍戦力 / 敵戦力 の比率で戦況を分類する
## [ConfigEditor 対象・すべて]
var COMBAT_RATIO_OVERWHELMING: float = 2.0  ## 圧倒的優勢
var COMBAT_RATIO_ADVANTAGE:    float = 1.2  ## 優勢
var COMBAT_RATIO_EVEN:         float = 0.8  ## 互角
var COMBAT_RATIO_DISADVANTAGE: float = 0.5  ## 劣勢
## 0.5 未満 → CRITICAL（危険）

## 戦況の分類値（_evaluate_strategic_status の戻り値 "situation" キー）
enum CombatSituation { SAFE, OVERWHELMING, ADVANTAGE, EVEN, DISADVANTAGE, CRITICAL }

## 戦力比の段階（ランク和のみ。HP を含めない純粋な戦力比較）
enum PowerBalance { OVERWHELMING, SUPERIOR, EVEN, INFERIOR, DESPERATE }
## [ConfigEditor 対象・すべて]
var POWER_BALANCE_OVERWHELMING: float = 2.0
var POWER_BALANCE_SUPERIOR:     float = 1.2
var POWER_BALANCE_EVEN:         float = 0.8
var POWER_BALANCE_INFERIOR:     float = 0.5

## 自軍HP充足率の段階（ポーション込み）
enum HpStatus { FULL, STABLE, LOW, CRITICAL }
## [ConfigEditor 対象・すべて]
var HP_STATUS_FULL:    float = 0.75
var HP_STATUS_STABLE:  float = 0.5
var HP_STATUS_LOW:     float = 0.25

## 戦力計算に占める装備 tier の重み係数
## strength_base = rank_sum + party_tier_sum × この値
## 装備 1 セット ≒ ランク 1 段階となる 0.33 が既定
## [ConfigEditor 対象]
var ITEM_TIER_STRENGTH_WEIGHT: float = 0.33

## 近接味方連合・近接敵の最大距離（マンハッタンマス数・自パリーダーからの距離）
## 戦況判断用の nearby_allied / nearby_enemy 集合に含めるメンバーの範囲を決める
## エリアベースの target_areas 判定（廃止済み）の代替
## [ConfigEditor 対象]
var COALITION_RADIUS_TILES: int = 8

## ------------------------------------------------------------
## SkillExecutor 関連（2026-04-18〜）
## ------------------------------------------------------------
## クリティカル率の計算に使用する除数。critical_rate = skill / この値（%表現）
## 例：CRITICAL_RATE_DIVISOR=300 なら skill 30 → 10% のクリ率。数値を下げるとクリ率上昇
## [ConfigEditor 対象]
var CRITICAL_RATE_DIVISOR: float = 300.0
## エネルギー（MP/SP）の自動回復速度（/秒）。各スキルの cost と直接連動するため慎重に調整
## [ConfigEditor 対象]
var ENERGY_RECOVERY_RATE: float = 3.0

## 1 マス移動のベース時間（秒）。move_speed=50 のキャラがこの値で 1 マス移動する
## 実効値 = BASE_MOVE_DURATION × 50 / move_speed（逆比例補正・設計原則「移動関連の二層構造」）
## [ConfigEditor 対象]
var BASE_MOVE_DURATION: float = 0.40

## ガード中の移動時間倍率。2.0 で移動速度が 50% になる（duration を 2 倍にする）
## [ConfigEditor 対象]
var GUARD_MOVE_DURATION_WEIGHT: float = 2.0

## ------------------------------------------------------------
## Effect 関連（2026-04-19〜）
## ------------------------------------------------------------
## 向き変更ディレイ（秒）。キーを押してから実際に向きが変わるまでの tween 時間
## [ConfigEditor 対象]
var TURN_DELAY: float = 0.15
## ターゲット自動キャンセル時のフラッシュ長（秒）。ターゲットが射程外に出て自動キャンセルされた瞬間の視覚フィードバック
## [ConfigEditor 対象]
var AUTO_CANCEL_FLASH: float = 0.25
## スライディング 1 歩の演出秒数（game_speed で除算して使用）。斥候の V 特殊攻撃の体感速度
## [ConfigEditor 対象]
var SLIDING_STEP_DUR: float = 0.12
## フォーカス中ターゲットのアウトライン太さ（screen px）。ターゲット選択中に現在選んでいる対象
## [ConfigEditor 対象]
var OUTLINE_WIDTH_FOCUSED: float = 2.5
## 非フォーカスのターゲット候補アウトライン太さ（screen px）。選択可能な候補の示唆
## [ConfigEditor 対象]
var OUTLINE_WIDTH_UNFOCUSED: float = 1.0
## ターゲット選択時の発光強度倍率（Character._update_modulate 内 Color(s, s, s, 1.0) の s）
## [ConfigEditor 対象]
var TARGETED_MODULATE_STRENGTH: float = 1.5
## 防御バフバリア（BuffEffect）の回転速度（度/秒）
## [ConfigEditor 対象]
var BUFF_EFFECT_ROT_SPEED_DEG: float = 60.0
## 無力化水魔法スタン時の渦（WhirlpoolEffect）の回転速度（度/秒）
## [ConfigEditor 対象]
var WHIRLPOOL_ROT_SPEED_DEG: float = 270.0

## 飛翔体（矢・火弾・水弾・雷弾）の移動速度（px/秒）。
## ダメージ判定は攻撃の瞬間に確定しており、本値は演出速度のみに影響する
## [ConfigEditor 対象]
var PROJECTILE_SPEED: float = 2000.0

## 飛翔体の表示サイズ（GRID_SIZE 比）。解像度非依存（高解像度でも GRID_SIZE に比例して大きくなる）
## 実効表示サイズ = GRID_SIZE × PROJECTILE_SIZE_RATIO（1920x1080 時 GRID_SIZE≈98 → 約 65px = 旧 64px 相当）
## [ConfigEditor 対象]
var PROJECTILE_SIZE_RATIO: float = 0.67

## 降下攻撃エフェクト（DiveEffect）の半径（GRID_SIZE 比）
## 実効半径 = GRID_SIZE × DIVE_EFFECT_RADIUS_RATIO（1920x1080 時 GRID_SIZE≈98 → 約 19.6px = 旧 18px 相当）
## [ConfigEditor 対象]
var DIVE_EFFECT_RADIUS_RATIO: float = 0.2

## スタン時のスプライト脈動周波数（Hz）。CONDITION_PULSE_HZ とは別概念（スタン専用）
## 値は一致しているが仕様上独立。将来別値にしたくなった時のために分離
## [GlobalConstants 集約のみ・UI 非公開]
var STUN_PULSE_HZ: float = 3.0

## ------------------------------------------------------------
## Item 関連（2026-04-19〜・定数ベース事前生成方式）
## ------------------------------------------------------------
## 各アイテムタイプは 2 ステータスを低・中・高の 3 段階で組み合わせた
## 9 パターン（単一ステータスの盾のみ 3 パターン）を事前生成し、
## フロア出現時に「基準段階＋距離重み」でランダム選択する。
## 詳細は docs/history.md の 2026-04-19 エントリおよび
## CLAUDE.md「装備の名前生成」節を参照。

## 低 bonus 段階の比率（対 _max）。例: power_max=30 × 0.33 = 9.9 → 10
## bonus 段階はステータスごとの補正強度（none=0 / low / mid / high）を表す
## [ConfigEditor 対象]
var ITEM_BONUS_LOW_RATIO:  float = 0.33
## 中 bonus 段階の比率（対 _max）。例: power_max=30 × 0.67 = 20.1 → 20
## [ConfigEditor 対象]
var ITEM_BONUS_MID_RATIO:  float = 0.67
## 高 bonus 段階の比率（対 _max）。例: power_max=30 × 1.0 = 30
## [ConfigEditor 対象]
var ITEM_BONUS_HIGH_RATIO: float = 1.0

## フロア 0〜1 の基準 tier（0=none / 1=low / 2=mid / 3=high）
## tier は装備全体の格付け（bonus 段階から ITEM_TIER_POLICY で導出）
## [ConfigEditor 対象]
var FLOOR_0_1_BASE_TIER: int = 1
## フロア 1〜2 の基準 tier
## [ConfigEditor 対象]
var FLOOR_1_2_BASE_TIER: int = 2
## フロア 2〜3 の基準 tier
## [ConfigEditor 対象]
var FLOOR_2_3_BASE_TIER: int = 3

## 基準段階の出現重み。各フロアで最もよく出る段階の重み
## [ConfigEditor 対象]
var FLOOR_BASE_WEIGHT:     int = 5
## 基準 ±1 段階（隣接）の出現重み
## [ConfigEditor 対象]
var FLOOR_NEIGHBOR_WEIGHT: int = 2
## 基準 ±2 段階以上離れた段階の出現重み。0 なら「出ない」
## [ConfigEditor 対象]
var FLOOR_FAR_WEIGHT:      int = 0

## アイテム段階判定方法（"max" / "min" / "avg"）
## bonus 段階（各ステータス）から tier（装備全体の格付け）を導出する policy
## "max": 2 ステータスの高い方を採用（power 中 × block 高 → tier 3=high）
## [ConfigEditor 対象]
var ITEM_TIER_POLICY: String = "max"

## 初期所持ヒールポーション数（全キャラ共通）
## [ConfigEditor 対象]
var INITIAL_POTION_HEAL_COUNT:   int = 5
## 初期所持エナジーポーション数（全キャラ共通）
## [ConfigEditor 対象]
var INITIAL_POTION_ENERGY_COUNT: int = 5

## ダメージ段階の閾値（battle メッセージの「小/中/大/特大ダメージ」判定に使用）
const DAMAGE_LEVEL_SMALL:  int = 5   ## 小ダメージの上限（これ以下）
const DAMAGE_LEVEL_MEDIUM: int = 15  ## 中ダメージの上限（これ以下）
const DAMAGE_LEVEL_LARGE:  int = 30  ## 大ダメージの上限（これ以下）
## 特大ダメージ: DAMAGE_LEVEL_LARGE より大きい

## OrderWindow 全体方針オプション値（order_window / 将来の AI から参照）
## GLOBAL_MOVE: Party.global_orders["move"] の選択肢（move_policy と対応）
const GLOBAL_MOVE:        Array[String] = ["follow", "same_room", "cluster", "explore", "standby"]
## 後方互換エイリアス（旧 GLOBAL_COMBAT → GLOBAL_MOVE）
const GLOBAL_COMBAT:      Array[String] = ["follow", "same_room", "cluster", "explore", "standby"]
const GLOBAL_TARGET:      Array[String] = ["nearest", "weakest", "same_as_leader", "support"]
## on_low_hp の選択肢（2026-04-21 リネーム：retreat → fall_back・全体方針 battle_policy="retreat" との重複解消）
const GLOBAL_LOW_HP:      Array[String] = ["keep_fighting", "fall_back", "flee"]
const GLOBAL_ITEM_PICKUP: Array[String] = ["aggressive", "passive", "avoid"]
const GLOBAL_HP_POTION:   Array[String] = ["use", "never"]
const GLOBAL_SP_MP_POTION: Array[String] = ["use", "never"]

## OrderWindow 個別指示オプション値（非ヒーラー）
const MEMBER_FORMATION:    Array[String] = ["surround", "rush", "rear", "gather"]
const MEMBER_COMBAT:       Array[String] = ["attack", "defense", "flee"]
const MEMBER_ATTACK_TARGET: Array[String] = ["nearest", "weakest", "same_as_leader", "support"]
const MEMBER_SPECIAL:      Array[String] = ["aggressive", "strong_enemy", "disadvantage", "never"]
## OrderWindow 個別指示オプション値（ヒーラー専用）
const MEMBER_HEAL:         Array[String] = ["aggressive", "leader_first", "lowest_hp_first", "none"]
const MEMBER_HEAL_TARGET:  Array[String] = ["lowest_hp", "nearest", "same_as_leader"]


## 画面サイズからGRID_SIZEを計算する
## 縦方向タイル数を固定してGRID_SIZEを決定（最小32px）
func initialize(viewport_size: Vector2) -> void:
	GRID_SIZE = maxi(32, int(viewport_size.y / float(TILES_VERTICAL)))


# ============================================================================
# ConfigEditor 対応：外部 JSON からの定数ロード／セーブ
# ============================================================================

const CONFIG_USER_PATH:    String = "res://assets/master/config/constants.json"
const CONFIG_DEFAULT_PATH: String = "res://assets/master/config/constants_default.json"

## ConfigEditor 管理対象の定数名一覧（var 宣言されているもの）
## 新規に外出しする定数はこのリストに追加する
## 並びは ConfigEditor 画面の「定数」タブに流れる順序となる
## （上から下 → 保存時に constants.json へ書き出す順序）
const CONFIG_KEYS: Array[String] = [
	# Character タブ
	"CONDITION_HEALTHY_THRESHOLD",
	"CONDITION_WOUNDED_THRESHOLD",
	"CONDITION_INJURED_THRESHOLD",
	"CONDITION_PULSE_HZ",
	"CONDITION_COLOR_SPRITE_HEALTHY",
	"CONDITION_COLOR_SPRITE_WOUNDED",
	"CONDITION_COLOR_SPRITE_INJURED",
	"CONDITION_COLOR_SPRITE_CRITICAL",
	"CONDITION_COLOR_GAUGE_HEALTHY",
	"CONDITION_COLOR_GAUGE_WOUNDED",
	"CONDITION_COLOR_GAUGE_INJURED",
	"CONDITION_COLOR_GAUGE_CRITICAL",
	"CONDITION_COLOR_TEXT_HEALTHY",
	"CONDITION_COLOR_TEXT_WOUNDED",
	"CONDITION_COLOR_TEXT_INJURED",
	"CONDITION_COLOR_TEXT_CRITICAL",
	"ATTACK_TYPE_MULT_MELEE",
	"ATTACK_TYPE_MULT_RANGED",
	"ATTACK_TYPE_MULT_DIVE",
	"ATTACK_TYPE_MULT_MAGIC",
	# PartyLeader タブ（戦況判断系）
	"COMBAT_RATIO_OVERWHELMING",
	"COMBAT_RATIO_ADVANTAGE",
	"COMBAT_RATIO_EVEN",
	"COMBAT_RATIO_DISADVANTAGE",
	"POWER_BALANCE_OVERWHELMING",
	"POWER_BALANCE_SUPERIOR",
	"POWER_BALANCE_EVEN",
	"POWER_BALANCE_INFERIOR",
	"HP_STATUS_FULL",
	"HP_STATUS_STABLE",
	"HP_STATUS_LOW",
	"ITEM_TIER_STRENGTH_WEIGHT",
	"COALITION_RADIUS_TILES",
	# NpcLeaderAI タブ
	"FLOOR_0_RANK_THRESHOLD",
	"FLOOR_1_RANK_THRESHOLD",
	"FLOOR_2_RANK_THRESHOLD",
	"FLOOR_3_RANK_THRESHOLD",
	"FLOOR_4_RANK_THRESHOLD",
	"FLOOR_RETREAT_RATIO",
	"NPC_POLICY_CHANGE_COOLDOWN",
	# EnemyLeaderAI タブ
	"PARTY_FLEE_ALIVE_RATIO",
	# UnitAI タブ
	"SELF_FLEE_HP_THRESHOLD",
	"FLEE_THREAT_RANGE",
	"FLEE_THREAT_WEIGHT",
	"FLEE_AREA_DISTANCE_WEIGHT",
	"FLEE_NON_RECOMMENDED_PENALTY",
	"FLEE_REEVAL_MIN_INTERVAL",
	"SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES",
	"SPECIAL_ATTACK_FIRE_ZONE_RANGE",
	"SPECIAL_ATTACK_FIRE_ZONE_MIN_ENEMIES",
	"NEAR_DEATH_THRESHOLD",
	"HEALER_HEAL_THRESHOLD",
	"POTION_SP_MP_AUTOUSE_THRESHOLD",
	# SkillExecutor タブ
	"CRITICAL_RATE_DIVISOR",
	# Character タブ（追加）
	"ENERGY_RECOVERY_RATE",
	"BASE_MOVE_DURATION",
	"GUARD_MOVE_DURATION_WEIGHT",
	# Effect タブ（2026-04-19〜）
	"TURN_DELAY",
	"AUTO_CANCEL_FLASH",
	"SLIDING_STEP_DUR",
	"OUTLINE_WIDTH_FOCUSED",
	"OUTLINE_WIDTH_UNFOCUSED",
	"TARGETED_MODULATE_STRENGTH",
	"BUFF_EFFECT_ROT_SPEED_DEG",
	"WHIRLPOOL_ROT_SPEED_DEG",
	"PROJECTILE_SPEED",
	"PROJECTILE_SIZE_RATIO",
	"DIVE_EFFECT_RADIUS_RATIO",
	# Item タブ（2026-04-19〜・定数ベース事前生成方式）
	"ITEM_BONUS_LOW_RATIO",
	"ITEM_BONUS_MID_RATIO",
	"ITEM_BONUS_HIGH_RATIO",
	"FLOOR_0_1_BASE_TIER",
	"FLOOR_1_2_BASE_TIER",
	"FLOOR_2_3_BASE_TIER",
	"FLOOR_BASE_WEIGHT",
	"FLOOR_NEIGHBOR_WEIGHT",
	"FLOOR_FAR_WEIGHT",
	"ITEM_TIER_POLICY",
	"INITIAL_POTION_HEAL_COUNT",
	"INITIAL_POTION_ENERGY_COUNT",
]

## 最後のセーブ／書き込み結果（ConfigEditor がエラー表示に使う）
## 成功時は空文字、失敗時はエラーメッセージ
var last_config_error: String = ""


func _ready() -> void:
	_load_constants()
	_rebuild_attack_type_mult()


## ATTACK_TYPE_MULT 辞書を 4 個の個別 var から再構築する
## Config Editor での値変更後にも呼び出される想定（将来）
func _rebuild_attack_type_mult() -> void:
	ATTACK_TYPE_MULT = {
		"melee":  ATTACK_TYPE_MULT_MELEE,
		"ranged": ATTACK_TYPE_MULT_RANGED,
		"dive":   ATTACK_TYPE_MULT_DIVE,
		"magic":  ATTACK_TYPE_MULT_MAGIC,
	}


## constants.json から値を読み込む。不足キーは constants_default.json で補完
## 読み込み失敗時はハードコード値を維持してエラーを last_config_error に記録
func _load_constants() -> void:
	last_config_error = ""
	var user_data: Variant = _read_json(CONFIG_USER_PATH)
	var default_data: Variant = _read_json(CONFIG_DEFAULT_PATH)
	if user_data == null and default_data == null:
		last_config_error = "定数 JSON が読み込めません（ハードコード値で継続）"
		push_warning("[GlobalConstants] " + last_config_error)
		return

	for key: String in CONFIG_KEYS:
		var value: Variant = null
		# ユーザー値を優先
		if user_data != null and (user_data as Dictionary).has(key):
			value = (user_data as Dictionary)[key]
		# なければデフォルトの value フィールドを使う
		elif default_data != null and (default_data as Dictionary).has(key):
			value = ((default_data as Dictionary)[key] as Dictionary).get("value")
		if value == null:
			continue
		_apply_value(key, value)


## JSON から 1 ファイル読み込む。失敗時は null
func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_warning("[GlobalConstants] JSON parse failed: " + path)
		return null
	return parsed


## JSON 由来の値を該当メンバーに適用する（型に応じて変換）
func _apply_value(key: String, raw: Variant) -> void:
	var meta := _get_meta_for(key)
	var type_name: String = (meta.get("type", "float") as String) if meta != null else "float"
	match type_name:
		"float":
			set(key, float(raw))
		"int":
			set(key, int(raw))
		"color":
			if raw is Array:
				var arr := raw as Array
				var r: float = float(arr[0]) if arr.size() >= 1 else 0.0
				var g: float = float(arr[1]) if arr.size() >= 2 else 0.0
				var b: float = float(arr[2]) if arr.size() >= 3 else 0.0
				var a: float = float(arr[3]) if arr.size() >= 4 else 1.0
				set(key, Color(r, g, b, a))
		"string":
			# 選択肢（choices）付き文字列は OptionButton で編集する（config_editor.gd）
			# 選択肢なしは LineEdit（将来拡張）
			set(key, str(raw))
		_:
			push_warning("[GlobalConstants] 未対応の型: " + type_name + " key=" + key)


## constants_default.json のメタ情報辞書を返す（type, category, min, max, step, description）
func _get_meta_for(key: String) -> Dictionary:
	var default_data: Variant = _read_json(CONFIG_DEFAULT_PATH)
	if default_data == null or not (default_data as Dictionary).has(key):
		return {}
	return (default_data as Dictionary)[key] as Dictionary


## 現在の値を ConfigEditor UI 用の形式で返す（Color は [r,g,b,a] 配列）
func get_config_value(key: String) -> Variant:
	var v: Variant = get(key)
	if v is Color:
		var c := v as Color
		return [c.r, c.g, c.b, c.a]
	return v


## 現在の定数値を constants.json に書き出す（編集 UI の「保存」ボタン）
## 成功時 true / 失敗時 false + last_config_error にメッセージ
func save_constants() -> bool:
	last_config_error = ""
	var out: Dictionary = {}
	for key: String in CONFIG_KEYS:
		out[key] = get_config_value(key)
	var f := FileAccess.open(CONFIG_USER_PATH, FileAccess.WRITE)
	if f == null:
		last_config_error = "書き込み失敗: %s (err=%d)" % [CONFIG_USER_PATH, FileAccess.get_open_error()]
		push_warning("[GlobalConstants] " + last_config_error)
		return false
	# sort_keys=false で CONFIG_KEYS の宣言順を保持
	f.store_string(JSON.stringify(out, "  ", false))
	f.close()
	return true


## constants_default.json の value を現在値に書き換える（「現在値をデフォルト化」ボタン）
func commit_as_defaults() -> bool:
	last_config_error = ""
	var default_data: Variant = _read_json(CONFIG_DEFAULT_PATH)
	if default_data == null or not default_data is Dictionary:
		last_config_error = "constants_default.json が読み込めません"
		return false
	var dd := default_data as Dictionary
	for key: String in CONFIG_KEYS:
		if not dd.has(key):
			continue
		var entry := dd[key] as Dictionary
		entry["value"] = get_config_value(key)
		dd[key] = entry
	var f := FileAccess.open(CONFIG_DEFAULT_PATH, FileAccess.WRITE)
	if f == null:
		last_config_error = "書き込み失敗: %s (err=%d)" % [CONFIG_DEFAULT_PATH, FileAccess.get_open_error()]
		push_warning("[GlobalConstants] " + last_config_error)
		return false
	# sort_keys=false で元 JSON のキー順・メタ情報の構造を保持
	f.store_string(JSON.stringify(dd, "  ", false))
	f.close()
	return true


## constants_default.json の値で現在値を上書き（「すべてデフォルトに戻す」ボタン）
## 現在メモリ上の値のみ変更・constants.json への書き込みは別途 save_constants() で
func reset_to_defaults() -> void:
	last_config_error = ""
	var default_data: Variant = _read_json(CONFIG_DEFAULT_PATH)
	if default_data == null or not default_data is Dictionary:
		last_config_error = "constants_default.json が読み込めません"
		return
	var dd := default_data as Dictionary
	for key: String in CONFIG_KEYS:
		if not dd.has(key):
			continue
		var entry := dd[key] as Dictionary
		if entry.has("value"):
			_apply_value(key, entry["value"])


## デフォルト値を返す（ConfigEditor の「デフォルト値」列と「薄黄ハイライト」比較用）
func get_default_value(key: String) -> Variant:
	var default_data: Variant = _read_json(CONFIG_DEFAULT_PATH)
	if default_data == null or not default_data is Dictionary:
		return null
	var dd := default_data as Dictionary
	if not dd.has(key):
		return null
	return (dd[key] as Dictionary).get("value")
