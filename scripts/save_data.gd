class_name SaveData
extends RefCounted

## セーブスロット1枠のデータ
## Phase 13: タイトル・セーブ・メニューシステム

var slot_index: int    = 0
var exists: bool       = false
var hero_name_male: String   = ""
var hero_name_female: String = ""
var current_floor: int = 0      ## 到達した最大フロア（スロット表示用）
var clear_count: int   = 0      ## 攻略成功回数
var playtime: float    = 0.0    ## 累計プレイ時間（秒）


func to_dict() -> Dictionary:
	return {
		"exists":           true,
		"hero_name_male":   hero_name_male,
		"hero_name_female": hero_name_female,
		"current_floor":    current_floor,
		"clear_count":      clear_count,
		"playtime":         playtime,
	}


static func from_dict(d: Dictionary, idx: int) -> SaveData:
	var sd := SaveData.new()
	sd.slot_index        = idx
	sd.exists            = bool(d.get("exists", false))
	sd.hero_name_male    = str(d.get("hero_name_male",   ""))
	sd.hero_name_female  = str(d.get("hero_name_female", ""))
	sd.current_floor     = int(d.get("current_floor",  0))
	sd.clear_count       = int(d.get("clear_count",    0))
	sd.playtime          = float(d.get("playtime",     0.0))
	return sd


## プレイ時間を "HH:MM" 形式でフォーマット
static func format_playtime(seconds: float) -> String:
	var total: int = int(seconds)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [total / 3600, (total % 3600) / 60]
