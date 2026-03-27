class_name LLMClient
extends Node

## Anthropic Messages API への非同期 HTTP クライアント
## Phase 2-3: LLMによるAI行動生成の基盤

signal response_received(result: Dictionary)
signal request_failed(error: String)

const API_URL     := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2023-06-01"
const MODEL       := "claude-haiku-4-5-20251001"
const MAX_TOKENS  := 1024

var _api_key: String = ""
var _http: HTTPRequest
var is_requesting: bool = false


func _ready() -> void:
	_load_api_key()
	_http = HTTPRequest.new()
	_http.name = "HTTPRequest"
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func _load_api_key() -> void:
	var file := FileAccess.open("res://api_key.txt", FileAccess.READ)
	if file == null:
		push_error("LLMClient: api_key.txt が見つかりません")
		return
	_api_key = file.get_as_text().strip_edges()
	file.close()


## プロンプトを送信する。すでにリクエスト中の場合は何もしない
func request(prompt: String) -> void:
	if is_requesting:
		return
	if _api_key.is_empty():
		push_error("LLMClient: APIキーが設定されていません")
		return

	is_requesting = true

	var body := JSON.stringify({
		"model": MODEL,
		"max_tokens": MAX_TOKENS,
		"messages": [
			{"role": "user", "content": prompt}
		]
	})

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-api-key: " + _api_key,
		"anthropic-version: " + API_VERSION
	])

	var err := _http.request(API_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		is_requesting = false
		request_failed.emit("HTTPRequest 送信失敗: " + str(err))


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_requesting = false

	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("通信エラー: result=" + str(result))
		return

	var body_text := body.get_string_from_utf8()

	if response_code != 200:
		request_failed.emit("APIエラー: HTTP %d / %s" % [response_code, body_text])
		return

	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null or not parsed is Dictionary:
		request_failed.emit("レスポンスのJSONパース失敗")
		return

	var content: Array = (parsed as Dictionary).get("content", [])
	if content.is_empty():
		request_failed.emit("レスポンスに content がありません")
		return

	var text: String = (content[0] as Dictionary).get("text", "")

	# LLM返答テキストをJSONとしてパース（```json ... ``` ブロックがあれば除去）
	text = _extract_json(text)
	var action_data: Variant = JSON.parse_string(text)
	if action_data == null or not action_data is Dictionary:
		request_failed.emit("LLM返答のJSONパース失敗: " + text)
		return

	response_received.emit(action_data as Dictionary)


## LLMが ```json ... ``` で囲んで返した場合に中身だけ取り出す
func _extract_json(text: String) -> String:
	var start := text.find("{")
	var end   := text.rfind("}")
	if start == -1 or end == -1:
		return text
	return text.substr(start, end - start + 1)
