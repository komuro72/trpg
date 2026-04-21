## メッセージログ管理（Autoload: MessageLog）
## MessageWindow と OrderWindow が共有するログバッファを管理する
## メッセージの種類（system / combat / ai / battle）と色分けを提供する
##
## 表示先の分離：
##   system / battle → MessageWindow（常時表示）
##   combat / ai     → CombatLogWindow のみ（debug_log_added シグナル経由）

extends Node

## メッセージ種別
enum MsgType { SYSTEM, COMBAT, AI, BATTLE }

const LOG_MAX: int = 50

## ログエントリ: { "text": String, "type": MsgType, "color": Color }
## system / battle のみ格納する（combat / ai は entries に追加しない）
var entries: Array[Dictionary] = []

## 新しいエントリが追加されたとき発火するシグナル（system / battle 用）
signal entry_added()

## バトルメッセージが追加されたとき発火するシグナル
## MessageWindow がバスト画像とテキストを更新するために購読する
## attacker / defender は Character 実体（null 可）。死亡判定に使用
signal battle_message_added(attacker_data: CharacterData, defender_data: CharacterData, message: String, attacker: Character, defender: Character)

## combat / ai メッセージが追加されたとき発火するシグナル（CombatLogWindow 用）
## エリアフィルタを無視して全メッセージを発火する
signal debug_log_added(text: String, color: Color)

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


## 戦闘計算メッセージ（黄）— entries には追加しない。debug_log_added シグナルのみ発火
func add_combat(text: String, grid_pos: Vector2i = Vector2i(-1, -1)) -> void:
	var color := Color(1.0, 1.0, 0.3)
	debug_log_added.emit(text, color)


## AI戦略変更メッセージ（水色）— entries には追加しない。debug_log_added シグナルのみ発火
func add_ai(text: String, grid_pos: Vector2i = Vector2i(-1, -1)) -> void:
	var color := Color(0.4, 0.9, 1.0)
	debug_log_added.emit(text, color)


## バトルメッセージ（オレンジ）— エリアフィルタなし・battle_message_added シグナルも発火
## attacker_data / defender_data はエントリ dict に格納し MessageWindow のアイコン表示に使用（null 可）
## attacker / defender は Character 実体（null 可）。MessageWindow の死亡チェックに使用
## segments: Array of {"text": String, "color": Color, "bold": bool（省略可）}
##   省略可。指定時は文字単位で色分け描画する（message は後方互換用にプレーンテキストも保持）
func add_battle(attacker_data: CharacterData, defender_data: CharacterData,
		message: String, attacker: Character = null, defender: Character = null,
		segments: Array = []) -> void:
	var entry: Dictionary = {
		"text": message,
		"type": int(MsgType.BATTLE),
		"color": Color(1.0, 0.60, 0.20),
		"attacker_data": attacker_data,
		"defender_data": defender_data,
	}
	if not segments.is_empty():
		entry["segments"] = segments
	entries.append(entry)
	if entries.size() > LOG_MAX:
		entries = entries.slice(entries.size() - LOG_MAX)
	entry_added.emit()
	battle_message_added.emit(attacker_data, defender_data, message, attacker, defender)


## 現在の表示フィルタに合致するエントリのみ返す（system / battle のみ）
## ※ combat / ai は entries に格納されないため常に SYSTEM と BATTLE のみ返す
func get_visible_entries() -> Array[Dictionary]:
	return entries


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
