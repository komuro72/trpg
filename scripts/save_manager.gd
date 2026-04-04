## SaveManager（Autoload: SaveManager）
## セーブデータの読み書き・アクティブセッション管理
## Phase 13: タイトル・セーブ・メニューシステム

extends Node

const SAVE_PATH   := "user://save_slot_%d.json"
const SLOT_COUNT  := 3

var _active_slot:  int      = 0
var _active_save:  SaveData = null
var _session_start: float   = 0.0


## 指定スロットのセーブデータを読み込む（なければ空データを返す）
func get_save_data(slot: int) -> SaveData:
	var path := SAVE_PATH % slot
	if not FileAccess.file_exists(path):
		var sd := SaveData.new()
		sd.slot_index = slot
		return sd
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var sd := SaveData.new()
		sd.slot_index = slot
		return sd
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		var sd := SaveData.new()
		sd.slot_index = slot
		return sd
	return SaveData.from_dict(parsed as Dictionary, slot)


## セーブデータをファイルに書き込む
func write_save(slot: int, data: SaveData) -> void:
	var path := SAVE_PATH % slot
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data.to_dict()))
	file.close()


## 何らかのセーブが存在するか
func has_any_save() -> bool:
	for i: int in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists(SAVE_PATH % i):
			return true
	return false


## セッション開始（スロット・データを確定。ゲーム開始時に呼ぶ）
func start_session(slot: int, data: SaveData) -> void:
	_active_slot   = slot
	_active_save   = data
	_session_start = Time.get_unix_time_from_system()


## 現在アクティブなセーブデータを返す（null = セッション未開始）
func get_active_save() -> SaveData:
	return _active_save


## プレイ時間を加算してファイルに保存する
func flush_playtime() -> void:
	if _active_save == null or _active_slot == 0:
		return
	var elapsed := Time.get_unix_time_from_system() - _session_start
	_active_save.playtime += elapsed
	_session_start = Time.get_unix_time_from_system()
	write_save(_active_slot, _active_save)


## 現在フロアを更新して保存（到達最大フロアのみ更新）
func update_floor(floor_index: int) -> void:
	if _active_save == null or _active_slot == 0:
		return
	if floor_index > _active_save.current_floor:
		_active_save.current_floor = floor_index
	flush_playtime()


## クリアを記録して保存
func record_clear() -> void:
	if _active_save == null or _active_slot == 0:
		return
	_active_save.clear_count += 1
	flush_playtime()
