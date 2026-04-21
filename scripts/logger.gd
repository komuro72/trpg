## デバッグ用ロガー（Autoload: DebugLog）
##
## 不具合調査のために Claude Code が一時的にログ出力を仕込むための仕組み。
## 出力は 2 系統（コンソール / ファイル）の両方に流す。Claude Code はファイル
## を直接読んで解析できる。問題解決後は DebugLog 呼び出しを削除する使い捨て運用。
##
## 使い方:
##   DebugLog.log("player hp=%d" % player.hp)
##   DebugLog.log("stair enter floor=%d pos=%s" % [floor, str(pos)])
##
## フォーマット:
##   [HH:MM:SS.mmm] メッセージ
##
## 出力先:
##   1) Godot コンソール（print）
##   2) res://logs/runtime.log（毎起動でリセット・書き込みごとに flush）
##
## Autoload 名に関する注意:
##   Godot 4.6 には抽象クラス `Logger` が組込みで存在するため、Autoload 名として
##   `Logger` を使うと `GDScriptNativeClass` と衝突し `DebugLog.log()` 形式の
##   外部呼び出しが `Static function "log()" not found` エラーで失敗する。
##   ゆえに Autoload 名は `DebugLog` に変更済み（ファイル名は logger.gd のまま）。
##
## TODO（Phase 14 Steam 配布）:
##   res:// への書き込みはエディタ実行時のみ保証される（Godot の仕様）。
##   エクスポート後は res:// は読み取り専用になるため、以下のいずれかに対応する必要がある:
##   - リリースビルドでは DebugLog 自体を無効化（OS.has_feature("editor") で分岐）
##   - 書き出し先を user:// に切り替え

extends Node

const LOG_DIR:  String = "res://logs"
const LOG_PATH: String = "res://logs/runtime.log"

## 書き込み先ファイルハンドル（起動時に開き、終了時にクローズ）
var _file: FileAccess = null


func _ready() -> void:
	# SceneTree がアプリ終了要求を通知してくれるように指定
	# （ボーダーレスウィンドウ・Alt+F4・タスクマネージャからの close 等）
	get_tree().set_auto_accept_quit(false)
	_open_log_file()
	# 起動マーカー（毎起動でファイルがリセットされたことを視覚的に分かりやすく）
	# self. を付けてメソッド呼出であることを明示（log は GDScript の組込関数名でもある）
	self.log("=== DebugLog started ===")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			_close_log_file()
			# CLOSE_REQUEST は set_auto_accept_quit(false) 時に自動終了しないため、
			# DebugLog 側でクローズ処理を済ませてから明示的に quit する
			if what == NOTIFICATION_WM_CLOSE_REQUEST:
				get_tree().quit()


## メインの API。メッセージを 1 行ログ出力する（コンソール + ファイル）。
## GDScript 組み込みの print() と名前衝突しないよう、あえて `log` を使う
## （DebugLog.log(...) の名前空間で呼ばれるため曖昧さはない）
func log(message: String) -> void:
	var line: String = "[%s] %s" % [_timestamp(), message]
	print(line)
	if _file != null:
		_file.store_line(line)
		_file.flush()


# --------------------------------------------------------------------------
# 内部
# --------------------------------------------------------------------------

func _open_log_file() -> void:
	# logs/ フォルダがなければ作成する
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		var err: int = DirAccess.make_dir_recursive_absolute(LOG_DIR)
		if err != OK:
			push_warning("[DebugLog] logs ディレクトリの作成に失敗: %s (err=%d)" % [LOG_DIR, err])
			return
	# 毎起動でリセット（WRITE モード）
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file == null:
		push_warning("[DebugLog] ログファイルのオープンに失敗: %s (err=%d)" % [LOG_PATH, FileAccess.get_open_error()])


func _close_log_file() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null


## [HH:MM:SS.mmm] 形式のタイムスタンプを返す
func _timestamp() -> String:
	var t: Dictionary = Time.get_time_dict_from_system()
	var ms: int = Time.get_ticks_msec() % 1000
	return "%02d:%02d:%02d.%03d" % [
		int(t.get("hour",   0)),
		int(t.get("minute", 0)),
		int(t.get("second", 0)),
		ms,
	]
