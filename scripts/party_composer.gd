class_name PartyComposer
extends RefCounted

## NPC パーティーの分類ベース自動編成（2026-04-26 導入）
##
## 役割分類（RoleCategory）と人数別の構成パターンに基づき、各メンバーに class_id と
## デフォルト装備を割り当てる。`dungeon_handcrafted.json` から class_id / image_set /
## items 直書きを廃止し、座標のみを JSON で指定する方式に対応する。
##
## 使用例:
##   var sizes := [1, 1, 1, 1, 1, 2, 2, 3, 3]
##   var classes := PartyComposer.compose_floor_classes(sizes)
##   # classes[0] -> ["fighter-sword"]、classes[5] -> ["scout","archer"] など
##
## 仕様詳細は CLAUDE.md「パーティー生成・初期構成」セクションを参照。


## 役割分類
enum RoleCategory { MELEE, RANGED, HEALER }


## 各分類に属するクラス ID（`assets/master/classes/*.json` のファイル名と一致）
const MELEE_CLASSES:  Array[String] = ["fighter-sword", "fighter-axe", "scout"]
const RANGED_CLASSES: Array[String] = ["archer", "magician-fire", "magician-water"]
const HEALER_CLASSES: Array[String] = ["healer"]


## クラス → デフォルト初期装備（item_type 文字列リスト）
## ItemGenerator.generate_initial(item_type) で tier=0 アイテム化される。
## 消耗品（potion_*）は PartyManager._build_npc_initial_items() が一律付与する。
const CLASS_DEFAULT_EQUIPMENT: Dictionary = {
	"fighter-sword":  ["sword",  "armor_plate", "shield"],
	"fighter-axe":    ["axe",    "armor_plate", "shield"],
	"archer":         ["bow",    "armor_cloth"],
	"scout":          ["dagger", "armor_cloth"],
	"magician-fire":  ["staff",  "armor_robe"],
	"magician-water": ["staff",  "armor_robe"],
	"healer":         ["staff",  "armor_robe"],
}


## 主人公分類に応じた 1 人パーティーのスロット配分（合計 4 枠）
##
## 主人公と同じ分類を 1 つ減らすことで、味方陣営全体での分類バランスを保ち、
## NPC を 14 人（4 + 2×2 + 2×3）に抑えて右パネルに収める設計。
##
## - 主人公 MELEE  → 近 1 + 遠 2 + 癒 1
## - 主人公 RANGED → 近 2 + 遠 1 + 癒 1
## - 主人公 HEALER → 近 2 + 遠 2 + 癒 0
##
## JSON 側の 1 人パーティーエントリは 5 個のまま維持し、コード側で 1 つを
## ランダムにスキップする（毎起動でスキップ位置が変わる）。
const SOLO_PARTY_SLOTS_BY_HERO_CATEGORY: Dictionary = {
	RoleCategory.MELEE:  [
		RoleCategory.MELEE,
		RoleCategory.RANGED, RoleCategory.RANGED,
		RoleCategory.HEALER,
	],
	RoleCategory.RANGED: [
		RoleCategory.MELEE, RoleCategory.MELEE,
		RoleCategory.RANGED,
		RoleCategory.HEALER,
	],
	RoleCategory.HEALER: [
		RoleCategory.MELEE, RoleCategory.MELEE,
		RoleCategory.RANGED, RoleCategory.RANGED,
	],
}


## 2 人パーティーの構成パターン（重み付き）
## ヒーラー入りは合計 25%（1/4）に抑える設計（ヒーラー過剰によるバランス崩壊防止）
const DUO_PATTERNS: Array = [
	{"weight": 75.0, "roles": [RoleCategory.MELEE,  RoleCategory.RANGED]},
	{"weight": 12.5, "roles": [RoleCategory.MELEE,  RoleCategory.HEALER]},
	{"weight": 12.5, "roles": [RoleCategory.RANGED, RoleCategory.HEALER]},
]


## 3 人パーティーの構成パターン（等確率・前衛 + 後衛が必須）
const TRIO_PATTERNS: Array = [
	[RoleCategory.MELEE,  RoleCategory.RANGED, RoleCategory.HEALER],
	[RoleCategory.MELEE,  RoleCategory.MELEE,  RoleCategory.RANGED],
	[RoleCategory.MELEE,  RoleCategory.RANGED, RoleCategory.RANGED],
]


# --------------------------------------------------------------------------
# 公開 API
# --------------------------------------------------------------------------


## フロア単位で全 NPC パーティーのクラス割り当てを決定する。
## party_member_counts: 各パーティーのメンバー数の配列（入力順は維持）
## hero_category: 主人公の役割分類（`RoleCategory` enum 値）。1 人パーティーの
##   スロット配分を主人公分類に応じて決めるために使用する
## 戻り値: 各パーティーごとの class_id 配列のリスト（入力順）
##   - 1 人パーティーで主人公分類に応じてスキップされたエントリは **空配列 `[]`**
##     を返す（呼出側で空配列ならスポーンしない）
##   例：hero_category=MELEE で party_member_counts=[1,1,1,1,1,2,3]
##     → [["fighter-sword"], [], ["archer"], ["magician-fire"], ["healer"], [...], [...]]
##
## 1 人パーティー：全体をシャッフルしてから先頭 1 つをスキップ・残りに
## `SOLO_PARTY_SLOTS_BY_HERO_CATEGORY[hero_category]`（4 枠）の順序で割り当てる。
## 1 人パーティーが 5 個未満の場合は枠を順番に消費（スキップなし）。
## 2/3 人パーティー：パーティー単位で個別に重み抽選 + 同分類内重複なしでクラス選択。
static func compose_floor_classes(party_member_counts: Array, hero_category: int) -> Array:
	var result: Array = []
	result.resize(party_member_counts.size())

	# 主人公分類に応じたスロット配分を取得（不正値は MELEE 扱いでフォールバック）
	var slots: Array = SOLO_PARTY_SLOTS_BY_HERO_CATEGORY.get(hero_category, []) as Array
	if slots.is_empty():
		push_warning("PartyComposer: unknown hero_category %d, falling back to MELEE" % hero_category)
		slots = SOLO_PARTY_SLOTS_BY_HERO_CATEGORY[RoleCategory.MELEE] as Array

	# 1 人パーティーのインデックスを集めてシャッフル
	var solo_indices: Array[int] = []
	for i: int in range(party_member_counts.size()):
		if int(party_member_counts[i]) == 1:
			solo_indices.append(i)
	solo_indices.shuffle()

	# 1 人パーティー数 > スロット数なら先頭 (solo_indices.size() - slots.size()) 個を
	# スキップ（空配列を入れる）。シャッフル済みなのでスキップ位置はランダム。
	var skip_count: int = max(0, solo_indices.size() - slots.size())
	for skip_i: int in range(skip_count):
		result[solo_indices[skip_i]] = []

	# 残った 1 人パーティーへの枠分配（4 枠想定・足りない場合はスロット先頭から消費）
	var melee_pool:  Array = MELEE_CLASSES.duplicate()
	var ranged_pool: Array = RANGED_CLASSES.duplicate()
	melee_pool.shuffle()
	ranged_pool.shuffle()
	var melee_used: int = 0
	var ranged_used: int = 0
	for slot_i: int in range(solo_indices.size() - skip_count):
		var party_idx: int = solo_indices[skip_count + slot_i]
		var slot_role: int = slots[slot_i % slots.size()] as int
		var class_id: String = ""
		match slot_role:
			RoleCategory.MELEE:
				if melee_used >= melee_pool.size():
					melee_pool.shuffle()
					melee_used = 0
				class_id = melee_pool[melee_used] as String
				melee_used += 1
			RoleCategory.RANGED:
				if ranged_used >= ranged_pool.size():
					ranged_pool.shuffle()
					ranged_used = 0
				class_id = ranged_pool[ranged_used] as String
				ranged_used += 1
			RoleCategory.HEALER:
				class_id = HEALER_CLASSES[0]
		result[party_idx] = [class_id]

	# 2 人パーティー：重み付き抽選
	for i: int in range(party_member_counts.size()):
		var sz: int = int(party_member_counts[i])
		if sz == 2:
			result[i] = _compose_duo_classes()
		elif sz == 3:
			result[i] = _compose_trio_classes()
		elif sz != 1 and sz != 2 and sz != 3:
			# 想定外の人数（4 人以上 / 0 人）：警告して空配列を入れる
			push_warning("PartyComposer: unsupported party size %d at index %d" % [sz, i])
			result[i] = []

	return result


## クラス ID から初期装備（item_type 文字列リスト）を取得
static func get_default_equipment(class_id: String) -> Array:
	return (CLASS_DEFAULT_EQUIPMENT.get(class_id, []) as Array).duplicate()


## クラス ID から RoleCategory を取得（デバッグ・ログ用途）
static func get_role_category(class_id: String) -> int:
	if HEALER_CLASSES.has(class_id):
		return RoleCategory.HEALER
	if RANGED_CLASSES.has(class_id):
		return RoleCategory.RANGED
	if MELEE_CLASSES.has(class_id):
		return RoleCategory.MELEE
	push_warning("PartyComposer: unknown class_id %s" % class_id)
	return RoleCategory.MELEE


# --------------------------------------------------------------------------
# 内部ユーティリティ
# --------------------------------------------------------------------------


## 2 人パーティーのクラス確定（重み抽選 + 各分類内ランダム）
static func _compose_duo_classes() -> Array:
	var pattern: Dictionary = _weighted_pick_pattern(DUO_PATTERNS)
	var roles: Array = pattern.get("roles", []) as Array
	return _classes_from_roles(roles)


## 3 人パーティーのクラス確定（等確率パターン抽選）
static func _compose_trio_classes() -> Array:
	var pattern: Array = TRIO_PATTERNS[randi() % TRIO_PATTERNS.size()] as Array
	return _classes_from_roles(pattern)


## RoleCategory 配列から class_id 配列へ変換（同一分類内は重複なし）
## パーティー内のクラス重複防止：MELEE が 2 枠なら 3 候補から 2 つを重複なしで選ぶ
static func _classes_from_roles(roles: Array) -> Array:
	var melee_pool:  Array = MELEE_CLASSES.duplicate()
	var ranged_pool: Array = RANGED_CLASSES.duplicate()
	melee_pool.shuffle()
	ranged_pool.shuffle()
	var melee_idx:  int = 0
	var ranged_idx: int = 0
	var result: Array = []
	for role_v: Variant in roles:
		var role_cat: int = role_v as int
		match role_cat:
			RoleCategory.MELEE:
				result.append(melee_pool[melee_idx])
				melee_idx += 1
			RoleCategory.RANGED:
				result.append(ranged_pool[ranged_idx])
				ranged_idx += 1
			RoleCategory.HEALER:
				result.append(HEALER_CLASSES[0])
	return result


## 重み付きパターン抽選
static func _weighted_pick_pattern(patterns: Array) -> Dictionary:
	var total: float = 0.0
	for p_v: Variant in patterns:
		total += float((p_v as Dictionary).get("weight", 0.0))
	var roll: float = randf() * total
	var cum: float = 0.0
	for p_v: Variant in patterns:
		var p: Dictionary = p_v as Dictionary
		cum += float(p.get("weight", 0.0))
		if roll < cum:
			return p
	return patterns[0] as Dictionary
