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

## スプライト素材のソース解像度（差し替え時もここを変えるだけでスケールが追従する）
const SPRITE_SOURCE_WIDTH: int = 512
const SPRITE_SOURCE_HEIGHT: int = 1024

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
const ATTACK_TYPE_MULT: Dictionary = {
	"melee":  0.3,
	"ranged": 0.2,
	"dive":   0.3,
	"magic":  0.2,
}

## フロア難易度ランク（フロアインデックス → ランク和の基準値）
## NPC が同フロアに留まるか上下するかの判断に使用
## rank_sum = 全メンバーの RANK_VALUES（C=3, B=4, A=5, S=6）の合計
## 各フロアの敵パーティー構成を参照して設定（F0: goblin中心, F1: B混成, F2: A混成, F3: 暗黒系A）
## F0→F1: rank_sum≥8（2人BまたはC3+1）/ F1→F2: rank_sum≥13（B3+でも進めない壁）
## F2→F3: rank_sum≥18（A3+以上が必要）/ F3→F4: rank_sum≥24（事実上不達・ボスフロア）
const FLOOR_RANK: Dictionary = {0: 0, 1: 8, 2: 13, 3: 18, 4: 24}

## NPC フロア遷移・戦闘継続の HP 最低閾値（最低 HP 率がこれを下回ると適正フロア-1）
const NPC_HP_THRESHOLD: float = 0.5
## NPC フロア遷移・戦闘継続の エネルギー（MP/SP）平均閾値（平均エネルギー率がこれを下回ると適正フロア-1）
const NPC_ENERGY_THRESHOLD: float = 0.3

## アイテム取得範囲（item_pickup=passive 設定時の取得判定距離・マンハッタン距離）
const ITEM_PICKUP_RANGE: int = 2
## 瀕死判定閾値（HP率がこれ以下で「瀕死」と判定。HPポーション自動使用・on_low_hp発動・heal "aggressive" モード対象選定に使用）
const NEAR_DEATH_THRESHOLD: float = 0.25
## ヒーラー回復閾値（heal "lowest_hp_first" / "leader_first" モードの対象判定。HP率がこれ未満のメンバーが回復対象）
const HEALER_HEAL_THRESHOLD: float = 0.5
## SP/MPポーション自動使用閾値（sp_mp_potion="use" 設定時、SP率/MP率がこれ未満で自動使用）
const POTION_SP_MP_AUTOUSE_THRESHOLD: float = 0.5
## 種族固有自己逃走HP閾値（goblin系の _should_self_flee がこの値未満で true を返す）
const SELF_FLEE_HP_THRESHOLD: float = 0.3
## パーティー逃走の生存率閾値（goblin/wolf リーダー：生存メンバー率がこれ未満で FLEE 戦略に切り替え）
const PARTY_FLEE_ALIVE_RATIO: float = 0.5
## 特殊攻撃の状況判定で使う「隣接敵数の最小値」
## 近接3クラス（剣士・斧戦士・斥候）と magician-fire の発動条件: 隣接8マスの敵がこの数以上
const SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES: int = 2
## 劣勢判定閾値（特殊攻撃「劣勢なら使う」用の参考値。現在は HpStatus enum で代替されており未使用）
const DISADVANTAGE_THRESHOLD: float = 0.6

## NPC が階段の位置を最初から知っているか（true: 地図持ち / false: 探索して発見）
## false の場合、訪問済みエリアにある階段のみ目標にし、未発見なら通常 explore にフォールバック
const NPC_KNOWS_STAIRS_LOCATION: bool = false

## 階段タイル種別定数（MapData.TileType と対応）
const TILE_STAIRS_DOWN: int = 4
const TILE_STAIRS_UP:   int = 5

## アイテム補正キーの日本語名
const STAT_NAME_JP: Dictionary = {
	"power":               "威力",
	"skill":               "技量",
	"physical_resistance": "物理耐性",
	"magic_resistance":    "魔法耐性",
	"defense_strength":    "防御強度",
	## 旧キー互換（セーブデータ等の後方互換用）
	"attack_power":        "威力",
	"magic_power":         "威力",
	"accuracy":            "技量",
}


## ConsumableBar の表示モード（player_controller / consumable_bar の両方から参照）
## ConsumableBar クラス内の enum は外部からアクセス時にパースエラーが出ることがあるため
## Autoload の GlobalConstants に定義して回避する
enum ConsumableDisplayMode { NORMAL, ITEM_SELECT, ACTION_SELECT, TRANSFER_SELECT }

## 状態ラベル（condition）の HP% 閾値（4段階）
## Character.get_condition() が返す文字列の判定基準
## 戦力評価で敵のHP推定に使用する（_estimate_hp_ratio_from_condition）
const CONDITION_HEALTHY_THRESHOLD:  float = 0.5   ## HP50%以上 → "healthy"
const CONDITION_WOUNDED_THRESHOLD:  float = 0.35  ## HP35%以上50%未満 → "wounded"
const CONDITION_INJURED_THRESHOLD:  float = 0.25  ## HP25%以上35%未満 → "injured"
## HP25%未満 → "critical"

## 状態ラベル色（全要素統一・2026-04-17〜）
## スプライト・顔アイコンは wounded 以降で 3Hz 点滅（condition_sprite_modulate）
## ゲージ・テキストは静的（condition_gauge_color / condition_text_color）
const CONDITION_PULSE_HZ: float = 3.0

## スプライト・顔アイコンの modulate 色（白 / 黄 / 橙 / 赤）
const CONDITION_COLOR_SPRITE_HEALTHY:  Color = Color.WHITE
const CONDITION_COLOR_SPRITE_WOUNDED:  Color = Color(1.00, 0.85, 0.20)
const CONDITION_COLOR_SPRITE_INJURED:  Color = Color(1.00, 0.65, 0.25)
const CONDITION_COLOR_SPRITE_CRITICAL: Color = Color(1.00, 0.35, 0.35)

## HP ゲージ色（緑 / 黄 / 橙 / 赤）
const CONDITION_COLOR_GAUGE_HEALTHY:  Color = Color(0.25, 0.80, 0.30)
const CONDITION_COLOR_GAUGE_WOUNDED:  Color = Color(0.95, 0.80, 0.15)
const CONDITION_COLOR_GAUGE_INJURED:  Color = Color(0.95, 0.55, 0.15)
const CONDITION_COLOR_GAUGE_CRITICAL: Color = Color(0.90, 0.20, 0.20)

## 状態ラベルテキスト色（緑 / 黄 / 橙 / 赤）
const CONDITION_COLOR_TEXT_HEALTHY:  Color = Color(0.40, 0.90, 0.40)
const CONDITION_COLOR_TEXT_WOUNDED:  Color = Color(1.00, 0.85, 0.20)
const CONDITION_COLOR_TEXT_INJURED:  Color = Color(1.00, 0.60, 0.20)
const CONDITION_COLOR_TEXT_CRITICAL: Color = Color(1.00, 0.35, 0.35)


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


## スプライト系パレットの静的色（点滅なし・DebugWindow 用）
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

## 戦況判断（_evaluate_combat_situation）の比率閾値
## 自軍戦力 / 敵戦力 の比率で戦況を分類する
const COMBAT_RATIO_OVERWHELMING: float = 2.0  ## 圧倒的優勢
const COMBAT_RATIO_ADVANTAGE:    float = 1.2  ## 優勢
const COMBAT_RATIO_EVEN:         float = 0.8  ## 互角
const COMBAT_RATIO_DISADVANTAGE: float = 0.5  ## 劣勢
## 0.5 未満 → CRITICAL（危険）

## 戦況の分類値（_evaluate_combat_situation の戻り値 "situation" キー）
enum CombatSituation { SAFE, OVERWHELMING, ADVANTAGE, EVEN, DISADVANTAGE, CRITICAL }

## 戦力比の段階（ランク和のみ。HP を含めない純粋な戦力比較）
enum PowerBalance { OVERWHELMING, SUPERIOR, EVEN, INFERIOR, DESPERATE }
const POWER_BALANCE_OVERWHELMING: float = 2.0
const POWER_BALANCE_SUPERIOR:     float = 1.2
const POWER_BALANCE_EVEN:         float = 0.8
const POWER_BALANCE_INFERIOR:     float = 0.5

## 自軍HP充足率の段階（ポーション込み）
enum HpStatus { FULL, STABLE, LOW, CRITICAL }
const HP_STATUS_FULL:    float = 0.75
const HP_STATUS_STABLE:  float = 0.5
const HP_STATUS_LOW:     float = 0.25

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
const GLOBAL_LOW_HP:      Array[String] = ["keep_fighting", "retreat", "flee"]
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
