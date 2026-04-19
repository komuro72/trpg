class_name ItemGenerator
extends Object

## アイテム事前生成セット（定数ベース総当たり方式）からのランタイム選択
## 詳細は docs/history.md 2026-04-19 / CLAUDE.md「装備の名前生成」節
##
## 装備品: assets/master/items/generated/{item_type}.json の全エントリから
##   フロア基準 tier（GlobalConstants.FLOOR_X_Y_BASE_TIER）＋ 距離重み
##   （FLOOR_BASE_WEIGHT / NEIGHBOR_WEIGHT / FAR_WEIGHT）で重み付きランダム選択
##   tier は 0=none / 1=low / 2=mid / 3=high の整数
##   tier=0 エントリはドロップに出ない（初期装備専用）
## 消耗品: assets/master/items/{item_type}.json（マスター JSON）の effect を
##   固定値で返す（depth_scale は設計判断で使用しない）
##   理由: 在庫管理問題を避けるため、ポーションは「使う時点の強さ」のみ重要

const GENERATED_DIR: String = "res://assets/master/items/generated/"
const MASTER_DIR:    String = "res://assets/master/items/"

## 初期装備専用の tier（無 bonus）
const TIER_NONE: int = 0

## 起動後に生成セット JSON をキャッシュ（item_type → Array of entries）
static var _entries_cache: Dictionary = {}
## マスター JSON のキャッシュ（item_type → Dictionary）
static var _master_cache:  Dictionary = {}


## item_type とフロアに応じた装備アイテムを返す（ドロップ用）
## tier=0（none）のエントリは選択候補から除外される
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
		"tier":      int(picked.get("tier", 2)),
	}


## 初期装備・初期消耗品を返す（主人公・NPC 共通）
## 装備: 対応する item_type の tier=0（none）エントリを返す
## 消耗品（potion_*）: 通常の消耗品生成ロジック（generate_consumable）に委譲
## 装備タイプで tier=0 エントリが見つからない場合は {} を返し push_error を出す
static func generate_initial(item_type: String) -> Dictionary:
	if item_type.begins_with("potion_"):
		return generate_consumable(item_type)

	var entries := _load_entries(item_type)
	if entries.is_empty():
		push_error("[ItemGenerator] 生成セットが見つかりません（初期装備）: " + item_type)
		return {}

	for entry_v: Variant in entries:
		var entry := entry_v as Dictionary
		if int(entry.get("tier", -1)) == TIER_NONE:
			var category := _load_category(item_type)
			return {
				"item_type": item_type,
				"category":  category,
				"item_name": str(entry.get("name", "")),
				"stats":     (entry.get("stats", {}) as Dictionary).duplicate(),
				"tier":      TIER_NONE,
				"equipped":  true,
			}

	push_error("[ItemGenerator] tier=0 エントリが見つかりません: " + item_type)
	return {}


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


## フロア基準 tier の重みでエントリを選ぶ（tier=0 は除外）
static func _weighted_pick(entries: Array, floor_index: int) -> Dictionary:
	var bands := _bands_for_floor(floor_index)
	var total_weight := 0
	var weights: Array[int] = []
	for entry_v: Variant in entries:
		var entry := entry_v as Dictionary
		var entry_tier := int(entry.get("tier", 2))
		if entry_tier == TIER_NONE:
			weights.append(0)  ## 初期装備専用なのでドロップ対象外
			continue
		var w := _weight_for_entry(entry_tier, bands)
		weights.append(w)
		total_weight += w
	if total_weight <= 0:
		return {}
	var roll := randi() % total_weight
	for i: int in range(entries.size()):
		if weights[i] == 0:
			continue
		roll -= weights[i]
		if roll < 0:
			return entries[i] as Dictionary
	return entries.back() as Dictionary  ## 理論上到達しない


## フロアが所属する band（基準 tier）のリストを返す
## 隣接するフロア帯の重みを合算することで、境界フロアでの偏りを軽減する
##   Floor 0 → [FLOOR_0_1_BASE_TIER]
##   Floor 1 → [FLOOR_0_1_BASE_TIER, FLOOR_1_2_BASE_TIER]
##   Floor 2 → [FLOOR_1_2_BASE_TIER, FLOOR_2_3_BASE_TIER]
##   Floor 3 → [FLOOR_2_3_BASE_TIER]
static func _bands_for_floor(floor_index: int) -> Array[int]:
	var bands: Array[int] = []
	if floor_index >= 0 and floor_index <= 1:
		bands.append(int(GlobalConstants.FLOOR_0_1_BASE_TIER))
	if floor_index >= 1 and floor_index <= 2:
		bands.append(int(GlobalConstants.FLOOR_1_2_BASE_TIER))
	if floor_index >= 2 and floor_index <= 3:
		bands.append(int(GlobalConstants.FLOOR_2_3_BASE_TIER))
	return bands


## エントリの tier と全 band の距離重みの合計を返す
static func _weight_for_entry(entry_tier: int, bands: Array[int]) -> int:
	var total := 0
	for base_tier: int in bands:
		var dist := absi(entry_tier - base_tier)
		total += _weight_for_distance(dist)
	return total


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
