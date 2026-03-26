class_name CharacterData
extends Resource

## キャラクター画像パス一元管理リソース
## 素材差し替え時はここのパスを変えるだけでよい

@export var character_id: String = ""
@export var sprite_front: String = ""
@export var sprite_back: String = ""
@export var sprite_left: String = ""
@export var sprite_right: String = ""

## 基本ステータス
@export var max_hp: int = 1
@export var attack: int = 1
@export var defense: int = 0

## LLM行動生成用：自然言語でキャラクターの行動傾向を記述する
@export var behavior_description: String = ""


## ヒーロー用データを生成する
static func create_hero() -> CharacterData:
	var data := CharacterData.new()
	data.character_id = "hero"
	data.sprite_front = "res://assets/characters/hero_front.png"
	data.sprite_back  = "res://assets/characters/hero_back.png"
	data.sprite_left  = "res://assets/characters/hero_left.png"
	data.sprite_right = "res://assets/characters/hero_right.png"
	data.max_hp  = 100
	data.attack  = 10
	data.defense = 5
	data.behavior_description = ""
	return data


## ゴブリン用データを生成する
static func create_goblin() -> CharacterData:
	var data := CharacterData.new()
	data.character_id = "goblin"
	data.max_hp  = 30
	data.attack  = 5
	data.defense = 2
	data.behavior_description = "集団で行動する。臆病な性格で強いと思った相手からはすぐ逃げる。"
	return data


## 指定した向きの画像パスを返す
func get_sprite_path(direction: int) -> String:
	match direction:
		0: return sprite_front  # Direction.FRONT
		1: return sprite_back   # Direction.BACK
		2: return sprite_left   # Direction.LEFT
		3: return sprite_right  # Direction.RIGHT
	return sprite_front
