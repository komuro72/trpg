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
var game_speed: float = 0.5

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

## フロア難易度ランク（フロアインデックス → 強さスコア基準値）
## NPC が同フロアに留まるか上下するかの判断に使用
## member_score = attack_power + physical_resistance + magic_resistance + defense_accuracy
## ランクC・細身・女性・若い の最弱ケースでも archer≈14, mage≈17 程度を想定して調整済み
const FLOOR_RANK: Dictionary = {0: 5, 1: 12, 2: 20, 3: 30, 4: 45}

## 階段タイル種別定数（MapData.TileType と対応）
const TILE_STAIRS_DOWN: int = 4
const TILE_STAIRS_UP:   int = 5

## アイテム補正キーの日本語名
const STAT_NAME_JP: Dictionary = {
	"attack_power":        "攻撃力",
	"magic_power":         "魔力",
	"accuracy":            "命中",
	"physical_resistance": "物理耐性",
	"magic_resistance":    "魔法耐性",
	"defense_strength":    "防御強度",
}


## 画面サイズからGRID_SIZEを計算する
## 縦方向タイル数を固定してGRID_SIZEを決定（最小32px）
func initialize(viewport_size: Vector2) -> void:
	GRID_SIZE = maxi(32, int(viewport_size.y / float(TILES_VERTICAL)))
