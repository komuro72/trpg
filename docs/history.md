# 変更履歴・バグ修正記録

> CLAUDE.md フェーズセクションの圧縮時に抽出した変更履歴。
> 正常に完了した新規実装の詳細は docs/spec.md を参照。

## 2026-04-16（UI・演出ブラッシュアップ）

### ヒットエフェクト3層刷新
- 変更内容: `scripts/hit_effect.gd` を全面書き換え。旧・単純な白い円のフォールバック（0.14秒）を廃止し、リング波紋＋光条フラッシュ＋パーティクル散布の3層プロシージャル描画（0.40秒）に。加算合成（`CanvasItemMaterial.BLEND_MODE_ADD`）で輝度を確保。ダメージ量に応じてリング最大半径とパーティクル数（6〜20）が増減する。
- 理由: 旧エフェクトは輝度が低く攻撃の手応えが薄かった。

### OrderWindow バグ修正と UI 改善
- 修正: 個別指示テーブルで左右キーは名前列を含めて全列で循環する方式に変更（当初の案を経て最終仕様に確定）。上下移動時は列インデックスではなく列の種類（`pos` 値）で対応づけるヘルパー `_get_col_pos_at_cursor()` / `_adjust_col_cursor_by_pos()` を追加し、非ヒーラー4列／ヒーラー5列で行を跨いでも同じ種類の列にカーソルが着地する。
- 修正: 所持アイテム表記を `[restore_hp:30]` から `[HP回復 30]` 形式に変更（ConsumableBar と同じ `EFFECT_LABELS` 方式）。
- 変更: 「パーティー指示」タイトル行を削除して上部スペースを詰めた。
- 変更: ステータス列ヘッダー（素値/補正/最終）を名前行直下に復活。
- 変更: ランクを色付きで描画（right_panel と同じ `_rank_color`。S/A=赤・B/C=橙・他=黄）。left_panel / OrderWindow 両方に展開。
- 変更: レイアウト再構成。全身画像を avail * 0.28（最大240px）に拡大。装備・所持アイテムをそれぞれ 2 列レイアウトに変更。画像は 1:1 のアスペクト比を維持（テキストが長くなっても画像は伸びない）。
- 変更: メンバー行選択時、名前列にもハイライト背景を描画（他の列と挙動統一）。非フォーカス時の名前は白、フォーカス行の名前は黄色（操作中は緑が優先）。
- 変更: ログ行を廃止。`_FocusArea.CLOSE` / `LOG`、`_log_mode` / `_log_scroll`、`_draw_log_section()` を削除。メンバー最終行で下キーは留まる。メッセージログは MessageWindow 側で見る運用に統一。

### メッセージウィンドウ大幅刷新
- 変更: 右スティック上下 / PageUp / PageDown でピクセル単位スムーズスクロール。`Input.get_action_strength()` でアナログ強度を取得し、2乗カーブ × `MANUAL_SCROLL_SPEED = 900.0 px/s`。新メッセージ到着で自動的に最新位置に戻る。時間停止は制御しない。
- 変更: R3 押し込み / Home でメッセージウィンドウの表示行数をトグル（`VISIBLE_LINES = 3` ↔ `EXPANDED_LINES = 7`）。拡大時は画面上端まで中央テキスト部だけが伸び、左右バスト画像は通常サイズ・下端寄せを維持。
- 変更: 背景不透明度を 0.80 → 0.55 に下げて半透明化。左右バスト部の背景・枠線・セパレータ線を削除し、キャラクター画像のみ表示。データが無い場合の黒矩形フォールバックも削除（ゲーム開始時の右エリアに黒背景が残っていた問題を解消）。
- 変更: アイコンサイズを文字2行分の仕様（`ICON_SCALE_RATIO = 2.0/3.0`、`LINE_HEIGHT_RATIO = 1.5`）に戻した。実試験縮小版（1/3・1.25）を廃止。
- 追加: 文字色分け。MessageLog のエントリに `segments: Array[{text, color, bold?}]` を追加し、セグメント単位で色分け描画できる `_draw_segments()` を実装。自パーティー名=青 / 未加入NPC名=水色 / 敵名=暗い緑 / 小ダメ=白 / 中ダメ=黄 / 大ダメ=オレンジ / 特大ダメ=赤＋太字。通常攻撃メッセージ（`character.gd._emit_damage_battle_msg`）と V スロット特殊攻撃メッセージ（`player_controller.gd._emit_v_skill_battle_msg` / `unit_ai.gd._emit_v_skill_battle_msg`・空振り・ヘッドショット・炎陣・スライディング）を segments 化。

### 状態ラベルを 4 段階に拡張＋色表示統一
- 変更: 状態ラベルを 4 段階（healthy / wounded / injured / critical）に拡張。閾値を `CONDITION_HEALTHY_THRESHOLD = 0.5` / `CONDITION_WOUNDED_THRESHOLD = 0.35` / `CONDITION_INJURED_THRESHOLD = 0.25` に再設定。
- 変更: キャラクタースプライト modulate・左右パネルのテキスト色・HP バー色を全て状態ラベル閾値に統一。スプライト: 白 / オレンジ / 赤 / 赤点滅。テキスト・ゲージ: 緑 / 黄 / オレンジ / 赤。中間色のハードコード閾値（0.60 / 0.30 / 0.10 / 0.5 / 0.25）を廃止。
- 変更: DebugWindow の HP 色分け 2 箇所も状態ラベル閾値に統一。`party_leader._estimate_hp_ratio_from_condition()` に injured ケースを追加。
- 備考: AI の `NEAR_DEATH_THRESHOLD = 0.25`（HPポーション自動使用・heal "aggressive" モード等）は変更せず据え置き。

### 攻撃フロー改善
- 追加: PRE_DELAY / TARGETING 中の他ボタン入力で攻撃をキャンセルし、そのボタンの機能を即時実行する `_handle_attack_switch_input()` を追加。アイテムボタン（C/X）でアイテム UI、V/Y で特殊攻撃開始（通常→特殊）、Z/A で通常攻撃開始（特殊→通常）に切替。
- 追加: TARGETING 突入時に `_valid_targets` が空なら射程オーバーレイを `AUTO_CANCEL_FLASH = 0.25 秒`だけ見せてから自動キャンセル。待機中は他の入力をブロック。
- 修正: ヒーラーの射程オーバーレイが前方±45°しか表示されなかった。`game_map._draw_tiles` の射程描画で `action == "heal" or action == "buff_defense"` 時は距離判定のみ（360度）に変更。実際の判定ロジックと整合。

### アイテム名称統一
- 変更: `HP回復ポーション` / `MP回復ポーション` / `SP回復ポーション` → `HPポーション` / `MPポーション` / `SPポーション`。`character.gd` の自然言語バトルメッセージ 3 箇所と CLAUDE.md / docs/spec.md のドキュメントを更新。
- 修正: SP ポーションが `活力薬` 表記になっていた箇所（`game_map.gd` の初期付与・`dungeon_handcrafted.json` の 53 箇所）を全て `SPポーション` に一括置換。

### 安全部屋専用タイル画像
- 追加: フロア 0 の「安全の広間」用の床タイル画像 `assets/images/tiles/stone_00001/safe_floor.png` を配置。`game_map._load_tile_textures()` でロードし、`_draw()` 内で `map_data.is_safe_tile(pos)` の FLOOR タイルのみ `_safe_floor_tex` で描画するように拡張。

### Character.joined_to_player 伝播
- 追加: `Character.joined_to_player: bool` フラグを追加。主人公は初期化時に `true`、NPC パーティーは `PartyManager.set_joined_to_player()` 呼び出し時にメンバー全員に伝播。メッセージ色分けの「自パーティー」判定に使用。

## Phase 2

### 設計変更: AI行動生成をLLMからルールベースに変更
- 理由: LLMベースのAI行動生成は実用的でなかった
- 変更内容: Phase 2-3 でルールベースAI行動生成に変更。LLMClient / DungeonGenerator はコード上残存しているが未使用（将来削除対象）

### 設計変更: A*ゴールタイル特例の廃止
- 理由: 同一パーティー内の敵重複が発生していた
- 変更内容: `_find_adjacent_goal` に `_is_passable` による占有チェックを追加し、A* のゴールタイル特例を廃止。全パーティー合算の `_all_enemies` を BaseAI が参照してパーティーをまたいだ敵同士の重複を防止

## Phase 3

### 設計変更: ダンジョン生成をLLMからClaude Code手作りに変更
- 理由: ゲーム内LLM生成はトークン上限が課題で実用的でなかった
- 変更内容: Claude Code が dungeon_handcrafted.json を手作りで作成・管理する方式に変更（ゲーム内LLM生成は廃止済み）

### 廃止: LLMClient / DungeonGenerator
- 理由: ルールベースAI・手作りダンジョンに移行済み
- 備考: コードはゲーム内に残存しているが現在は未使用（将来削除対象）

## Phase 5

### 設計変更: RUBBLE → OBSTACLE にリネーム
- 理由: タイル種別名称の統一
- 変更内容: タイル種別定数・コメント等で RUBBLE を OBSTACLE にリネーム

### 廃止: AIデバッグパネル（RightPanel下半分）
- 理由: Phase 10-2準備でMessageWindowのデバッグメッセージ方式（F1でON/OFF）に移行。後に DebugWindow（F1トグル）方式へさらに移行
- 変更内容: RightPanel からAIデバッグ表示を削除。敵情報表示のみ残す

## Phase 6

### 設計変更: AIアーキテクチャを2層構造にリファクタリング
- 理由: 仲間AI・パーティー管理の汎用化
- 変更内容: BaseAI/GoblinAI → PartyLeaderAI + UnitAI に再編。EnemyManager → PartyManager に汎用化

### バグ修正: ノード名衝突
- 原因: party_manager.gd で複数マネージャーのノード名が衝突
- 修正: マネージャー名をプレフィックスに追加

### バグ修正: freed オブジェクトキャストクラッシュ
- 原因: unit_ai.gd で freed されたオブジェクトに対してキャストを行いクラッシュ
- 修正: is_instance_valid チェックを追加

### 設計変更: 共闘判定をポーリングからイベント駆動に変更
- 理由: 効率化
- 変更内容: `_update_fought_together_flags()` ポーリング方式から `Character.dealt_damage_to / took_damage_from` シグナルのイベント駆動に変更

### 廃止: DialogueWindow.gd
- 理由: Phase 10-2準備で会話UIをMessageWindowに統合
- 変更内容: 会話の選択肢をMessageWindow下部にインライン表示する方式に変更。後に Phase 12-8 で NpcDialogueWindow として独立ウィンドウに再分離

### 設計変更: NPC会話トリガーをバンプ方式からAボタン方式に変更
- 理由: Phase 12-14 で矢印キーバンプ方式だと移動との競合が問題になった
- 変更内容: プレイヤー起点の A ボタン押下時に隣接 NPC を検索して発火する方式に変更

### 設計変更: NPC自発申し出を無効化
- 理由: ゲームプレイ上の調整
- 変更内容: `wants_to_initiate()` は常に false を返す。プレイヤー起点の会話のみ有効

## Phase 8

### バグ修正: enemy_id のハイフンとアンダーバーの不整合
- 原因: party_manager._spawn_member() が enemy_id（例: "goblin-mage"）をそのまま使用し、JSONファイル名（goblin_mage.json）と不一致
- 修正: enemy_id のハイフンをアンダーバーに変換してJSONファイルを正しく読み込む

### バグ修正: dark_priest.json の id 不整合
- 原因: id が "dark_priest" だったが画像フォルダ名は `dark-priest_...`
- 修正: id を "dark_priest" → "dark-priest" に修正

### 設計変更: dungeon_handcrafted.json の再作成
- 理由: 11種の敵対応に伴い旧データが不適合
- 変更内容: 旧 dungeon_handcrafted.json を削除し、12部屋x4フロア+ボス1部屋の5フロア構成で再作成。handcrafted ダンジョン読み込みロジックを復元

## Phase 9

### 設計変更: PlayerController の移動方式をタイマーから先行入力バッファに変更
- 理由: 1回押しで2マス進む問題、斜め移動（補間途中から別方向補間）、長押し停止の問題を解消
- 変更内容: タイマー方式を廃止し先行入力バッファ方式（_move_buffer）に変更。アニメーション中は is_moving() で移動をブロック

### 設計変更: UnitAI の MOVE_INTERVAL 変更
- 理由: 歩行アニメーション導入に伴う速度調整
- 変更内容: MOVE_INTERVAL を 0.4s → 1.2s に変更（後に Phase 11-2 で 0.40s に再変更）

### バグ修正: LB後退サイクルバグ
- 原因: `_refresh_targets()` がキャンセル状態を毎フレームリセットしていた
- 修正: was_cancel フラグで保持

### 設計変更: 衝突判定の改善（先着優先方式）
- 理由: 移動中の衝突判定が不十分だった
- 変更内容: `_can_move_to()` を `grid_pos` のみで判定。`static var _all_chars` レジストリを追加し、移動進捗50%（コミット時）に競合チェック。競合があれば `abort_move()` で移動をキャンセル

### 設計変更: attack_melee → attack にリネーム・1ボタン統合
- 理由: 攻撃タイプ（melee/ranged）はクラスのスロット定義から自動判定するため2ボタン不要
- 変更内容: attack_ranged を削除。attack_melee → attack にリネーム。AttackSlot.X・_slot_x・DEFAULT_SLOT_X を削除

## Phase 10

### 設計変更: ステータスフィールドリネーム
- 理由: 統合・一貫性の向上
- 変更内容: `attack` → `attack_power`、`heal_power` → `magic_power`（魔法攻撃力+回復力を統合）

### 廃止: AIデバッグパネル（RightPanel）
- 理由: MessageLog方式（後にDebugWindow方式）に移行
- 変更内容: RightPanel からAIデバッグ表示を削除。MessageLog（Autoload）を新設

### 設計変更: NPC パーティーのデフォルト戦略を WAIT → EXPLORE に変更
- 理由: 敵なし時にNPCが何もしないのは不自然
- 変更内容: Strategy enum に EXPLORE を追加。NPC パーティーのデフォルト戦略を EXPLORE に変更

### 設計変更: 全キャラクター常時行動化
- 理由: 画面外のNPCも自律行動させるため
- 変更内容: NPC パーティーをゲーム開始時に即座にアクティブ化。画面外のNPCは非表示のまま自律行動

### 廃止: DialogueWindow（Phase 10-2準備）
- 理由: MessageWindowに統合
- 変更内容: 会話の選択肢をMessageWindow下部にインライン表示

### 廃止: OrderWindow の旧「操作」列
- 理由: サブメニュー方式に刷新
- 変更内容: サブメニュー項目を「操作切替 / アイテム」に変更

### 設計変更: 装備補正値の新仕様統一
- 理由: 初期装備と敵ドロップの補正値体系を整理
- 変更内容: 初期装備は全補正値0。武器の `skill` 補正を廃止。盾の旧 `physical_resistance` を削除し `block_left_front` のみに。防具は physical_resistance + magic_resistance の両方を持つように修正

### 設計変更: 主人公を hero.json 固定からランダム生成に変更
- 理由: 他キャラと同様のシステムに統一
- 変更内容: CharacterGenerator を使用したランダム生成に変更。dungeon_handcrafted.json の主人公定義を character_id:"hero" → class_id:"fighter-sword" に変更

### 設計変更: カメラデッドゾーン比率変更
- 理由: 先読みマージン拡大・出会いがしら軽減
- 変更内容: デッドゾーン比率を 0.70 → 0.40 に変更

### バグ修正: アイテム選択UIに装備中アイテムが表示される
- 原因: 装備中の武器・防具・盾がアイテム選択UIに表示されていた
- 修正: `is_same()` で判定して装備中アイテムを除外

### バグ修正: sprite_front ファイル不在時のクラッシュ
- 原因: `_get_char_front_texture()` が sprite_front パスが設定されているがファイルが存在しない場合を考慮していなかった
- 修正: sprite_face にフォールバックするよう修正

### 設計変更: OrderWindow を誰でも開けるように変更
- 理由: 非リーダー操作中もステータスを確認したい
- 変更内容: 誰を操作中でも Tab / Select でウィンドウを開ける（旧：リーダーのみ）。非リーダー操作中は閲覧のみ

## Phase 11

### バグ修正: クロスフロアすり抜け・不可視攻撃（Phase 11-1）
- 原因: フロア遷移後に (1)敵・NPCスポーン時にcurrent_floorが未設定 (2)blocking_charactersが旧フロアのまま (3)別フロアのターゲットが残留
- 修正: 3点修正 - current_floorセット、blocking_characters再構築、別フロアターゲットをnullに排除

### バグ修正: 矢印キー長押しで階段を通り抜ける（Phase 11-1）
- 原因: 階段タイル静止中に移動バッファが処理されていた
- 修正: 階段タイル静止中は移動バッファをブロック。stair_just_transitioned フラグで遷移直後はブロック解除

### バグ修正: NPC アクティブ化が未訪問エリアでも発生
- 原因: 起動時・フロア遷移時に全NPCをアクティブ化していた
- 修正: 訪問済みエリアのみに限定

### 設計変更: カメラ X 方向デッドゾーン変更
- 理由: 進行方向の視野を改善
- 変更内容: 0.40 → 0.20 に変更

### 設計変更: MAP_BORDER 追加
- 理由: マップ端での画面端寄りを解消
- 変更内容: DungeonBuilder に MAP_BORDER = 6 を追加（四方6タイルの境界壁）

### バグ修正: 魔法敵が攻撃しない問題（Phase 11-2）
- 原因: `party_leader_ai.gd` の `magic_power > 0` 条件が魔法攻撃キャラを WAIT に固定していた
- 修正: 条件を `heal_mp_cost > 0 or buff_mp_cost > 0` に修正

### バグ修正: 敵の初動が遅い問題（Phase 11-2）
- 原因: `unit_ai.gd` の move アクション開始時タイマーが `_get_move_interval()` で初期化されていた
- 修正: タイマーを `0.0` に変更（最初の1歩の待ち時間を解消）

### 設計変更: 敵・NPCの移動速度調整（Phase 11-2）
- 理由: プレイヤー速度（0.30 s/タイル）に対して遅すぎた
- 変更内容: `MOVE_INTERVAL` を `1.2` → `0.40` 秒/タイルに変更

## Phase 12

### 設計変更: SPポーションアイコン色変更
- 理由: 水色だと magician-water の水弾と紛らわしい
- 変更内容: 水色 → 緑（`Color(0.2, 0.8, 0.3)`）に変更

### 設計変更: ConsumableDisplayMode を GlobalConstants に移動
- 理由: Godot 4 のパース順問題で ConsumableBar.DisplayMode が外部から参照できないエラー
- 変更内容: `GlobalConstants` に enum を移動し、全参照箇所を統一

### 設計変更: 操作体系変更（Phase 12-5）
- 理由: LB/RBキャラ切り替え・C/X短押しアイテム選択UI導入
- 変更内容: 旧 `slot_prev`/`slot_next` を空に（未使用）。`switch_char_prev`/`switch_char_next` を追加

### バグ修正: NPC パーティーがプレイヤーを追従する問題（Phase 12-7）
- 原因: `party_leader_ai._assign_orders()` の formation_ref 決定ロジックが未加入 NPC パーティーにも `_player` を渡していた
- 修正: `joined_to_player` フラグを追加。合流済みの場合のみ `formation_ref = _player`。未加入NPCリーダーは自由行動

### バグ修正: 仲間の「同じ部屋」指示が機能しない問題（Phase 12-7）
- 原因: 通路タイル（area_id が空文字）の場合に常に true を返していた
- 修正: 通路にいる場合はマンハッタン距離 ≤3 のフォールバック判定に切り替え

### バグ修正: ヒーラーが他パーティーのNPCに回復・バフをかける問題（Phase 12-7）
- 原因: `_find_heal_target()` / `_find_buff_target()` が `_all_members` 全体を対象にしていた
- 修正: `_party_peers` フィールドを追加し、自パーティーメンバー+hero に限定

### バグ修正: アイテムが未訪問フロアに出現する問題（Phase 12-7）
- 原因: `_floor_items` がフラット辞書で全フロアのアイテムが混在
- 修正: `_floor_items` を `{floor_idx: {Vector2i: item}}` のネスト構造に変更

### バグ修正: A* 経路探索で階段タイルを通り抜ける問題（Phase 12-7）
- 原因: `_astar()` が階段タイルを中間ノードとして通過可能として扱っていた
- 修正: 階段タイルを中間ノードとしてスキップ。`_find_adjacent_goal()` で非階段タイルを優先。階段上にいる場合は隣接非階段タイルへ移動するフォールバック追加

### バグ修正: 未加入NPCの意図しないフロア遷移（Phase 12-7）
- 原因: NpcManager の `get_explore_move_policy()` を確認せずに遷移を実行していた
- 修正: "stairs_down"/"stairs_up" の意図がない場合は遷移をスキップ

### バグ修正: NPC リーダー遷移時に全メンバーが一括ワープ（Phase 12-7追加修正）
- 原因: `_transition_npc_floor()` がパーティー全員を一括で新フロアへ転送していた
- 修正: プレイヤーパーティーメンバー遷移と同じ個別遷移方式を採用。リーダーのみ先行遷移、非リーダーは個別に追従

### バグ修正: OrderWindow 名前列で右キーがサブメニューを開く（Phase 12-8）
- 原因: 名前列（_col_cursor=0）で右キーを押すとサブメニューが開いていた
- 修正: 右キーは常に列移動のみ。サブメニューを開くのは Z/A のみ

### 設計変更: NPC会話をMessageWindowからNpcDialogueWindow に分離（Phase 12-8）
- 理由: 会話UIを専用ウィンドウにして操作性向上
- 変更内容: NpcDialogueWindow を新設（CanvasLayer layer=20、ゲーム一時停止）。MessageWindowの会話モードはNPC会話には使用しない

### 廃止: CHOICE_JOIN_THEM（「連れて行って」）（Phase 12-8）
- 理由: UI簡略化（後に Phase 12-14 で「一緒に行く」として復活、さらに Phase 13-8 で再度廃止）
- 変更内容: join_us のみ対応に変更

### バグ修正: 別フロアのキャラクターが移動をブロックする問題（Phase 12-8）
- 原因: `_rebuild_blocking_characters()` が全フロアの敵・NPC を無差別に追加していた（current_floor フィルターなし）。無効参照（freed キャラ）も混入
- 修正: current_floor フィルタリング + is_instance_valid チェック。`_can_move_to()` / `_try_move()` / `_get_valid_targets()` にも同フロアフィルターを追加（二重防衛）

### バグ修正: 敵がプレイヤー以外を攻撃しない問題（Phase 12-8）
- 原因: (1)全敵リーダーAIの `_select_target_for()` が `return _player` 固定 (2)`set_friendly_list()` を呼ぶ時点で `_leader_ai == null` でリストが破棄
- 修正: (1)PartyLeaderAI に `_friendly_list` と検索メソッドを追加 (2)PartyManager に `_friendly_list` を保存し `_start_ai()` 内で渡す

### 設計変更: 左パネルからMAP表示を削除（Phase 12-9）
- 理由: 12人対応のためスペースが必要
- 変更内容: minimap_h（下25%）を廃止し全高さをキャラクター表示に使用

### バグ修正: NPC が同フロア敵全滅後に探索モードへ移行しない問題（Phase 12-11）
- 原因: `_evaluate_party_strategy()` が全フロアの敵を無差別にチェックしていた
- 修正: 同フロアの敵のみ ATTACK トリガーにする

### 設計変更: NPC フロアランクスコアロジック全面改修（Phase 12-11）
- 理由: 平均スコアベースではNPCが適切なフロアに移動しなかった
- 変更内容: 3段階で改修。最終的に RANK_VALUES（C=3, B=4, A=5, S=6）の合計方式に変更。FLOOR_RANK を `{0:0, 1:8, 2:13, 3:18, 4:24}` に更新

### 設計変更: NPC の階段探索を視界ベースに変更（Phase 12-11）
- 理由: NPCが全階段位置を知っているのは不自然
- 変更内容: `NPC_KNOWS_STAIRS_LOCATION: bool = false` フラグ追加。パーティー単位で訪問情報を共有し、未発見の場合は探索にフォールバック

### バグ修正: NPC がフロア遷移後に動かない問題（Phase 12-11）
- 原因: `_generate_queue()` のフロア追従チェックが `is_friendly` で判定しており、未加入NPCが hero と別フロアにいると追従命令になり停止
- 修正: `_follow_hero_floors` フラグを追加。合流済みメンバーのみフロア追従

### バグ修正: NPC がフロア遷移後にすり抜けられる問題（Phase 12-11）
- 原因: `_transition_npc_floor()` で NPC 到着時に `_rebuild_blocking_characters()` が呼ばれていなかった
- 修正: 到着ブロックに `_rebuild_blocking_characters()` 呼び出しを追加

### バグ修正: NPC 複数パーティーが同一階段タイルに集中（Phase 12-11）
- 原因: 常に `spawn_stairs[0]` を全パーティーの着地基点にしていた
- 修正: 旧フロアで踏んでいた階段タイルの座標に最も近い新フロアの階段を着地点として選択

### 設計変更: dungeon_handcrafted.json 全面再生成（Phase 12-13）
- 理由: 新敵種追加・バランス調整
- 変更内容: 12部屋x4フロア+ボス1部屋。フロア深度に応じたアイテム補正値スケール

### バグ修正: ConsumableBar.DisplayMode パースエラー（Phase 12-13）
- 原因: Godot 4 のパース順問題で外部から参照できない
- 修正: GlobalConstants に enum を移動

### バグ修正: ConsumableBar アイテム画像が表示されない（Phase 12-13）
- 原因: ダンジョン JSON のアイテム定義に `image` フィールドがないため img_path が空
- 修正: img_path が空のとき `"assets/images/items/" + itype + ".png"` を導出するフォールバックを追加

### バグ修正: daggar.png typo
- 原因: ファイル名のスペルミス
- 修正: `assets/images/items/daggar.png` → `dagger.png` にリネーム

### 設計変更: ステータスフィールド名統一（Phase 12-14）
- 理由: attack_power / magic_power の二重管理を解消
- 変更内容: `attack_power` / `magic_power` → `power` に統一。`accuracy` → `skill` に統一。旧キーはフォールバック互換維持

### 設計変更: ガード防御改修（Phase 12-14）
- 理由: 旧x3乗算がバランスを崩していた
- 変更内容: 正面攻撃は防御判定100%成功・防御強度分カットに変更（旧x3乗算廃止）

### 設計変更: NPC会話トリガーをバンプ方式からAボタン方式に変更（Phase 12-14）
- 理由: 移動との競合防止
- 変更内容: バンプ検出方式を廃止。Aボタンで隣接NPCに話しかける方式に変更

### 設計変更: NPC会話選択肢の刷新（Phase 12-14）
- 理由: 「一緒に行く」（join_them）選択肢を復活
- 変更内容: 「仲間にする」「一緒に行く」「キャンセル」の3択に変更。会話UI開き直後2フレームの入力スキップ（ボタンリーク修正）

### バグ修正: 「一緒に行く」合流時のハイライト誤切り替え（Phase 12-14）
- 原因: 操作キャラ（hero）のハイライトがNPCリーダーに移っていた
- 修正: ハイライトを維持するよう修正。`_switch_character()` の判定を `character.is_leader` ベースに変更

### 設計変更: ステータス生成をハードコードから設定ファイル方式に移行（Phase 12-15）
- 理由: CLASS_STAT_BASES ハードコード定数では管理が困難
- 変更内容: class_stats.json / attribute_stats.json による設定ファイル方式に移行。全ステータス 0-100 スケールに統一

### 廃止: クラスJSON の "mp" / "max_sp" フィールド（Phase 12-15）
- 理由: energy ステータスで代替
- 変更内容: vitality → max_hp、energy → 魔法クラスは max_mp・非魔法クラスは max_sp に格納

### 設計変更: 「特殊スキル」→「特殊攻撃」全置換（Phase 12-14）
- 理由: 用語の統一
- 変更内容: コード・UI・MessageLog で全置換

### バグ修正: NPC フロア遷移時の freed hero クラッシュ（Phase 12-18）
- 原因: hero が死亡済み（freed）の状態で `dialogue_trigger.setup(hero, ...)` を呼ぶ
- 修正: `is_instance_valid(hero)` チェックを追加

### バグ修正: party.members の freed キャラへの as キャストクラッシュ（Phase 12-18）
- 原因: 死亡したキャラクターが party.members に残留し as Character キャストでクラッシュ
- 修正: `for member_var: Variant` に変更し `is_instance_valid()` チェックを先に実施（4箇所）

### バグ修正: フロア遷移後の敵が動かない問題（Phase 12-18）
- 原因: `_link_all_character_lists()` が起動時にしか呼ばれず、新フロアの EnemyManager が set_friendly_list() を受け取れない
- 修正: `_transition_floor()` 内で `_link_all_character_lists()` を呼ぶ

### バグ修正: VisionSystem._process で freed party メンバーへのクラッシュ（Phase 12-18）
- 原因: 死亡キャラが _party.members に残り3か所でクラッシュ
- 修正: is_instance_valid(m) チェックを3箇所に追加

### バグ修正: LB/RB キャラ切り替えが2人目操作後に効かなくなる問題（Phase 12-18）
- 原因: `_switch_character()` が `character.is_leader` で判定していたため、非リーダーキャラに切り替えると以降不可に
- 修正: `player_is_leader` フラグを追加し、NPC パーティーに合流した場合のみ false に設定

### バグ修正: 攻撃キャンセル後にアウトラインが操作キャラに残る（Phase 12-18）
- 原因: `_exit_targeting()` 末尾で不要な `set_outline()` を呼んでいた
- 修正: 不要な呼び出しを削除。アウトラインクリアを全キャラ走査に変更

### バグ修正: 敵ヒーラーがプレイヤーを回復する（Phase 12-19）
- 原因: `_find_heal_target()` が `is_friendly == true` でフィルタしており、敵ヒーラーが hero を回復対象にしていた
- 修正: `ch.is_friendly != my_friendly` に変更し同じ陣営のみ対象

### バグ修正: 回復スキルを持たない敵が回復行動を生成する（Phase 12-19）
- 原因: `_generate_heal_queue()` に `heal_mp_cost <= 0` のガードがなかった
- 修正: `cost <= 0` の場合は早期リターンを追加

### バグ修正: アウトラインシェーダーが modulate を無視する（Phase 12-19）
- 原因: `COLOR = texture(TEXTURE, UV)` で生テクスチャ色を書き込み、Godot が渡す modulate を上書き
- 修正: COLOR（modulate 情報）を保持し、テクスチャ色に乗算するよう変更

### バグ修正: hero 死亡後のフロア初期化クラッシュ（Phase 12-19）
- 原因: hero が freed の状態で `em.setup(members, hero, ...)` が呼ばれる
- 修正: `_setup_floor_enemies()` / `_setup_floor_npcs()` に `is_instance_valid(hero)` ガードを追加

### バグ修正: party.sorted_members() の freed キャラクラッシュ（Phase 12-19）
- 原因: 死亡キャラが members に残留し `m as Character` でクラッシュ
- 修正: キャスト前に `is_instance_valid(m)` チェックを追加

### 廃止: 武器の skill 補正（Phase 12-19）
- 理由: 仕様通り skill は装備で変化しない
- 変更内容: `refresh_stats_from_equipment()` から skill 加算を削除。order_window の skill 行の装備補正表示を 0 固定に

### 廃止: 古い敵画像フォルダ（Phase 12-19）
- 理由: コード・マスターデータから未参照の旧画像整理
- 変更内容: 3/30 作成の22フォルダを削除。新画像（4/7 作成・16種）のみ残す

## Phase 13

### 設計変更: メインシーンを game_map.tscn → title_screen.tscn に変更
- 理由: タイトル画面・メニューシステム導入
- 変更内容: project.godot のメインシーンを変更

### 廃止: Esc キーによる get_tree().quit()
- 理由: ポーズメニュー導入
- 変更内容: KEY_ESCAPE をポーズメニュー開閉に変更

### 設計変更: MessageWindow 全面刷新（Phase 13-1）
- 理由: 戦闘メッセージのアイコン行方式・自然言語化
- 変更内容: スクロール型に統一（左右バスト画像・MESSAGE_WINDOW_SCROLL_MODE フラグを廃止）。バトルメッセージに攻撃側・被攻撃側の face.png アイコンを表示

### 設計変更: 攻撃タイプ別ダメージ倍率変更（Phase 13-2）
- 理由: バランス調整
- 変更内容: melee 0.5→0.3、dive 0.5→0.3

### バグ修正: NPC 探索で全員が同じエリアを目標にして一塊になる（Phase 13-2）
- 原因: 全員が最近傍エリアを目標にしていた
- 修正: `_member.name.hash() % candidates.size()` で NPC ごとに異なるエリアを割り当て

### バグ修正: NPC 目標フロア到達後に探索を開始しない（Phase 13-2）
- 原因: EXPLORE 戦略時に move_policy が "same_room" のままだった
- 修正: pol == "explore" のとき全メンバーの move_policy を "explore" に設定

### 設計変更: 部屋制圧判定に敵走離脱を追加（Phase 13-2）
- 理由: 従来は全員死亡のみが発火条件だった
- 変更内容: 部屋外にいる + FLEE 戦略のメンバーを離脱扱いにカウント

### バグ修正: MessageWindow 上端クリッピング（Phase 13-3）
- 原因: スクロール中にエントリが上端に食い込む
- 修正: SubViewportContainer + SubViewport 構成に変更してピクセル単位のクリップ領域を確保

### 設計変更: F1 デバッグ表示のデフォルトを ON → OFF に変更（Phase 13-3）
- 理由: DebugWindow 方式への移行に伴い通常プレイ中はデバッグ非表示が適切
- 変更内容: デフォルト OFF

### バグ修正: 通路の _carve_corridor() が wall_tiles の WALL を上書き（Phase 13-4）
- 原因: `_carve_corridor()` が部屋形状のための wall_tiles 設定の WALL を CORRIDOR に上書き
- 修正: 条件を `t != FLOOR and t != WALL` に変更し部屋形状の壁タイルを保護

### バグ修正: WALL 上書き禁止が廊下の外壁貫通も妨げる（Phase 13-4）
- 原因: wall_tiles/obstacle_tiles を先に適用すると通路が掘削できない
- 修正: 処理順を `_carve_room()` → `_carve_corridor()` → `_apply_room_overlays()` に変更。CORRIDOR タイルは上書きしない

### 設計変更: OrderWindow 全体方針を1行プリセット選択 → 6行個別設定に刷新（Phase 13-5）
- 理由: より細かい指示が必要
- 変更内容: move/battle_policy/target/on_low_hp/item_pickup/hp_potion/sp_mp_potion の6行に拡張

### 設計変更: 個別指示テーブルを6列 → 4列に変更（Phase 13-5）
- 理由: 全体方針に移動した項目を削除し、UIをシンプルに
- 変更内容: 旧6列（移動/隊形/戦闘/ターゲット/低HP/アイテム取得）を4列（ターゲット/隊形/戦闘/特殊攻撃）に。移動/低HP/取得列は全体方針に移動

### 廃止: 旧 COL_OPTIONS/COL_LABELS/COL_HEADERS/COL_KEYS/PRESETS/PRESET_TABLE（Phase 13-5）
- 理由: MEMBER_COLS/HEALER_COLS 方式に刷新
- 変更内容: 旧定数群を削除。新方式ではクラスごとに列定義を切り替え

### 設計変更: Party.global_orders キー・デフォルト値の変更（Phase 13-6）
- 理由: Phase 13-5 で確定した仕様の反映
- 変更内容: `"combat"` → `"move"` にキー名変更。item_pickup デフォルト "aggressive"→"passive"。target デフォルト "nearest"→"same_as_leader"。on_low_hp デフォルト "keep_fighting"→"retreat"

### 設計変更: 移動前回転実装（Phase 13-7）
- 理由: 向きだけ変える操作が未実装だった
- 変更内容: 入力方向が現在の向きと異なる場合、まず回転のみ行い移動しない。回転完了時にキーが押されていれば移動実行、離されていれば向きだけ変わって停止

### 廃止: NPC会話の「一緒に行く」選択肢（Phase 13-8）
- 理由: UI簡略化
- 変更内容: 「仲間にする」「キャンセル」の2択に変更

### 設計変更: OrderWindow ステータス表示を2列化（Phase 13-9）
- 理由: 縦幅の節約・情報密度の向上
- 変更内容: 左列（HP/SP・MP/威力/技量/防御強度）と右列（耐性/防御技量/攻撃タイプ/射程/統率力/従順度）の2列レイアウトに変更。「ランク」行をヘッダーに統合して廃止

### 設計変更: ヒーラーの heal 指示デフォルトを変更（Phase 13-10後続修正）
- 理由: 瀕死度優先のほうが実用的
- 変更内容: デフォルトを `"lowest_hp_first"` に変更

### 設計変更: character.gd の current_order デフォルト値変更（Phase 13-11）
- 理由: プレイヤーパーティーとの整合
- 変更内容: move "cluster"→"follow"、combat "aggressive"→"attack"、target "nearest"→"same_as_leader"、on_low_hp "keep_fighting"→"retreat"、item_pickup "aggressive"→"passive"

### 設計変更: 戦闘中の隊形優先（Phase 13-11）
- 理由: 戦闘中に move_policy（follow/cluster 等）で移動先が決まると直感的でなかった
- 変更内容: Strategy.ATTACK 時は battle_formation のみで移動先を決定。move_policy は WAIT/EXPLORE 時のみ適用

### 設計変更: follow 追従ロジック改善（Phase 13-11）
- 理由: 旧ロジックでは味方がリーダーの前方に居座ることがあった
- 変更内容: リーダー後方1タイル以内を維持するよう変更。前方にいる場合は後ろに回り込む

### 廃止: _formation_satisfied() / _target_in_formation_zone() の一部使用箇所（Phase 13-11）
- 理由: 戦闘中は battle_formation のみで判定するよう変更
- 変更内容: Strategy.ATTACK ブランチ（ターゲットあり）での呼び出しを廃止

### バグ修正: EXPLORE 時に全員が "explore" に上書きされ follow が効かない（Phase 13-11）
- 原因: `party_leader_ai._assign_orders()` で EXPLORE + 未加入NPC の場合、全員のmove_policyを "explore" に上書きしていた
- 修正: リーダーのみ "explore"、非リーダーは `current_order["move"]`（= "follow"）を使うよう変更

### 設計変更: フロア0をゴブリンのみに変更（Phase 13-11）
- 理由: 序盤の難易度調整
- 変更内容: goblin-archer / goblin-mage / hobgoblin をフロア0から除去。フロア1以降で登場

## Phase外の改善

### 設計変更: 敵リーダーAI継承構造のリファクタリング
- 理由: Goblin/Wolf/Hobgoblin/DefaultLeaderAI の4クラスで `_evaluate_party_strategy()` と `_select_target_for()` がほぼ同一コードの重複。新敵種追加時に共通ロジックをコピペする必要があった
- 変更内容:
  - `DefaultLeaderAI` → `EnemyLeaderAI` にリネーム（`default_leader_ai.gd` → `enemy_leader_ai.gd`）
  - EnemyLeaderAI に敵共通のデフォルト行動を定義（ATTACK/WAIT 判定、最近傍ターゲット選択）
  - GoblinLeaderAI / WolfLeaderAI / HobgoblinLeaderAI の継承先を `PartyLeaderAI` → `EnemyLeaderAI` に変更
  - 各種族AIは差分のみオーバーライド（Goblin/Wolf: FLEE条件追加、Hobgoblin: 差分なし）
  - 重複していた `_select_target_for()` を種族AIから削除（EnemyLeaderAI のデフォルトを継承）
  - `party_manager._create_leader_ai()` の参照を `DefaultLeaderAI` → `EnemyLeaderAI` に更新

### 設計変更: PartyLeader 基底クラスの抽出
- 理由: PartyLeaderAI と PartyLeaderPlayer の共通ロジック（指示伝達・UnitAI管理・セッター群等）を基底クラスに分離し、プレイヤーパーティーもAIパーティーも同じ枠組みで動作させる設計にする
- 変更内容:
  - `party_leader.gd`（PartyLeader）を新設: `_assign_orders()` / UnitAI管理 / セッター群 / 縄張り判定 / ログ等の共通機能を `party_leader_ai.gd` から移動
  - `party_leader_ai.gd` を `extends PartyLeader` に変更（AI固有のデフォルト実装のみ保持）
  - `party_leader_player.gd`（PartyLeaderPlayer）を新設: プレイヤー操作パーティー用リーダー。`global_orders.battle_policy` → 戦略変換、敵リストからのターゲット選択
  - PartyManager / NpcManager の型参照を `PartyLeaderAI` → `PartyLeader` に更新
  - `_evaluate_combat_situation()` スタブを PartyLeader に追加（将来の戦況判断ルーチン用）
- ~~残作業: PartyLeaderPlayer は未接続~~ → 下記「PartyManager 統合リファクタリング」で完了

### PartyManager 統合リファクタリング（Step 3 完了）
- NpcManager / EnemyManager を廃止し PartyManager に統合
  - `party_type`（`"enemy"` / `"npc"` / `"player"`）で setup / _create_leader_ai を分岐
  - NpcManager の `_spawn_member()` → `_spawn_npc_member()` として移植
  - NpcManager の `set_enemy_list()` / `_apply_attack_preset_to_member()` を移植
  - EnemyManager（空の後方互換ラッパー）を削除
- hero_manager を `PartyManager`（party_type="player"）に変更
  - `_create_leader_ai()` が `PartyLeaderPlayer` を生成するようになった
  - `suppress_floor_navigation = true` の行を削除（PartyLeaderPlayer にはフロア遷移判断がないため不要）
- 全ファイルの型参照を `NpcManager` / `EnemyManager` → `PartyManager` に置き換え
  - 対象: game_map / vision_system / right_panel / dialogue_trigger / npc_dialogue_window / dialogue_window / debug_window / base_ai / enemy_ai（計10ファイル）

### バグ修正: freed オブジェクトへの as Object キャストクラッシュ
- 原因: `is_instance_valid(mv as Object)` の `as Object` キャストが freed オブジェクトに対してクラッシュする
- 修正: `as Object` を削除（`is_instance_valid()` は Variant を直接受け付ける）。npc_leader_ai / debug_window / left_panel / unit_ai の全6箇所を修正

### バグ修正: party_leader.gd.uid 未登録によるクラス解決エラー
- 症状: `_evaluate_party_strength()` not found in base self（npc_leader_ai.gd:104）
- 原因: Godot 4.6 の `.gd.uid` ファイルが Git にコミットされておらず、PartyLeader クラスのリソース解決が不安定になっていた
- 修正: 未登録の `.gd.uid` ファイル（party_leader / party_leader_player / debug_window / enemy_leader_ai）をコミット。削除済みの default_leader_ai.gd.uid を反映

### 設計変更: 状態ラベル（condition）の統一と戦況判断システム実装
- 理由: 敵のHP推定・戦力比較を情報制限に準拠した方法で行うため
- 変更内容:
  - `Character.get_condition()` メソッドを追加（HP割合 → healthy/wounded/critical）
  - 旧 `_condition()` ローカル関数（4箇所コピペ・閾値不統一）を統一
  - `_evaluate_party_strength_for()` を追加（敵にも適用可能な戦力評価。状態ラベル経由でHP推定）
  - `_evaluate_combat_situation()` を実装（同エリア敵との戦力比較 → CombatSituation enum）
  - `_get_opposing_characters()` 仮想メソッドを追加（敵AI=friendly_list、味方AI=enemy_list）
  - 戦況結果を `receive_order()` の `combat_situation` フィールドで UnitAI に伝達
  - `GlobalConstants` に閾値定数・`CombatSituation` enum を追加

### 設計変更: NpcLeaderAI に戦況判断ベースの撤退ロジックを追加
- 理由: NPC パーティーに FLEE 判断がなく、圧倒的に不利な戦闘でも攻撃し続けていた
- 変更内容:
  - `_evaluate_party_strategy()` に `_combat_situation` の参照を追加
  - CombatSituation.CRITICAL（戦力比 < 0.5）で FLEE に切り替え
  - 撤退後に SAFE に戻ると EXPLORE に復帰し、目標フロアを再計算
  - UnitAI に `_combat_situation` フィールドを追加（receive_order 経由で保存）
  - EnemyLeaderAI には適用しない（種族固有 AI の既存 FLEE 判断を維持）

### バグ修正: item_pickup=passive でもアイテムを拾いに行かない
- 原因: アイテム取得ナビゲーションが `Strategy.WAIT` のときのみ有効だった。敵がいる部屋では `Strategy.ATTACK` になるため、敵全滅後もすぐに拾いに行けなかった
- 修正: 判定条件を `Strategy.WAIT` → `_is_combat_safe()`（戦況 SAFE = 同エリアに敵なし）に変更。戦闘終了後に即座にアイテム取得ナビが有効になる

### リファクタリング: UnitAI Strategy enum の廃止
- 理由: PartyLeader が global_orders を Strategy に中間変換して渡す方式が、仕様通りの行動を妨げていた
- 変更内容:
  - `_resolve_strategy()` 仮想メソッドを廃止。代わりに `_determine_effective_action()` が combat/on_low_hp/combat_situation から行動を直接決定
  - 種族フックメソッドを新設（`_should_ignore_flee()` / `_should_self_flee()` / `_can_attack()`）
  - `_assign_orders()` から `effective_strat` 算出ロジックを削除。`combat` / `on_low_hp` / `party_fleeing` をそのまま UnitAI に渡す
  - 種族 UnitAI サブクラス12ファイルの `_resolve_strategy()` をフックメソッドに移管

### バグ修正: 味方キャラ同士が重なる・味方を迂回できない問題
- 原因1: `_link_all_character_lists()` が現フロアの `npc_managers` / `enemy_managers` のみ走査していたため、フロア遷移後に旧フロアの NPC パーティーが `_all_members` から漏れ、UnitAI の `_is_passable()` で味方を認識できなかった
- 原因2: NPC/メンバーのフロア遷移時（`_transition_npc_floor` / `_transition_member_floor`）に `_link_all_character_lists()` が呼ばれず `_all_members` が更新されなかった
- 原因3: NPC 合流時（`_merge_npc_into_player_party` / `_merge_player_into_npc_party`）に `_link_all_character_lists()` が呼ばれず、新メンバーが占有チェック対象に含まれなかった
- 原因4: A* 経路探索の1歩目が味方タイルだった場合にフォールバックがなく、味方を迂回できなかった
- 修正:
  - `_link_all_character_lists()` を `_per_floor_enemies` / `_per_floor_npcs` 全フロア走査に変更
  - `_transition_npc_floor` / `_transition_member_floor` / `_merge_npc_into_player_party` / `_merge_player_into_npc_party` に `_link_all_character_lists()` 呼び出しを追加
  - `party.members` を `all_combatants` に含めるよう変更
  - A* の1歩目が `_is_passable` で false の場合に `_next_step_direct` にフォールバックして迂回

### バグ修正: item_pickup=passive でもアイテムを拾いに行かない（NPC パーティー）
- 原因1: `_start_ai()` で `set_floor_items()` が `setup()` より前に呼ばれていたため、`_unit_ais` が空で UnitAI にフロアアイテム辞書が届かなかった
- 原因2: `set_floor_items()` に空チェック（`is_empty()`）があり、セットアップ時に空の辞書を渡さなかった。Dictionary は参照型なので空でも渡しておけば後からアイテム追加時に反映される
- 原因3: 1マス移動完了ごとのアイテムチェックがなく、移動中にアイテムを見逃していた
- 原因4: アイテムチェックでキューを差し替えるたびに移動がリセットされ、同じアイテムに向かっている場合に無限ループしていた
- 修正:
  - `_start_ai()` で `set_floor_items()` を `setup()` の後に移動
  - `set_floor_items()` の空チェックを削除（常に渡す）
  - 1マス移動完了ごとにアイテムチェックを実行（SAFE 時のみ）
  - 既に同じアイテムに向かっている場合はキュー差し替えをスキップ

### 設計変更: 特殊攻撃のAI接続
- 理由: special_skill 指示がUI定義のみでAI未接続だった
- 変更内容:
  - `_evaluate_combat_situation()` の戻り値に `power_balance`（ランク和のみの戦力比）と `hp_status`（HP充足率）を追加
  - `_generate_special_attack_queue()` を UnitAI に追加。クラスごとの使用条件に基づいて特殊攻撃を発動
  - `_should_use_special_skill()` で special_skill 指示（aggressive / strong_enemy / disadvantage / never）と戦況を照合
  - ヒーラーの `_generate_buff_queue()` も `_should_use_special_skill()` を参照するよう統合
  - `receive_order()` に `special_skill` フィールドを追加
  - `current_order` のデフォルトに `special_skill: "strong_enemy"` を追加

### 設計変更: AI Vスロット攻撃の実行処理を追加
- 理由: `_generate_special_attack_queue()` がキューを生成しても、`v_attack` アクションの実行処理が UnitAI になかった
- 変更内容:
  - `_start_action` に `"v_attack"` ケースを追加
  - クラスごとの特殊攻撃実行メソッドを追加（_v_rush_slash / _v_whirlwind / _v_headshot / _v_flame_circle / _v_water_stun / _v_sliding）
  - 特殊攻撃の `take_damage` に `suppress_battle_msg=true` を追加（通常攻撃メッセージとの2重表示防止）
  - SP回復後に特殊攻撃が使われない問題を修正（`receive_order` の early return にVスロットコストチェックを追加）
  - キューに `v_attack` が含まれている場合はキュー再生成をスキップ（移動中のリセット防止）

### バグ修正: ヘッドショットの即死が防御・耐性で軽減されていた
- 原因: `take_damage(_target.hp)` で現在HPをダメージとして渡していたが、防御判定・耐性適用で軽減された
- 修正: `instant_death_immune=false` の場合は `take_damage` を経由せず直接 `hp=0` + `die()` で即座に倒す

### バグ修正: ポーション使用時にインベントリから削除されない（無限使用）
- 原因: `use_consumable()` が効果を適用するだけでインベントリからアイテムを削除していなかった
- 修正: `character_data.inventory.erase(item)` を追加

### バグ修正: HPポーションの効果キーが間違っていた
- 原因: `use_consumable()` が `heal_hp` を参照していたが、JSON定義は `restore_hp`
- 修正: `restore_hp` に変更

### 設計変更: メッセージ表記方針の策定
- バトルメッセージは自然言語で記述し、記号的表現（`HP+30` 等）を避ける
- アイテム名を統一: HP回復ポーション / MP回復ポーション / SP回復ポーション
- 上級ポーションは設けない方針

### 設計変更: 突進斬り・スライディングの修正
- 突進斬り: 敵のマスに着地していた → 敵を通過して次の空きマスに着地するよう修正
- スライディング: 敵をすり抜けできなかった → 敵・味方をスキップして空きマスに着地するよう修正

### 設計変更: エフェクト画像の統合
- `assets/images/projectiles/` を `assets/images/effects/` に統合
- StunEffect → WhirlpoolEffect にリネーム（画像: whirlpool.png）
- 炎陣エフェクトを画像ベースに変更（flame.png、スケール脈動＋アルファ揺らぎ）
- 左パネルのMP/SPバーに特殊攻撃不可時の紫色変化を追加

### 設計変更: 戦況判断を「リーダーのエリア＋隣接エリア」方式に変更
- 理由: 部屋単位のみで敵・味方を収集すると、部屋境界付近で戦況がフレーム単位でぶれる
- 変更内容:
  - ダンジョンJSONの各 corridor に `id` フィールド（`c{フロア番号}_{連番}`）を追加
  - `DungeonBuilder._carve_corridor()` が corridor の JSON `id` をタイルの area_id に設定（未指定時は従来形式 `corridor_{from}_{to}` にフォールバック）
  - `PartyLeader._evaluate_combat_situation()` が `MapData.get_adjacent_areas()` を使ってリーダーのエリア＋隣接エリアを対象にキャラクターを収集
  - 自軍側も同じ対象エリアに絞ってランク和・戦力・HP充足率を算出
- 通路は従来どおり敵・階段配置なし。area_id を持つのみ
- 視界システム（VisionSystem）は変更なし。敵アクティブ化は部屋単位のまま

### 設計変更: 戦況判断に同陣営他パーティーの戦力を加算
- 理由: 自パーティー単独の戦力比で判定していたため、同エリアに友好パーティーがいても考慮されず、合流前のNPCパーティー等が不当に劣勢判定されて特殊攻撃を発動していた
- 変更内容: `PartyLeader._evaluate_combat_situation()` が `_all_members` から同陣営の他パーティー（同 `is_friendly`）のエリア内生存メンバーを収集し、ランク和・戦力値に加算するよう変更
- HpStatus は従来どおり自パーティーのみで計算（他パーティーのポーション所持を把握できないため）
- 敵パーティー同士でも同じルールが適用され、敵の密集エリアでは強気になる

### 設計変更: ヒーラー回復閾値の追加と各種閾値の定数化
- 理由: `lowest_hp_first` モードが閾値1.0（満タン以外全員）で動作しており、微量ダメージでもMP浪費していた
- 変更内容:
  - `GlobalConstants.HEALER_HEAL_THRESHOLD = 0.5` を追加。`lowest_hp_first` / `leader_first`（リーダー判定）の閾値に使用
  - `lowest_hp_first` を「HP率 < 0.5 のうち最もHP率が低い1人」に変更
  - `leader_first` のリーダー判定閾値を `NEAR_DEATH_THRESHOLD (0.25)` から `HEALER_HEAL_THRESHOLD (0.5)` に変更
  - ハードコードされていた閾値を定数化:
    - `SELF_FLEE_HP_THRESHOLD = 0.3`（goblin系 `_should_self_flee`）
    - `POTION_SP_MP_AUTOUSE_THRESHOLD = 0.5`（SP/MPポーション自動使用）
    - `PARTY_FLEE_ALIVE_RATIO = 0.5`（goblin/wolf リーダーの FLEE 判定）
- CLAUDE.md に「ゲーム内閾値一覧」セクションを新設し、HP系/MP/SP系/パーティー系/戦況系/ヒーラー回復モードの全閾値を表で記載

### 設計変更: 近接クラス特殊攻撃の発動状況判定を追加
- 理由: 剣士・斧戦士・斥候の特殊攻撃は囲まれた状況で効果を発揮するが、敵1体相手でも発動して無駄遣いしていた
- 変更内容:
  - `GlobalConstants.SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES = 2` を追加
  - `_count_adjacent_enemies()` を4方向→8方向に拡張（斜め隣接も含む）
  - `_can_rush_slash_through()` ヘルパを新設（前方2マス内に敵+着地マス確認）
  - `_generate_special_attack_queue()` のクラス分岐を更新:
    - fighter-sword: 隣接2体以上 かつ 前方に敵+着地可能マス
    - fighter-axe: 隣接2体以上（既存ロジックを定数化）
    - scout: 隣接2体以上（包囲脱出兼ダメージ）
  - archer / magician-* / healer は変更なし（従来通り）

### 設計変更: フロア間メンバー追従ロジックを UnitAI に移動
- 理由: PartyLeader._assign_orders 内のクロスフロア追従が move_policy を直接 stairs_down/up に上書きしており、他の上書きと混在して挙動が追いづらかった。NPC リーダーが階段を降りてもメンバーが付いてこないバグの原因切り分けも難しかった
- 変更内容:
  - `party_leader.gd:_assign_orders()` のクロスフロア追従ブロック（move_policy を stairs_down/up に書き換える処理）を削除
  - `unit_ai.gd:_generate_move_queue()` 冒頭で「move_policy が cluster/follow/same_room かつリーダーが別フロア」を判定し、`_generate_stair_queue(dir, ignore_visited=true)` を返す
  - `_generate_stair_queue` に `ignore_visited` パラメータを追加。フロア間追従時はリーダーが既に使った階段なので未踏でも候補にする
- 影響範囲: 個別指示の cluster/follow/same_room を選んだ NPC メンバーが、リーダー降下後に必ず追従するようになる。他の移動方針（standby/explore/guard_room）はフロア間追従の対象外（自律行動を維持）

### バグ修正: ヒーラーAIが非アンデッド敵にダメージを与えていた
- 症状: ヒーラー（attack_type="heal"）が回復対象もアンデッド敵もないとき、ATTACK 戦略で `attack` アクションを生成 → `_execute_attack` の match に "heal" ケースなく default(melee) に落ち、非アンデッドにダメージを与えていた
- 修正:
  - `unit_ai.gd:_generate_queue` ATTACK分岐: `atype == "heal"` かつターゲット非アンデッドなら `_generate_move_queue()` にフォールバック
  - `unit_ai.gd:_execute_attack` 冒頭: `atype == "heal"` でターゲット非アンデッドなら return（防御的二重チェック）

### バグ修正: NPCデバッグ表示 戦力(0/0)・enemy_list 初期転送漏れ
- 症状: DebugWindow で NPC パーティーの戦力が常に「○○(0/0)」と表示
- 原因①: `NpcLeaderAI.get_global_orders_hint()` が PartyLeader のオーバーライドだが、my_rank_sum / enemy_rank_sum を hint に追加していなかった
- 原因②: `PartyManager._start_ai()` が AI 起動時に `_enemy_list` を leader_ai に転送しておらず、起動前に set_enemy_list された分が反映されていなかった
- 修正: 両方とも転送するよう追加

### バグ修正: NPCリーダー降下後の追従遅延・FLEE阻害
- 症状: NPCリーダーが階段を降りても、cluster 指示の非リーダーメンバーが付いてこない
- 原因① (遅延): 敵がいない時はメンバーが3秒の wait アクション中で再評価されず、リーダーのフロア変化を検知できなかった
- 原因② (阻害): リーダーが下フロアに単独で降りると戦況評価が「リーダー1人 vs F1の敵集団」になり PowerBalance 劣勢→ Strategy.FLEE。非リーダーは party_fleeing=true → ATTACK/FLEE/WAIT 分岐の中で `[wait]` を返して固定
- 修正:
  - `party_leader.gd:_process` でリーダーの current_floor 変化を毎フレーム検知 → 全 UnitAI に `notify_situation_changed()`
  - `unit_ai.gd:notify_situation_changed` が WAIT 中なら IDLE に戻してキューを破棄
  - `unit_ai.gd:_generate_queue` 冒頭にクロスフロア追従判定を移動（FLEE/WAIT/ATTACK 何の戦略でも cluster/follow/same_room メンバーは階段優先）
  - `_step_toward_goal` の友好キャラ押し出しもクロスフロア追従時に有効化

### 設計変更: メッセージウィンドウのアイコン縮小と各種改善
- アイコン縮小（試験的）:
  - `ICON_SCALE_RATIO = 1.0/3.0`（旧 2.0/3.0 の半分）
  - `ICON_MIN_SIZE = 20` / `LINE_HEIGHT_RATIO = 1.25`（旧 1.5）
  - 元に戻す場合は `ICON_SCALE_RATIO = 2.0/3.0` / `LINE_HEIGHT_RATIO = 1.5`
- バトル行高さ計算修正: `box_h` を `line_h * VISIBLE_LINES` から `max(line_h, icon_sz+4) * VISIBLE_LINES` に変更（最上段が見切れる問題）
- 対象なしバトルメッセージ（ポーション・スライディング等）で右側アイコン・矢印を非表示
- 突進斬り/振り回しを敵ごとに「○○が突進斬りで△△を攻撃し、大ダメージを与えた」形式で per-target 表示。プレイヤー側 `_execute_rush`/`_execute_whirlwind` で `add_combat`→`add_battle` に変更し、`take_damage` に `suppress_battle_msg=true` を渡す

### DebugWindow 機能拡張
- 各メンバーの行動目的を3行目に表示（`UnitAI.get_debug_goal_str()` に集約）
  - 例: `→DOWN階段(15,3)` / `→攻撃Goblin` / `L追従(DOWN/キュー空/WAIT)` / `[cluster]キュー空(IDLE)`
  - 末尾に `_state` ラベル（IDLE/MOV/WAIT/ATKp/ATKpost）併記
- パーティー表示順を プレイヤー → NPC → 敵 に変更（行数不足時に重要情報を優先）
- パーティーブロック間の 2px 空白を撤去
- 別フロアにいるメンバーも全員表示（名前頭に `[Fx]` 注釈）。表示条件は「いずれか1人が表示フロアにいること」

## ダンジョン再構成（5フロア×20部屋）

### 設計変更: CLAUDE.md NPC加入形態を1種類に統一
- 理由: 実装上も「プレイヤーがリーダーのまま相手パーティーを引き入れる」1種類のみ（相手パーティーに自分が加わる形態は未実装かつ仕様としても維持不要）
- 変更内容: CLAUDE.md NPC仕様セクションの記述を「加入形態：プレイヤーがリーダーのまま、相手パーティーを丸ごと引き入れる（1種類のみ）」に修正

### 設計変更: ダンジョン構成を12部屋→20部屋に拡張・上り階段部屋は敵初期配置なし
- 理由: プレイヤーの探索感と戦闘密度を上げるため。特に上り階段部屋は遷移直後の安全地帯として機能させたい
- 変更内容:
  - 各フロア 4列 × 5行 = 20部屋の格子レイアウトに変更
  - 階段 3か所（上り・下り）。上り階段部屋は敵初期配置なし（追跡してきた敵は入れる）
  - フロア0：主人公1人 + NPC 8パーティー（1人×5+2人×2+3人×1=12人）+ 敵11部屋（下り階段3部屋含む）
  - フロア1-3：上り階段3部屋（敵なし）+ 敵17部屋（下り階段3部屋含む）
  - フロア4：上り階段3部屋（敵なし）+ 敵17部屋（r5_18にボス dark_lord + 取り巻き4体）
- 生成方式: `work/gen_dungeon.py`（Python）で JSON を直接出力。乱数シード固定（20260415）で再現性確保
- 非矩形部屋パターン: 占有マス（敵/NPC/プレイヤー/階段）と衝突しないパターン10種に絞り約25%の部屋に適用。入口・ボス部屋は適用外

### 設計変更: NPC構成を主人公1人スタート・12人に拡張
- 変更前: 初期パーティー4人（主人公+仲間3人）でスタート、フロア0に未加入NPC 11人
- 変更後: 主人公1人のみでスタート、フロア0に未加入NPC 12人（1人×5+2人×2+3人×1=8パーティー）
- 理由: 序盤の「仲間集め」を強調した設計に統一

## UI・操作感の改善

### 機能追加: 時間停止中の画面暗転オーバーレイ（瞬時切替）
- 目的: `world_time_running=false` の状態をプレイヤーに視覚的に知らせる
- 実装: `time_stop_overlay.gd`（CanvasLayer layer=5）にアンカー全画面の ColorRect（Color(0,0,0.05,0.35)）を配置し、`_process` で visible を切替
- フェードはせず瞬時切替
- `game_map.gd:_finish_setup()` から生成

### バグ修正: 階段上に静止していると反対側の階段に再遷移してしまう
- 症状: プレイヤーが階段を下りて遷移先の階段（反対側）の上に静止したまま 1.5秒の `_stair_cooldown` が切れると、`_check_stairs_step()` が反対側の階段タイルを検知して再遷移していた
- 原因: `_stair_cooldown` 切れ後に `stair_just_transitioned` をチェックせず、階段タイルに静止しているだけで遷移条件が成立していた
- 修正: `game_map.gd:_check_stairs_step()` に `player_controller.stair_just_transitioned` をチェックするガードを追加。プレイヤーが階段タイルから一度外に出るまで再遷移を抑止

## 安全部屋システム

### 設計変更: フロア0中央に安全部屋を新設
- 変更前: フロア0は主人公1部屋 + NPC 8部屋（各部屋1パーティー） + 敵11部屋 = 20部屋
- 変更後: フロア0は安全部屋1つ（主人公+NPC全8パーティー集約） + 敵19部屋 = 20部屋
- 理由: 序盤の「仲間集め」体験を集中化。プレイヤーが1か所でパーティー状態を確認できる拠点を作る
- 実装:
  - `map_data.gd`: `_safe_tiles` 辞書・`mark_safe_tile`/`is_safe_tile`/`is_walkable_for_enemy` メソッドを追加
  - `dungeon_builder.gd`: 部屋JSONの `"is_safe_room": true` フラグを読み、内部FLOORタイルを `mark_safe_tile()` でマーク。`"npc_parties_multi"` 配列（1部屋に複数NPCパーティー）もサポート。入口部屋にもNPC配置を許可
  - `unit_ai.gd`: `_is_walkable_for_self(pos)` ヘルパで `_member.is_friendly == false` かつ `is_safe_tile(pos)` を拒否。A*経路探索・移動可否判定など約10箇所を置換
- 動作: 敵は安全部屋に隣接する通路まで侵入できるが、部屋内部のFLOORタイルはA*経路探索で除外されるため進入不可。追跡してきた敵が通路で立ち往生する形になる
- サイズ: 15×11（通常部屋 9×7 より大きい）・フロア中央のグリッド (col=1, row=2) に配置・上下左右4部屋と通路接続

## 撤退先ロジックの変更

### 機能追加: 味方パーティーの撤退先を明確化
- 変更前: `Strategy.FLEE` になると味方・敵ともに `_find_flee_goal(threat)` で脅威の反対方向へ5マス逃げるだけ（目的地が不明確で撤退判定が曖昧）
- 変更後:
  - 味方（`_member.is_friendly == true`）：
    - フロア0：最寄りの安全タイル（安全部屋 r1_10 の内部）を目指す
    - フロア1以降：最寄りの上り階段（`STAIRS_UP`）を目指す
  - 敵：従来通り（脅威反対方向 + 縄張り帰還）
- 理由: 安全部屋実装に合わせて味方の撤退先を「安全な拠点」に統一。上り階段は安全部屋に通じる経路にもなるため、フロアを跨いで安全部屋に逃げ帰るフローが自然に成立
- 実装:
  - `map_data.gd`: `get_safe_tiles() -> Array[Vector2i]` を追加
  - `unit_ai.gd`:
    - `_find_friendly_retreat_goal() -> Vector2i` を新設（安全タイル優先・なければ最寄り上り階段）
    - FLEE 分岐（`_generate_queue` strategy==1）で味方は `move_to_explore` に撤退先 goal を積む
- 復帰: 撤退先に到達後はキュー再生成のたびに戦況が再評価される。安全部屋に入ると `CombatSituation.SAFE` になり通常行動（ATTACK / EXPLORE）に戻る

## 今セッションのバグ修正・UI調整まとめ

### バグ修正
- **HPポーションが使えない**: `_use_item_from_ui` が effect キーを `heal_hp` で読んでいたが実データは `restore_hp`。`restore_hp` に修正（player_controller.gd）
- **ポーション使用で2個減る**: `use_consumable()` 内部の `inventory.erase(item)` と `_use_item_from_ui` の追加削除ループが重複。追加削除ループを削除（player_controller.gd）
- **水魔導士の弾が赤い**: `_spawn_projectile` が `is_water` 引数を渡さず `fire_bullet.png` にフォールバック。`class_id == "magician-water"` で `is_water=true` を設定（player_controller.gd）
- **初期ポーション数が1表示になる**: ConsumableBar はエントリ数で `×n` を表示、`use_consumable` は辞書 erase するため `quantity:5` のエントリ1つでは ×1 にしかならず使用1回で消える。5個の独立エントリに変更（work/gen_dungeon.py, game_map.gd）
- **プレイヤーキャラだけ初期ポーションなし**: `_dbg_items` で装備上書きされポーションが捨てられていた。クラス確定後に HP×5 + SP/MP×5 を追加（game_map.gd）
- **フォーカス不一致**: ITEM_SELECT 開始時に通常バーの `selected_consumable_index` と同じ item_type を探して `_last_item_index` を合わせる。カーソル移動時も逆方向に同期（player_controller.gd）
- **階段上で再遷移バグ**: 遷移後の階段タイルに留まると 1.5秒後に反対側の階段へ再遷移。`stair_just_transitioned` チェックを `_check_stairs_step()` に追加（game_map.gd）
- **ブロック時に時間停止**: 壁や味方に塞がれると `_try_move` が何もせず `is_moving()=false` で時間停止。`Character.walk_in_place()` 新設し、入力継続中は足踏みアニメを再生して時間を流す（character.gd, player_controller.gd）
- **DebugWindow 表示順と選択順の不一致**: `_build_leader_list` を描画順（プレイヤー→NPC→敵）に統一、`_get_any_leader` を `is_leader` 優先に変更（debug_window.gd）

### UI・メッセージ調整
- **時間停止オーバーレイ**: `Color(0,0,0.05,0.35)` の半透明レイヤーを `layer=5` に追加。切替時は 0.1秒の Tween でフェード（time_stop_overlay.gd 新設）
- **NPCリング非表示**: 未接触NPCパーティーは `party_ring_visible=false` でリング非表示。会話時に `mark_contacted()` で全員点灯（character.gd, party_manager.gd, game_map.gd）
- **DebugWindow 1行化**: ヘッダーとメンバー一覧を同一行に描画、移動ログ行を削除（debug_window.gd）
- **DebugWindow にメンバー目的を復活**: 各メンバー末尾に `get_member_goal_str()` の結果を薄シアンで付記（debug_window.gd）
- **キャンセル時のメッセージ抑止**: 「誘いを断った」はNPC起点時のみ。プレイヤー起点キャンセルは「○○のパーティーに話しかけた」に切替（game_map.gd）
- **勧誘メッセージ**: 「仲間にする」選択時のみ「○○のパーティーに話しかけ、仲間にならないかと誘った」を表示（game_map.gd）
- **NPC起点会話の削除**: `wants_to_initiate()=false` で実質無効化済みの分岐を整理（game_map.gd）
- **NPC に話しかける向き判定**: `_find_adjacent_npc` を隣接4方向 → 正面1マスに変更（player_controller.gd）
- **勧誘理由メッセージ**: `will_accept_with_reason` で主要因 reason を返し、承諾・拒否に応じた台詞メッセージを「」形式で表示（npc_leader_ai.gd, game_map.gd）

### アイテムUI統合
- 従来の ACTION_SELECT / TRANSFER_SELECT のポップアップを廃止し、ITEM_SELECT と同じアイコン列＋右側詳細パネル方式に統合
- 数量表示を `×n` の横並びからアイコン右下コーナーのオーバーレイ（影付き）に変更
- 使用/装備不可アイテムをグレーアウト
- 装備時の補正差分を「威力 3→11 (+8)」形式で表示
- 「渡して装備させる」アクションを追加
- 「渡す」「渡して装備させる」の可視条件から「リーダー限定」「他メンバー存在」を撤廃（非リーダー操作時でも譲渡可能。渡し先0人時は「渡せる相手がいない」ログ表示で ACTION_SELECT に留まる）

### ヒーラー支援行動
- 回復・バフの対象に **自分自身** を含める
- 友軍対象時は方向制限撤廃（360°）。アンデッド特効は通常攻撃扱いで前方コーン制限を維持
