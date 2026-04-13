class_name HUD
extends CanvasLayer

## ステータス表示HUD
## Phase 2-4: プレイヤーと各敵のHP・状態をテキストで画面左上に表示

var _player: Character
var _enemies: Array[Character] = []
var _label: Label


func _ready() -> void:
	layer = 10  # ゲーム画面より手前に表示

	# 背景パネル（視認性確保）
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.55)
	panel.size = Vector2(220, 200)
	panel.position = Vector2(8, 8)
	add_child(panel)

	_label = Label.new()
	_label.position = Vector2(14, 14)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_label)


func setup(player: Character, enemies: Array[Character]) -> void:
	_player  = player
	_enemies = enemies


func _process(_delta: float) -> void:
	var lines: PackedStringArray = []

	if _player != null and is_instance_valid(_player):
		lines.append("■ Player  HP: %d / %d  [%s]" % \
			[_player.hp, _player.max_hp, _player.get_condition()])

	lines.append("")  # 空行で区切り

	for enemy: Character in _enemies:
		if is_instance_valid(enemy):
			lines.append("▲ %s  HP: %d / %d  [%s]" % \
				[enemy.name, enemy.hp, enemy.max_hp, enemy.get_condition()])

	_label.text = "\n".join(lines)


