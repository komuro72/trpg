class_name CharacterData
extends Resource

## キャラクターデータ管理リソース
## パラメータ・画像パスはJSONから読み込む。素材差し替え時はJSONを変更するだけでよい。
## Phase 5:   トップビュー対応。sprite_top（フィールド表示）・sprite_front（UI表示）に変更。
##             is_flying フラグを追加。
## Phase 6-0: クラスシステム対応。class_id / image_set / sprite_face / sex / age / build を追加。
## Phase 8:   MP・攻撃タイプ（melee/ranged/dive）・回復力フィールドを追加。

var character_id: String = ""
var character_name: String = ""

## クラス情報（Phase 6-0〜）
var class_id: String = ""   # クラスID（例: "fighter-sword"）
var sex:      String = ""   # 性別（male / female）
var age:      String = ""   # 年齢（young / adult / elder）
var build:    String = ""   # 体格（slim / medium / muscular）

## 画像セット（Phase 6-0〜）
## フォルダパス（例: "res://assets/images/characters/fighter-sword_male_young_slim_01"）
var image_set:        String = ""
var sprite_top:       String = ""  # フィールド表示用（真上から見た画像）
var sprite_walk1:     String = ""  # 歩行パターン1・左足（未設定時は sprite_top を使用）
var sprite_walk2:     String = ""  # 歩行パターン2・右足（未設定時は sprite_top を使用）
var sprite_top_ready:  String = ""  # ターゲット選択中の構え画像（未設定時は sprite_top を使用）
var sprite_top_guard:  String = ""  # ガード中の画像（未設定時は sprite_top_ready → sprite_top にフォールバック）
var sprite_top_attack: String = ""  # 攻撃モーション中の画像（未設定時は sprite_top_ready → sprite_top にフォールバック）
var sprite_front:     String = ""  # UI・ステータス画面用（全身正面画像）
var sprite_face:      String = ""  # 顔アイコン（LeftPanel 表示用）

## 基本ステータス
var max_hp:       int   = 1
var max_mp:       int   = 0     ## 0 = MP なし（物理攻撃のみのキャラはデフォルト0）
var max_sp:       int   = 0     ## 0 = SP なし（魔法クラスはデフォルト0）
var power:        int   = 1     ## 物理威力 or 魔法威力（クラスに応じてUI表示名を切り替え）
var skill:        int   = 0     ## 物理技量 or 魔法技量（命中・クリティカル率の基礎値）
var defense:      int   = 0
var defense_accuracy: int = 50  ## 防御技量（0〜100。防御判定の成功率%。装備による変化なし）

## 攻撃タイプ（melee=近接 / ranged=遠距離（物理） / dive=降下攻撃 / magic=魔法攻撃）
## カウンター有効: melee・dive  カウンター無効: ranged・magic（将来実装）
var attack_type: String = "melee"

## 遠距離・魔法・回復の射程（タイル数。melee は 1 固定）
var attack_range: int = 1

## 回復スキルのMP消費（power を回復量として使用）
var heal_mp_cost: int = 0

## バフスキルのMP消費（防御力アップなど）
var buff_mp_cost: int = 0

## 耐性（能力値。内部で軽減率に変換。クラス素値＋装備補正。Phase 10-2〜）
## 変換式: 軽減率 = 能力値 / (能力値 + 100.0)（逓減カーブ・100で50%軽減）
var physical_resistance: int = 0  ## 物理耐性の能力値
var magic_resistance:    int = 0  ## 魔法耐性の能力値

## インベントリ（アイテムインスタンスの辞書リスト。Phase 10-1〜）
var inventory: Array = []

## 消耗品選択インデックス（inventory内の消耗品リストのインデックス。Phase 10-3〜）
var selected_consumable_index: int = 0

## 装備スロット（Phase 10-2〜）
var equipped_weapon: Dictionary = {}  ## 装備中の武器（空= 未装備）
var equipped_armor:  Dictionary = {}  ## 装備中の防具（空= 未装備）
var equipped_shield: Dictionary = {}  ## 装備中の盾（空= 未装備・盾装備可クラスのみ）

## 飛行キャラクターフラグ
var is_flying: bool = false
## アンデッドフラグ（true のとき回復魔法が逆ダメージになる。Phase 12-12〜）
var is_undead: bool = false
## 即死耐性フラグ（ボス級は true。ヘッドショット無効・無力化水魔法短縮）
var instant_death_immune: bool = false
## 巻き添えフラグ（将来実装。範囲攻撃が味方・他パーティーにも当たる）
var friendly_fire: bool = false
## 飛翔体種別（"" = 攻撃タイプから自動判定 / "thunder_bullet" = 雷弾。Phase 12-12〜）
var projectile_type: String = ""

## LLM行動生成用：自然言語でキャラクターの行動傾向を記述する
var behavior_description: String = ""

## キャラクターランク（S/A/B/C）。右パネルでのランク色分け表示・ステータス計算に使用
var rank: String = "C"

## 攻撃クールタイム（秒）
var pre_delay: float = 0.3   # 攻撃前の溜め時間
var post_delay: float = 0.5  # 攻撃後の硬直時間

## 統率力（リーダー側）：高いほど無理な指示でも従わせやすい。クラス・ランクから算出して確定後不変。当面は値のみ保持
var leadership: int = 5
## 従順度（個体側）：高いほど指示に素直に従う（0.0〜1.0）。クラス・種族・ランクから算出して確定後不変。当面は値のみ保持
var obedience: float = 0.5


## JSONファイルからCharacterDataを生成する
static func load_from_json(path: String) -> CharacterData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CharacterData: JSONファイルが見つかりません: " + path)
		return null
	var json_text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		push_error("CharacterData: JSONのパースに失敗しました: " + path)
		return null
	var d := parsed as Dictionary

	var data := CharacterData.new()
	data.character_id         = d.get("id", "")
	data.character_name       = d.get("name", "")
	data.max_hp               = int(d.get("hp", 1))
	data.max_mp               = int(d.get("mp", 0))
	data.max_sp               = int(d.get("max_sp", 0))
	# power: 新 "power" キーを優先。旧キー "attack_power"/"magic_power" にフォールバック
	var raw_power: int = int(d.get("power", -1))
	if raw_power < 0:
		var ap: int = int(d.get("attack_power", d.get("attack", -1)))
		var mp: int = int(d.get("magic_power", -1))
		raw_power = maxi(ap, mp) if ap >= 0 or mp >= 0 else 1
		if raw_power < 0:
			raw_power = 1
	data.power                = raw_power
	data.skill                = int(d.get("skill", d.get("accuracy", 0)))
	data.defense              = int(d.get("defense", 0))
	# defense_accuracy: 旧形式 float（0.0〜1.0）は ×100 で変換。新形式 int（0〜100）はそのまま
	var da_raw: Variant = d.get("defense_accuracy", null)
	if da_raw == null:
		data.defense_accuracy = 50
	elif float(da_raw) <= 1.0:
		data.defense_accuracy = int(float(da_raw) * 100.0)
	else:
		data.defense_accuracy = int(float(da_raw))
	data.attack_type          = d.get("attack_type",  "melee")
	data.attack_range         = int(d.get("attack_range", 1))
	data.heal_mp_cost         = int(d.get("heal_mp_cost", 0))
	data.buff_mp_cost         = int(d.get("buff_mp_cost", 0))
	data.is_flying            = bool(d.get("is_flying", false))
	data.is_undead            = bool(d.get("is_undead", false))
	data.instant_death_immune = bool(d.get("instant_death_immune", false))
	data.friendly_fire        = bool(d.get("friendly_fire", false))
	data.projectile_type      = str(d.get("projectile_type", ""))
	data.behavior_description = d.get("behavior_description", "")
	data.pre_delay            = float(d.get("pre_delay", 0.3))
	data.post_delay           = float(d.get("post_delay", 0.5))
	data.rank                    = d.get("rank", "C")
	data.leadership              = int(d.get("leadership", 5))
	data.obedience               = float(d.get("obedience", 0.5))
	data.physical_resistance     = int(d.get("physical_resistance", 0))
	data.magic_resistance        = int(d.get("magic_resistance",    0))

	# クラス情報（Phase 6-0〜）
	data.class_id = d.get("class_id", "")
	data.sex      = d.get("sex",      "")
	data.age      = d.get("age",      "")
	data.build    = d.get("build",    "")

	var sprites: Dictionary = d.get("sprites", {})
	data.image_set        = sprites.get("image_set",  "")
	data.sprite_top       = sprites.get("top",        "")
	data.sprite_walk1     = sprites.get("walk1",      "")
	data.sprite_walk2     = sprites.get("walk2",      "")
	data.sprite_front     = sprites.get("front",      "")
	data.sprite_face      = sprites.get("face",       "")
	# 構え画像: sprites.top_ready を優先し、なければトップレベルの ready_image を使用
	var ready := sprites.get("top_ready", "") as String
	if ready.is_empty():
		ready = d.get("ready_image", "") as String
	data.sprite_top_ready = ready
	data.sprite_top_guard  = sprites.get("top_guard",  "") as String
	data.sprite_top_attack = sprites.get("top_attack", "") as String

	return data


## inventory 内の消耗品（category == "consumable"）リストを返す
func get_consumables() -> Array:
	return inventory.filter(func(item: Variant) -> bool:
		return (item as Dictionary).get("category", "") == "consumable")


## 選択中の消耗品を返す（消耗品がなければ空辞書）
## selected_consumable_index を自動クランプする
func get_selected_consumable() -> Dictionary:
	var list := get_consumables()
	if list.is_empty():
		return {}
	selected_consumable_index = clampi(selected_consumable_index, 0, list.size() - 1)
	return list[selected_consumable_index] as Dictionary


## アイテム辞書を inventory に追加し、equipped=true のものを装備スロットにセットする
## items: [{ "item_type", "category", "item_name", "stats", "equipped"(opt), ... }]
func apply_initial_items(items: Array) -> void:
	for item_v: Variant in items:
		var item := (item_v as Dictionary).duplicate()
		var is_equipped: bool = bool(item.get("equipped", false))
		item.erase("equipped")  # inventory 内では equipped フラグではなく装備スロットで管理
		inventory.append(item)
		if is_equipped:
			_equip_item(item)


## アイテムを適切なスロットに装備する（クラス制限なし：初期装備付与時に呼ぶ想定）
func _equip_item(item: Dictionary) -> void:
	var cat: String = item.get("category", "") as String
	match cat:
		"weapon":
			equipped_weapon = item
		"armor":
			equipped_armor = item
		"shield":
			equipped_shield = item


## 装備中の武器から射程補正を返す（弓・杖のみ range_bonus を持つ。他は 0）
func get_weapon_range_bonus() -> int:
	return int((equipped_weapon.get("stats", {}) as Dictionary).get("range_bonus", 0))


## 装備中の武器から威力補正を返す（物理・魔法共用）
func get_weapon_power_bonus() -> int:
	var stats := equipped_weapon.get("stats", {}) as Dictionary
	var v: int = int(stats.get("power", -1))
	if v < 0:
		# 旧キー互換（attack_power / magic_power の大きい方）
		var ap: int = int(stats.get("attack_power", 0))
		var mp: int = int(stats.get("magic_power",  0))
		v = maxi(ap, mp)
	return v


## 装備中の武器から技量補正を返す
func get_weapon_skill_bonus() -> int:
	var stats := equipped_weapon.get("stats", {}) as Dictionary
	var v: int = int(stats.get("skill", -1))
	if v < 0:
		# 旧キー互換（accuracy は float だったので ×10 に変換）
		var acc: float = float(stats.get("accuracy", 0.0))
		v = int(acc * 10.0)
	return v


## 装備中の武器から防御強度を返す
func get_weapon_block_power() -> int:
	return int((equipped_weapon.get("stats", {}) as Dictionary).get("defense_strength", 0))


## 装備中の盾から防御強度を返す
func get_shield_block_power() -> int:
	return int((equipped_shield.get("stats", {}) as Dictionary).get("defense_strength", 0))


## 装備補正込みの物理耐性の能力値合計を返す（素値 + 防具 + 盾）
func get_total_physical_resistance_score() -> int:
	var bonus := int((equipped_armor.get("stats",  {}) as Dictionary).get("physical_resistance", 0))
	var shield := int((equipped_shield.get("stats", {}) as Dictionary).get("physical_resistance", 0))
	return physical_resistance + bonus + shield


## 装備補正込みの魔法耐性の能力値合計を返す（素値 + 防具 + 盾）
func get_total_magic_resistance_score() -> int:
	var bonus := int((equipped_armor.get("stats",  {}) as Dictionary).get("magic_resistance", 0))
	var shield := int((equipped_shield.get("stats", {}) as Dictionary).get("magic_resistance", 0))
	return magic_resistance + bonus + shield


## 能力値から軽減率に変換する（逓減カーブ: score / (score + 100)）
static func resistance_to_ratio(score: int) -> float:
	if score <= 0:
		return 0.0
	return float(score) / (float(score) + 100.0)


## 装備補正込みの物理耐性の軽減率を返す（0.0〜1.0）
func get_total_physical_resistance() -> float:
	return resistance_to_ratio(get_total_physical_resistance_score())


## 装備補正込みの魔法耐性の軽減率を返す（0.0〜1.0）
func get_total_magic_resistance() -> float:
	return resistance_to_ratio(get_total_magic_resistance_score())


## ヒーロー用データをJSONから生成する
static func create_hero() -> CharacterData:
	return load_from_json("res://assets/master/characters/hero.json")


## ゴブリン用データをJSONから生成する
static func create_goblin() -> CharacterData:
	return load_from_json("res://assets/master/enemies/goblin.json")
