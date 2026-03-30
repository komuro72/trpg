class_name CharacterData
extends Resource

## キャラクターデータ管理リソース
## パラメータ・画像パスはJSONから読み込む。素材差し替え時はJSONを変更するだけでよい。
## Phase 5:   トップビュー対応。sprite_top（フィールド表示）・sprite_front（UI表示）に変更。
##             is_flying フラグを追加。
## Phase 6-0: クラスシステム対応。class_id / image_set / sprite_face / sex / age / build を追加。
## Phase 8:   MP・攻撃タイプ（melee/ranged/dive）・回復力フィールドを追加。

var character_id: String = ""
var character_name: String = ""

## クラス情報（Phase 6-0〜）
var class_id: String = ""   # クラスID（例: "fighter-sword"）
var sex:      String = ""   # 性別（male / female）
var age:      String = ""   # 年齢（young / adult / elder）
var build:    String = ""   # 体格（slim / medium / muscular）

## 画像セット（Phase 6-0〜）
## フォルダパス（例: "res://assets/images/characters/fighter-sword_male_young_slim_01"）
var image_set:        String = ""
var sprite_top:       String = ""  # フィールド表示用（真上から見た画像）
var sprite_top_ready: String = ""  # ターゲット選択中の構え画像（未設定時は sprite_top を使用）
var sprite_front:     String = ""  # UI・ステータス画面用（全身正面画像）
var sprite_face:      String = ""  # 顔アイコン（LeftPanel 表示用）

## 基本ステータス
var max_hp:  int = 1
var max_mp:  int = 0   ## 0 = MP なし（物理攻撃のみのキャラはデフォルト0）
var attack:  int = 1
var defense: int = 0

## 攻撃タイプ（melee=近接 / ranged=遠距離 / dive=降下攻撃）
## カウンター有効: melee・dive  カウンター無効: ranged（将来実装）
var attack_type: String = "melee"

## 遠距離・回復の射程（タイル数。melee は 1 固定）
var attack_range: int = 1

## 回復力（ヒーラー・ダークプリースト用。1回の回復スキルで回復するHP）
var heal_power: int = 0
## 回復スキルのMP消費
var heal_mp_cost: int = 0

## バフスキルのMP消費（防御力アップなど）
var buff_mp_cost: int = 0

## 飛行キャラクターフラグ
var is_flying: bool = false

## LLM行動生成用：自然言語でキャラクターの行動傾向を記述する
var behavior_description: String = ""

## キャラクターランク（S/A/B/C）。右パネルでのランク色分け表示・ステータス計算に使用
var rank: String = "C"

## 攻撃クールタイム（秒）
var pre_delay: float = 0.3   # 攻撃前の溜め時間
var post_delay: float = 0.5  # 攻撃後の硬直時間

## 統率力（リーダー側）：高いほど無理な指示でも従わせやすい。クラス・ランクから算出して確定後不変。当面は値のみ保持
var leadership: int = 5
## 従順度（個体側）：高いほど指示に素直に従う（0.0〜1.0）。クラス・種族・ランクから算出して確定後不変。当面は値のみ保持
var obedience: float = 0.5


## JSONファイルからCharacterDataを生成する
static func load_from_json(path: String) -> CharacterData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CharacterData: JSONファイルが見つかりません: " + path)
		return null
	var json_text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		push_error("CharacterData: JSONのパースに失敗しました: " + path)
		return null
	var d := parsed as Dictionary

	var data := CharacterData.new()
	data.character_id         = d.get("id", "")
	data.character_name       = d.get("name", "")
	data.max_hp               = int(d.get("hp", 1))
	data.max_mp               = int(d.get("mp", 0))
	data.attack               = int(d.get("attack", 1))
	data.defense              = int(d.get("defense", 0))
	data.attack_type          = d.get("attack_type",  "melee")
	data.attack_range         = int(d.get("attack_range", 1))
	data.heal_power           = int(d.get("heal_power",   0))
	data.heal_mp_cost         = int(d.get("heal_mp_cost", 0))
	data.buff_mp_cost         = int(d.get("buff_mp_cost", 0))
	data.is_flying            = bool(d.get("is_flying", false))
	data.behavior_description = d.get("behavior_description", "")
	data.pre_delay            = float(d.get("pre_delay", 0.3))
	data.post_delay           = float(d.get("post_delay", 0.5))
	data.rank                 = d.get("rank", "C")
	data.leadership           = int(d.get("leadership", 5))
	data.obedience            = float(d.get("obedience", 0.5))

	# クラス情報（Phase 6-0〜）
	data.class_id = d.get("class_id", "")
	data.sex      = d.get("sex",      "")
	data.age      = d.get("age",      "")
	data.build    = d.get("build",    "")

	var sprites: Dictionary = d.get("sprites", {})
	data.image_set        = sprites.get("image_set",  "")
	data.sprite_top       = sprites.get("top",        "")
	data.sprite_front     = sprites.get("front",      "")
	data.sprite_face      = sprites.get("face",       "")
	# 構え画像: sprites.top_ready を優先し、なければトップレベルの ready_image を使用
	var ready := sprites.get("top_ready", "") as String
	if ready.is_empty():
		ready = d.get("ready_image", "") as String
	data.sprite_top_ready = ready

	return data


## ヒーロー用データをJSONから生成する
static func create_hero() -> CharacterData:
	return load_from_json("res://assets/master/characters/hero.json")


## ゴブリン用データをJSONから生成する
static func create_goblin() -> CharacterData:
	return load_from_json("res://assets/master/enemies/goblin.json")
