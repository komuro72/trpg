class_name VisionSystem
extends Node

## 視界システム
## Phase 5: 部屋単位の視界管理。同じエリアの敵のみ表示・アクティブ化する
## Phase 6改: 訪問済みエリア管理を追加。
##   - 未訪問エリアのタイル・敵は非表示
##   - 一度訪問したエリアはずっと表示（暗くしない）
##   - 訪問済みフラグはパーティー単位で管理（将来の仲間視界共有に対応）

## エリアが変わったとき（通路含む）
signal area_changed(new_area: String)
## 新エリアを訪問してタイルが開示されたとき（game_map の再描画用）
signal tiles_revealed()

## プレイヤーパーティーID（将来複数パーティー対応時に拡張）
const PLAYER_PARTY_ID := 1

var _player: Character
var _party: Party = null   ## パーティー全員の探索に使用（set_party() で設定）
var _map_data: MapData
var _enemy_managers: Array = []
var _npc_managers: Array = []
var _current_area: String = ""

## パーティー単位の訪問済みエリア管理
## { party_id: int -> { area_id: String -> true } }
var _visited_by_party: Dictionary = {}

## 可視タイルのキャッシュ { Vector2i -> true }
## 訪問済みエリアのタイル + 隣接壁タイルを保持する
var _visible_tiles: Dictionary = {}

## エリアデータが存在するか（存在しない場合は視界システムを無効化して全タイル表示）
var _has_area_data: bool = false


func setup(player: Character, map_data: MapData) -> void:
	_player   = player
	_map_data = map_data
	_visited_by_party[PLAYER_PARTY_ID] = {}

	# 開始エリアを即座に訪問済みにする
	var start_area := map_data.get_area(player.grid_pos)
	_has_area_data = not start_area.is_empty()
	if _has_area_data:
		_visit_area(PLAYER_PARTY_ID, start_area)
		_current_area = start_area


## パーティーをセットする（メンバー全員の移動を探索トリガーとして使用）
func set_party(party: Party) -> void:
	_party = party


func add_enemy_manager(em: EnemyManager) -> void:
	_enemy_managers.append(em)


func add_npc_manager(nm: NpcManager) -> void:
	_npc_managers.append(nm)


func remove_npc_manager(nm: NpcManager) -> void:
	_npc_managers.erase(nm)


func get_current_area() -> String:
	return _current_area


## 指定エリアがいずれかのパーティーメンバーに訪問済みかどうかを返す
func is_area_visited(area_id: String) -> bool:
	for party_id: int in _visited_by_party.keys():
		if (_visited_by_party[party_id] as Dictionary).has(area_id):
			return true
	return false


## 可視タイルの辞書を返す（game_map._draw() で使用）
## エリアデータが存在しない場合は空辞書を返す（呼び出し側が全タイル描画にフォールバック）
func get_visible_tiles() -> Dictionary:
	return _visible_tiles


func _process(_delta: float) -> void:
	if _player == null or _map_data == null:
		return

	var area := _map_data.get_area(_player.grid_pos)
	if area != _current_area:
		_current_area = area
		area_changed.emit(area)
		# 部屋に入ったとき（通路=空文字を除く）に入室音を再生
		if not area.is_empty():
			SoundManager.play(SoundManager.ROOM_ENTER)
		# 未訪問エリアに入ったら訪問済みにしてタイルを開示
		if _has_area_data and not area.is_empty() and not is_area_visited(area):
			_visit_area(PLAYER_PARTY_ID, area)

	# パーティーメンバーの移動も探索判定に加える
	if _party != null:
		for m: Variant in _party.members:
			var ch := m as Character
			if not is_instance_valid(ch) or ch == _player:
				continue
			var member_area := _map_data.get_area(ch.grid_pos)
			if _has_area_data and not member_area.is_empty() and not is_area_visited(member_area):
				_visit_area(PLAYER_PARTY_ID, member_area)

	# 敵・NPC マネージャーに可視性を通知
	var visited := _visited_by_party.get(PLAYER_PARTY_ID, {}) as Dictionary
	for em_var: Variant in _enemy_managers:
		var em := em_var as EnemyManager
		if is_instance_valid(em):
			em.update_visibility(_current_area, _map_data, visited)
	for nm_var: Variant in _npc_managers:
		var nm := nm_var as NpcManager
		if is_instance_valid(nm):
			nm.update_visibility(_current_area, _map_data, visited)


## 指定パーティーがエリアを訪問する
func _visit_area(party_id: int, area_id: String) -> void:
	(_visited_by_party[party_id] as Dictionary)[area_id] = true
	_reveal_tiles(area_id)
	tiles_revealed.emit()


## エリアのタイルと隣接する壁タイルを可視タイルセットに追加する
func _reveal_tiles(area_id: String) -> void:
	var area_tiles := _map_data.get_tiles_in_area(area_id)
	for pos: Vector2i in area_tiles:
		_visible_tiles[pos] = true
		# 隣接する壁タイルも表示（8方向）
		for offset: Vector2i in [
			Vector2i( 0,  1), Vector2i( 0, -1),
			Vector2i( 1,  0), Vector2i(-1,  0),
			Vector2i( 1,  1), Vector2i( 1, -1),
			Vector2i(-1,  1), Vector2i(-1, -1),
		]:
			var npos := pos + offset
			if _map_data.get_tile(npos) == MapData.TileType.WALL:
				_visible_tiles[npos] = true
