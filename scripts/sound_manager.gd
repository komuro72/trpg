## SoundManager（Autoload: SoundManager）
## 効果音の一元管理。AudioStreamPlayer をプールして同時再生（ポリフォニー）に対応。
## ファイルが存在しない場合は警告なしでスキップ（将来の差し替えも容易）。
extends Node

# --------------------------------------------------------------------------
# 効果音 ID 定数
# --------------------------------------------------------------------------
const MELEE_SLASH   := 0   ## 近接攻撃・斬撃（剣士・ゴブリン等）
const MELEE_AXE     := 1   ## 近接攻撃・斧（斧戦士）
const MELEE_DAGGER  := 2   ## 近接攻撃・ダガー（斥候）
const ARROW_SHOOT   := 3   ## 弓の発射（弓使い・ゴブリンアーチャー）
const MAGIC_SHOOT   := 4   ## 魔法弾の発射（魔法使い・ゴブリンメイジ・ダークメイジ）
const FLAME_SHOOT   := 5   ## 炎の発射（サラマンダー）
const HIT_PHYSICAL  := 6   ## 命中音・物理攻撃
const HIT_MAGIC     := 7   ## 命中音・魔法攻撃
const TAKE_DAMAGE   := 8   ## ダメージを受けた
const DEATH         := 9   ## 死亡
const HEAL          := 10  ## 回復
const ROOM_ENTER    := 11  ## 部屋に入った
const ITEM_GET      := 12  ## アイテム取得
const STAIRS        := 13  ## 階段を使った

const _SOUND_PATHS: Dictionary = {
	MELEE_SLASH:  "res://assets/sounds/slash.ogg",
	MELEE_AXE:    "res://assets/sounds/axe.ogg",
	MELEE_DAGGER: "res://assets/sounds/dagger.ogg",
	ARROW_SHOOT:  "res://assets/sounds/arrow_shoot.ogg",
	MAGIC_SHOOT:  "res://assets/sounds/magic_shoot.ogg",
	FLAME_SHOOT:  "res://assets/sounds/flame_shoot.ogg",
	HIT_PHYSICAL: "res://assets/sounds/hit_physical.ogg",
	HIT_MAGIC:    "res://assets/sounds/hit_magic.ogg",
	TAKE_DAMAGE:  "res://assets/sounds/take_damage.ogg",
	DEATH:        "res://assets/sounds/death.ogg",
	HEAL:         "res://assets/sounds/heal.ogg",
	ROOM_ENTER:   "res://assets/sounds/room_enter.ogg",
	ITEM_GET:     "res://assets/sounds/item_get.ogg",
	STAIRS:       "res://assets/sounds/stairs.ogg",
}

## 同時再生できる最大チャンネル数
const MAX_POLYPHONY := 8

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}  ## sound_id → AudioStream（起動時キャッシュ）

## 空間フィルタ用：現在の操作キャラクターと MapData
## set_listener() で設定する。null なら全音を再生（フィルタなし）
var _listener: Character = null
var _listener_map_data: MapData = null


## 操作キャラクターと MapData を設定する（game_map から呼ぶ）
func set_listener(ch: Character, md: MapData) -> void:
	_listener       = ch
	_listener_map_data = md


func _ready() -> void:
	# AudioStreamPlayer をプール生成
	for i: int in MAX_POLYPHONY:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_preload_streams()


## 起動時に全サウンドを事前ロード（ファイルがなければスキップ）
func _preload_streams() -> void:
	for sound_id: int in _SOUND_PATHS.keys():
		var path: String = _SOUND_PATHS[sound_id] as String
		if ResourceLoader.exists(path):
			_streams[sound_id] = load(path) as AudioStream


## Master バスの音量を設定する（0.0〜1.0）
func set_volume(vol: float) -> void:
	var db := linear_to_db(clampf(vol, 0.0001, 1.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)


## 指定 ID のサウンドを再生する
## 空きプレイヤーがなければ最も古いチャンネルを上書き
func play(sound_id: int) -> void:
	var stream: Variant = _streams.get(sound_id, null)
	if stream == null:
		return  # ファイル未配置・未ロードは無音でスキップ
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = stream as AudioStream
			p.play()
			return
	# 全チャンネル使用中 → 先頭を上書き
	_players[0].stream = stream as AudioStream
	_players[0].play()


# --------------------------------------------------------------------------
# 攻撃サウンドのヘルパー（他スクリプトから呼ぶ）
# --------------------------------------------------------------------------

## キャラクターの攻撃タイプ・クラスに応じた攻撃音を再生する
func play_attack(attacker: Character) -> void:
	play(get_attack_sound_id(attacker))


## 攻撃側のタイプに応じた命中音を再生する
func play_hit(attacker: Character) -> void:
	play(get_hit_sound_id(attacker))


## source キャラクターの位置が操作キャラと同じ部屋なら play() を呼ぶ
func play_from(sound_id: int, source: Character) -> void:
	if _is_audible(source):
		play(sound_id)


## source の攻撃音を空間フィルタ付きで再生する
func play_attack_from(attacker: Character) -> void:
	if _is_audible(attacker):
		play_attack(attacker)


## source の命中音を空間フィルタ付きで再生する
func play_hit_from(attacker: Character) -> void:
	if _is_audible(attacker):
		play_hit(attacker)


## source が操作キャラと同じ部屋にいるか判定する
## listener 未設定・エリア情報なし・通路は常に true（再生する）
func _is_audible(source: Character) -> bool:
	if _listener == null or _listener_map_data == null:
		return true
	if not is_instance_valid(source) or not is_instance_valid(_listener):
		return true
	var src_area := _listener_map_data.get_area(source.grid_pos)
	var lst_area := _listener_map_data.get_area(_listener.grid_pos)
	# エリア情報がない（通路など）場合は再生する
	if src_area.is_empty() or lst_area.is_empty():
		return true
	return src_area == lst_area


## キャラクターから攻撃音 ID を決定する
## ranged: 弓/魔法/炎を識別  melee/dive: 武器種（axe/dagger/slash）を識別
static func get_attack_sound_id(ch: Character) -> int:
	if ch == null or ch.character_data == null:
		return MELEE_SLASH
	var atype    : String = ch.character_data.attack_type
	var cid      : String = ch.character_data.character_id
	var class_id : String = ch.character_data.class_id
	match atype:
		"ranged":
			if cid == "salamander":
				return FLAME_SHOOT
			elif class_id == "archer" or cid == "goblin-archer":
				return ARROW_SHOOT
			else:
				return MAGIC_SHOOT
		_:  # melee / dive
			match class_id:
				"fighter-axe": return MELEE_AXE
				"scout":       return MELEE_DAGGER
				_:             return MELEE_SLASH


## 攻撃側のタイプから命中音 ID を決定する（魔法系 → hit_magic）
static func get_hit_sound_id(attacker: Character) -> int:
	if attacker == null or attacker.character_data == null:
		return HIT_PHYSICAL
	var atype : String = attacker.character_data.attack_type
	var cid   : String = attacker.character_data.character_id
	# ranged かつ魔法・炎系キャラは魔法命中音
	if atype == "ranged":
		if cid in ["goblin-mage", "dark-mage", "dark-priest", "salamander"] \
				or attacker.character_data.class_id in ["magician-fire", "healer"]:
			return HIT_MAGIC
	return HIT_PHYSICAL
