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
	"melee":  0.5,
	"ranged": 0.2,
	"dive":   0.5,
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


## 画面サイズからGRID_SIZEを計算する
## 縦方向タイル数を固定してGRID_SIZEを決定（最小32px）
func initialize(viewport_size: Vector2) -> void:
	GRID_SIZE = maxi(32, int(viewport_size.y / float(TILES_VERTICAL)))
