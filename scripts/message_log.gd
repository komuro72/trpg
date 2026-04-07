## メッセージログ管理（Autoload: MessageLog）
## MessageWindow と OrderWindow が共有するログバッファを管理する
## メッセージの種類（system / combat / ai）と色分け、デバッグ表示フィルタを提供する

extends Node

## メッセージ種別
enum MsgType { SYSTEM, COMBAT, AI }

## デバッグメッセージ（COMBAT / AI）の表示切替。F1 キーでトグル
var debug_visible: bool = true

const LOG_MAX: int = 50

## ログエントリ: { "text": String, "type": MsgType, "color": Color }
var entries: Array[Dictionary] = []

## 新しいエントリが追加されたとき発火するシグナル
signal entry_added()

## エリアフィルタ用（setup_area_filter で設定）
var _map_data: MapData = null
var _get_player_area: Callable


## エリアフィルタを設定する（game_map から呼ぶ）
## get_player_area: プレイヤーの現在エリアIDを返す Callable
func setup_area_filter(map_data: MapData, get_player_area: Callable) -> void:
	_map_data = map_data
	_get_player_area = get_player_area


## システムメッセージ（白）— エリアフィルタなし
func add_system(text: String) -> void:
	_add(text, MsgType.SYSTEM, Color(1.0, 1.0, 1.0))


## 戦闘計算メッセージ（黄）— grid_pos でエリアフィルタ
func add_combat(text: String, grid_pos: Vector2i = Vector2i(-1, -1)) -> void:
	# デバッグモード中はエリア外の戦闘ログも表示する
	if not debug_visible and not _is_in_player_area(grid_pos):
		return
	_add(text, MsgType.COMBAT, Color(1.0, 1.0, 0.3))


## AI戦略変更メッセージ（水色）— grid_pos でエリアフィルタ
func add_ai(text: String, grid_pos: Vector2i = Vector2i(-1, -1)) -> void:
	if not _is_in_player_area(grid_pos):
		return
	_add(text, MsgType.AI, Color(0.4, 0.9, 1.0))


## デバッグ表示トグル
func toggle_debug() -> void:
	debug_visible = not debug_visible
	entry_added.emit()


## 現在の表示フィルタに合致するエントリのみ返す
func get_visible_entries() -> Array[Dictionary]:
	if debug_visible:
		return entries
	var result: Array[Dictionary] = []
	for e: Dictionary in entries:
		if int(e.get("type", 0)) == int(MsgType.SYSTEM):
			result.append(e)
	return result


## grid_pos のエリアがプレイヤーエリアと一致するか判定する
## grid_pos が (-1,-1) の場合はフィルタなし（後方互換）
func _is_in_player_area(grid_pos: Vector2i) -> bool:
	if grid_pos == Vector2i(-1, -1):
		return true
	if _map_data == null or not _get_player_area.is_valid():
		return true
	var char_area := _map_data.get_area(grid_pos)
	var player_area: String = _get_player_area.call()
	if player_area.is_empty() or char_area.is_empty():
		return true
	return char_area == player_area


func _add(text: String, type: MsgType, color: Color) -> void:
	entries.append({"text": text, "type": int(type), "color": color})
	if entries.size() > LOG_MAX:
		entries = entries.slice(entries.size() - LOG_MAX)
	entry_added.emit()
