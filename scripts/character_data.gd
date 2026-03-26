class_name CharacterData
extends Resource

## キャラクター画像パス一元管理リソース
## 素材差し替え時はここのパスを変えるだけでよい

@export var character_id: String = ""
@export var sprite_front: String = ""
@export var sprite_back: String = ""
@export var sprite_left: String = ""
@export var sprite_right: String = ""


## ヒーロー用データを生成する
static func create_hero() -> CharacterData:
	var data := CharacterData.new()
	data.character_id = "hero"
	data.sprite_front = "res://assets/characters/hero_front.png"
	data.sprite_back  = "res://assets/characters/hero_back.png"
	data.sprite_left  = "res://assets/characters/hero_left.png"
	data.sprite_right = "res://assets/characters/hero_right.png"
	return data


## 指定した向きの画像パスを返す
func get_sprite_path(direction: int) -> String:
	match direction:
		0: return sprite_front  # Direction.FRONT
		1: return sprite_back   # Direction.BACK
		2: return sprite_left   # Direction.LEFT
		3: return sprite_right  # Direction.RIGHT
	return sprite_front
