class_name ItemGenerator
extends Object

## アイテム事前生成セット（定数ベース総当たり方式）からのランタイム選択
## 詳細は docs/history.md 2026-04-19 / CLAUDE.md「装備の名前生成」節
##
## 装備品: assets/master/items/generated/{item_type}.json の全エントリから
##   フロア基準段階（GlobalConstants.FLOOR_X_Y_BASE_TIER）＋ 距離重み
##   （FLOOR_BASE_WEIGHT / NEIGHBOR_WEIGHT / FAR_WEIGHT）で重み付きランダム選択
## 消耗品: assets/master/items/{item_type}.json（マスター JSON）の effect を
##   固定値で返す（depth_scale は設計判断で使用しない）
##   理由: 在庫管理問題を避けるため、ポーションは「使う時点の強さ」のみ重要

const GENERATED_DIR: String = "res://assets/master/items/generated/"
const MASTER_DIR:    String = "res://assets/master/items/"

## 段階の序数（低=0, 中=1, 高=2）
const TIER_ORDER: Array[String] = ["low", "mid", "high"]

## 起動後に生成セット JSON をキャッシュ（item_type → Array of entries）
static var _entries_cache: Dictionary = {}
## マスター JSON のキャッシュ（item_type → Dictionary）
static var _master_cache:  Dictionary = {}


## item_type とフロアに応じた装備アイテムを返す
## 戻り値: { item_type, category, item_name, stats } の辞書
## 未定義の item_type / 生成セット欠落時は {} を返す
static func generate(item_type: String, floor_index: int) -> Dictionary:
	# 消耗品は別経路
	if item_type.begins_with("potion_"):
		return generate_consumable(item_type)

	var entries := _load_entries(item_type)
	if entries.is_empty():
		push_warning("[ItemGenerator] 生成セットが見つかりません: " + item_type)
		return {}

	var picked := _weighted_pick(entries, floor_index)
	if picked.is_empty():
		return {}

	var category := _load_category(item_type)
	return {
		"item_type": item_type,
		"category":  category,
		"item_name": str(picked.get("name", "")),
		"stats":     (picked.get("stats", {}) as Dictionary).duplicate(),
	}


## 消耗品の生成（ポーション）。depth_scale は使用しない（設計判断・上記コメント参照）
static func generate_consumable(item_type: String) -> Dictionary:
	var master := _load_master(item_type)
	if master.is_empty():
		return {}
	return {
		"item_type": item_type,
		"category":  str(master.get("category", "consumable")),
		"item_name": str(master.get("name", item_type)),
		"effect":    (master.get("effect", {}) as Dictionary).duplicate(),
		"quantity":  1,
	}


# ============================================================================
# 内部
# ============================================================================

## 生成セット JSON を読み込んでキャッシュ
static func _load_entries(item_type: String) -> Array:
	if _entries_cache.has(item_type):
		return _entries_cache[item_type] as Array
	var path := GENERATED_DIR + item_type + ".json"
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		return []
	var data := parsed as Dictionary
	var entries: Array = data.get(item_type, []) as Array
	_entries_cache[item_type] = entries
	return entries


## マスター JSON を読み込んでキャッシュ
static func _load_master(item_type: String) -> Dictionary:
	if _master_cache.has(item_type):
		return _master_cache[item_type] as Dictionary
	var path := MASTER_DIR + item_type + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		return {}
	var data := parsed as Dictionary
	_master_cache[item_type] = data
	return data


## マスター JSON から category（weapon / armor / shield / consumable）を取得
static func _load_category(item_type: String) -> String:
	return str(_load_master(item_type).get("category", ""))


## フロア基準段階の重みでエントリを選ぶ
static func _weighted_pick(entries: Array, floor_index: int) -> Dictionary:
	var bands := _bands_for_floor(floor_index)
	var total_weight := 0
	var weights: Array[int] = []
	for entry_v: Variant in entries:
		var entry := entry_v as Dictionary
		var entry_tier := str(entry.get("tier", "mid"))
		var w := _weight_for_entry(entry_tier, bands)
		weights.append(w)
		total_weight += w
	if total_weight <= 0:
		return {}
	var roll := randi() % total_weight
	for i: int in range(entries.size()):
		roll -= weights[i]
		if roll < 0:
			return entries[i] as Dictionary
	return entries.back() as Dictionary  ## 理論上到達しない


## フロアが所属する band（基準段階）のリストを返す
## 隣接するフロア帯の重みを合算することで、境界フロアでの偏りを軽減する
##   Floor 0 → [low]
##   Floor 1 → [low, mid]  （[0,1] と [1,2] の両方に属する）
##   Floor 2 → [mid, high]
##   Floor 3 → [high]
static func _bands_for_floor(floor_index: int) -> Array[String]:
	var bands: Array[String] = []
	if floor_index >= 0 and floor_index <= 1:
		bands.append(str(GlobalConstants.FLOOR_0_1_BASE_TIER))
	if floor_index >= 1 and floor_index <= 2:
		bands.append(str(GlobalConstants.FLOOR_1_2_BASE_TIER))
	if floor_index >= 2 and floor_index <= 3:
		bands.append(str(GlobalConstants.FLOOR_2_3_BASE_TIER))
	return bands


## エントリの tier と全 band の距離重みの合計を返す
static func _weight_for_entry(entry_tier: String, bands: Array[String]) -> int:
	var total := 0
	var e_idx := _tier_index(entry_tier)
	for base_tier: String in bands:
		var b_idx := _tier_index(base_tier)
		var dist := absi(e_idx - b_idx)
		total += _weight_for_distance(dist)
	return total


## 段階名を序数に変換（low=0, mid=1, high=2）
static func _tier_index(tier: String) -> int:
	var idx := TIER_ORDER.find(tier)
	return idx if idx >= 0 else 1  ## 未知の tier は mid 扱い


## 距離に応じた重み
static func _weight_for_distance(dist: int) -> int:
	match dist:
		0:
			return GlobalConstants.FLOOR_BASE_WEIGHT
		1:
			return GlobalConstants.FLOOR_NEIGHBOR_WEIGHT
	return GlobalConstants.FLOOR_FAR_WEIGHT


## テスト用：キャッシュをクリアする（Config Editor で定数変更後にも呼びたい）
static func clear_cache() -> void:
	_entries_cache.clear()
	_master_cache.clear()
