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
	"magician-fire":   "魔法使い",
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
const ITEM_PICKUP_RANGE: int = 5
## 瀕死判定閾値（HP率がこれ以下で「瀕死」と判定。HPポーション使用・on_low_hp発動・heal対象選定に使用）
const NEAR_DEATH_THRESHOLD: float = 0.25
## 劣勢判定閾値（パーティーの生存率がこれ以下で「劣勢」と判定。special_skill「劣勢なら使う」に使用）
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
