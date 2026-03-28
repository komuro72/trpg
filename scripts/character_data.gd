class_name CharacterData
extends Resource

## キャラクターデータ管理リソース
## パラメータ・画像パスはJSONから読み込む。素材差し替え時はJSONを変更するだけでよい。
## Phase 5: トップビュー対応。sprite_top（フィールド表示）・sprite_front（UI表示）に変更。
##          is_flying フラグを追加。

var character_id: String = ""
var character_name: String = ""
var sprite_top: String = ""        # フィールド表示用（真上から見た画像）
var sprite_top_ready: String = ""  # ターゲット選択中の構え画像（未設定時は sprite_top を使用）
var sprite_front: String = ""      # UI・ステータス画面用（正面画像）

## 基本ステータス
var max_hp: int = 1
var attack: int = 1
var defense: int = 0

## 飛行キャラクターフラグ
var is_flying: bool = false

## LLM行動生成用：自然言語でキャラクターの行動傾向を記述する
var behavior_description: String = ""

## 敵ランク（S/A/B/C/D/E/F）。右パネルでのランク色分け表示に使用
var rank: String = "D"

## 攻撃クールタイム（秒）
var pre_delay: float = 0.3   # 攻撃前の溜め時間
var post_delay: float = 0.5  # 攻撃後の硬直時間


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
	data.attack               = int(d.get("attack", 1))
	data.defense              = int(d.get("defense", 0))
	data.is_flying            = bool(d.get("is_flying", false))
	data.behavior_description = d.get("behavior_description", "")
	data.pre_delay            = float(d.get("pre_delay", 0.3))
	data.post_delay           = float(d.get("post_delay", 0.5))
	data.rank                 = d.get("rank", "D")

	var sprites: Dictionary = d.get("sprites", {})
	data.sprite_top       = sprites.get("top",   "")
	data.sprite_front     = sprites.get("front", "")
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
