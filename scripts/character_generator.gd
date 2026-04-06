class_name CharacterGenerator
extends RefCounted

## キャラクター生成システム
## assets/images/characters/ のフォルダを走査してグラフィックセット一覧を取得し、
## クラス・ランク・ステータスをランダム決定して CharacterData を生成する。
## Phase 6-0 実装。

const GRAPHIC_SET_DIR       := "res://assets/images/characters/"
const ENEMY_GRAPHIC_SET_DIR := "res://assets/images/enemies/"
const NAMES_JSON_PATH := "res://assets/master/names.json"
const CLASS_JSON_DIR  := "res://assets/master/classes/"

const KNOWN_CLASSES: Array = [
	"fighter-sword", "fighter-axe", "magician-fire", "magician-water", "archer", "healer", "scout"
]

## ランク値（加算式: final = base + rank_amount × rank_value）
const RANK_VALUE: Dictionary = {"C": 0, "B": 1, "A": 2, "S": 3}

## ランク重み（0〜99 で引いた値との対応。C=50%, B=30%, A=15%, S=5%）
const RANK_THRESHOLDS: Array = [
	[5,  "S"],
	[20, "A"],
	[50, "B"],
	[100,"C"],
]

## ステータス生成ベースデータ（クラスごと・全ステータス 0-100 に収まる値に設定）
## 各エントリ: { base, rank, sex:{m,f}, age:{y,a,e}, build:{mu,me,sl}, rand }
## final = base + rank × RANK_VALUE[rank] + sex[sex] + age[age] + build[build] + randi()%rand
const CLASS_STAT_BASES: Dictionary = {
	"fighter-sword": {
		"power":               {"base": 20, "rank": 15, "sex": {"male":  5, "female": -2}, "age": {"young": 0, "adult": 3, "elder": -3}, "build": {"muscular":  8, "medium": 0, "slim": -5}, "rand": 5},
		"skill":               {"base": 18, "rank": 10, "sex": {"male":  0, "female":  3}, "age": {"young": 3, "adult": 0, "elder": -2}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 4},
		"physical_resistance": {"base": 20, "rank":  8, "sex": {"male":  5, "female": -2}, "age": {"young": 0, "adult": 0, "elder":  3}, "build": {"muscular":  8, "medium": 0, "slim": -5}, "rand": 3},
		"magic_resistance":    {"base":  5, "rank":  4, "sex": {"male":  0, "female":  0}, "age": {"young": 0, "adult": 0, "elder":  3}, "build": {"muscular":  0, "medium": 0, "slim":  0}, "rand": 2},
		"defense_accuracy":    {"base": 40, "rank":  8, "sex": {"male":  0, "female":  3}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 3},
		"max_hp":              {"base": 60, "rank": 10, "sex": {"male":  8, "female": -5}, "age": {"young":-5, "adult": 0, "elder": -5}, "build": {"muscular": 15, "medium": 0, "slim":-10}, "rand":10},
	},
	"fighter-axe": {
		"power":               {"base": 22, "rank": 15, "sex": {"male":  6, "female": -2}, "age": {"young": 0, "adult": 3, "elder": -3}, "build": {"muscular": 10, "medium": 0, "slim": -6}, "rand": 5},
		"skill":               {"base": 15, "rank":  9, "sex": {"male":  0, "female":  3}, "age": {"young": 3, "adult": 0, "elder": -2}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 4},
		"physical_resistance": {"base": 22, "rank":  8, "sex": {"male":  5, "female": -2}, "age": {"young": 0, "adult": 0, "elder":  3}, "build": {"muscular":  8, "medium": 0, "slim": -5}, "rand": 3},
		"magic_resistance":    {"base":  4, "rank":  4, "sex": {"male":  0, "female":  0}, "age": {"young": 0, "adult": 0, "elder":  3}, "build": {"muscular":  0, "medium": 0, "slim":  0}, "rand": 2},
		"defense_accuracy":    {"base": 38, "rank":  8, "sex": {"male":  0, "female":  3}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 3},
		"max_hp":              {"base": 65, "rank": 10, "sex": {"male":  8, "female": -5}, "age": {"young":-5, "adult": 0, "elder": -5}, "build": {"muscular": 15, "medium": 0, "slim":-10}, "rand":10},
	},
	"archer": {
		"power":               {"base": 18, "rank": 13, "sex": {"male": -2, "female":  3}, "age": {"young": 3, "adult": 0, "elder": -2}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 4},
		"skill":               {"base": 25, "rank": 12, "sex": {"male": -2, "female":  3}, "age": {"young": 5, "adult": 0, "elder": -3}, "build": {"muscular": -5, "medium": 0, "slim":  7}, "rand": 4},
		"physical_resistance": {"base":  8, "rank":  5, "sex": {"male":  0, "female":  0}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular":  3, "medium": 0, "slim": -2}, "rand": 2},
		"magic_resistance":    {"base":  6, "rank":  4, "sex": {"male":  0, "female":  0}, "age": {"young": 0, "adult": 0, "elder":  3}, "build": {"muscular":  0, "medium": 0, "slim":  0}, "rand": 2},
		"defense_accuracy":    {"base": 35, "rank":  8, "sex": {"male":  0, "female":  3}, "age": {"young": 3, "adult": 0, "elder": -2}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 3},
		"max_hp":              {"base": 50, "rank":  8, "sex": {"male":  5, "female": -3}, "age": {"young":-3, "adult": 0, "elder": -3}, "build": {"muscular": 10, "medium": 0, "slim": -7}, "rand": 8},
	},
	"scout": {
		"power":               {"base": 16, "rank": 12, "sex": {"male": -2, "female":  5}, "age": {"young": 3, "adult": 0, "elder": -2}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 4},
		"skill":               {"base": 22, "rank": 12, "sex": {"male": -2, "female":  5}, "age": {"young": 5, "adult": 0, "elder": -3}, "build": {"muscular": -5, "medium": 0, "slim":  8}, "rand": 4},
		"physical_resistance": {"base":  8, "rank":  5, "sex": {"male":  0, "female":  0}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular":  3, "medium": 0, "slim": -2}, "rand": 2},
		"magic_resistance":    {"base":  7, "rank":  4, "sex": {"male":  0, "female":  0}, "age": {"young": 0, "adult": 0, "elder":  3}, "build": {"muscular":  0, "medium": 0, "slim":  0}, "rand": 2},
		"defense_accuracy":    {"base": 42, "rank":  8, "sex": {"male":  0, "female":  3}, "age": {"young": 3, "adult": 0, "elder": -2}, "build": {"muscular": -3, "medium": 0, "slim":  7}, "rand": 3},
		"max_hp":              {"base": 48, "rank":  8, "sex": {"male":  5, "female": -3}, "age": {"young":-3, "adult": 0, "elder": -3}, "build": {"muscular":  8, "medium": 0, "slim": -6}, "rand": 8},
	},
	"magician-fire": {
		"power":               {"base": 22, "rank": 14, "sex": {"male": -3, "female":  5}, "age": {"young":-2, "adult": 0, "elder":  5}, "build": {"muscular": -5, "medium": 0, "slim":  5}, "rand": 4},
		"skill":               {"base": 20, "rank": 10, "sex": {"male": -2, "female":  3}, "age": {"young": 2, "adult": 0, "elder": -2}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 3},
		"physical_resistance": {"base":  4, "rank":  3, "sex": {"male":  0, "female":  0}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular":  0, "medium": 0, "slim":  0}, "rand": 2},
		"magic_resistance":    {"base": 15, "rank":  7, "sex": {"male":  0, "female":  3}, "age": {"young": 0, "adult": 0, "elder":  5}, "build": {"muscular":  0, "medium": 0, "slim":  3}, "rand": 3},
		"defense_accuracy":    {"base": 30, "rank":  7, "sex": {"male":  0, "female":  3}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 3},
		"max_hp":              {"base": 45, "rank":  7, "sex": {"male":  3, "female": -3}, "age": {"young":-3, "adult": 0, "elder": -3}, "build": {"muscular":  8, "medium": 0, "slim": -5}, "rand": 7},
	},
	"magician-water": {
		"power":               {"base": 20, "rank": 13, "sex": {"male": -3, "female":  5}, "age": {"young":-2, "adult": 0, "elder":  5}, "build": {"muscular": -5, "medium": 0, "slim":  5}, "rand": 4},
		"skill":               {"base": 22, "rank": 10, "sex": {"male": -2, "female":  3}, "age": {"young": 2, "adult": 0, "elder": -2}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 3},
		"physical_resistance": {"base":  4, "rank":  3, "sex": {"male":  0, "female":  0}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular":  0, "medium": 0, "slim":  0}, "rand": 2},
		"magic_resistance":    {"base": 15, "rank":  7, "sex": {"male":  0, "female":  3}, "age": {"young": 0, "adult": 0, "elder":  5}, "build": {"muscular":  0, "medium": 0, "slim":  3}, "rand": 3},
		"defense_accuracy":    {"base": 32, "rank":  7, "sex": {"male":  0, "female":  3}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 3},
		"max_hp":              {"base": 45, "rank":  7, "sex": {"male":  3, "female": -3}, "age": {"young":-3, "adult": 0, "elder": -3}, "build": {"muscular":  8, "medium": 0, "slim": -5}, "rand": 7},
	},
	"healer": {
		"power":               {"base": 25, "rank": 14, "sex": {"male": -3, "female":  5}, "age": {"young":-3, "adult": 0, "elder":  7}, "build": {"muscular": -5, "medium": 0, "slim":  3}, "rand": 4},
		"skill":               {"base": 18, "rank":  9, "sex": {"male": -2, "female":  3}, "age": {"young": 2, "adult": 0, "elder":  0}, "build": {"muscular": -3, "medium": 0, "slim":  3}, "rand": 3},
		"physical_resistance": {"base":  5, "rank":  3, "sex": {"male":  0, "female":  0}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular":  0, "medium": 0, "slim":  0}, "rand": 2},
		"magic_resistance":    {"base": 18, "rank":  7, "sex": {"male":  0, "female":  3}, "age": {"young": 0, "adult": 0, "elder":  5}, "build": {"muscular":  0, "medium": 0, "slim":  3}, "rand": 3},
		"defense_accuracy":    {"base": 30, "rank":  7, "sex": {"male":  0, "female":  3}, "age": {"young": 0, "adult": 0, "elder":  0}, "build": {"muscular": -3, "medium": 0, "slim":  5}, "rand": 3},
		"max_hp":              {"base": 48, "rank":  7, "sex": {"male":  3, "female": -3}, "age": {"young":-3, "adult": 0, "elder": -3}, "build": {"muscular":  8, "medium": 0, "slim": -5}, "rand": 7},
	},
}

## 使用済み名前・画像セットの追跡（重複防止）。シーン再起動でリセットされる
static var _used_names: Dictionary = {}       ## { name: String -> true }
static var _used_image_sets: Dictionary = {}  ## { folder: String -> true }


## 使用済みリストをリセットする（シーン再起動時に呼ぶ）
static func reset_used() -> void:
	_used_names.clear()
	_used_image_sets.clear()


## 指定クラスのキャラクターを1体生成する。class_id が空ならランダム選択
static func generate_character(class_id: String = "") -> CharacterData:
	# 1. グラフィックセット選択
	var sets := scan_graphic_sets(class_id)
	if sets.is_empty():
		sets = scan_graphic_sets()  # フォールバック：クラス不問で全セットから選ぶ
	if sets.is_empty():
		push_error("CharacterGenerator: 利用可能なグラフィックセットがありません")
		return null

	# 未使用の画像セットを優先（枯渇時はフォールバック）
	var unused_sets: Array = []
	for s: Dictionary in sets:
		if not _used_image_sets.has(s.get("folder", "")):
			unused_sets.append(s)
	var pool: Array = unused_sets if not unused_sets.is_empty() else sets
	var chosen_set: Dictionary = pool[randi() % pool.size()]
	var chosen_class: String   = chosen_set.get("class", "")

	# 2. クラスデータ読み込み
	var class_json := _load_class_json(chosen_class)
	if class_json.is_empty():
		push_error("CharacterGenerator: クラスデータが見つかりません: " + chosen_class)
		return null

	# 3. ランク決定
	var rank := _random_rank()

	# 4. 名前・属性取得
	var sex:   String = chosen_set.get("sex",   "male")
	var age:   String = chosen_set.get("age",   "adult")
	var build: String = chosen_set.get("build", "medium")
	var char_name := _random_unused_name(sex)

	# 5. ステータス計算
	var stats := _calc_stats(chosen_class, rank, sex, age, build)

	# 6. CharacterData 組み立て
	var data := CharacterData.new()
	data.class_id           = chosen_class
	data.character_name     = char_name
	data.character_id       = "generated_" + chosen_class + "_" + str(randi() % 9000 + 1000)
	data.rank               = rank
	data.sex                = sex
	data.age                = age
	data.build              = build
	data.max_hp                  = stats.max_hp
	data.power                   = stats.power
	data.skill                   = stats.skill
	data.defense                 = int(class_json.get("base_defense", 3))
	data.physical_resistance     = stats.physical_resistance
	data.magic_resistance        = stats.magic_resistance
	data.defense_accuracy        = stats.defense_accuracy
	data.pre_delay          = float(class_json.get("pre_delay",  0.3))
	data.post_delay         = float(class_json.get("post_delay", 0.5))
	data.is_flying          = bool(class_json.get("is_flying",  false))
	data.behavior_description = str(class_json.get("behavior_description", ""))
	data.attack_type        = str(class_json.get("attack_type",  "melee"))
	data.attack_range       = int(class_json.get("attack_range", 1))
	data.max_mp             = int(class_json.get("mp",            0))
	data.max_sp             = int(class_json.get("max_sp",        0))
	data.heal_mp_cost       = int(class_json.get("heal_mp_cost",  0))
	data.buff_mp_cost       = int(class_json.get("buff_mp_cost",  0))

	var folder: String = GRAPHIC_SET_DIR + str(chosen_set.get("folder", ""))
	data.image_set         = folder
	data.sprite_top        = folder + "/top.png"
	data.sprite_walk1      = folder + "/walk1.png"
	data.sprite_walk2      = folder + "/walk2.png"
	data.sprite_top_ready  = folder + "/ready.png"
	data.sprite_top_guard  = folder + "/guard.png"
	data.sprite_top_attack = folder + "/attack.png"
	data.sprite_front      = folder + "/front.png"
	data.sprite_face       = folder + "/face.png"

	# 使用済みとして登録
	_used_names[char_name] = true
	_used_image_sets[str(chosen_set.get("folder", ""))] = true

	return data


## JSON の image_set フィールドで指定されたフォルダ名を CharacterData に適用する
## folder_name: 例 "fighter-sword_male_young_slim_00001"（res://... プレフィックスなし）
static func apply_image_set_override(data: CharacterData, folder_name: String) -> void:
	if data == null or folder_name.is_empty():
		return
	var folder: String = GRAPHIC_SET_DIR + folder_name
	data.image_set         = folder
	data.sprite_top        = folder + "/top.png"
	data.sprite_walk1      = folder + "/walk1.png"
	data.sprite_walk2      = folder + "/walk2.png"
	data.sprite_top_ready  = folder + "/ready.png"
	data.sprite_top_guard  = folder + "/guard.png"
	data.sprite_top_attack = folder + "/attack.png"
	data.sprite_front      = folder + "/front.png"
	data.sprite_face       = folder + "/face.png"
	var info := _parse_folder_name(folder_name)
	if not info.is_empty():
		data.sex   = str(info.get("sex",   data.sex))
		data.age   = str(info.get("age",   data.age))
		data.build = str(info.get("build", data.build))
	_used_image_sets[folder_name] = true


## assets/images/enemies/ を走査して利用可能な敵グラフィックセット情報を返す
## enemy_type が空ならすべてのセットを返す
static func scan_enemy_graphic_sets(enemy_type: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var folders := DirAccess.get_directories_at(ENEMY_GRAPHIC_SET_DIR)
	for folder: String in folders:
		var info := _parse_enemy_folder_name(folder)
		if info.is_empty():
			continue
		if enemy_type.is_empty() or info.get("enemy_type") == enemy_type:
			info["folder"] = folder
			result.append(info)
	return result


## 敵 CharacterData に画像フォルダのパスを割り当てる
## character_id に対応するフォルダが見つかれば sprite_* を上書きする
## 見つからなければ JSON 指定のパス（またはプレースホルダー）をそのまま維持する
static func apply_enemy_graphics(data: CharacterData) -> void:
	if data == null:
		return
	var enemy_type := data.character_id
	if enemy_type.is_empty():
		return
	var sets := scan_enemy_graphic_sets(enemy_type)
	if sets.is_empty():
		return
	var chosen_set: Dictionary = sets[randi() % sets.size()]
	var folder: String = ENEMY_GRAPHIC_SET_DIR + str(chosen_set.get("folder", ""))
	data.image_set         = folder
	data.sprite_top        = folder + "/top.png"
	data.sprite_walk1      = folder + "/walk1.png"
	data.sprite_walk2      = folder + "/walk2.png"
	data.sprite_top_ready  = folder + "/ready.png"
	data.sprite_top_guard  = folder + "/guard.png"
	data.sprite_top_attack = folder + "/attack.png"
	data.sprite_front      = folder + "/front.png"
	data.sprite_face       = folder + "/face.png"
	data.sex   = str(chosen_set.get("sex",   data.sex))
	data.age   = str(chosen_set.get("age",   data.age))
	data.build = str(chosen_set.get("build", data.build))


## assets/images/characters/ を走査して利用可能なグラフィックセット情報を返す
## class_id が空ならすべてのセットを返す
static func scan_graphic_sets(class_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var folders := DirAccess.get_directories_at(GRAPHIC_SET_DIR)
	for folder: String in folders:
		var info := _parse_folder_name(folder)
		if info.is_empty():
			continue
		if class_id.is_empty() or info.get("class") == class_id:
			info["folder"] = folder
			result.append(info)
	return result


# --------------------------------------------------------------------------
# 内部ユーティリティ
# --------------------------------------------------------------------------

## フォルダ名を {class, sex, age, build, id} に解析する
## フォーマット: {class}_{sex}_{age}_{build}_{id}
## class には "-" が含まれるため既知クラスリストでプレフィックスマッチする
static func _parse_folder_name(folder: String) -> Dictionary:
	for c: String in KNOWN_CLASSES:
		if folder.begins_with(c + "_"):
			var rest  := folder.substr(c.length() + 1)
			var parts := rest.split("_")
			if parts.size() >= 3:
				return {
					"class": c,
					"sex":   parts[0],
					"age":   parts[1],
					"build": parts[2],
					"id":    parts[3] if parts.size() >= 4 else "01",
				}
	return {}


## 敵フォルダ名を {enemy_type, sex, age, build, id} に解析する
## フォーマット: {enemy_type}_{sex}_{age}_{build}_{id}
## enemy_type には "-" が含まれるため "_male_" / "_female_" でセックス境界を検出する
static func _parse_enemy_folder_name(folder: String) -> Dictionary:
	for sex_str: String in ["male", "female"]:
		var sep := "_" + sex_str + "_"
		var idx := folder.find(sep)
		if idx < 0:
			continue
		var enemy_type := folder.substr(0, idx)
		if enemy_type.is_empty():
			continue
		var rest  := folder.substr(idx + sep.length())
		var parts := rest.split("_")
		if parts.size() >= 2:
			return {
				"enemy_type": enemy_type,
				"sex":        sex_str,
				"age":        parts[0],
				"build":      parts[1],
				"id":         parts[2] if parts.size() >= 3 else "01",
			}
	return {}


## クラス定義 JSON を読み込んで Dictionary を返す
static func _load_class_json(class_id: String) -> Dictionary:
	var path := CLASS_JSON_DIR + class_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


## ランクをランダム決定する（C=50%, B=30%, A=15%, S=5%）
static func _random_rank() -> String:
	var roll := randi() % 100
	for entry: Array in RANK_THRESHOLDS:
		if roll < int(entry[0]):
			return str(entry[1])
	return "C"


## names.json から未使用の名前を優先してランダム選択（枯渇時はフォールバック）
static func _random_unused_name(sex: String) -> String:
	var file := FileAccess.open(NAMES_JSON_PATH, FileAccess.READ)
	if file == null:
		return "名無し"
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return "名無し"
	var names_list: Array = (parsed as Dictionary).get(sex, [])
	if names_list.is_empty():
		return "名無し"
	# 未使用の名前を優先
	var unused: Array = []
	for n: Variant in names_list:
		if not _used_names.has(str(n)):
			unused.append(n)
	var pool: Array = unused if not unused.is_empty() else names_list
	return str(pool[randi() % pool.size()])


## ステータス計算（Phase 12-14 加算式 / 0-100 レンジ）
## final = base + rank_amount × rank_value + sex_bonus + age_bonus + build_bonus + randi()%rand
static func _calc_stats(class_id: String, rank: String, sex: String,
		age: String, build: String) -> Dictionary:
	var bases: Dictionary = CLASS_STAT_BASES.get(class_id, CLASS_STAT_BASES.get("fighter-sword", {})) as Dictionary
	var rv: int = RANK_VALUE.get(rank, 0) as int
	var result: Dictionary = {}
	for stat_key: String in bases.keys():
		var s: Dictionary = bases[stat_key] as Dictionary
		var base_v: int  = int(s.get("base", 0))
		var rank_a: int  = int(s.get("rank", 0))
		var rand_m: int  = int(s.get("rand", 0))
		var sex_b: Dictionary  = s.get("sex",   {}) as Dictionary
		var age_b: Dictionary  = s.get("age",   {}) as Dictionary
		var build_b: Dictionary = s.get("build", {}) as Dictionary
		var val: int = base_v \
			+ rank_a * rv \
			+ int(sex_b.get(sex,   0)) \
			+ int(age_b.get(age,   0)) \
			+ int(build_b.get(build, 0)) \
			+ (randi() % (rand_m + 1) if rand_m > 0 else 0)
		result[stat_key] = maxi(0, val)
	return result
