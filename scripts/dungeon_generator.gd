class_name DungeonGenerator
extends Node

## LLMを使ってダンジョン構造JSONを生成し、ファイルに保存する
## Phase 3: フィールド生成

signal generation_completed(dungeon_data: Dictionary)
signal generation_failed(error: String)

const SAVE_PATH       := "res://assets/master/maps/dungeon_generated.json"
## 一度に生成するフロア数。増やすとトークン消費が増える
const FLOOR_COUNT     := 3
const ROOMS_PER_FLOOR := 5
const MAX_TOKENS      := 4096

var _llm: LLMClient


func _ready() -> void:
	_llm = LLMClient.new()
	_llm.name = "LLMClient"
	_llm.max_tokens = MAX_TOKENS
	add_child(_llm)
	_llm.response_received.connect(_on_response_received)
	_llm.request_failed.connect(_on_request_failed)


## ダンジョン生成を開始する
func generate() -> void:
	if _llm.is_requesting:
		return
	print("[DungeonGenerator] LLMリクエスト送信 (%d層)" % FLOOR_COUNT)
	var seed_val := randi()
	var prompt := _build_prompt(seed_val)
	_llm.request(prompt)


func _build_prompt(seed_val: int) -> String:
	var p := "乱数シード: %d\n" % seed_val
	p += "あなたはタクティクスRPGのダンジョン設計者です。\n"
	p += "以下の仕様に従い、ダンジョン構造データをJSONで生成してください。\n\n"
	p += "【仕様】\n"
	p += "- %d層構造、1フロアに%d部屋\n" % [FLOOR_COUNT, ROOMS_PER_FLOOR]
	p += "- 部屋サイズ：幅10〜20、高さ10〜20タイル\n"
	p += "- 部屋はX/Y座標で配置し、重なりがないようにすること\n"
	p += "- 各部屋の座標はフロア全体に余裕をもって分散させること（各部屋間に最低4タイルの間隔）\n"
	p += "- 部屋は通路（corridors）でつながり、フロア内で分岐があること\n"
	p += "- 階段（stairs）は各フロアに2〜3か所（1層目にはdown階段のみ、最下層にはup階段のみ）\n"
	p += "- 敵：goblinのみ、各部屋に2〜4体配置（入口部屋を除く）\n"
	p += "- 入口部屋にはenemyを配置しない、is_entrance: trueを設定する\n"
	p += "- 1層目の入口部屋にプレイヤーを配置（is_entranceをtrueにする）\n"
	p += "- 敵のx/y座標は部屋の絶対座標で指定する\n\n"
	p += "【出力フォーマット（このJSONのみ返すこと、説明文不要）】\n"
	p += '{"dungeon":{"floors":[{"floor":1,"entrance_room":"r1_1","rooms":[{"id":"r1_1","x":2,"y":2,"width":12,"height":10,"type":"normal","is_entrance":true,"enemy_party":{"members":[]}},{"id":"r1_2","x":20,"y":2,"width":14,"height":12,"type":"normal","is_entrance":false,"enemy_party":{"members":[{"enemy_id":"goblin","x":22,"y":4},{"enemy_id":"goblin","x":24,"y":6}]}}],"corridors":[{"from":"r1_1","to":"r1_2"}],"stairs":[{"room":"r1_2","direction":"down"}]}]}}'
	return p


func _on_response_received(result: Dictionary) -> void:
	print("[DungeonGenerator] レスポンス受信: keys=" + str(result.keys()))

	# "dungeon" キーがある場合（{"dungeon": {"floors": [...]}}）
	var floors_array: Array = []
	if result.has("dungeon") and result["dungeon"] is Dictionary:
		floors_array = ((result["dungeon"] as Dictionary).get("floors", [])) as Array
	# "floors" キーが直接ある場合（{"floors": [...]}）
	elif result.has("floors") and result["floors"] is Array:
		floors_array = result["floors"] as Array
	else:
		var msg := "予期しないJSON構造: " + str(result.keys())
		push_error("[DungeonGenerator] " + msg)
		generation_failed.emit(msg)
		return

	if floors_array.is_empty():
		var msg := "floors 配列が空です"
		push_error("[DungeonGenerator] " + msg)
		generation_failed.emit(msg)
		return

	# 保存用に正規化（常に {"dungeon": {"floors": [...]}} 形式で保存）
	var save_data := {"dungeon": {"floors": floors_array}}
	var json_text := JSON.stringify(save_data, "\t")

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		var msg := "保存先ファイルを開けません (error=%d): %s" % [FileAccess.get_open_error(), SAVE_PATH]
		push_error("[DungeonGenerator] " + msg)
		generation_failed.emit(msg)
		return

	file.store_string(json_text)
	file.close()

	print("[DungeonGenerator] 保存完了 → %s  (%d floors)" % [SAVE_PATH, floors_array.size()])
	generation_completed.emit(save_data)


func _on_request_failed(error: String) -> void:
	push_error("[DungeonGenerator] LLMリクエスト失敗: " + error)
	generation_failed.emit(error)
