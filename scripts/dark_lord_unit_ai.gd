class_name DarkLordUnitAI
extends UnitAI

## ダークロード個体AI
## behavior_description: "暗黒の覇者。3秒ごとにランダムにワープし、着地点に炎陣を設置する。絶対に逃げない。"
##
## 従順度: 1.0
## ワープ: WARP_INTERVAL 秒ごとにランダムな空きタイルへ瞬間移動
## 炎陣:   ワープ後にワープ先（自分の位置）に FlameCircle を設置
## 通常攻撃: 近接（melee）は UnitAI に委譲

const WARP_INTERVAL := 3.0   ## ワープ間隔（秒）
const FLAME_RADIUS  := 2     ## 炎陣の半径（タイル）
const FLAME_DAMAGE  := 4     ## 炎陣の tick ダメージ
const FLAME_DURATION := 3.0  ## 炎陣の持続時間（秒）
const WARP_RANGE    := 8     ## ワープ先の最大探索半径（タイル）

var _warp_timer: float = WARP_INTERVAL  ## 初回は WARP_INTERVAL 後にワープ


func _init() -> void:
	obedience = 1.0


## 自己保存フック: 絶対に逃げない
func _resolve_strategy(ordered_strategy: Strategy) -> Strategy:
	if ordered_strategy == Strategy.FLEE:
		return Strategy.ATTACK
	return ordered_strategy


## _process をオーバーライドしてワープロジックを追加する
func _process(delta: float) -> void:
	# 通常の AI 処理（移動・攻撃など）
	super._process(delta)

	# ワープタイマーは world_time_running 中のみカウント
	if not GlobalConstants.world_time_running:
		return
	if _member == null or not is_instance_valid(_member):
		return
	if _member.is_player_controlled or _member.is_stunned or _member.hp <= 0:
		return

	_warp_timer -= delta / GlobalConstants.game_speed
	if _warp_timer <= 0.0:
		_warp_timer = WARP_INTERVAL
		_do_warp()


## ランダムな空きタイルへワープし、炎陣を設置する
func _do_warp() -> void:
	if _map_data == null or _member == null or not is_instance_valid(_member):
		return

	var dest := _find_warp_destination()
	if dest == Vector2i(-1, -1):
		return  # 適切なワープ先が見つからなかった

	# ワープ実行（sync_position で瞬間移動）
	_member.grid_pos = dest
	_member.sync_position()

	# ワープ先に炎陣を設置
	_place_flame_circle(_member.position)


## ワープ先候補を探す（WARP_RANGE タイル内のランダムな通過可能タイル）
func _find_warp_destination() -> Vector2i:
	var candidates: Array[Vector2i] = []
	var origin: Vector2i = _member.grid_pos

	for dx: int in range(-WARP_RANGE, WARP_RANGE + 1):
		for dy: int in range(-WARP_RANGE, WARP_RANGE + 1):
			if dx == 0 and dy == 0:
				continue
			var pos := Vector2i(origin.x + dx, origin.y + dy)
			if not _map_data.is_walkable(pos):
				continue
			if _is_occupied(pos):
				continue
			candidates.append(pos)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	return candidates[randi() % candidates.size()]


## 指定ワールド座標に FlameCircle を設置する
func _place_flame_circle(world_pos: Vector2) -> void:
	var map_node := _member.get_parent()
	if map_node == null:
		return

	var flame := FlameCircle.new()
	flame.z_index = 1
	map_node.add_child(flame)
	flame.setup(
		world_pos,
		_member.grid_pos,
		FLAME_RADIUS,
		FLAME_DAMAGE,
		FLAME_DURATION,
		0.5,
		_member,
		_all_members
	)


## タイルが他キャラに占有されているか確認する
func _is_occupied(pos: Vector2i) -> bool:
	for entry: Variant in _all_members:
		var ch := entry as Character
		if not is_instance_valid(ch) or ch == _member or ch.hp <= 0:
			continue
		if ch.grid_pos == pos:
			return true
	return false
