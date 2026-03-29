class_name CharacterGenerator
extends RefCounted

## キャラクター生成システム
## assets/images/characters/ のフォルダを走査してグラフィックセット一覧を取得し、
## クラス・ランク・ステータスをランダム決定して CharacterData を生成する。
## Phase 6-0 実装。

const GRAPHIC_SET_DIR := "res://assets/images/characters/"
const NAMES_JSON_PATH := "res://assets/master/names.json"
const CLASS_JSON_DIR  := "res://assets/master/classes/"

const KNOWN_CLASSES: Array = [
	"fighter-sword", "fighter-axe", "magician-fire", "archer", "healer", "scout"
]

## ランク補正（hp / attack / defense 共通）
const RANK_MULT: Dictionary = {
	"S": 2.0, "A": 1.5, "B": 1.2, "C": 1.0
}

## 体格補正（muscular ↔ slim で約 1.5 倍差）
const BUILD_MULT: Dictionary = {
	"slim":     {"hp": 0.85, "attack": 0.80, "defense": 0.90},
	"medium":   {"hp": 1.00, "attack": 1.00, "defense": 1.00},
	"muscular": {"hp": 1.15, "attack": 1.25, "defense": 1.10},
}

## 性別補正（±20%）
const SEX_MULT: Dictionary = {
	"male":   {"hp": 1.10, "attack": 1.10, "defense": 1.00},
	"female": {"hp": 0.90, "attack": 0.90, "defense": 1.00},
}

## 年齢補正（±20%）
const AGE_MULT: Dictionary = {
	"young": {"hp": 0.90, "attack": 1.00, "defense": 0.90},
	"adult": {"hp": 1.00, "attack": 1.00, "defense": 1.00},
	"elder": {"hp": 1.05, "attack": 0.95, "defense": 1.10},
}

## ランク重み（0〜99 で引いた値との対応。C=50%, B=30%, A=15%, S=5%）
const RANK_THRESHOLDS: Array = [
	[5,  "S"],
	[20, "A"],
	[50, "B"],
	[100,"C"],
]


## 指定クラスのキャラクターを1体生成する。class_id が空ならランダム選択
static func generate_character(class_id: String = "") -> CharacterData:
	# 1. グラフィックセット選択
	var sets := scan_graphic_sets(class_id)
	if sets.is_empty():
		sets = scan_graphic_sets()  # フォールバック：クラス不問で全セットから選ぶ
	if sets.is_empty():
		push_error("CharacterGenerator: 利用可能なグラフィックセットがありません")
		return null

	var chosen_set: Dictionary = sets[randi() % sets.size()]
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
	var char_name := _random_name(sex)

	# 5. ステータス計算
	var base_hp      := int(class_json.get("base_hp",      100))
	var base_attack  := int(class_json.get("base_attack",  10))
	var base_defense := int(class_json.get("base_defense", 3))
	var stats := _calc_stats(base_hp, base_attack, base_defense, rank, sex, age, build)

	# 6. CharacterData 組み立て
	var data := CharacterData.new()
	data.class_id           = chosen_class
	data.character_name     = char_name
	data.character_id       = "generated_" + chosen_class + "_" + str(randi() % 9000 + 1000)
	data.rank               = rank
	data.sex                = sex
	data.age                = age
	data.build              = build
	data.max_hp             = stats.hp
	data.attack             = stats.attack
	data.defense            = stats.defense
	data.pre_delay          = float(class_json.get("pre_delay",  0.3))
	data.post_delay         = float(class_json.get("post_delay", 0.5))
	data.is_flying          = bool(class_json.get("is_flying",  false))
	data.behavior_description = str(class_json.get("behavior_description", ""))

	var folder := GRAPHIC_SET_DIR + chosen_set.get("folder", "")
	data.image_set        = folder
	data.sprite_top       = folder + "/top.png"
	data.sprite_top_ready = folder + "/ready.png"
	data.sprite_front     = folder + "/front.png"
	data.sprite_face      = folder + "/face.png"

	return data


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


## names.json から指定性別の名前をランダム選択
static func _random_name(sex: String) -> String:
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
	return str(names_list[randi() % names_list.size()])


## ステータス計算
## 最終値 = base × rank × build × sex × age（hp/defense 最低1、attack 最低0）
static func _calc_stats(base_hp: int, base_attack: int, base_defense: int,
		rank: String, sex: String, age: String, build: String) -> Dictionary:
	var rm: float      = RANK_MULT.get(rank,  1.0) as float
	var bm: Dictionary = BUILD_MULT.get(build, BUILD_MULT["medium"]) as Dictionary
	var sm: Dictionary = SEX_MULT.get(sex,    SEX_MULT["male"])   as Dictionary
	var am: Dictionary = AGE_MULT.get(age,    AGE_MULT["adult"])  as Dictionary

	var hp_mult      := rm * (bm.get("hp",      1.0) as float) * (sm.get("hp",      1.0) as float) * (am.get("hp",      1.0) as float)
	var attack_mult  := rm * (bm.get("attack",  1.0) as float) * (sm.get("attack",  1.0) as float) * (am.get("attack",  1.0) as float)
	var defense_mult := rm * (bm.get("defense", 1.0) as float) * (sm.get("defense", 1.0) as float) * (am.get("defense", 1.0) as float)

	return {
		"hp":      maxi(1, int(float(base_hp)      * hp_mult)),
		"attack":  maxi(0, int(float(base_attack)  * attack_mult)),
		"defense": maxi(0, int(float(base_defense) * defense_mult)),
	}
