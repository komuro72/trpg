class_name CharacterData
extends Resource

## キャラクターデータ管理リソース
## パラメータ・画像パスはJSONから読み込む。素材差し替え時はJSONを変更するだけでよい。

var character_id: String = ""
var character_name: String = ""
var sprite_front: String = ""
var sprite_back: String = ""
var sprite_left: String = ""
var sprite_right: String = ""

## 基本ステータス
var max_hp: int = 1
var attack: int = 1
var defense: int = 0

## LLM行動生成用：自然言語でキャラクターの行動傾向を記述する
var behavior_description: String = ""

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
	data.behavior_description = d.get("behavior_description", "")
	data.pre_delay            = float(d.get("pre_delay", 0.3))
	data.post_delay           = float(d.get("post_delay", 0.5))

	var sprites: Dictionary = d.get("sprites", {})
	data.sprite_front = sprites.get("front", "")
	data.sprite_back  = sprites.get("back", "")
	data.sprite_left  = sprites.get("left", "")
	data.sprite_right = sprites.get("right", "")

	return data


## ヒーロー用データをJSONから生成する
static func create_hero() -> CharacterData:
	return load_from_json("res://assets/master/characters/hero.json")


## ゴブリン用データをJSONから生成する
static func create_goblin() -> CharacterData:
	return load_from_json("res://assets/master/enemies/goblin.json")


## 指定した向きの画像パスを返す
func get_sprite_path(direction: int) -> String:
	match direction:
		0: return sprite_front  # Direction.FRONT
		1: return sprite_back   # Direction.BACK
		2: return sprite_left   # Direction.LEFT
		3: return sprite_right  # Direction.RIGHT
	return sprite_front
