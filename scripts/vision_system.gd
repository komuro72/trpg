class_name VisionSystem
extends Node

## 視界システム
## Phase 5: 部屋単位の視界管理。同じエリアの敵のみ表示・アクティブ化する
## Phase 6改: 訪問済みエリア管理を追加。
##   - 未訪問エリアのタイル・敵は非表示
##   - 一度訪問したエリアはずっと表示（暗くしない）
##   - 訪問済みフラグはパーティー単位で管理（将来の仲間視界共有に対応）
## Phase 11-1: フロアインデックスごとに訪問済みエリア・可視タイルを管理。
##   switch_floor() でアクティブフロアを切り替える。

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
var _current_floor_index: int = 0

## フロアごとの訪問済みエリア管理
## [ floor_index -> { party_id: int -> { area_id: String -> true } } ]
var _floor_visited: Array = []

## フロアごとの可視タイルキャッシュ
## [ floor_index -> { Vector2i -> true } ]
var _floor_visible_tiles: Array = []

## 現在フロアの可視タイル（_floor_visible_tiles[_current_floor_index] への参照）
var _visible_tiles: Dictionary = {}

## エリアデータが存在するか（存在しない場合は視界システムを無効化して全タイル表示）
var _has_area_data: bool = false

## デバッグ時に未探索区域を表示するフラグ（F1 PartyStatusWindow 表示中に true）
var debug_show_all: bool = false

## PartyStatusWindow で別フロアを閲覧中のフロアインデックス（-1=通常・game_map が設定）
var debug_view_floor: int = -1


func setup(player: Character, map_data: MapData) -> void:
	_player   = player
	_map_data = map_data
	_current_floor_index = player.current_floor

	_ensure_floor_data(_current_floor_index)
	(_floor_visited[_current_floor_index] as Dictionary)[PLAYER_PARTY_ID] = {}
	_visible_tiles = _floor_visible_tiles[_current_floor_index] as Dictionary

	# 開始エリアを即座に訪問済みにする
	var start_area := map_data.get_area(player.grid_pos)
	_has_area_data = not start_area.is_empty()
	if _has_area_data:
		_visit_area(PLAYER_PARTY_ID, start_area)
		_current_area = start_area


## パーティーをセットする（メンバー全員の移動を探索トリガーとして使用）
func set_party(party: Party) -> void:
	_party = party


func add_enemy_manager(em: PartyManager) -> void:
	_enemy_managers.append(em)


func remove_enemy_manager(em: PartyManager) -> void:
	_enemy_managers.erase(em)


func add_npc_manager(nm: PartyManager) -> void:
	_npc_managers.append(nm)


func remove_npc_manager(nm: PartyManager) -> void:
	_npc_managers.erase(nm)


func get_current_area() -> String:
	return _current_area


## 指定エリアがいずれかのパーティーメンバーに訪問済みかどうかを返す
func is_area_visited(area_id: String) -> bool:
	if _current_floor_index >= _floor_visited.size():
		return false
	var fv := _floor_visited[_current_floor_index] as Dictionary
	for party_id: int in fv.keys():
		if (fv[party_id] as Dictionary).has(area_id):
			return true
	return false


## 可視タイルの辞書を返す（game_map._draw() で使用）
## エリアデータが存在しない場合、またはデバッグ全表示中は空辞書を返す（呼び出し側が全タイル描画にフォールバック）
func get_visible_tiles() -> Dictionary:
	if debug_show_all:
		return {}
	return _visible_tiles


## アクティブフロアを切り替える（階段遷移時に呼ぶ）
## 新フロアの MapData と、遷移後のプレイヤーを渡す
func switch_floor(floor_index: int, map_data: MapData, player: Character) -> void:
	_current_floor_index = floor_index
	_map_data  = map_data
	_player    = player
	_current_area = ""

	_ensure_floor_data(floor_index)
	# 訪問済みパーティーデータが未初期化なら初期化
	var fv := _floor_visited[floor_index] as Dictionary
	if not fv.has(PLAYER_PARTY_ID):
		fv[PLAYER_PARTY_ID] = {}

	# _visible_tiles を新フロアのキャッシュにリバインド（参照渡し）
	_visible_tiles = _floor_visible_tiles[floor_index] as Dictionary

	# 開始エリアを即座に訪問済みにする
	var start_area := map_data.get_area(player.grid_pos)
	_has_area_data = not start_area.is_empty()
	if _has_area_data and not start_area.is_empty() and not is_area_visited(start_area):
		_visit_area(PLAYER_PARTY_ID, start_area)
		_current_area = start_area
	else:
		_current_area = start_area


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
			if not is_instance_valid(m):
				continue
			var ch := m as Character
			if ch == null or ch == _player:
				continue
			var member_area := _map_data.get_area(ch.grid_pos)
			if _has_area_data and not member_area.is_empty() and not is_area_visited(member_area):
				_visit_area(PLAYER_PARTY_ID, member_area)

	# プレイヤーパーティーがいるエリアの隣接エリアを先行可視化
	if _has_area_data:
		_reveal_adjacent_areas()

	# フレンドリーキャラ（プレイヤーパーティー + NPC）の占有エリアを収集
	var friendly_areas: Dictionary = {}
	if not _current_area.is_empty():
		friendly_areas[_current_area] = true
	if _party != null:
		for m: Variant in _party.members:
			if not is_instance_valid(m):
				continue
			var ch := m as Character
			if ch != null:
				var a := _map_data.get_area(ch.grid_pos)
				if not a.is_empty():
					friendly_areas[a] = true
	for nm_var: Variant in _npc_managers:
		var nm := nm_var as PartyManager
		if is_instance_valid(nm):
			for member: Character in nm.get_members():
				if is_instance_valid(member):
					var a := _map_data.get_area(member.grid_pos)
					# NPCのいるエリアは訪問済み判定に関わらず friendly_areas に含める
					# （NPCが自律探索で未訪問部屋に入ったとき敵をアクティブ化する）
					if not a.is_empty():
						friendly_areas[a] = true

	# 敵・NPC マネージャーに可視性を通知
	# デバッグ別フロア閲覧中は debug_view_floor を使用（リーダー先行遷移中の正確な可視判定に必要）
	var vis_floor: int = debug_view_floor if debug_view_floor >= 0 else _current_floor_index
	var visited: Dictionary = {}
	if _current_floor_index < _floor_visited.size():
		visited = (_floor_visited[_current_floor_index] as Dictionary).get(PLAYER_PARTY_ID, {}) as Dictionary
	for em_var: Variant in _enemy_managers:
		var em := em_var as PartyManager
		if is_instance_valid(em):
			em.update_visibility(_current_area, _map_data, visited, friendly_areas, vis_floor, debug_show_all)
	for nm_var: Variant in _npc_managers:
		var nm := nm_var as PartyManager
		if is_instance_valid(nm):
			nm.update_visibility(_current_area, _map_data, visited, {}, vis_floor, debug_show_all)


## プレイヤーパーティーメンバーの隣接タイルが未訪問エリアに属していれば先行可視化する
## 通路の端に立ったら次の部屋の中が見える（部屋のタイルに隣接するまで発動しない）
func _reveal_adjacent_areas() -> void:
	var positions: Array[Vector2i] = []
	if _player != null and is_instance_valid(_player):
		positions.append(_player.grid_pos)
	if _party != null:
		for m: Variant in _party.members:
			if not is_instance_valid(m):
				continue
			var ch := m as Character
			if ch != null and ch != _player:
				positions.append(ch.grid_pos)
	for pos: Vector2i in positions:
		var my_area := _map_data.get_area(pos)
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1)]:
			var npos := pos + offset
			var neighbor_area := _map_data.get_area(npos)
			if not neighbor_area.is_empty() and neighbor_area != my_area \
					and not is_area_visited(neighbor_area):
				_visit_area(PLAYER_PARTY_ID, neighbor_area)


## 指定パーティーがエリアを訪問する
func _visit_area(party_id: int, area_id: String) -> void:
	var fv := _floor_visited[_current_floor_index] as Dictionary
	if not fv.has(party_id):
		fv[party_id] = {}
	(fv[party_id] as Dictionary)[area_id] = true
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


## フロアデータ配列を必要なサイズに拡張する
func _ensure_floor_data(floor_index: int) -> void:
	while _floor_visited.size() <= floor_index:
		_floor_visited.append({})
	while _floor_visible_tiles.size() <= floor_index:
		_floor_visible_tiles.append({})
