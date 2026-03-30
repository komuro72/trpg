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
	p += "- タイル種別：FLOOR(0)=部屋の床、WALL(1)=壁、RUBBLE(2)=瓦礫、CORRIDOR(3)=通路\n"
	p += "- 通路はCorridorsで部屋間の接続情報のみ記述する（タイルデータはエンジン側で生成）\n"
	p += "- 階段（stairs）は各フロアに2〜3か所（1層目にはdown階段のみ、最下層にはup階段のみ）\n"
	p += "- 入口部屋にはenemyを配置しない、is_entrance: trueを設定する\n"
	p += "- 1層目の入口部屋にプレイヤーを配置（is_entranceをtrueにする）\n"
	p += "- 敵のx/y座標は部屋の絶対座標で指定する\n"
	p += "- 各部屋・通路に name フィールドを追加する（ダークファンタジーの雰囲気に合わせた日本語名。例：「古びた礼拝堂」「血塗られた回廊」「処刑場跡」「骸骨の間」など）\n\n"
	p += "【使用可能な敵の種類と配置ガイドライン】\n"
	p += "- goblin: 最も基本的な敵。2〜4体の集団で配置（臆病・逃げやすい）\n"
	p += "- goblin-archer: 弓使いゴブリン。ゴブリンの後方に1〜2体（遠距離攻撃）\n"
	p += "- goblin-mage: 魔法使いゴブリン。ゴブリンの後方に1体（MP制限あり）\n"
	p += "- hobgoblin: ゴブリンの上位種。goblinと混成で1体（強い・絶対逃げない）\n"
	p += "- zombie: アンデッド。2〜3体の集団（低速・止まらない）\n"
	p += "- wolf: 狼。2〜4体の群れ（高速・側面攻撃）\n"
	p += "- harpy: 飛行型。1〜3体（飛行・障害物無視）\n"
	p += "- salamander: 炎を吐く大型トカゲ。1〜2体（遠距離火炎・後退行動）\n"
	p += "- dark-knight: 人型の強敵。1〜2体（高防御・絶対逃げない。深層向き）\n"
	p += "- dark-mage: 人型の魔法使い。1〜2体（遠距離魔法・MP制限。深層向き）\n"
	p += "- dark-priest: 人型の支援役。1体（仲間を回復・バフ。他の人型と組み合わせる）\n\n"
	p += "【フロア別の敵配置目安】\n"
	p += "- 1層（浅い）: goblin、goblin-archer、zombie、wolf中心\n"
	p += "- 2層（中間）: goblin、hobgoblin、harpy、salamander、wolf中心\n"
	p += "- 3層（深い）: dark-knight、dark-mage、dark-priest、hobgoblin、salamander中心\n"
	p += "- 各部屋の敵は2〜5体。単一種族または2種族の混成パーティー\n\n"
	p += "【出力フォーマット（このJSONのみ返すこと、説明文不要）】\n"
	p += '{"dungeon":{"floors":[{"floor":1,"entrance_room":"r1_1","rooms":[{"id":"r1_1","name":"廃墟の入口","x":2,"y":2,"width":12,"height":10,"type":"normal","is_entrance":true,"enemy_party":{"members":[]}},{"id":"r1_2","name":"古びた礼拝堂","x":20,"y":2,"width":14,"height":12,"type":"normal","is_entrance":false,"enemy_party":{"members":[{"enemy_id":"goblin","x":22,"y":4},{"enemy_id":"goblin","x":24,"y":6},{"enemy_id":"goblin-archer","x":26,"y":6}]}}],"corridors":[{"from":"r1_1","to":"r1_2","name":"血塗られた回廊"}],"stairs":[{"room":"r1_2","direction":"down"}]}]}}'
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
