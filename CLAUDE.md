# プロジェクト概要
半リアルタイムタクティクスRPG
ゲームタイトル：Rally the Parties

## セッション開始時のガイド

新しいセッションを開始する際、まず以下を確認すると全体像を迅速に把握できます。

### 現在のフェーズ
- Phase 13（パーティーシステム刷新）完了
- Phase 14（Steam 配布準備）未着手
- 現状は「リファクタリング・定数整理・設計明示化・legacy 一掃」の段階（2026-04-22 時点）
- 直近の実プレイ検証で即死問題がほぼ解消し、FLEE システムが活かされる耐久性を確保

### 最近の大きな変更

#### 2026-04-24（本日の成果：fall_back 個体アクションの二段階協調実装）

CLAUDE.md「FLEE 派生課題 4 個体アクションの実行ロジック差別化」のうち **`fall_back` 部分**を完了。FLEE と対称な「リーダー推奨 + メンバー採用」の二段階協調構造に統一した。

1. **リーダー層 `_determine_fallback_recommended_goal()` 新設**（[party_leader.gd](scripts/party_leader.gd)）
   - 味方パーティー限定。敵・パーティー FLEE 中は Vector2i(-1, -1) を返して配布しない（FLEE 優先）
   - リーダー位置中心・マンハッタン半径 `FALL_BACK_SEARCH_RADIUS`（既定 6）の歩行可能タイルを候補集合として列挙
   - 各候補の合成コスト = 脅威コスト付き A* 経路コスト（リーダー UnitAI の `_astar_with_cost` + `_calc_threat_cost` 流用）+ リーダー距離 × `FALL_BACK_LEADER_DISTANCE_WEIGHT` + 味方重心距離 × `FALL_BACK_ALLY_CENTROID_WEIGHT`
   - 味方重心は `_calc_ally_centroid()`（自パ生存メンバー grid_pos 平均）
   - 敵不在（`combat_situation.nearby_enemy_rank_sum == 0`）時は配布不要・Vector2i(-1, -1) で早期 return
   - 更新タイミング：`PartyLeader._process()` の `REEVAL_INTERVAL = 1.5s` 周期のみ（2026-04-24 夕の修正）

2. **UnitAI 層 `_find_fall_back_goal()` 新設**（[unit_ai.gd](scripts/unit_ai.gd)）
   - 味方メンバー：リーダーが配布した `_formation_fallback_goal` をそのまま採用（FLEE のような脅威コスト再評価はしない・同エリア内の近距離目標なので軽量）
   - 敵メンバー：legacy 直線後退（`_find_flee_goal_legacy`）を継続
   - 推奨なし（未配布 / リーダー計算失敗）時も legacy にフォールバック

3. **アクション分岐の差別化**
   - `_start_action` / `_step_toward_goal` の `"flee" / "fall_back" / "keep_distance"` 共有分岐を分離
   - `fall_back` → `_find_fall_back_goal()`、残り 2 つ → 従来の `_find_flee_goal()`
   - `keep_distance` は現状維持（ゴブリンアーチャーの挙動良好のため触らない）

4. **`formation_fallback_goal` キー新設**（receive_order 辞書）
   - 将来 `keep_distance` でも流用できるように一般化命名（fall_back 専用ではない）

5. **GlobalConstants UnitAI カテゴリに定数追加**（Config Editor 編集可能）
   - 当初：`FALL_BACK_SEARCH_RADIUS` (6) / `FALL_BACK_LEADER_DISTANCE_WEIGHT` (1.0) / `FALL_BACK_ALLY_CENTROID_WEIGHT` (0.5) / `FALL_BACK_REEVAL_MIN_INTERVAL` (0.3)
   - 最終（2026-04-24 深夜・FLEE 再利用方式へ刷新後）：`FALL_BACK_MARGIN` (2) のみ残存。他は全廃

6. **PartyStatusWindow に `fb→(x,y)` 表示追加**
   - 詳細度「低」・味方メンバーのみ・`flee→(x,y)` と並んで表示
   - `VAR_PRIORITY` に `formation_fallback_goal: 2` 追加

**設計原則**：「パーティー戦略はリーダー個人の属性ではない」「受信キーは receive_order 経由で統一」「敵ステータス直接参照禁止」を踏襲。FLEE とほぼ同じ構造・計算ロジックで、候補集合（出口 vs リーダー周辺）とコスト式（エリア距離 vs 味方重心距離）だけを置き換える形で実装。

**スコープ外**（将来タスク）:
- 敵パーティーへの適用（FLEE 派生課題 1 と合流予定）
- 「後衛が前に進む問題」の解決（味方クラスへの `keep_distance` 適用＝派生課題 3）
- `keep_distance` / `flee` の追加差別化

**2026-04-24 夕方の修正：fall_back 更新頻度の見直し（頻度だけ削減・結局不十分だった）**

当初、`on_member_area_changed` の fall_back 再評価ブランチを削除して頻度を抑えたが、その後の静的再分析（下記 2026-04-24 深夜）で**単発コスト自体が ~560ms**と判明。最終的に設計刷新（下記）で全廃した。

**2026-04-24 深夜の修正：fall_back を FLEE 計算結果の再利用方式に刷新（パフォーマンス根治）**

単発の候補タイル × A* 方式が実機で 1 秒フリーズを引き起こしていたため、設計を抜本的に変更した。

**Step A 静的分析で判明した主因**：
- `_determine_fallback_recommended_goal()` は 70 候補 × `_astar_with_cost` を回す
- A* 内で `_calc_threat_cost` が毎ノード展開呼ばれ、`_all_members`（全フロア合計 150 体）を線形反復
- 合計 `~3,400 回の _calc_threat_cost 呼び出し / フレーム` × GDScript Callable dispatch のコスト
- 推定単発コスト **560ms〜1秒**（前回見積もり 1〜5ms は 100 倍過小評価）

**設計転換：FLEE の計算結果を再利用**

Step 1 の FLEE 実装調査で判明した本質（FLEE は「毎ステップ現エリアの最善出口を局所最適で選ぶ」連鎖動作）を踏まえ、fall_back は「FLEE の途中停止バージョン」として再設計した。

- **リーダー層**：`_update_flee_recommended_goal()` のガードを緩和し、敵検知中の味方パーティーでは FLEE 中でなくても常時計算。`_determine_flee_recommended_goal()` 自体は無変更（計算結果は従来と同一）
- **配布キー**：既存の `flee_recommended_goal` をそのまま共用（意味拡張：「撤退方向の推奨出口」）
- **メンバー層**：`_find_fall_back_goal()` を射程外判定のラッパーに変更
  - `_is_far_enough_from_threats()` で「最近の脅威との距離 ≥ `attack_range + FALL_BACK_MARGIN`」判定
  - 射程外なら現在位置を返して停止
  - そうでなければ `_find_flee_goal()` に委譲（FLEE と同じ出口評価）
- **停止判定**：`_generate_queue(FALL_BACK)` 冒頭でも `_is_far_enough_from_threats()` 判定 → true なら `[{wait}]`（FLEE の `_is_in_refuge_area()` と対称）
- **エリア変化再評価**：FLEE 中ガードを外し、敵検知中の味方パーティーでも効くように戻す。推奨出口は 2〜6 出口 × A* の軽量計算（~数ms）なので許容範囲

**削除したもの**:
- 定数 3 個：`FALL_BACK_SEARCH_RADIUS` / `FALL_BACK_LEADER_DISTANCE_WEIGHT` / `FALL_BACK_ALLY_CENTROID_WEIGHT`
- PartyLeader 関数 3 個：`_determine_fallback_recommended_goal()` / `_calc_ally_centroid()` / `_update_fallback_recommended_goal()`
- PartyLeader state: `_fallback_recommended_goal`
- UnitAI state: `_formation_fallback_goal`
- receive_order キー: `formation_fallback_goal`
- PartyStatusWindow `VAR_PRIORITY["formation_fallback_goal"]`

**追加したもの**:
- `FALL_BACK_MARGIN = 2`（1 定数のみ）
- `UnitAI._is_far_enough_from_threats()`（停止判定）

**表示**:
- `fb→(x,y)` は `_flee_recommended_goal` を参照し、現在実行中アクションが `fall_back` のときはラベルを `fb` に切り替える（FLEE 実行中は従来どおり `flee→(x,y)`）

**理論効果**: 1 パーティー単発 ~560ms → ~数ms（FLEE と同等）。100 倍以上の高速化。Komuro 実機確認でフリーズ解消を確認する。

**2026-04-24 深夜の追加修正：脅威マップ事前計算による FLEE/fall_back 推奨出口計算の高速化**

fall_back FLEE 再利用方式の実装後、計測ログ（`[EXIT_PERF]`）から単発コストが **25〜76 ms（中央値 50 ms）** と判明。1.5 秒周期に 8〜9 パーティーが時間差発火し、合計 130〜210 ms のカクつきが残存していた。

**主因**：`_calc_threat_cost` を A* の内ループで毎回呼ぶ設計。1 回の出口評価で A* が 50〜100 ノード展開し、各ノード × 4 近傍で `_all_members` 150 体を線形反復 → **18〜24 万回のキャラ評価**が発生。

**対策**：`_determine_flee_recommended_goal()` の先頭で脅威コストマップ（`Dictionary: Vector2i → float`）を 1 回だけ構築。A* の `cost_fn` はマップを辞書参照するだけにする。

- 新設：`_build_threat_map(for_member)` 関数（[party_leader.gd](scripts/party_leader.gd)）
  - 各敵について「範囲内タイルに貢献を加算」する逆方向構築（`_calc_threat_cost` のループを転置）
  - 計算量：150 体 × 影響範囲 ~41 タイル = 6,150 ops（~2 ms）
  - `_calc_threat_cost` と**数値結果完全一致**（加算順序の入れ替えのみ・数学的等価性を関数 doc で証明）
- `_determine_flee_recommended_goal()` 内の `threat_fn` をマップ参照ラムダに差し替え：
  ```gdscript
  var threat_map: Dictionary = _build_threat_map(leader_char)
  var threat_fn: Callable = func(tile): return threat_map.get(tile, 0.0)
  ```
- `_astar_with_cost` / `_path_cost` は無変更（cost_fn を受け取る汎用関数のまま）
- `_calc_threat_cost` も無変更（他からの呼び出し可能性に備え残置）

**理論効果**:
- A* 内の cost_fn 呼び出し：~225 μs/回 × 1,600 回 = **~360 ms** → ~1 μs/回 × 1,600 回 = **~1.6 ms**
- `_determine_flee_recommended_goal` 単発：**50 ms → 5〜10 ms**（40〜80 倍高速化）
- 1.5 秒周期のピーク負荷：210 ms → 20 ms 以下に収まる見込み
- FLEE にも自動適用（共通関数）

**Komuro 実機確認**：ディレイ解消を `[EXIT_PERF]` ログで確認する。効果確認後、計測コードは別コミットで削除予定。

**2026-04-24 深夜の追加修正：合流 NPC の追従バグ修正**

fall_back 動作確認中、Komuro が「合流済み NPC がプレイヤーから離れていく」問題を発見。調査の結果、2026-04-23 のポーション修正（commit `798d3cc` で `_assign_orders` を `_build_orders_part()` 経由に統一）の副作用と判明。

- 原因：[NpcLeaderAI._build_orders_part()](scripts/npc_leader_ai.gd) が `_is_in_explore_mode()` 時に `move = "explore"` を上書きする処理が、合流済み NPC パーティーにも効いていた。加入時 `nm.set_joined_to_player(true)` されるが、この explore 上書きには `joined_to_player` ガードが無かった
- 修正：explore 上書き分岐に `not joined_to_player` ガード追加（1 行）
- 効果：合流済み NPC がプレイヤーの `global_orders` の move_policy（follow 等）に従うようになり、追従が回復
- 無回帰：未加入 NPC（joined_to_player=false）は従来通り explore で動く

**2026-04-24 深夜の追加修正：パーティー加入処理の完全化（Step 1+2）**

仲間システム調査で判明した「二重表示問題」の根本対応。`_merge_npc_into_player_party` が加入先にメンバーを追加するだけで、加入元 NpcManager から除去していなかった問題を解消した。

- **PartyLeader 基底に動的 API 新設**（[party_leader.gd](scripts/party_leader.gd)）：
  - `adopt_member(member, unit_ai)`：外部から受け取ったメンバーと UnitAI を自パーティーに組み入れる・UnitAI を self の子ノードに reparent・walker コンテキストを再設定・全 UnitAI の peers を再配布
  - `release_member(member) -> UnitAI`：自パーティーから切り離して UnitAI を返す・呼出側が adopt に渡す
- **PartyManager に薄いラッパー追加**（[party_manager.gd](scripts/party_manager.gd)）：
  - `release_member` で `Character.died` シグナル切断・`adopt_member` で新 manager 側に再接続（idempotent な `is_connected` ガード付き）
- **`_merge_npc_into_player_party` を新 API で改修**（[game_map.gd](scripts/game_map.gd)）：
  - 各メンバーを `nm.release_member` → `_hero_manager.adopt_member` で完全移管
  - 既存 UnitAI を reparent で流用（`_queue` / `_state` / `_flee_recommended_goal` 等の状態を保持）
  - nm を `_per_floor_npcs` から erase・`queue_free` で解体
  - `_find_floor_of_nm` ヘルパ新設
- **副次効果**：
  - PartyStatusWindow の二重表示が解消（NPC セクションから消え・プレイヤーセクションのみに表示）
  - 加入メンバーが `_hero_manager.get_unit_ai()` で正しく取得できる → アクション / move / 指示すべて表示
  - AI 管理主体が一本化され、`set_global_orders` / `set_party_ref` / `set_floor_items` 等の重複配布が不要に
- **UnitAI 移管方式**：案 a（既存流用）を採用。状態保持・変更範囲最小・味方側サブクラス不整合の心配なし

**2026-04-24 深夜の追加修正：`_member_to_npc_manager` 除去クリーンアップ（Step 3）**

Step 1+2 で残置された `_member_to_npc_manager` 参照を整理。Step 2 で AI 管理主体が `_hero_manager` に一本化されたことで、このマップの存在意義がなくなっていた。

**実施のきっかけ**：Step 1+2 適用後の実機動作確認で `_link_all_character_lists` に `Trying to cast a freed object` クラッシュが発生。原因は `_member_to_npc_manager` に `queue_free()` 済み nm 参照が残り、`as PartyManager` キャストで失敗したため。当初は別コミット予定だったが、Step 2 単体では挙動上の問題（map_data 未更新 / freed cast）が残るため Step 3 を前倒しで一体実施。

**実施内容**:
- `PartyLeader.set_member_map_data(member_name, map_data)` は既存（Step 3 新設は不要だった。基底に既に定義済み）
- `_transition_member_floor` の `_member_to_npc_manager.get(ch)` を `_hero_manager.set_member_map_data(ch, new_map)` に置換（加入メンバーも `_hero_manager` 管理下なので正しい経路）
- `_link_all_character_lists` の joined_nms ループを削除（freed cast の発生箇所・Step 2 で nm が解体されるため不要）
- `_merge_npc_into_player_party` の `_member_to_npc_manager[member] = nm` 代入を削除
- `_member_to_npc_manager` Dictionary 定義を削除

**効果**：仲間システムの管理主体が `_hero_manager` に完全一本化。freed 参照蓄積が原理的に発生しない状態に。

**学び**：GDScript 4.x の `as` キャストは freed object に対してエラーを投げる（`is_instance_valid` は cast 後でないと効かない）。Dictionary に Node 参照を保持する場合は、所有者解体時に必ず辞書もクリーンアップする必要がある。

### 次タスク

- **fall_back 動作確認**：仲間システム問題で中断していた本来のタスクに戻る
  - `on_low_hp = fall_back` のメンバーが critical 状態で推奨出口方向に下がる挙動を観察
  - 射程外（`attack_range + FALL_BACK_MARGIN`）で停止することを確認
  - PartyStatusWindow の `fb→(x,y)` 表示が正しいこと
  - 必要に応じて `FALL_BACK_MARGIN`（既定 2）の調整
- **FLEE 派生課題 4 のクローズ**：fall_back 完了後、残る `keep_distance` / 後衛前進問題へ

#### 2026-04-23（TARGETING 時間停止リーク修正 + デバッグログ検出機構整備 + 回転 Tween ガード + 同フレーム race 修正 + 解放後の新規敵攻撃抑止 + 射程オーバーレイ追従 + 移動中攻撃 PRE_DELAY 並行消化 + PartyStatusWindow デバッグ表示拡充 + NPC ポーション自動使用修正 + 状態ラベル閾値リネーム + ポーション INJURED 発動拡張 + ヒーラー回復モード 4 モード再設計）

0-4. **移動中攻撃入力時の PRE_DELAY 並行消化を明示的に仕様化**（設計原則の明文化 + 実装整理）
   - 背景：移動中（`is_moving() == true`）に攻撃ボタンを押下した際の挙動が明示的に設計されていなかった。Komuro の当初想定は「PRE_DELAY タイマーは移動中から並行消化、TARGETING 突入時はマス中央に静止」だったが、コードは「PRE_DELAY は並行進行・TARGETING 突入は視覚補間と無関係」で片手落ち状態
   - 設計原則（本日明文化）：(1) PRE_DELAY タイマーは移動中から並行消化 (2) TARGETING 突入は「タイマー完了 AND 視覚補間完了」の両方を要件とする (3) `abort_move()` による視覚中断は呼ばず、自然完了を待つ
   - 実装変更：
     - [_process_pre_delay()](scripts/player_controller.gd:533) の TARGETING 突入条件に `and not character.is_moving()` を追加
     - [_process_pre_delay_released()](scripts/player_controller.gd:565) の Phase 2 突入条件に同じガードを追加・Phase 判定を `_cursor != null` で明示
     - [_process_guard_and_move()](scripts/player_controller.gd:470) の dead code だった `_attack_buffer = true` 設定を削除（攻撃入力は line 450 の `_enter_pre_delay()` で先に捕捉済み）
   - 効果：TARGETING 突入時に必ずキャラがマス中央・マーカー表示時は世界が完全静止という設計原則が守られる。既存の pre_delay < 移動時間のクラスでも、視覚補間完了を待って TARGETING に入る

0-3. **移動中に攻撃した際、射程オーバーレイが PRE_DELAY 中にキャラ位置に追従しない問題を修正**
   - 症状：プレイヤーが視覚補間中（`_visual_duration > 0`）に攻撃ボタンを押すと、PRE_DELAY 中に `grid_pos` が次マスにコミットしても射程オーバーレイが古い位置に残る
   - 原因：[game_map.gd:_process()](scripts/game_map.gd:196) の redraw トリガーが「`is_in_attack_windup()` の状態切替時のみ」で、windup 中の `grid_pos` 変化を捕捉していなかった
   - 修正：windup 中は毎フレーム `queue_redraw()` するように変更（PRE_DELAY / PRE_DELAY_RELEASED / TARGETING の短時間だけ・通常時は従来どおり切替時のみ）

0-2. **「アウトライン非表示なのに攻撃する」症状を修正**（Option A・解放時スナップショット）
   - 症状：長押しホールド中は敵が射程外でアウトライン非表示 → リリース → 間もなく敵が射程内に入ってしまい攻撃発動（プレイヤー視点では「何も狙っていないのに撃った」）
   - 原因：[_process_targeting()](scripts/player_controller.gd:608) の解放分岐で `_refresh_targets()` が毎フレーム走り、`_valid_targets` が非空になった瞬間に `_confirm_target()` → 攻撃。リリース後でも新規入り敵に対して発火する構造だった
   - 修正：`_released_without_target` フラグを新設。リリース時に `_valid_targets` が空なら true にセット → 以降の auto_cancel_flash 中は `_valid_targets` が非空になっても攻撃しない（countdown を消化して `_exit_targeting`）。`_enter_pre_delay` / `_exit_targeting` でフラグを false に初期化
   - セマンティクス：「プレイヤーが見ていたターゲット（＝リリース時点で射程内だった敵）のみ攻撃対象にする」

0. **PRE_DELAY → TARGETING 遷移時の同一フレーム race を修正**（実機再現後の 3 段目修正）
   - 症状：アウトラインが一瞬表示されて即座に消える。検出ログ `[CHAR.*]` には出ない（死角）
   - 原因：ゴブリンアーチャーなどの AI が pre_delay 中に移動を開始 → PRE_DELAY → TARGETING 遷移フレーム N では archer の `grid_pos` がまだ (10, 19) → `_setup_targeting_cursor` でアウトライン適用 → 次フレーム N+1 の Character._process で `world_time_running` が未だ true のため visual_move が進み `grid_pos` を (9, 19) にコミット → さらに次の `_refresh_targets` で射程外判定されアウトライン除去
   - 検出死角：`[CHAR.grid_commit] during TARGETING hold!` は `debug_targeting_hold == true` を条件にするが、commit が起きるフレーム頭では `_update_world_time()` がまだ mode=PRE_DELAY 前提で評価していたため `debug_targeting_hold == false`。よってログが出ない
   - 修正：[_start_targeting()](scripts/player_controller.gd:723) 内で `_set_mode(TARGETING)` 直後に `_update_world_time()` を追加呼出。これにより同一フレーム内の以降の Character._process が `world_time_running == false` を見て visual_move を止める（grid_pos が固定される）
1. **回転 Tween が time stop 中に継続するバグ修正**（TARGETING ホールド中に向きだけ変わる残存症状の対処）
   - 原因：[Character.start_turn_animation()](scripts/character.gd:549) が生成する rotation Tween は Godot の SceneTreeTween で、`_process` 非依存で走り続ける。`_update_visual_move` は `world_time_running` でガード済みなので位置補間は停止するが、Tween だけは継続 → TARGETING ホールド中にアウトライン対象の敵が「移動せず向きだけ変える」症状として観察された
   - 修正（A 案・侵襲小）：[character.gd:_process()](scripts/character.gd:216) で `should_process_visuals == (world_time_running or is_player_controlled)` を算出し、false のとき `_turn_tween.pause()` / true で `_turn_tween.play()` を呼ぶ。位置補間と回転 Tween が同じガード条件で動く対称構造になった
   - 回転の新規開始は move_to() 経由か PlayerController 経由のみで、どちらも `should_process_visuals == true` のキャラでしか起きないため、新規 Tween が time stop 中に始まるケースはない（ガード済み経路の継続実行のみ対処）
2. **TARGETING ホールド中に敵が動く問題の根本修正**（持越し課題・ログ調査で原因特定）
   - 原因：[game_map.gd:_process()](scripts/game_map.gd:196) の周期処理 5 関数が `world_time_running` ガードを持たず、time stop 中も走っていた。特に [_check_npc_member_stairs()](scripts/game_map.gd:1500) が NPC リーダーのフロア遷移を発火 → 新フロア敵・NPC スポーンで `sync_position` 100 件が TARGETING 中に連打 → ターゲット位置が変動していた
   - 修正：以下 5 関数の冒頭に `if not GlobalConstants.world_time_running: return` を追加
     - [_activate_enemies_on_npc_floors()](scripts/game_map.gd:1787)
     - [_check_item_pickup()](scripts/game_map.gd:1340)
     - [_check_stairs_step()](scripts/game_map.gd:1880)
     - [_check_party_member_stairs()](scripts/game_map.gd:1421)
     - [_check_npc_member_stairs()](scripts/game_map.gd:1500)
   - 関連：「射程表示中に被弾で攻撃キャンセル」問題も同根の疑いあり。実機検証で合わせて確認
2. **デバッグログ検出機構の整備**（2 系統に分離）
   - 永続保持（検出機構）：`Character` 側 5 系統（`[CHAR.move_to]` / `[CHAR.abort_move]` / `[CHAR.sync_position]` / `[CHAR._update_visual_move]` / `[CHAR.grid_commit]`）。`GlobalConstants.debug_targeting_hold == true` のときだけ発火する防御検出器。将来 `game_map.gd` 等に新しい周期処理が追加された際に即検知できる
   - 一時保持（原因特定用・実機検証完了後に削除）：`PlayerController` 側（`[MODE]` / `[WT]` / `[TGT-HOLD]` / `[TGT-SET]` / `[CURSOR]`）
   - `GlobalConstants.debug_targeting_hold` フラグ新設（[global_constants.gd](scripts/global_constants.gd)）・[_update_world_time()](scripts/player_controller.gd) が維持
3. **派生タスク記録**：`_stair_cooldown` / `_member_stair_cooldown` / `_npc_enemy_activate_timer` のタイマー減算が time stop 中も進行している件を CLAUDE.md「要調査・要整理項目」相当のメモとして残す（他のキャラタイマーとの対称性が取れていない）

4. **PartyStatusWindow デバッグ表示の拡充 + 構造整理**
   - **HP 満表示の内訳追加**：`HP:満` とだけ表示されて誤解を招く（ポーション込み算出のため実 HP 4/41 でも満と表示される）問題を解消。`HP:満(4+150/41)` 形式で「実 HP + ポーション回復量 / max_hp」を可視化
   - **戦況比の内訳追加**：`戦況:優勢(9.0/5.0=1.80)` 形式で「自軍戦力 / 敵戦力 = 戦力比」を可視化
   - **NPC パーティーの表示が更新されない問題**：NpcLeaderAI が `get_global_orders_hint()` を override していたため基底の改修が NPC に反映されなかった。テンプレートメソッドパターンに整理（`get_global_orders_hint()` は共通・`_build_orders_part()` のみサブクラスで override）
   - **起動直後に内訳が出ない問題**：`_combat_situation` が空の一瞬の挙動。仕様範囲内として運用（`REEVAL_INTERVAL` 後に表示される）
   - **指示グループの最適化**：`on_low_hp` / `hp_potion` / `sp_mp_potion` / `item_pickup` は常にヘッダー行と同値のため省略。`move_policy` は UnitAI で per-member に書き換えられうる（explore/guard_room）ため別枠 `move:` プレフィックスで表示。個別指示グループ `指示:` は T/C/F/S/H のみに絞る
   - **target/heal 略号追加**：ヒーラーの回復モード `H:` とターゲット方針 `T:` を個別指示グループに追加

5. **NPC ポーション自動使用の修正（二重 SoT 解消）**
   - 症状：未加入 NPC パーティー（joined_to_player=false）のメンバーが HP 低下してもヒールポーションを自動使用しない
   - 原因：未加入 NPC は `party.global_orders` を受け取らず `_global_orders` が空 → `_assign_orders()` の `_global_orders.get("hp_potion", "never")` が常に "never" に落ちていた。display 側は NpcLeaderAI の `_build_orders_part()` デフォルト（"use"）を返していたため「表示 use / 実動 never」の二重 SoT 不整合
   - 修正：(a) `_assign_orders()` で party-level 指示参照を `_build_orders_part()` 経由に統一。(b) `NpcLeaderAI._build_orders_part()` を「baseline + `_global_orders` マージ」方式に変更し、CRITICAL 時 `battle_policy="retreat"` 書き換え後も NPC デフォルトが保持されるように

6. **HP 状態ラベル閾値定数のリネーム**（命名と意味の整合）
   - 背景：HP は満タンから減っていくため「この値を**下回ったら**次の悪い状態になる」が自然な意味。旧命名は「HP率 ≥ この値なら healthy/wounded/injured」と逆向きだった
   - 変更内容：
     - `CONDITION_HEALTHY_THRESHOLD` (0.5) → `CONDITION_WOUNDED_THRESHOLD` に改名（HP 率 < 0.5 で wounded 以下）
     - `CONDITION_WOUNDED_THRESHOLD` (0.35) → `CONDITION_INJURED_THRESHOLD` に改名
     - `CONDITION_INJURED_THRESHOLD` (0.25) → `CONDITION_CRITICAL_THRESHOLD` に改名
   - 値は据え置き・命名のみリネーム・`get_condition()` も新命名で自然な読み下しに書き換え

7. **HP ポーション自動使用の判定を二段階化 + INJURED で発動に引き上げ**
   - 背景：実プレイ観察で「HP 1 桁でようやくポーション使用」となり次の被弾で即死するリスクが高かった
   - 変更内容：
     - `NEAR_DEATH_THRESHOLD` 定数を物理削除（3 箇所の参照を状態ラベル経由に置き換え）
     - ポーション自動使用：「状態が `critical`」→「状態が `injured` または `critical`」に拡張
     - on_low_hp 発動・ヒーラー `aggressive` モード（旧判定）は状態ラベル経由に移行したが発動条件は据え置き（`critical` のみ）
     - `NPC._auto_share_potions()` もポーション自動使用トリガーと揃えて injured/critical に拡張
   - CLAUDE.md に「AI 行動判定における状態ラベル経由の原則」節を新設（HP 率直接比較を避け、必ず状態ラベル経由で判定）
   - 効果：実プレイで NPC がほぼ死ななくなった

8. **ヒーラー回復モードの 4 モード再設計**
   - 背景：旧 `aggressive` が命名と裏腹に最も消極的・`leader_first` と `none` は実用性が低い・他パーティーへの回復に条件がないのが不自然
   - 新モード構成:

     | モード | 対象 | 他パ対象 |
     |--------|------|---------|
     | `aggressive`（積極回復） | HP 満タン以外で最低 HP 率 1 人 | あり |
     | `lowest_hp_first`（瀕死度優先） | HP 減少量 ≥ 回復量 のうち最低 HP 率 1 人 | あり |
     | `own_party_first`（自パーティー優先） | HP 減少量 ≥ 回復量 のうち自パの最低 HP 率 1 人 | なし |
     | `conservative`（温存） | 状態が wounded 以下の自パで最低 HP 率 1 人 | なし |
   - 判定軸は「回復の無駄の許容度」と「他パ援護の有無」の 2 軸
   - 廃止：`leader_first` / `none`（自パ優先があれば代替可・回復は特殊攻撃ではないので常時撃つ前提）。`_migrate_heal_mode()` で旧値を新値に透過マップ
   - `HEALER_HEAL_THRESHOLD` 定数を物理削除（新ロジックで参照されなくなった）
   - 回復量は `healer.power × slots.Z.heal_mult`（装備補正込み・`SkillExecutor.execute_heal` と同式）で動的算出
   - デフォルトは `lowest_hp_first`：主人公 1 人スタート時に他パ NPC ヒーラーから回復を受けられる序盤救済が重要なため
   - 設計制約：`heal_mult` は「1 回の回復で wounded 境界（HP 率 50%）を跨がない」ように設定（跨ぐと瀕死度優先が `conservative` と区別できなくなる）

#### 2026-04-22（本日の成果：ダメージ倍率調整 + ゲージ表示刷新 + ログラベル修正）

実プレイ検証を経て、バランス調整と可読性改善の 3 つの変更を実施。

1. **ログラベル「スキル」→「クラス補正」変更**：ダメージ計算ログの `スキル N.NN` 表記が Character の `skill` ステータス（クリティカル率用）と命名衝突していたため、実体である `damage_mult` を表す「クラス補正」にリネーム（[character.gd:1189-1205](scripts/character.gd:1189)）。計算ロジックは未変更。関連調査：[`docs/investigation_damage_formula_skill_label.md`](docs/investigation_damage_formula_skill_label.md)
2. **HP/MP/SP ゲージを絶対値 100 スケール化**（左パネルのみ）：`HP_REF = MP_REF = SP_REF = 100.0`（[left_panel.gd:289-292](scripts/left_panel.gd:289)）。HP=100 でバー全幅・50 で半分・25 で 1/4。キャラ個別の max 値に関わらず一定基準で描画。狙いは (1) HP 50 のキャラが「半分しかない」と誤認される不安感の解消、(2) キャラ個性（max HP の高低）の可視化。**内部データ（`hp` / `max_hp` / `energy` / `max_energy`）の意味・計算は従来どおり・HP 上限 100 キャップは意図的に実装していない**
3. **ATTACK_TYPE_MULT 調整（0.3→0.2 / 0.2→0.1）**：近距離グループ（melee / dive）と遠距離グループ（ranged / magic）の比率を **2 : 1** に設計変更（旧 1.5 : 1 相当）。旧値では遠距離が「安全なのに火力も高い」状態でリスク/リワード対応が崩れていた。絶対値（0.2 / 0.1）は実プレイで即死問題がほぼ解消した値。詳細は「命中・被ダメージ計算」節
4. **Config Editor 変更セルのハイライト色を暗色化**：`HIGHLIGHT_BG_COLOR` を `(1.0, 1.0, 0.8)` → `(0.40, 0.32, 0.08)` に変更（[config_editor.gd:19](scripts/config_editor.gd:19)）。明るい文字色との衝突で変更済みセルが読めなかった問題を修正

#### 2026-04-22 夕方以降の成果：ガード中アニメ修正 + 向き変更バグ修正

1. **ガード中移動時の歩行アニメ欠落を修正**
   - 原因：[character.gd](scripts/character.gd) の `_update_visual_move()` 内、アニメ切替条件に `is_guarding` が含まれており、ガード中は全てのフレーム切替が抑制されていた
   - 仕様：「歩行中は walk1/walk2/top の通常サイクル、静止中のみ guard.png」に統一
   - 修正箇所：[character.gd](scripts/character.gd) の 3 箇所（`abort_move` / `_update_visual_move` のフレーム切替 / 同・移動完了時）
   - ガード中かつ静止/移動完了時は `_update_ready_sprite()` 経由で guard.png に復帰させる形に整理
   - 副作用なし（攻撃中×ガード中・ターゲット中×ガード中・ガード解除いずれも既存挙動維持）

2. **向き変更中に攻撃ボタンを押すと TARGETING 時間停止が無効化されるバグを修正**
   - 原因：`_turn_timer` の減算場所が [_process_guard_and_move()](scripts/player_controller.gd:444) 内のみで、PRE_DELAY 中は呼ばれないため `_is_turning` が永遠に true のまま → [_update_world_time()](scripts/player_controller.gd:983) が `_is_turning` を先に評価して TARGETING 時間停止を上書きしていた
   - 再現ログ：`logs/runtime.log` の line 191〜256（向き変更開始 0.09 秒後に攻撃 → TARGETING で `wtr=true` が 1.25 秒継続 → 敵が射程外へ）
   - 仕様：**向き変更時間を pre_delay に含める（並行消化）**
   - 修正方針：
     - `_turn_timer` を [_process()](scripts/player_controller.gd:357) の早段で一元管理（mode 問わず減算・`world_time_running = false` のときは停止）
     - [_update_world_time()](scripts/player_controller.gd:983) の判定順を変更（**TARGETING を turning より先に評価**）
     - [_start_targeting()](scripts/player_controller.gd:711) で `_is_turning` が残っていたら強制完了する安全網を追加（pre_delay < TURN_DELAY のクラスが将来追加された場合への備え）
   - 効果：プレイヤー体感「押してから TARGETING まで＝ pre_delay の長さ」が一定に。通常は pre_delay (0.3〜0.5s) > TURN_DELAY (0.15s) なので turn は pre_delay 消化中に完了する
   - 位置付け：これは「要調査・要整理項目」の **Step 4「向き変更コストの完全対称化」の一部先取り**

3. **`_set_mode()` ヘルパー関数を新設**（リファクタリング）
   - [player_controller.gd:1019](scripts/player_controller.gd:1019) に `_set_mode(new_mode, reason)` を追加。全 `_mode = Mode.XXX` 代入をこのヘルパー経由に統一（7 箇所）
   - 現状は代入を一元化するだけの薄いラッパ。将来 `_mode` 遷移の追跡が必要になったら 1 箇所に `DebugLog.log` を仕込むだけで全遷移を追える状態を維持
   - 原因調査時に仕込んだデバッグログ（`[WT] [MODE] [OUTLINE] [RT] [SHADER]` 系）は本日の修正完了時点で全て削除済み（`_set_mode` ヘルパーと `_reason` 引数名だけ残存）

4. **`get_current_target()` の freed 参照クラッシュを修正**
   - [right_panel.gd:122](scripts/right_panel.gd:122) で `_draw_char_row` 第6引数が freed オブジェクトとなる `InputValidationError` が発生
   - 原因：[player_controller.gd:200](scripts/player_controller.gd:200) `get_current_target()` が `_valid_targets[_target_index]` の validity を確認せず返していた
   - 修正：`is_instance_valid(t)` で freed なら null を返すように変更

#### 2026-04-21（FLEE システム大改訂 + PartyStatusWindow 統合 + Character ステータス統一）

本日は以下の 7 テーマに跨って大量の作業を実施。詳細は番号項目で個別記述。

**テーマ別サマリ**：
- **A. FLEE システム大改訂（ステップ 1〜3 + 避難先表示）**：項目 11 / 14 / 15 / 16（味方 FLEE を `battle_policy` 駆動 + 二段階逃走先決定に統一・避難先情報を PartyStatusWindow に表示）
- **B. 個体アクションの 3 種分離**：項目 13（`flee` → `keep_distance` / `fall_back` / `flee` にセマンティック分離）
- **C. PartyStatusWindow 大改訂**：項目 3 / 5 / 6 / 7（F1/F2 分離・横一列化・敵リーダー行刷新・敵固有表示グループ）
- **D. デバッグ機能**：項目 1 / 2 / 12（DebugLog Autoload・F7 スナップショット・個別ファイル分離）
- **E. Character ステータス設計統一**：項目 4（13 ステータス最終値集約・装備補正取得の単一 API 化）
- **F. 調査ドキュメント 5 件**：項目 9 / 10（`investigation_debug_variables` / `_enemy_order_system` / `_enemy_order_effective` / `_receive_order_keys` / `_party_strategy_ally_removal`・加えて `investigation_unit_ai_actions` も新規）
- **G. その他**：項目 8（dead code 削除）・Step 1-B 調整（BASE_MOVE_DURATION 0.40 → 0.30）

1. **DebugWindow の上下分離**：旧 DebugWindow を F1=`PartyStatusWindow`（パーティー状態）・F2=`CombatLogWindow`（combat/ai ログ）の 2 つの独立ウィンドウに分離。相互排他トグル・各 85%×85% サイズ・layer=15 完全透過
2. **デバッグ用ロガー DebugLog Autoload を新設**：`DebugLog.log(message)` 1 関数。コンソール + `res://logs/runtime.log`（毎起動リセット・flush 付き）の 2 系統に出力。旧 F2「デバッグ情報コンソール出力（`user://debug_floor_info.txt`）」は**機能ごと廃止**（当初 Autoload 名 `Logger` で実装したが、Godot 4.6 組込 `Logger` クラスとの衝突を避けるため `DebugLog` にリネーム）
3. **PartyStatusWindow の表示拡充**（複数セッションに跨る大規模改訂）
   - F3 詳細度トグル（高のみ → 高+中 → 高+中+低 の 3 段階循環・セッション内のみ保持）
   - 旧 F3「無敵モード」を F6 に移動
   - メンバー情報を**横一列化**（旧：強制 1〜3 行/メンバーを廃止）。幅超過時のみ自然折返し
   - リーダー行から**名前・クラス名を除去**・クラス名は各メンバー行（`★名前[C](ヒーラー)`）へ移動
   - 行動ラインに `MP:x/y` / `SP:x/y`（energy）を追加（クラスに応じて MP/SP 切替）
   - 詳細度「低」でフラグライン拡張：UnitAI 側（P↓ F↑ warp）＋ Character 12 ステータス（pow/skl/rng/br/bl/bf/pr/mr/da/ld/ob/mv_s/fac/leader）を `abbr:base+bonus` 形式で表示
4. **Character クラスのステータス設計統一**（大規模リファクタリング）
   - 13 ステータス全てを Character に**最終値フィールドとして保持**（素値＋装備補正）。従来 `power` / `attack_range` / `max_hp` / `max_energy` のみだった対称性の欠落を解消
   - `CharacterData.get_equipment_bonus(stat_name)` に**単一 API 集約**（旧 7 個別 getter を物理削除）
   - 呼出側（`Character.take_damage` / `_calc_block_*` / `UnitAI` / `NpcLeaderAI` / `OrderWindow` / `PlayerController`）を Character 最終値参照に切替
5. **敵リーダー行の `mv/battle/tgt/hp` 表示を廃止**、`strategy=<ENUM>`（`_party_strategy` の素値）直接表示に統一。`PartyLeader.get_global_orders_hint()` の仮想ヒント合成コード（`match _party_strategy` ブランチ）を物理削除
6. **敵メンバー行の指示ライン廃止**（M/C/F/L/S/HP/E/I）。敵では全 8 項目が Character デフォルト固定または `is_friendly` ガードで参照されないため表示する意味なし
7. **敵固有表示グループを新設**：
   - 動的判断（中）：`種: sflee nomp lich:水`（`_should_self_flee` / `_can_attack` / Lich の `_lich_water`）
   - 静的属性（低）：`ignfle undead flying immune proj:... chase:N terr:N`（`_should_ignore_flee` / is_undead / is_flying / instant_death_immune / projectile_type / chase_range / territory_range）
8. **dead code 整理**：`Character.get_direction_multiplier()`（方向ダメージ倍率 dead code）を物理削除。`guard_facing` コメント残骸も修正
9. **調査ドキュメント 3 件新規作成**：
   - [`docs/investigation_debug_variables.md`](docs/investigation_debug_variables.md)：PartyLeader / UnitAI / Character の状態変数棚卸し（22 + 42 + 71 行）
   - [`docs/investigation_enemy_order_system.md`](docs/investigation_enemy_order_system.md)：敵の指示体系がなぜ味方と異なるか（8 フィールド比較マトリクス・(A)/(B)/(C) 分類）
   - [`docs/investigation_enemy_order_effective.md`](docs/investigation_enemy_order_effective.md)：敵リーダー行の旧表示が実動に効くか（7 フィールド全て (A) 表示のみ・根本原因は仮想ヒント合成）
10. **追加調査ドキュメント 2 件**：
    - [`docs/investigation_receive_order_keys.md`](docs/investigation_receive_order_keys.md)：`receive_order()` 辞書の全 12 キー棚卸し（指示 9 / パーティー文脈 2 / 戦況判断 1）・dead transmission なし・`_leader_ref` のみ表示追加候補
    - [`docs/investigation_party_strategy_ally_removal.md`](docs/investigation_party_strategy_ally_removal.md)：味方側 `_party_strategy` 廃止の影響範囲調査（参照 40 箇所・変更 5 ファイル・中規模）
11. **味方側 `_party_strategy` / `party_fleeing` 廃止（ステップ 1）**：
    - 背景：味方の個別指示（プレイヤーが細かく設定した値）が `party_fleeing = true` によって上書きされる仕様違反を修正
    - `PartyLeaderPlayer._evaluate_party_strategy()` / `NpcLeaderAI._evaluate_party_strategy()` を削除
    - 基底 `party_leader.gd` で `_is_enemy_party()` / `_is_in_explore_mode()` / `_is_in_guard_room_mode()` フックを新設。戦略評価・`party_fleeing` 配布・EXPLORE/GUARD_ROOM 分岐を敵専用にゲート
    - NpcLeaderAI は `_has_visible_enemy()` 単独判定 + `_is_in_explore_mode()` override で探索挙動を維持
    - PartyStatusWindow の `P↓` 表示を敵メンバー限定に絞る
    - **一時的な副作用**：NpcLeaderAI の CombatSituation.CRITICAL 時自動 FLEE が失われる（ステップ 2 で `battle_policy="retreat"` 自動書き換え方式で復活予定）
    - 設計原則を「パーティーシステムのアーキテクチャ」→「戦略システムの設計原則」として明文化
12. **F7 PartyStatusWindow スナップショット機能**：現在の全パーティー状態を `res://logs/snapshot_<timestamp>.log` に個別ファイルとして書き出す（詳細度は常に最大・ウィンドウ非表示でも動作・ConfigEditor 開時は無効）。`runtime.log` には押下マーカー 1 行のみ記録し、瞬間の状態記録は独立ファイルとして履歴を蓄積。静止画スクリーンショットより情報密度の高いデバッグ記録として、戦略切替・FLEE 発動・戦力比変化などの時系列追跡に利用できる
13. **個体アクション `flee` を 3 種に分離**：同じ `flee` アクションが「HP 低下逃走・パーティー撤退・種族カイティング」の 3 コンテキストで共用され PartyStatusWindow で区別できなかった問題を解消
    - `keep_distance`（距離確保）：GoblinArcher / Salamander の射程維持カイティング
    - `fall_back`（後退）：個別指示 `on_low_hp = "fall_back"` + HP 低下時の前線後退（新設）
    - `flee`（逃走）：戦闘離脱用（`on_low_hp = "flee"` / `combat = "flee"` / 敵 `_party_strategy == FLEE`）
    - `on_low_hp` の内部値 `"retreat"` → `"fall_back"` にリネーム（全体方針 `battle_policy = "retreat"` との内部名重複を解消・UI 表示「後退」は維持）
    - 実行ロジックは当面 3 種とも同じ（`_find_flee_goal()` で脅威から離れる方向に移動）。差別化は後のタスク
    - `_STRATEGY_FALL_BACK = 3` を UnitAI 内部戦略値として追加（PartyLeader.Strategy とは独立）
    - 関連：[`docs/investigation_unit_ai_actions.md`](docs/investigation_unit_ai_actions.md)
14. **ステップ 2 完了：NpcLeaderAI CRITICAL 時 `battle_policy` 自動書き換え**：ステップ 1 で失われた NPC の自動 FLEE 機能を別経路で復活
    - `_evaluate_party_strategy()` は復活させず、代わりに `_global_orders["battle_policy"] = "retreat"` を自動書き換え（PartyLeaderPlayer と同じ「味方は battle_policy 駆動」構造に統一）
    - CRITICAL（戦力比 < 0.5）→ `retreat` / SAFE（敵未検知）→ `attack` の 2 閾値切替。中間領域（DISADVANTAGE / EVEN / ADVANTAGE / OVERWHELMING）は現状維持で境界振動を抑える
    - クールダウン `NPC_POLICY_CHANGE_COOLDOWN`（既定 3.0 秒）で短時間の再書き換えを抑制
    - プリセット流し込み機構 `apply_battle_policy_preset()` を `PartyLeader` 基底に新設（OrderWindow.BATTLE_POLICY_PRESET を再利用・NPC / プレイヤー共通経路化）
    - 書き換え時は `notify_situation_changed()` を呼んで即座にメンバーへ伝達
    - `[NPC戦況判断]` ログを MessageLog に出力（戦況と新 battle_policy を記録）
16. **PartyStatusWindow の FLEE 時避難先情報表示**：ヘッダーの戦況判断ブロック末尾に `避難先:<area_id>(d:<n>)@(<x>,<y>)`（通常）/ `避難先:!fb@(<x>,<y>)`（フォールバック）を追加
    - `PartyLeader` に `_flee_refuge_area_id` / `_flee_refuge_distance` / `_flee_is_fallback` を保持
    - `_determine_flee_recommended_goal()` で最適出口選択時に対応する避難先エリア ID と BFS 距離も記録
    - 味方パーティー限定（敵の FLEE 実装は別タスク）
    - `battle_policy` は全体指示（プレイヤー設定値）なので触らず、避難先情報は戦況判断の派生情報として独立表示
    - F7 スナップショットにも自動反映（既存機構経由）

15. **ステップ 3 完了：FLEE 時の逃走先決定ロジック**（味方パーティー対応）
    - 二段階方式：リーダーが推奨出口決定・メンバーに配布 → メンバーは自分の位置から全出口を評価・推奨バイアスで選択
    - 脅威コスト付き A*（`_astar_with_cost`）で現エリア内最適経路・エリア間は BFS 距離（`MapData.get_area_distance`）で評価
    - 避難先：フロア 0 = 安全部屋エリア / フロア 1 以降 = 上り階段エリア（複数候補対応・`MapData.get_refuge_area_ids`）
    - パーティー FLEE 時：`FLEE_NON_RECOMMENDED_PENALTY`（既定 15.0）で統率された集団逃走
    - 個体 FLEE 時：推奨バイアスなしで自律判断
    - 敵パーティーの FLEE 挙動は現状維持（派生課題として残課題に記録）
    - エリア変化検知：メンバーがエリアをまたいだら `on_member_area_changed` 経由でリーダーに通知、`FLEE_REEVAL_MIN_INTERVAL`（既定 0.3 秒）で再評価クールダウン
    - MapData に 4 API 新設：`get_refuge_area_ids` / `get_area_distance` / `get_exit_tiles_from` / `get_adjacent_area_ids_of_exit`
    - GlobalConstants に 5 定数新設（UnitAI カテゴリ）：`FLEE_THREAT_RANGE` / `FLEE_THREAT_WEIGHT` / `FLEE_AREA_DISTANCE_WEIGHT` / `FLEE_NON_RECOMMENDED_PENALTY` / `FLEE_REEVAL_MIN_INTERVAL`
    - PartyStatusWindow（詳細度「低」・味方メンバーのみ）に `flee→(x,y)` 推奨出口表示
    - 敵ステータス直接参照禁止ルール準拠：脅威コストは位置と `is_friendly` のみ参照

#### 2026-04-20（前日の成果）
- **攻撃操作の 1 発 1 押下化**：TARGETING モードの時間停止仕様を再設計。Z/A 押下中は射程表示＋向き変更可、離した瞬間に攻撃発動の一本化モデルへ。4 つの内部ステート（`PRE_DELAY` / `PRE_DELAY_RELEASED` / `TARGETING` / `POST_DELAY`）で状態遷移を整理し、連打（素早く離す）とじっくり狙う（pre_delay 完了後の時間停止）の両立を実現。詳細は「攻撃フロー（一発一押下モデル）」節
  - 設計過程：(1) 確定の二度押し廃止＋release-to-fire を実装 → (2) ボタン解放を「攻撃ボタンを押している間だけ向き変更」に縛るよう改修 → (3) PRE_DELAY 終了後 TARGETING への引き継ぎでも向き変更を有効化 → (4) ボタン解放時の自動キャンセルタイマー再起動を追加 → (5) TARGETING 時間停止を「ホールド中のみ」に再設計し、PRE_DELAY_RELEASED 状態を新設して連打のテンポ感を回復
- **Config Editor の hidden フラグ導入**：定数メタデータに `hidden: true` を追加できるようにし、デフォルトでは Config Editor から非表示。下部ボタン列右端に「隠し項目も表示」チェックボックスを追加（セッション内のみ保持・open() ごとにリセット・薄いアルファでグレーアウト気味に表示）。既存の `CONDITION_COLOR_*`（スプライト/ゲージ/テキスト × 4 段階 = 12 個）を hidden 化
- **freed クラッシュ修正**：`PartyLeader._calc_stats` / `_get_my_combat_members` / `_calc_hp_status_for` の 3 箇所で `as Character` キャストが解放済みオブジェクトでクラッシュする問題を修正（キャスト前 `is_instance_valid(mv)` ガード）
- **移動関連の包括調査完了**：3 件の調査ドキュメントを作成
  - [`docs/investigation_turn_cost.md`](docs/investigation_turn_cost.md) — 向き変更コストの現状（プレイヤー TURN_DELAY のみ・AI 即時の非対称性）
  - [`docs/investigation_movement_constants.md`](docs/investigation_movement_constants.md) — 移動・時間系定数の全洗い出し（38 項目）と game_speed 適用パターンの 4 分類
  - [`docs/investigation_enemy_class_stats.md`](docs/investigation_enemy_class_stats.md) — 敵クラスステータスの利用状況（10/11 ステータスは正常・move_speed のみ dead）
  - **重要発見**：(1) `character_data.move_speed` が完全 dead data、(2) `MOVE_INTERVAL` の SoT が PlayerController / UnitAI に分裂（同名・別値・別ファイル）、(3) game_speed 適用パターンが 4 種類混在（pre-scaled / post-scaled / 未適用 / 逆方向バグ）、(4) `enemy_class_stats.json` が Config Editor で編集不可、(5) 16 敵中 11 敵が人間 class_stats を借用
- **設計原則の追記**：「移動関連の二層構造」を新設。時間系ステータスはベース値（GlobalConstants）× 能力値（character_data）× `BASE × 50 / status` の逆比例補正で管理する方針を明文化
- **Step 1-A 完了：敵ステータスの Config Editor 対応 + タブフラット化**：事前調査でステータス算出ロジックは既に味方・敵で統一済み（`_calc_stats` 共用・attribute_stats.json 共用）と判明し、当初想定より小さい範囲で完了
  - Config Editor のトップタブをフラット 8 タブ構造に再編：`定数 | 味方クラス | 味方ステータス | 属性補正 | 敵一覧 | 敵クラス | 敵ステータス | アイテム`
  - 旧「ステータス」タブ内の 2 サブタブ（クラスステータス / 属性補正）を廃止しトップレベルに昇格。属性補正は味方・敵共用ルールなので味方ブロックと敵ブロックの橋渡し位置に独立タブとして配置
  - 新タブ「敵ステータス」で `enemy_class_stats.json`（敵固有 5 クラス）を編集可能に。leadership / obedience は敵クラス定義に存在しないため表示されない（仕様どおり・敵 AI が参照しないため）
  - 描画関数 `_build_class_stats_tab(parent, tab_name, source_id, data, class_ids)` を共通化。味方ステータス・敵ステータスは同じグリッドを再利用（source_id="ally"/"enemy" で切り分け）
- **Step 1-B 完了：`move_speed` 有効化＋ガード WEIGHT 定数化**：移動関連の二層構造を実装開始
  - `character_data.move_speed` を 0-100 スコア直接格納に変更（従来の事前変換 `_convert_move_speed` 廃止）
  - `Character.get_move_duration()` 新設：`BASE_MOVE_DURATION × 50 / move_speed`（逆比例補正・ガード中は GUARD_MOVE_DURATION_WEIGHT 倍・下限 0.10 秒ハードコード）
  - GlobalConstants の Character カテゴリに `BASE_MOVE_DURATION = 0.40` / `GUARD_MOVE_DURATION_WEIGHT = 2.0` 追加（Config Editor で調整可）
  - `PlayerController.MOVE_INTERVAL = 0.30` / `UnitAI.MOVE_INTERVAL = 0.40`（SoT 分裂状態）を廃止し、`character.get_move_duration()` 呼出に一本化
  - Wolf / Zombie の `_get_move_interval()` オーバーライド削除。`enemy_class_stats.json` の `wolf.move_speed=40` / `zombie.move_speed=10` が初めてゲーム挙動に反映される
  - **挙動変化**：Wolf 0.27s → 約 0.50s（遅くなる）、Zombie → 約 2.00s（非常に遅い）、人間キャラも class_stats 値 × attribute_stats 補正が効くようになる。スケール校正は実プレイで実施
- **Step 1-B 実装後の観察事項**：人間キャラの動作速度低下・死亡率上昇・ガード中歩行アニメ欠落・射程表示中の被弾キャンセルが観察された。次セッションで切り分け調査予定（詳細は「次セッションで検討するタスク」セクションの「最優先：Step 1-B 実装後の挙動調査」参照）

#### 2026-04-19
- **バグ修正**：敵の V スロット特殊攻撃が誤発動する問題・戦闘メッセージで敵表示名が「斧戦士」等のクラス日本語名になる問題を修正（Phase B の `class_id = stat_type` 設定の副作用）
- **アイテム事前生成機構の完成**：定数ベース事前生成（2 ステータス × 3 段階 = 9 パターン）× フロア重み選択方式を採用。`scripts/item_generator.gd` 新設・事前生成セット 9 ファイル（計 75 エントリ）を `assets/master/items/generated/` に配置
- **Config Editor 機能拡張**：Effect カテゴリ新設（+11 定数）・Item カテゴリ新設（+11 定数：bonus 比率 3・フロア基準 tier 3・距離重み 3・tier policy 1・初期ポーション個数 2）・トップレベル「アイテム」タブ新設（1 行 1 タイプ形式の横断表）・`string` 型（OptionButton / LineEdit）編集サポート追加
- **画像サイズ設計是正**：`Projectile.SPRITE_REF_SIZE` / `DiveEffect.RADIUS` を GRID_SIZE 比率化（解像度追従）。`PROJECTILE_SPEED` を SkillExecutor → Effect カテゴリへ移動
- **Legacy コード大量削除**（合計約 1,300 行以上）：
  - Legacy LLM AI コード 5 クラス（BaseAI / EnemyAI / LLMClient / DungeonGenerator / GoblinAI）+ dead method
  - 個別敵 JSON の legacy 6 フィールド × 16 ファイル
  - アイテムマスター JSON の `{stat}_min` / `depth_scale`
  - effect キー legacy フォールバック（`restore_mp/sp` × 5 ファイル）+ dead accessor 3 個
  - GlobalConstants dead constants・`_crop_single_tile` stale 関数
  - CLAUDE.md の LLM 参考仕様 3 セクション
- **UI バグ修正**：装備補正値の表示で stats 辞書を固定キーでフィルタしていた 3 箇所を全キー反復方式に変更（block_right_front 等の欠落を解消）。ステータス画面の 3 防御強度行を常時表示に
- **定数タブ**：Character / PartyLeader / NpcLeaderAI / EnemyLeaderAI / UnitAI / SkillExecutor / Effect / Item の 8 タブ構成（約 57 個の定数）

##### 午後以降の追加作業
- **「無（none）」段階の導入**：3 段階 → 4 段階（none/low/mid/high）に拡張。tier=0 エントリを各装備 9 タイプに追加（計 +9 エントリ）
- **bonus / tier 概念分離**：`ITEM_TIER_*_RATIO` → `ITEM_BONUS_*_RATIO`、`FLOOR_X_Y_BASE_TIER` を String → int 型変更、`generated/*.json` の tier も整数化
- **初期装備の統合生成**：`_dbg_items` / `dungeon_handcrafted.json` を `item_type` 文字列リスト化し、`ItemGenerator.generate_initial()` で実体化。player_party の死にコード装備を物理削除
- **初期ポーション個数を Config Editor 化**：`INITIAL_POTION_HEAL_COUNT` / `INITIAL_POTION_ENERGY_COUNT` 追加
- **ItemGenerator 戻り値に tier 追加**（実装漏れ修正）
- **戦力計算への装備 tier 反映**：戦力式を `(rank_sum + party_tier_sum × ITEM_TIER_STRENGTH_WEIGHT) × HP率` に拡張。`ITEM_TIER_STRENGTH_WEIGHT`（デフォルト 0.33）追加・DebugWindow に内訳表示
- **戦力計算・戦況判断の統合 (`_evaluate_strategic_status()`)**：旧 `_evaluate_party_strength*` / `_evaluate_combat_situation` を 1 関数に統合。3 集合（full_party / nearby_allied / nearby_enemy）× 1 度ずつ統計算出
- **距離ベース連合**：エリアベース `target_areas` 判定を廃止し、マンハッタン `COALITION_RADIUS_TILES` マス以内（デフォルト 8・Komuro 調整で 6）に変更
- **敵の非対称設計**：enemy は自軍戦力 = full_party のみ（協力しない世界観）。味方は nearby_allied（連合）
- **バグ修正**：`PartyLeader.setup()` の `_all_members` 未伝播・NpcLeaderAI tier キー欠落・freed member アクセスクラッシュ
- **DebugWindow 3 点表示**：`PB F(R+T)s C(R+T)s E(R+T)s` 形式。プレイヤー R:45 違和感を解消
- **旧キー完全削除**：`my_rank_sum` / `enemy_rank_sum` 等は後方互換なしで置換
- **FLOOR_RANK の Config Editor 化**：`const FLOOR_RANK: Dictionary` 削除 → `FLOOR_0_RANK_THRESHOLD`〜`FLOOR_4_RANK_THRESHOLD` の 5 個と `FLOOR_RETREAT_RATIO` に分解。NpcLeaderAI カテゴリが実体化（0 個 → 6 定数）。値は据え置き（次セッションで実プレイ調整）

#### 2026-04-18（前日の成果）
- **SkillExecutor 抽出完了**：10 種スキル（heal / melee / ranged / flame_circle / water_stun / buff / rush / whirlwind / headshot / sliding）の Player/AI 計算を統一
- **MP/SP を `energy` に統合**：内部データは単一フィールド、UI はクラスに応じて MP/SP 表示を切替
- **ポーション刷新**：ヒールポーション / エナジーポーション（MP/SP ポーション統合）

### 参照順序の推奨
1. CLAUDE.md「アーキテクチャ方針」「設計原則」「パーティーシステムのアーキテクチャ」「AI と実処理の責務分離方針」
2. CLAUDE.md「次セッションで検討するタスク」→「最優先：2026-04-22 の調整を踏まえた実プレイ再検証」「FLEE 実装の完了状況 / FLEE 派生課題」
3. CLAUDE.md「要調査・要整理項目」→「優先度別インデックス」で FLEE 以外の未完了タスクを俯瞰
4. `docs/history.md` の 2026-04-22 / 2026-04-21 / 2026-04-20 / 2026-04-19 エントリ群で直近の経緯
5. `docs/` 配下の `investigation_*.md` で詳細な背景情報：
   - ダメージ計算表記：`investigation_damage_formula_skill_label.md`
   - FLEE / 戦略系：`investigation_party_strategy_ally_removal.md` / `investigation_receive_order_keys.md` / `investigation_unit_ai_actions.md`
   - デバッグ変数・敵指示：`investigation_debug_variables.md` / `investigation_enemy_order_system.md` / `investigation_enemy_order_effective.md`
   - 移動・時間系：`investigation_turn_cost.md` / `investigation_movement_constants.md` / `investigation_enemy_class_stats.md`
6. 実装前に `docs/spec.md` で仕様詳細を確認

### コードベースの主要ファイル
- `scripts/skill_executor.gd` — スキル計算の集約（Player/AI 共通ロジック）
- `scripts/item_generator.gd` — アイテム事前生成セットからのフロア重み選択（2026-04-19 新設）
- `scripts/config_editor.gd` — F4 で開く定数・データエディタ（2026-04-19 にアイテムタブ追加）
- `scripts/unit_ai.gd` — AI 個体行動（種族別にサブクラス継承）
- `scripts/player_controller.gd` — プレイヤー操作
- `scripts/character.gd` — キャラクター実体（状態変化・HP 管理）
- `scripts/party_manager.gd` — パーティー管理（全 `party_type` で共通）

### データ配置
- `assets/master/items/*.json` — 各アイテムタイプの**ルール**（base_stats.{stat}_max）。Config Editor で編集
- `assets/master/items/generated/*.json` — **個別アイテム**（事前生成セット・75 エントリ）。Claude Code が生成セットを手動作成／再生成する
- `assets/master/config/constants.json` / `constants_default.json` — Config Editor の定数値とメタ情報
- `assets/master/enemies/*.json` — 個別敵の固有項目のみ（legacy 6 フィールドは 2026-04-19 に削除）
- `assets/master/classes/*.json` — 味方 7 + 敵固有 5 クラス定義
- `assets/master/stats/*.json` — クラス・属性ステータス定義

### 次セッションで検討するタスク（優先順）

#### 🔧 TODO：一時デバッグログ・トラッカーの削除（2026-04-23 持越し）

2026-04-23 の TARGETING 系バグ調査で仕込んだ一時保持デバッグログ・トラッカーは、**全症状が解消したことを実機で確信した後**に削除する。以下をまとめて削除すること:

**`scripts/player_controller.gd`**:
- `_dbg_prev_world_time_running` / `_dbg_prev_targeting_hold` / `_dbg_prev_valid_target_ids` / `_dbg_prev_cursor_target_id` / `_dbg_prev_cursor_grid` 変数 (5 個・line 150 付近)
- `_update_world_time()` 内の `[WT]` / `[TGT-HOLD]` ログ呼出
- `_set_mode()` 内の `[MODE]` ログ呼出
- `_refresh_targets()` 内の `[TGT-SET]` ログ呼出（`if _mode == Mode.TARGETING:` ブロック全体）
- `_update_cursor()` 内の `[CURSOR] →` / `[CURSOR] cleared` / `[CURSOR] ≈` ログ呼出
- `_try_facing_change_from_input()` 内の `[PLAYER-TURN]` ログ呼出
- `_exit_targeting()` 内の `_dbg_prev_*` リセット行（line 761 付近）

**`scripts/character.gd`**: **削除しない**（`[CHAR.*]` 系は永続保持の防御検出器として残す）

**`scripts/global_constants.gd`**: **`debug_targeting_hold` フラグは残す**（永続保持組 `[CHAR.*]` が参照するため）

**`scripts/player_controller.gd:_update_world_time()`**: `new_hold` 変数・`GlobalConstants.debug_targeting_hold = new_hold` 代入・`new_hold` を reason 文字列に含める処理は**残す**（永続保持組が参照するため）

**削除判定基準**：次セッションで Komuro から「TARGETING 系の挙動は全て安定」と確認が取れたタイミング。その確認が取れるまでは、Claude Code 側から一時ログを自発的に削除しない。

#### ✅ 修正済み（要実機検証）：TARGETING ホールド中にアウトラインされた敵が動く問題

**原因**（2026-04-23 ログから特定）：
[game_map.gd:_process()](scripts/game_map.gd) の周期処理 5 つが `world_time_running` ガードを持たず、TARGETING ホールド中も走り続けていた。特に [_check_npc_member_stairs()](scripts/game_map.gd:1500) が NPC リーダーのフロア遷移を発火させ、新フロアの敵・NPC スポーン（各キャラ 2 回の `sync_position` 連打 = 100 件）が TARGETING 中に実行されていた。

**修正**（2026-04-23）：以下 5 関数の冒頭に `if not GlobalConstants.world_time_running: return` を追加
- [_activate_enemies_on_npc_floors()](scripts/game_map.gd:1787)
- [_check_item_pickup()](scripts/game_map.gd:1340)
- [_check_stairs_step()](scripts/game_map.gd:1880)
- [_check_party_member_stairs()](scripts/game_map.gd:1421)
- [_check_npc_member_stairs()](scripts/game_map.gd:1500)

**関連する未解決**：
- 「射程表示中に被弾すると攻撃がキャンセルされるように見える」問題（同根の疑い・本修正で解消するか実機確認）

**以下は旧記述（原因特定過程の記録・参考用）**：

本日の向き変更バグ修正で、`_is_turning` に起因する TARGETING 時間停止無効化は解消した。しかし Komuro の実機再現では、**向き変更を伴わないケースでもアウトラインされた敵が動く現象が依然として発生**している。

すなわち、本日の調査で発見した経路（`_is_turning` による上書き）とは**別経路**がまだ存在する。前回調査「TARGETING ホールド中に敵が動く経路はない」の結論は誤り（マトリクスに更に抜けがある）。

**同一原因の疑い**：元々の発端である「射程表示中に被弾すると攻撃がキャンセルされるように見える」問題とも同根の可能性が高い（敵が動いて射程外に出ることで `_valid_targets` が空になりターゲットロスト）。

**調査項目（次セッション）**：

1. `_turn_timer` 一元管理で解消されなかった経路の特定
2. `_is_turning` 以外で `_update_world_time()` が TARGETING 時間停止を上書きする条件がないか再確認
3. [character.gd](scripts/character.gd) / [unit_ai.gd](scripts/unit_ai.gd) / その他のキャラ位置更新処理に、`world_time_running` ガードが抜けている経路がないか再調査
4. Tween / Timer / `_physics_process` 等 Godot 標準機構で world_time_running 非参照の経路がないか（例：`_turn_tween` は既に確認済みで rotation のみだが grid_pos に影響する経路が他にないか）

**デバッグログの方針（2026-04-23 修正確認後の整理）**：

ログは 2 系統に分けて管理する：

1. **永続保持**（回帰防止の検出機構として残す・本修正後も削除しない）
   - `Character` 側 5 系統：`[CHAR.move_to]` / `[CHAR.abort_move]` / `[CHAR.sync_position]` / `[CHAR._update_visual_move]` / `[CHAR.grid_commit(half|end)]`
   - すべて `GlobalConstants.debug_targeting_hold == true` のときだけ発火する防御検出器。将来 `game_map.gd` 等に新しい周期処理が追加された際に同種のバグを即検知できる
   - `GlobalConstants.debug_targeting_hold` フラグと `PlayerController._update_world_time` の維持ロジックもこれを支えるので残す

2. **一時保持**（原因特定を終えたので、本修正の実機検証が完了したら削除）
   - `PlayerController` 側：`[MODE]` / `[WT]` / `[TGT-HOLD]` / `[TGT-SET]` / `[CURSOR]`
   - 削除時は `_dbg_prev_world_time_running` / `_dbg_prev_targeting_hold` / `_dbg_prev_valid_target_ids` / `_dbg_prev_cursor_target_id` 変数も一式削除
   - ただし `debug_targeting_hold` フラグの維持コード（`new_hold` 変数と `GlobalConstants.debug_targeting_hold = new_hold` 行）は**残す**（永続保持組が参照するため）

**実機検証の観点**：
1. `TARGETING ホールド中にアウトラインされた敵が動く`現象が再現しないか
2. 「射程表示中に被弾で攻撃キャンセル」問題も同根の疑いがあったので、合わせて再現チェック
3. `runtime.log` に `[CHAR.*]` 系の `"during TARGETING hold!"` ログが 1 件も出ないこと（出たらそれが新たな未ガード経路）

**関連する未解決**：

- 「射程表示中に被弾すると攻撃がキャンセルされるように見える」問題（項目 3 と同根の可能性大・項目 3 解決後に再現するか確認）

**派生タスク（優先度：中・別セッション）**：[game_map.gd:_process()](scripts/game_map.gd:196) のインラインタイマー減算が time stop 中も進行している:
- `_stair_cooldown` / `_member_stair_cooldown`（階段クールダウン）
- `_npc_enemy_activate_timer`（NPC 不在フロア敵アクティブ化用）

これらは他のキャラタイマー（stun / buff / energy 回復）が `world_time_running` で停止するのと対称性が取れていない。`game_speed` 適用パターンの 4 分類混在問題（[docs/investigation_movement_constants.md](docs/investigation_movement_constants.md)）と合わせて整理するのが自然。今回の TARGETING 問題の主因ではないが、次に手を付けるならここ。

---

#### 🔥 最優先：2026-04-22 の調整を踏まえた実プレイ再検証

2026-04-22 の 3 変更（ダメージ倍率 0.3/0.2→0.2/0.1・HP ゲージ 100 スケール化・ログラベル修正）により即死問題はほぼ解消したとの Komuro 確認済み。次セッションは**同じ変更セットでの継続検証＋次の微調整判断**を行う段階。

**セッション開始時の最優先タスク：ドキュメント更新の確認**（このファイル・[docs/spec.md](docs/spec.md)・[docs/history.md](docs/history.md) は 2026-04-22 作業終了時に更新済み。読み戻して直近の設計意図を把握する）

**検証項目**：

1. **戦闘テンポの確認**
   - 敵を倒すのが冗長に感じないか
   - 1 戦の平均所要時間が許容範囲か
2. **Floor 0 のアーチャー問題の再評価**
   - 遠距離倍率半減後、Floor 0 にアーチャーが居ても問題ないか
   - 問題あれば Floor 0 はゴブリンのみに戻す判断を改めて検討
3. **FLEE システムの動作確認**
   - NPC が CRITICAL 時に正しく FLEE するか（`[NPC戦況判断]` ログの出現・F7 スナップショットでの `battle_policy = retreat` 確認）
   - 即死しなくなった今、FLEE が間に合って逃げ切れるか
   - `避難先:xxx(d:n)@(x,y)` 表示が実挙動と一致するか（フォールバック `!fb` 多発時はマップ設計 or 実装不備の疑い）
4. **最低保証 1 張り付き問題**
   - ログで多くの攻撃が「最終 1」になっていないか確認
   - 防御強度・耐性の違いがダメージに反映されているか
   - 張り付きが多発していれば倍率の再調整を検討
5. **味方側の火力バランス**
   - 弓使い・魔法使いの火力が半減したことで、戦闘が間延びしないか
   - 特殊スキル（whirlwind 等）の存在感がどうか

**2026-04-23 追加検証項目**：

6. **ヒーラー回復モード 4 種の挙動確認**
   - 各モードで意図通りに動くか（積極回復・瀕死度優先・自パ優先・温存）
   - デフォルト `lowest_hp_first` で主人公 1 人スタート時に他パ NPC ヒーラーから救済されるか
   - 「満タンにしてくれない」現象は `lowest_hp_first` の仕様（HP 減少量 < 回復量で候補外）どおり
   - `heal_mult` と wounded 境界（0.5）の逆転が起きていないか

7. **ヒーラー強すぎ問題の有無**
   - Komuro 予測：ヒーラー強すぎ問題が発生しそう・発生したら回復量（`Z_heal_mult`）で調整
   - 逆に弱すぎて戦闘テンポが間延びしないかも観察

8. **INJURED でポーション使用後のバランス**
   - NPC がほぼ死ななくなった（2026-04-23 確認済み）が、過剰に生存する反動で戦闘が間延びしないか
   - ポーション消費ペースが早すぎないか（補給追いつくか）

**観察結果次第で調整する候補**：

- **数値調整**：HP ベース値 / `damage_mult`（スロット定義値）/ 耐性（`physical_resistance` / `magic_resistance` の `score/(score+100)` カーブ）
- **FLEE 閾値調整**：CombatSituation.CRITICAL の発火条件（`COMBAT_RATIO_DISADVANTAGE = 0.5` 等）
- **脅威コスト・避難先距離の重みバランス**：`FLEE_THREAT_RANGE` / `FLEE_THREAT_WEIGHT` / `FLEE_AREA_DISTANCE_WEIGHT` / `FLEE_NON_RECOMMENDED_PENALTY` / `FLEE_REEVAL_MIN_INTERVAL`
- **クールダウン調整**：`NPC_POLICY_CHANGE_COOLDOWN`（境界振動の観察結果次第）
- **フロア基準値**：`FLOOR_*_RANK_THRESHOLD` / `FLOOR_RETREAT_RATIO`（装備 tier 戦力反映後の再校正）

**優先度低・メモ（実プレイで要確認）**：

- **クリティカル率**（`CRITICAL_RATE_DIVISOR = 300`）：攻撃力半減でクリティカル事故死の圧力も半減したため、旧来の「クリティカル率が高すぎる」問題は自動的に解消した可能性あり。クリティカル事故死が起きなければ現状維持
- **ランク補正強化**：敵が硬く感じるようなら、B・A ランクの強化でプレイヤー側の成長実感を高める選択肢。実プレイで必要性を確認してから
- **ゴブリン斧戦士の強さ**：Floor 0 で囲まれると厳しい問題はダメージ半減で緩和されているはず。再発したら個別調整

**作業方針の確認**：

- 一度に複数の変更を入れず、一つずつ実プレイで効果を確認する
- 余計な操作は入れない（例：HP 100 キャップ等、本質と無関係な変更を混ぜない）
- 設計思想の変更は CLAUDE.md に明記してから実装に進む

---

#### 継続：「移動関連の二層構造」設計原則の段階的適用

各 Step は独立せず順序依存があるため、上から順に進める。

1. ✅ **Step 1-A：`enemy_class_stats` の Config Editor 対応**（2026-04-20 完了・タブのフラット化を含む）

2. ✅ **Step 1-B：`move_speed` 有効化＋ガード WEIGHT 定数化**（2026-04-20 完了）
   - `character_data.move_speed` を live data 化（0-100 スコアで直接格納）
   - `Character.get_move_duration()` を新設：`BASE_MOVE_DURATION × 50 / move_speed`（標準能力値 50 を基準とする逆比例補正・ガード中は GUARD_MOVE_DURATION_WEIGHT 倍・下限 0.10 秒）
   - `BASE_MOVE_DURATION = 0.40` / `GUARD_MOVE_DURATION_WEIGHT = 2.0` を GlobalConstants Character カテゴリに追加
   - `_convert_move_speed()` 廃止・`PlayerController.MOVE_INTERVAL` / `UnitAI.MOVE_INTERVAL` 廃止
   - Wolf / Zombie の `_get_move_interval()` オーバーライド廃止（`enemy_class_stats.json` の move_speed 値が反映される）
   - スケール校正は実プレイで実施（Wolf は現状 0.27s → 設計値 約 0.50s に遅くなる見込み）

#### 最優先：Step 1-B 実装後の挙動調査

Step 1-B（move_speed 有効化・MOVE_INTERVAL 廃止・ガード WEIGHT 導入）実装後、以下の挙動が観察された。Step 2 に進む前に切り分け調査が必要。Step 1-B 由来のバグか、それ以前の変更由来か、仕様どおりかを確認する。

**観察された挙動**：

1. **人間キャラの動作が遅くなった**（Step 1-B 影響度：高）
   - 旧式 `_convert_move_speed`: `seconds = max(0.1, 0.8 - score × 0.006)`（score=50 → 0.50s）
   - 新式 `get_move_duration`: `BASE_MOVE_DURATION × 50 / move_speed`（move_speed=50 → 0.40s）
   - 単純比較では新式のほうが速いはずなのに遅くなったのは不自然
   - 調査ポイント：
     - 旧 score と新 move_speed で保存値自体が異なる可能性
     - 生成経路の中間変換で move_speed が想定外の値になっている可能性
     - 実際の move_speed 値を DebugWindow または Config Editor で確認

2. **人間キャラが死にやすくなった**（Step 1-B 影響度：中）
   - 移動が遅くなった副次効果（敵接近で逃げきれない）の可能性
   - または独立した別要因
   - 項目 1 の切り分け結果を踏まえて判断

3. **防御ボタンを押して移動するときアニメーションしない**（Step 1-B 影響度：高）
   - `GUARD_MOVE_DURATION_WEIGHT = 2.0` によるガード中移動時間の倍化が歩行アニメ（walk1 → top → walk2 → top の 4 枚切替）と連動していない可能性
   - 旧 `MOVE_INTERVAL` 固定値に依存していたアニメ切替ロジックが `get_move_duration()` の動的値に追従できていない可能性
   - 調査ポイント：アニメ切替周期の算出が MOVE_INTERVAL 直参照だったか

4. **射程表示中に攻撃を受けるとキャンセルされる**（Step 1-B 影響度：低）
   - Step 1-B は移動系のみで攻撃フローは未変更
   - 2026-04-20 の「攻撃操作の 1 発 1 押下化」の残存バグの可能性が高い
   - 論点：被弾時キャンセルは仕様か否かの確認（CLAUDE.md 未記載）
     - TARGETING（時間停止中）では被弾しないはず
     - PRE_DELAY / PRE_DELAY_RELEASED（時間進行中）での被弾時の扱いが未定義

**調査の進め方（提案）**：
- 項目 1・3 を先に（Step 1-B 直接関連・必要ならロールバック検討）
- 項目 2 を項目 1 の切り分け後に（副次効果か別要因か）
- 項目 4 を独立タスクとして（攻撃フロー側の問題）

3. **Step 2：時間系定数の `GlobalConstants` 化**
   - `WAIT_DURATION` / `REEVAL_INTERVAL` / `AUTO_ITEM_INTERVAL` / `WARP_INTERVAL` / `FLAME_DURATION` 等を整理
   - **バグ修正**：`DarkLordUnitAI._warp_timer -= delta / game_speed` が逆方向（高速設定でボスが遅くなる）

4. **Step 3：`game_speed` 適用パターンの統一**
   - 現状 4 パターン混在（pre-scaled / post-scaled / 未適用 / 逆方向）
   - スタン・バフ・エネルギー回復・自動キャンセルの未適用を統一
   - 「全タイマーは `delta * game_speed` で減算する」を設計原則として明文化

5. **Step 4：向き変更コストの完全対称化**
   - 全局面で向き変更コストを発生させる（プレイヤーの通常移動のみコストありの非対称を解消）
   - `BASE_TURN_DURATION` を新設、`move_speed` で同様に補正（`BASE_TURN_DURATION × 50 / move_speed`）
   - ✅ dead code 整理は 2026-04-21 に完了：`character.gd` の `get_direction_multiplier` 関数を物理削除・`guard_facing` コメントを `facing を維持` に修正（詳細は [docs/history.md](docs/history.md) 参照）
   - TURN_DELAY 中の論理 facing 不一致（0.15 秒間旧向きのまま）を修正

6. **Step 5：近接攻撃範囲拡大**
   - 前方 5 マス化（正面 1 + 左右 1 + 斜め前 2）
   - 斜め前攻撃後の向きは維持、左右攻撃後は向きを変える（既存挙動を維持）
   - スプライトの 45° 回転で斜め前を表現するか試す

#### FLEE 実装の完了状況（2026-04-21 にステップ 1〜3 全て完了）

味方パーティーの FLEE は二段階ロジック（リーダー推奨出口 + メンバー自律選択）で動作する:

1. ✅ **ステップ 1 完了**：味方側 `_party_strategy` / `party_fleeing` 廃止（敵専用概念に統一）
2. ✅ **ステップ 2 完了**：NpcLeaderAI CRITICAL 時 `battle_policy` 自動書き換え（クールダウン `NPC_POLICY_CHANGE_COOLDOWN` で境界振動抑制）
3. ✅ **ステップ 3 完了**：FLEE 時の逃走先決定ロジック（`flee_recommended_goal` キー新設・脅威コスト付き A* + エリア BFS 距離の複合評価）

##### FLEE 派生課題（いずれも優先度：中）

次セッション以降の残課題。Phase 14 実プレイ検証とは独立して進められる（ただし優先度は実プレイ検証の方が高い）:

1. **敵パーティーへの FLEE 逃走先ロジック適用**
   - 現状：敵の `flee` は「脅威から 5 タイル離れる」旧実装（`_find_flee_goal_legacy`）のまま
   - 目標：味方と同じ二段階ロジックを敵にも適用
   - 避難先は敵種族ごとに異なる可能性（縄張り戻り / 階段逃走など）の設計検討が必要

2. **敵側の `_party_strategy` enum 直接配布（`party_fleeing` フラグ廃止）**
   - 現状：敵では `party_fleeing = (strategy == FLEE)` とブール化してメンバーに配布
   - 目標：enum 値そのものをメンバーに配布し、`party_fleeing` ブールフラグを廃止
   - メリット：(1) 情報量の減少を避ける、(2) 味方との対称性（味方は戦略を持たない・敵は戦略 enum を持つ）が明確に
   - 背景：味方側 `_party_strategy` 廃止作業（2026-04-21）の対称作業として残された

3. **味方クラスへの `keep_distance` 適用**
   - 現状：`keep_distance`（射程維持カイティング）は GoblinArcher / Salamander の敵種族専用
   - 目標：味方の弓使い・魔法使い（攻撃魔法）クラスにも適用
   - ATTACK 戦略中 + 敵接近時に自動発火させる形に拡張（種族 AI と同じ仕組みを共通化する方法を検討）

4. **個体アクションの実行ロジック差別化**
   - ✅ `fall_back` 差別化完了（2026-04-24 深夜・最終版）：FLEE の推奨出口計算結果を再利用し、メンバー層に `_is_far_enough_from_threats()` 射程外判定を追加。FLEE 実装は無変更。当初の候補タイル × A* 方式（560ms フリーズの原因）は全廃
   - 残課題：
     - `keep_distance`：射程内を保つ（遠ざかりすぎない・attack_range を参照）→ 味方クラスへの適用（派生課題 3）と合わせて対応・`flee_recommended_goal` の流用を視野
     - `flee`：ステップ 3 で避難先情報を使う形に既に実装済み（2026-04-21）
   - 背景：2026-04-21 にアクション名だけ分離した残作業。挙動も意味に合わせる方針

5. **戦況判断と避難先計算の関数統合**
   - 現状：`_evaluate_strategic_status()` と `_determine_flee_recommended_goal()` が別関数・別データ
   - 目標：避難先情報も戦況判断の一部として統合し、receive_order 経由で `combat_situation` 辞書に含める
   - 背景：リーダーが自律計算する情報は全て 1 箇所に集約するのが設計原則（2026-04-19 の `_evaluate_strategic_status()` 統合と同じ方針）

6. **`_find_friendly_retreat_goal` 関数の削除**（優先度：低・dead code）
   - ステップ 3 以降は味方 FLEE も `_find_flee_goal` の新ロジックを使うため、`_find_friendly_retreat_goal` は呼び出し元が無くなった

7. **敵パーティーの FLEE 避難先情報表示**（優先度：低）
   - 敵パーティーは避難先情報を保持しない（FLEE 実装が旧 legacy のみ）。敵への FLEE 新ロジック適用（派生課題 1）と同時に対応

#### 本日（2026-04-21）の調査で判明した残課題

PartyStatusWindow の表示改善の過程で判明したが、本日は対応しなかった課題群。Step 2 以降とは独立に、優先度低めで継続する。

1. **敵の UnitAI 指示フィールドの物理削除検討**（優先度：低）
   - 現状：`_combat` / `_battle_formation` / `_on_low_hp` / `_move_policy` / `_special_skill` / `_hp_potion` / `_sp_mp_potion` / `_item_pickup` の 8 項目は敵では Character デフォルト固定で実動に関与しない（本日の調査で確認・全項目 (A) / (B) / (C) のいずれかに分類）
   - 本日の対応：PartyStatusWindow の表示から消しただけで、コード上は `_assign_orders()` で敵にも渡している
   - 将来検討：`_assign_orders()` 側で敵には渡さないようにする設計見直し。ただし味方では有効なフィールドなので、安易な削除より `is_friendly` 分岐で早期リターンする等の整理が妥当
   - 詳細：[`docs/investigation_enemy_order_system.md`](docs/investigation_enemy_order_system.md) / [`docs/investigation_enemy_order_effective.md`](docs/investigation_enemy_order_effective.md)

2. **味方側の UnitAI 指示ラインの表示妥当性の再点検**（優先度：低）
   - 敵側で指示ライン（M / C / F / L / S / HP / E / I）を廃止した流れを受けて、味方側で表示している同フィールドも本当に全項目デバッグ価値があるか再検討したい
   - 特に `_hp_potion` / `_sp_mp_potion` / `_item_pickup` など「use / never」「aggressive / passive」等の単純な 2〜3 値フィールドは、見るメリットと画面占有コストのバランスが悪い可能性
   - 判断基準：ゲーム中に値が動的に変化するか。指示のまま固定なら画面占有するほどの価値はない
   - PartyStatusWindow の `_build_orders_field_list` の見直し候補

3. **`UnitAI.obedience` の状態変数扱いの再検討**（優先度：低）
   - 棚卸し調査で「`_init()` でサブクラス固定値を設定する事実上の定数」と判明（[`docs/investigation_debug_variables.md`](docs/investigation_debug_variables.md)）
   - 現状は var 扱いだが、デバッグ表示価値はほぼなし（値が変化しないので）
   - `const` 化するか、`character_data.obedience`（0.0〜1.0 の装備補正込み最終値）と統合するか要検討

4. **`PartyLeader.get_global_orders_hint()` 現状の再整理**（優先度：低）
   - 2026-04-21 に仮想ヒント合成（`match _party_strategy`）を物理削除済み。現在は `_global_orders.duplicate()` + combat_situation 付与のみ
   - 敵では `_global_orders` が常に空なので、実質的に「戦況判断の配信 API」になっている。命名 `get_global_orders_hint` が実態と乖離
   - 改名候補：`get_party_debug_hint()` / `get_combat_status_hint()` 等
   - 影響範囲：`party_status_window.gd` / `party_manager.gd` / `npc_leader_ai.gd`（override している）の 3 箇所

#### 並行して継続するタスク
- **フロア基準値（`FLOOR_*_RANK_THRESHOLD` / `FLOOR_RETREAT_RATIO`）の実プレイ調整**：装備 tier 戦力反映（2026-04-19）により同じ基準値でも降下しやすくなっている。DebugWindow の `F(R+T)s` 表示で観察
- **Phase 14 バランス調整**（CLAUDE.md「Phase 14 バランス調整の事前情報」参照）
- **残りの棚卸し候補**（CLAUDE.md「要調査・要整理項目」参照）：`PlayerController._spawn_heal_effect` の生死判定 / `hero.json` の整理 / `BUST_SRC_*` の比率化 / エフェクト線幅の GRID_SIZE 連動 / dark-lord のワープ・炎陣を SkillExecutor 経由へ / エフェクト生成の一系統化

## ジャンル・コンセプト
- 半リアルタイム進行（ターン制なし）。`world_time_running` フラグで AI タイマーを制御
  - プレイヤー行動中（移動・攻撃前後）：時間進行（AI・タイマーが動く）
  - プレイヤー待機中・ターゲット選択中・アイテムUI中：時間停止（AI・タイマーが止まる）
- 2Dグリッドマップ（将来的に自由移動へ拡張予定、次バージョン以降）
- 視点：トップビュー（キャラ画像1枚・GRID_SIZEサイズ・rotationで方向対応）

## キャラクター・パーティーシステム
- 主人公1人からスタートし、ダンジョン内でNPCと出会い仲間に加入
- プレイヤーは主人公または仲間の誰かを選んで直接操作
- 操作切替時：旧キャラはAIに切替、新キャラをプレイヤーが操作
- 非操作キャラはAIが自動行動
- 1パーティー構成（将来：複数パーティー連携を想定、設計は今から考慮）

## 仲間への指示システム
- 攻撃：近くの敵を積極的に攻撃
- 防衛：その場を守る・反撃中心
- 待機：動かない
- 追従：操作キャラのそばにいる
- 撤退：安全な場所に下がる

## 技術スタック
- エンジン：Godot 4.x
- 言語：GDScript
- 配布先：Steam（将来）

## アセット方針
- キャラクター画像：AI生成（プロトタイプは仮素材・差し替え前提）
- 配布前に商用利用可能な素材に差し替える
- 装備差分はSAM2で抽出、Godotでレイヤー合成（将来実装）
- 画風統一：イラスト調（アニメとリアルの中間）、ダークファンタジー寄り

### 画像フォーマット（Phase 6-0〜）
```
assets/images/characters/
  {class}_{sex}_{age}_{build}_{id}/
    top.png      (1024x1024, フィールド表示用・rotationで方向対応)
    walk1.png    (1024x1024, 歩行パターン1・左足を出した状態)
    walk2.png    (1024x1024, 歩行パターン2・右足を出した状態)
    ready.png    (1024x1024, 構えポーズ・ターゲット選択中・攻撃モーション中)
    guard.png    (1024x1024, ガード姿勢・X/Bホールド中。なければready.png→top.pngにフォールバック)
    front.png    (1024x1024, 全身正面・UI表示用)
    face.png     (256x256, frontから顔切り出し・左パネル表示用)

assets/images/enemies/
  {enemy_type}_{sex}_{age}_{build}_{id}/
    top.png / walk1.png / walk2.png / ready.png / front.png / face.png  （味方と同じ構成・walk1/walk2/guard.pngは省略可）
```
- 味方: class = fighter-sword, fighter-axe, archer, magician-fire, magician-water, healer, scout
  - ヒーラーは白系・魔法使い(水)は青〜水色系の画風（magician-fireの赤系・healerの白系と区別）
- 敵: enemy_type = goblin, goblin-archer, goblin-mage, hobgoblin, dark-knight, dark-mage, dark-priest, wolf, zombie, harpy, salamander, skeleton, skeleton-archer, lich, demon, dark-lord 等
- sex: male, female
- age: young, adult, elder
- build: slim, medium, muscular
- id: 01〜99
- view名にアンダーバー不使用
- 歩行アニメ: `walk1 → top → walk2 → top` の4枚ループ。walk1/walk2がない場合はtop固定（フォールバック）
- 攻撃アニメーション（attack1.png / attack2.png）は将来実装。当面は攻撃モーション中も ready → top の切り替えのまま
- 画像がない敵はJSONのフラットパス指定またはプレースホルダー色にフォールバック

### タイル画像フォーマット
```
assets/images/tiles/
  {category}_{id}/
    floor.png      (部屋の床タイル)
    wall.png       (壁タイル)
    obstacle.png   (障害物タイル。カテゴリに応じて瓦礫・溶岩溜まり等)
    corridor.png   (通路タイル。省略時はfloor.pngにフォールバック)
```
- category: stone, dirt, lava 等（当面は stone のみ）
- id: 5桁ゼロ埋め（00001〜99999）
- ダンジョンデータのフロアごとに tile_set を指定（未指定時は "stone_00001"）
- 旧 RUBBLE → OBSTACLE にリネーム（タイル種別定数・コメント等）
- 高解像度画像（1024x1024）は左上1/4を切り出して1セルに表示（_crop_single_tile）

## 使用アセットとライセンス
> **「アセット」の定義**：ここに掲載する対象は「ネット取得素材」「サードパーティ製シェーダー」など、Komuro 管理範囲外の外部成果物に限る。プロシージャル描画クラス（HitEffect / HealEffect / BuffEffect 等）や自作シェーダー（outline.gdshader）は自作コードなので対象外。

| アセット | 用途 | ライセンス | 帰属表示 |
|---------|------|-----------|---------|
| ~~Kenney Particle Pack~~ | ~~ヒットエフェクト（hit_01〜06.png）~~ | ~~CC0（パブリックドメイン）~~ | ~~不要~~ |
| ※上記は当初採用 → 2026 年中にプロシージャル描画の `HitEffect` に完全移行済み（画像は未使用） | | | |
| Kenney RPG Audio | slash / axe / dagger / arrow_shoot / room_enter / item_get | CC0（パブリックドメイン） | 不要 |
| Kenney Impact Sounds | hit_physical / hit_magic / take_damage / stairs | CC0（パブリックドメイン） | 不要 |
| Kenney Sci-fi Sounds | magic_shoot / flame_shoot / death | CC0（パブリックドメイン） | 不要 |
| Kenney Interface Sounds | heal | CC0（パブリックドメイン） | 不要 |

## 画像生成フロー
- 正面画像：Nano Banana（プロンプトテンプレートは work/prompt_template.md に保存）
- トップビュー変換：QIE（Qwen Image Edit）+ LoRA
- 背景除去：RemBG
- 将来の装備差分：SAM2で領域抽出 → Godotでレイヤー合成

## ファイル構成
- assets/master/characters/：味方キャラクターのマスターデータ（JSON）
- **assets/master/classes/**：クラスのマスターデータ（JSON）
  - 人間系 7 クラス：`fighter-sword.json` / `fighter-axe.json` / `archer.json` / `magician-fire.json` / `magician-water.json` / `healer.json` / `scout.json`
  - 敵固有 5 クラス：`zombie.json` / `wolf.json` / `salamander.json` / `harpy.json` / `dark-lord.json`
  - クラス JSON には `attack_type` / `attack_range` / `is_flying` / `slots.Z` / `slots.V`（pre_delay・post_delay・damage_mult・mp_cost 等）などの「クラスで決まる項目」を集約する
- assets/master/enemies/：敵個体ごとのマスターデータ（JSON、16 種）
  - **個体固有項目のみ**: `id` / `name` / `is_undead` / `is_flying` / `instant_death_immune` / `chase_range` / `territory_range` / `behavior_description` / `projectile_type` / `sprites`
  - クラス項目（`attack_type` / `pre_delay` / `post_delay` 等）は個別 JSON には持たない。クラス JSON から起動時に注入する
  - **数値ステータス（`hp` / `power` / `skill` / `physical_resistance` / `magic_resistance` / `rank`）は個別 JSON に持たない**（2026-04-19 物理削除済み）。`apply_enemy_stats()` が `enemy_list.json` の stat_type / rank / stat_bonus と `class_stats.json` / `enemy_class_stats.json` から算出する
- assets/master/enemies/enemies_list.json：読み込む敵ファイルのパス一覧
- assets/master/stats/class_stats.json：人間クラスのステータス定義
- assets/master/stats/enemy_class_stats.json：敵固有クラスのステータス定義
- assets/master/stats/attribute_stats.json：性別・年齢・体格の補正値・random_max
- assets/master/stats/enemy_list.json：敵 ID → `{stat_type, rank, stat_bonus}` のマッピング
- assets/master/maps/：マップデータ（JSON、マップごとにファイルを分ける）
- assets/master/names.json：名前ストック（性別ごと）
- assets/images/characters/：味方キャラクターの画像（{class}_{sex}_{age}_{build}_{id}/ フォルダ構成）
- assets/images/enemies/：敵キャラクターの画像
- assets/images/items/：アイテム画像（potion_heal.png, potion_energy.png 等）
- assets/images/effects/：エフェクト画像（飛翔体: arrow.png, fire_bullet.png 等 / 渦: whirlpool.png）
- JSONに画像ファイルパスを含めて一元管理
- work/：作業用ファイル置き場（コードから参照しない。AI生成の元画像・参考資料など）
- ※ work/ 配下はGodotのインポート対象外。フォルダ構成は自由に変更してよい

## マップデータ仕様
- タイルデータ（壁・床）、プレイヤーパーティー初期配置、敵パーティー初期配置をひとまとめに管理
- プレイヤー・敵ともにパーティー単位で配置情報を記述（将来の複数パーティー対応を考慮）
- マップにIDを付与して複数用意し、プレイヤーがゲーム開始時に選択できる形にする（将来実装）
- 同じマップを繰り返しプレイ可能（敵配置・装備補正値は固定）
- 将来：マップごとのクリア率・クリア時間などの統計を記録
```json
{
  "map_id": "dungeon_01",
  "width": 20,
  "height": 15,
  "tiles": [...],
  "player_parties": [
    {
      "party_id": 1,
      "members": [
        { "character_id": "hero", "x": 2, "y": 2 }
      ]
    }
  ],
  "enemy_parties": [
    {
      "party_id": 1,
      "members": [
        { "enemy_id": "goblin", "x": 10, "y": 5 },
        { "enemy_id": "goblin", "x": 11, "y": 5 },
        { "enemy_id": "goblin", "x": 10, "y": 6 }
      ]
    }
  ]
}
```

## グリッド・表示設定
- GRID_SIZEを定数で一元管理（GlobalConstants.gd / Autoload）
- 起動時に画面サイズから動的計算：`GRID_SIZE = viewport_height / TILES_VERTICAL`
- TILES_VERTICAL = 11（縦11タイル固定）→ 1920x1080時に約98px
- キャラクター表示サイズ：GRID_SIZE x GRID_SIZE（正方形。トップビュー用）
- ウィンドウサイズ：1920x1080（project.godot で設定）
- ウィンドウ設定：ボーダーレス（開発中はウィンドウモード、配布時にフルスクリーン予定）

## アニメーション仕様
- 判定・座標管理：グリッド単位（マス）で行う。衝突判定・攻撃当たり判定もすべてグリッド座標
- 表示：tween補間なし。1マス移動する間に `walk1 → top → walk2 → top` の4枚を順番に切り替えて表示
- 移動中のみアニメーション再生、静止中は top に戻る
- 攻撃アニメ：当面は ready（振り上げ）→ top（振り下ろし）の切り替え。将来 attack1/attack2 に差し替え予定

## キー操作・ゲームパッド対応（開発中）

基準：Xbox系コントローラー（Steam標準）。デバッグ機能（F1/F5など）はキーボードのみ。

### フィールド操作

| 操作 | キーボード | ゲームパッド | 備考 |
|------|-----------|-------------|------|
| 移動 | 矢印キー | 左スティック or 十字キー | |
| 攻撃（一発一押下：Z/A 押下 → 離して攻撃発動） | Z | A | クラスの攻撃タイプで近接/遠距離を自動切替。押している間は時間進行・離した瞬間に発動 |
| ガード（ホールド） | X | B | ホールド中ガード姿勢。正面攻撃のブロック量3倍・移動速度50%・向き固定 |
| アイテム選択UI（短押し） | C | X | 所持アイテム一覧を開く（使用/装備/渡す）。UI中は時間停止 |
| 特殊攻撃 | V | Y | Vスロット特殊攻撃（Phase 12-4で全クラス実装済み） |
| キャラクター切り替え | 未定 | LB / RB | パーティーメンバーを表示順で循環切り替え（通常時・パーティーリーダーが主人公のときのみ有効） |
| アイテムUI中のカーソル移動 | 矢印キー | LB / RB | アイテムUI中のみ有効（LBで前、RBで次） |
| ターゲット循環（TARGETING中） | 矢印キー | LB / RB | ターゲット選択中のみ有効 |
| 指示／ステータスウィンドウ | Tab | Select / Back | |
| ポーズメニュー開閉 | Esc | Start | |
| パーティー状態ウィンドウの表示/非表示 | F1 | — | 画面中央に PartyStatusWindow をトグル表示（パーティー状態）。F2 ログウィンドウが開いていたら自動で閉じる（相互排他）。ゲーム進行継続 |
| combat/ai ログウィンドウの表示/非表示 | F2 | — | 画面中央に CombatLogWindow をトグル表示（ログのみ）。F1 パーティー状態ウィンドウが開いていたら自動で閉じる（相互排他）。ゲーム進行継続 |
| PartyStatusWindow 詳細度トグル | F3 | — | 表示情報量を 3 段階で循環（高のみ → 高+中 → 高+中+低 → 高のみ…）。PartyStatusWindow 表示中のみ有効・セッション内のみ保持（再起動で「高のみ」にリセット） |
| ConfigEditor の表示/非表示 | F4 | — | 定数管理UI。タイトル画面・ゲーム中の両方で起動可。ゲーム中は時間停止 |
| パーティー強化（プレイヤー側） | F6 | — | プレイヤーパーティー全員をワンショット強化（開発用・トグル無し）。ランク S・統率 100・従順 1.0・HP/MP/SP × 10。ゲーム再起動でリセット。PartyStatusWindow 不要・どこでも有効 |
| PartyStatusWindow スナップショット | F7 | — | 現在の全パーティー状態を `res://logs/snapshot_<timestamp>.log` に個別ファイル出力（詳細度は常に最大・ウィンドウ非表示でも動作・ConfigEditor 開時は無効・`runtime.log` には押下マーカー 1 行のみ記録） |
| シーン再スタート | F5 | — | |
| ゲーム即時終了（開発用） | F12 | — | タイトル画面・ゲーム中の両方で有効。Alt+F4 の代替 |

### メニュー内共通操作

OrderWindow・サブメニュー・アイテム一覧・アクションメニュー・相手選択で共通。

| 操作 | キーボード | ゲームパッド |
|------|-----------|-------------|
| 項目選択 | 上下キー | 上下キー / 左スティック |
| 決定 | Z または 右キー | A または 右キー |
| 戻る | X または 左キー | B または 左キー |

- 全階層で左右キーが使える（右=決定、左=戻る）
- OrderWindowトップレベルで「戻る」を押すとウィンドウを閉じる（Tab/Selectと同じ）
- テーブル内の指示値切替（移動/隊形/戦闘/ターゲット/低HP/アイテム取得の各列）は左右キーで値を切替。「決定/戻る」は名前列・全体方針行・ログ行でのみ適用

### デバッグウィンドウ（PartyStatusWindow / CombatLogWindow）
2026-04-21 に旧 DebugWindow を上下 2 つの独立ウィンドウに分離した。F1・F2 は相互排他でトグル（両方同時表示は発生しない）。どちらも画面中央・**背景パネルなし・完全透過**・CanvasLayer layer=15。ゲームは進行継続（時間停止しない）。

**トグル動作（相互排他）**
- 何も表示されていない状態で F1 → 上段（PartyStatusWindow）のみ表示
- 何も表示されていない状態で F2 → 下段（CombatLogWindow）のみ表示
- 上段表示中に F2 → 下段のみ表示（上段は自動で閉じる）
- 下段表示中に F1 → 上段のみ表示（下段は自動で閉じる）
- 上段表示中に F1 → 全て閉じる
- 下段表示中に F2 → 全て閉じる

#### 上段：PartyStatusWindow（F1・`scripts/party_status_window.gd`）
- 現在フロアの全パーティー状態をリアルタイム表示（0.2秒ごとに更新）
- サイズ：画面幅 85% × 高さ 85%（中央配置・単独表示なので従来の 55% 上半分制約から解放）
- 表示対象：プレイヤーパーティー（青系）→ NPCパーティー（緑系）→ 敵パーティー（赤系）の順
- 表示条件: いずれか1人が表示フロアにいるパーティーを表示。別フロアのメンバーは名前頭に `[Fx]` を付加
- HP 比率で色分け（スプライト系パレット）：healthy=白 / wounded=黄 / injured=橙 / critical=赤
- **上下キーでリーダー行を循環選択**（PartyStatusWindow 表示中のみ有効・入力は伝播しない。敵・NPC・プレイヤーの全リーダーが対象）。下段単体表示中は上下キー無効
- 選択中リーダー行は黄色「▶」マーカーを行頭に表示
- リーダーを選択するとカメラがそのキャラを追跡（`leader_selected` シグナル → `game_map.set_debug_follow_target()`）
- F1 で閉じる／F2 で切替時は選択リセット・カメラは操作キャラの追跡に戻る
- `vision_system.debug_show_all` は PartyStatusWindow の可視状態と連動（上段表示中のみ未探索エリアも含めて全敵可視化）

##### 詳細度トグル（F3・3 段階循環）
- ウィンドウ表示中に F3 を押すたびにメンバー行の情報量が切り替わる：**高のみ → 高+中 → 高+中+低 → 高のみ…**
- セッション内のみ保持・ゲーム再起動で「高のみ」にリセット（永続化なし）
- 非表示時は F3 を無視
- 現在のステート表示は行わない（切り替えると表示内容が変わるので視覚的に判別可能）
- 変数と優先度のマッピングは `PartyStatusWindow.VAR_PRIORITY` 定数に一元管理（変数名→優先度レベル 0〜2）。新しい状態変数を追加・優先度を微調整するときはここだけ触る

##### レイアウト（2026-04-21 改訂：横一列流し）
パーティーブロック = **ヘッダー行 1 行** + **メンバー行 N 行（1 メンバー = 1 論理行・幅超過時のみ折返し）**。

改訂の要点：
- メンバー情報は**横一列に流す**レイアウトに変更。行動・指示・ステータスを 1 メンバー 1 論理行に集約し、幅超過時のみ自然に折り返す（旧：強制 1〜3 行/メンバーを廃止）
- リーダー行から**リーダー名・クラス名を除去**。クラス名は各メンバー行（`★名前[C](ヒーラー)` のように）に移動
- **敵パーティーも味方と同じ詳細度表示**（指示グループ・ステータスグループ）。ただし敵のヘッダーは `item=` を省略（敵は item_pickup 指示を持たないため）

**ヘッダー行（パーティー全体情報・常に 1 行）**

味方と敵で末尾のフィールドが異なる（2026-04-21 改訂）：

- **味方（プレイヤー・NPC）**：`[種別]  生存:x/y  戦況:xxx 戦力:F(R+T)s C(R+T)s E(R+T)s HP:xxx  mv=... battle=... tgt=... hp=... item=...`
  - `mv / battle / tgt / hp / item` は `_global_orders` の実値（プレイヤーは OrderWindow で変更可・NPC は自律判断）
  - NPC は `item=` を含む（プレイヤー経由の item_pickup 指示）。敵は `item=` なし（item_pickup 指示を持たないため）
- **敵**：`[種別]  生存:x/y  戦況:xxx 戦力:... HP:...  strategy=<ENUM>`
  - `strategy=` は `PartyLeader._party_strategy` の素値（`ATTACK` / `FLEE` / `WAIT` / `DEFEND` / `EXPLORE` / `GUARD_ROOM`）。日本語化せず enum 名のまま表示し「素の変数値」であることを視覚的に明示
  - 敵の行動は UnitAI 指示フィールドではなく、パーティー戦略 + 種族フック + ハードコード種族ロジックで決まる。味方と同じ `mv=... battle=...` 表示は誤解を招くため廃止（旧実装は `_party_strategy` から仮想ラベル合成 → 2026-04-21 削除）
- リーダー名・クラス名は載せない（識別は `[種別]` + 色分け + メンバー行の `★` / `(クラス)` で行う）
- 優先度「中」で追加：`re:0.8s 探索:5`（`_reeval_timer` / `_visited_areas` サイズ）
- 優先度「低」で追加（NPC パーティーのみ該当）：`合流:Y 拒絶:N 共闘:Y 回復:N 床固定`
- **FLEE 中の避難先情報**（2026-04-21 ステップ 3 の追加表示・味方パーティー限定）：
  - 通常：`避難先:<area_id>(d:<n>)@(<x>,<y>)` — `_flee_refuge_area_id` / `_flee_refuge_distance` / `_flee_recommended_goal` から合成
  - フォールバック時：`避難先:!fb@(<x>,<y>)` — 避難先エリア不明 or 選択出口から到達不能（`_flee_is_fallback == true`）
  - パーティー FLEE でないときは表示なし（既存ヘッダーの形を変えない）
  - 敵パーティーは FLEE 実装が別タスクのため現状は表示しない
- 関連調査：`docs/investigation_enemy_order_system.md` / `docs/investigation_enemy_order_effective.md`

**メンバー行（1 メンバー = 1 論理行。幅超過時のみ自然折返し）**

詳細度ごとに横一列に追加される情報群：

1. **行動ボディ**（常時・HP 色）：`[Fx]★名前[ランク](クラス) HP:x/y MP|SP:x/y mv=0.40s [ス][ガ]`
   - `(クラス)` は `CLASS_NAME_JP`（例：ヒーラー・剣士）。2026-04-21 にリーダー行から移動
   - `★` は `is_player_controlled`（操作中マーカー）
   - MP/SP は `CharacterData.is_magic_class()` でクラス分岐（`max_energy == 0` のキャラでは省略）
2. **目的**（常時・シアン）：` →攻撃Goblin[ATKp 0.34s q3]` のように `UnitAI._state` / `_timer` / `_queue.size()` を付加
3. **移動方針プレフィックス**（詳細度 >= 1・黄緑・**味方メンバーのみ**）：`  move:cluster`
   - 全体指示だが UnitAI で per-member に書き換えられうる唯一の項目（explore/guard_room モードでリーダー→`explore` / 非リーダー→`cluster` / 階段ナビ中→`stairs_down/up` に差し替え）のため、個別指示グループとは別枠で先頭に表示する
4. **指示グループ**（詳細度 >= 1・黄緑・**味方メンバーのみ**）：`  指示: T:same_as_ C:attack F:surround S:strong H:lowest_h`
   - 略号：T=target / C=combat / F=battle_formation / S=special_skill / H=heal（ヒーラー限定）
   - 個別指示（OrderWindow の MEMBER_COLS / HEALER_COLS で per-member に変更可能）のみを含む
   - 各フィールドは `_shorten()` で 8 文字以内に短縮（空文字列 / null は `-` に置換）
   - **2026-04-23 改訂**：全体指示（on_low_hp / hp_potion / sp_mp_potion / item_pickup）はヘッダー行と常に同値のため本グループから除外。move_policy は UnitAI で書き換えられるため別枠（項目 3）に移動
   - **2026-04-21 改訂**：敵メンバーでは本グループを出力しない。敵では全 8 項目が Character デフォルトから変化せず・または `is_friendly == false` ガードで参照されないため、表示しても意味がない（調査：`docs/investigation_enemy_order_system.md` / `docs/investigation_enemy_order_effective.md`）
4. **敵固有・動的判断グループ**（詳細度 >= 1・黄緑・**敵メンバーのみ**）※ 2026-04-21 追加：`  種: sflee nomp lich:水`
   - sflee=`_should_self_flee()` 戻り値 true（ゴブリン系が HP 30% 未満で動的判定）
   - nomp=`_can_attack()` 戻り値 false（魔法系の MP 不足で攻撃不可）
   - lich:水/火=`LichUnitAI._lich_water`（次攻撃の属性切替・攻撃ごとに反転）
   - 該当なしの場合は「種:」グループごと省略（味方では常に省略）
   - 背景：敵は OrderWindow 経由の指示を受けず、種族フックで独自判断する（詳細は `docs/investigation_enemy_order_system.md`）。味方の指示グループの代替表示として位置付ける
5. **状態グループ**（詳細度 >= 2・茶系）：`  状態: P↓ F↑ warp:1.2s`（UnitAI 側フラグが非空のときのみ）
   - P↓=party_fleeing / F↑=floor_following / warp:1.2s=DarkLord 次ワープ残秒
   - ※ lich:水/火 は 2026-04-21 に「敵固有・動的判断」として上のグループ 4 に移動
6. **12 ステータスグループ**（詳細度 >= 2・茶系）：`  pow:70+4 skl:45 rng:1 br:20+10 pr:5+8 mr:5 da:50 ld:5 ob:50 mv_s:50 fac:味方 leader`
   - 各ステータスは `abbr:base+bonus` 形式（装備補正が非 0 のとき）・または `abbr:base`（補正 0）
   - 素値と装備補正の**両方が 0** のフィールドは省略（クラス固有差分・例：弓使いは `br/bl` を持たないので省略）
7. **敵固有・静的属性グループ**（詳細度 >= 2・茶系・**敵メンバーのみ**）※ 2026-04-21 追加：` ignfle undead flying immune proj:fire chase:10 terr:50`
   - フック系（true のときのみ表示）：ignfle=`_should_ignore_flee()`（DarkKnight / Zombie 等 9 種族）
   - JSON 属性（true のときのみ表示）：undead=is_undead / flying=is_flying / immune=instant_death_immune
   - 文字列（非空のときのみ表示）：proj:{type}=projectile_type
   - 数値（敵なら常に表示）：chase:{n}=chase_range / terr:{n}=territory_range
   - 12 ステータスグループの直後に続けて表示（同じ茶系色・グループ間にダブルスペース挟まず流れる）

**実装面**：セグメント単位（行動ボディ / 目的 / 指示プレフィックス + 各フィールド / 種プレフィックス + 敵動的判断 / 状態プレフィックス + 各フラグ / 各ステータス部品 / 敵静的属性）でチャンク化し、行幅を超えたセグメント境界で自動折返しする。折返し後の継続行ではセグメント先頭の空白を削除して頭から描画する。

##### Character ステータス略称表（12 ステータス + fac/leader）
| 略称 | フィールド | 備考 |
|-----|-----------|------|
| `pow`  | `power` | 物理/魔法威力（クラス共通フィールド） |
| `skl`  | `skill` | 物理/魔法技量 |
| `rng`  | `attack_range` | 射程（タイル） |
| `br`   | `block_right_front` | 右手防御強度（正面・右側面で有効） |
| `bl`   | `block_left_front` | 左手防御強度（正面・左側面で有効） |
| `bf`   | `block_front` | 両手防御強度（正面のみ有効） |
| `pr`   | `physical_resistance` | 物理耐性の能力値（軽減率は逓減変換） |
| `mr`   | `magic_resistance` | 魔法耐性の能力値 |
| `da`   | `defense_accuracy` | 防御判定成功率（%） |
| `ld`   | `leadership` | 統率力（NPC 合流交渉） |
| `ob`   | `obedience` | 従順度（内部 0.0〜1.0 を ×100 表示） |
| `mv_s` | `move_speed` | 移動速度スコア（生値）。実効秒は行動ラインの `mv=...` で別表示 |
| `fac`  | `is_friendly` | 陣営（味方/敵）ラベル |
| `leader` | `is_leader` | リーダーフラグ（true 時のみ表示） |

##### 敵固有表示略称表（2026-04-21 追加・敵メンバーのみ表示）
| 略称 | フィールド / フック | 詳細度 | 表示条件 |
|-----|-----------------|-------|--------|
| `sflee`  | `UnitAI._should_self_flee()` | 中 | true 時のみ（ゴブリン系の HP 30% 未満） |
| `nomp`   | `UnitAI._can_attack()` | 中 | false 時のみ（魔法系の MP 不足） |
| `lich:水` / `lich:火` | `LichUnitAI._lich_water` | 中 | Lich のみ（常時） |
| `ignfle` | `UnitAI._should_ignore_flee()` | 低 | true 時のみ（DarkKnight / Zombie 等 9 種族） |
| `undead` | `character_data.is_undead` | 低 | true 時のみ（Skeleton / Skeleton-archer / Lich） |
| `flying` | `character_data.is_flying` | 低 | true 時のみ（Harpy / Demon / DarkLord） |
| `immune` | `character_data.instant_death_immune` | 低 | true 時のみ（ボス級） |
| `proj:{type}` | `character_data.projectile_type` | 低 | 非空のとき（例 `proj:thunder_bullet`） |
| `chase:{n}` | `character_data.chase_range` | 低 | 敵なら常に表示 |
| `terr:{n}`   | `character_data.territory_range` | 低 | 敵なら常に表示 |

##### 行数上限への配慮
「高のみ」モードなら現状と同程度（1 + 1×メンバー数 行/パーティー）で収まる。「高+中+低」モードで画面下端からあふれる場合は、単純に下端で打ち切る（スクロール未実装）。フロア 0 に全 NPC 12 パーティー同居する最悪ケースでは 1+3×平均メンバー数 × 12 = 画面上限近くなるので、必要なら後日「選択中リーダーのみ詳細展開」の二層表示を検討（別タスク）。

#### 下段：CombatLogWindow（F2・`scripts/combat_log_window.gd`）
- combat/ai ログ（最新50件・新着が下に追加）
- サイズ：画面幅 85% × 高さ 85%（中央配置）
- combat=黄色、ai=水色（MessageWindow と同じ色分け）
- `MessageLog.debug_log_added` シグナル経由で受信（エリアフィルタなし・全メッセージ表示）
- ログ蓄積はウィンドウの可視状態に関わらず常に行う（閉じていても最新50件は保持）

#### 共通
- MessageWindow には combat/ai メッセージは流れない（system/battle のみ表示）
- 旧「デバッグ情報コンソール出力（F2 → user://debug_floor_info.txt 書き出し）」は 2026-04-21 に機能ごと廃止した。代替は DebugLog Autoload（「デバッグ用ロガー（DebugLog）」節参照）。必要になれば DebugLog 経由で再実装する

#### F7 スナップショット（2026-04-21 追加・PartyStatusWindow と独立）
現在の全パーティー状態を `res://logs/snapshot_<timestamp>.log` に個別ファイルとして書き出すデバッグ補助機能。バランス調整・戦略切替の時系列記録・FLEE 発動の追跡などに使う。静止画スクリーンショットより情報密度の高い「状態スナップショット」を残すための機能。

- **トリガー**：F7 押下（`game_map.gd:_input` で受信）
- **ウィンドウ独立**：PartyStatusWindow の表示・非表示に関わらず動作（F1 閉じていても F7 だけで取得可能）
- **詳細度は常に最大**：F3 で画面が「高のみ」になっていても、スナップショットには「高+中+低」相当の全情報を出力する（画面の `_detail_level` には影響しない・終了時に復元）
- **ConfigEditor（F4）開時は無効**：誤動作防止
- **出力先（2 系統）**：
  1. **本体**：`res://logs/snapshot_YYYYMMDD_HHMMSS_mmm.log` を毎回新規作成（タイムスタンプはミリ秒まで含めて衝突回避・毎起動リセットしない・手動削除で履歴管理）
  2. **マーカー**：`res://logs/runtime.log` に `F7 snapshot → snapshot_<timestamp>.log` の 1 行を `DebugLog.log()` で記録（runtime.log から「いつ F7 を押したか」と対応ファイル名を辿れる）
- **出力内容（本体ファイル）**：
  - 区切り線 + ヘッダー部（時刻・フロア・操作キャラ・ゲーム速度）
  - プレイヤーパーティー → NPC パーティー → 敵パーティー（画面表示と同順序・同条件）
  - 各メンバーは 1 行にフラット化（画面では折返しあり・スナップショットは折返しなしで `|` 区切り）
  - 画面と同じ略称・同じ値（`_format_action_body` / `_build_orders_field_list` / `_build_char_stat_parts` 等を再利用）
- **ファイル整理方針**：snapshot ファイルは自動削除しない。大量にたまったら手動で削除する。将来「最新 N 件のみ保持」等の自動整理機構を追加する余地あり（今回スコープ外）
- **実装**：[`scripts/party_status_window.gd`](scripts/party_status_window.gd) の `snapshot_to_log()` が公開 API。`_build_snapshot_text()` → `_snapshot_player_party_lines()` / `_snapshot_party_block_lines()` / `_build_member_line()` で多行テキストを組み立て、`FileAccess.WRITE` で個別ファイルに書き出す

### メッセージ表記方針
- メッセージウィンドウに表示するバトルメッセージは**自然言語**で記述する（記号的表現を避ける）
  - 良い例：「○○がヒールポーションを使い、自身のHPを回復した」
  - 悪い例：「○○がヒールポーションを使った（HP+30）」
- 数値は原則として表示しない（ダメージ段階「小/中/大/特大」等の表現を使う）
- アイテム名は統一表記を使う：ヒールポーション / エナジーポーション（旧 MPポーション / SPポーションは energy 統合により「エナジーポーション」に一本化）
- **表示名の規則**（`Character._battle_name`）：
  - 味方（player / npc）：`character_data.character_name`（個別名。例：「ヘレン」）
  - 敵：`character_data.character_name`（個別敵 JSON の `name` = 種族名。例：「ホブゴブリン」「ゴブリン」）
  - どちらも同じ `character_name` フィールドを参照する（`CharacterData.load_from_json` が JSON の `name` から取り込む）
  - 敵にクラス日本語名（「斧戦士」等）は使わない（内部的な `class_id = stat_type` はあくまで挙動制御用。プレイヤー視点では種族名で統一）

### UI 用語の分離方針
プレイヤー向け UI と開発者向けコード・デバッグ表示で用語を意図的に分離している：
- **プレイヤー向け UI**：
  - リソースバー（左パネル）・ステータス表示（OrderWindow）：クラス種別で分岐（魔法クラス→「MP」/ 非魔法クラス→「SP」）
  - バトルメッセージ（キャラクター特定時）：同じくクラス種別で「MP を回復した」/「SP を回復した」に切替
  - アイテム名：「ヒール」「エナジー」のカタカナ
  - **アイテム効果の表記**：固定で「**MP/SP回復**」と両併記（ポーションを他メンバーに渡すこともあるため、閲覧中キャラのクラスで決め打ちしない）
  - **装備補正値の表記**（同じ原則）：アイテムが持つ全 stats キーを閲覧中キャラのクラスに関係なく表示する。例：archer が「守りの剣」を所持していても `[威力+10, 右手防御+20]` と両方表示する。渡し先で有効な補正値が見えなくなるのを防ぐ
  - **OrderWindow ステータス画面の防御強度 3 行**（右手／左手／両手）：常に全 3 行表示（キャラ素値・装備補正ともに 0 でも表示）。理由は同上
- **内部データ**：`energy` / `max_energy` / `restore_energy` / `heal_cost` / `v_slot_cost` 等の英語表記で統一（開発者向け）
- **デバッグ表示**（DebugWindow / Config Editor 等）：`energy` 表記のまま（プレイヤーには見えない）
- **「エネルギー」というカタカナ表記はプレイヤー UI では使わない**（`エナジー` はアイテム名のみ使用）
- コード内のコメント・docs は可読性優先で「エネルギー」を使ってよい（仕様書としての明確性）

### 指示／ステータスウィンドウ（OrderWindow）
- 専用ボタンでいつでも開閉可能（ポーズなし・時間進行継続）
- リーダー操作中：指示の変更可。非リーダー操作中：閲覧のみ（変更不可）
- テーブルの列構成：名前 / 移動 / 隊形 / 戦闘 / ターゲット / 低HP / アイテム取得
- 名前列で Z を押すとサブメニュー表示：操作切替 / アイテム
  - 操作切替：そのキャラを操作キャラにする（常時有効）
  - アイテム：そのキャラの所持アイテム一覧を表示（未装備品のみ。装備中品はステータス欄で確認）
    - アイテムを選んで Z → アクションメニュー：
      - 装備する：選択キャラのクラスで装備可能な場合のみ表示。上書き時、旧装備は未装備品として手元に残る。誰を操作中でも全メンバー変更可
      - 渡す → 渡す相手をメンバー一覧から選択：リーダー操作中のみ表示
      - スロットに割り当て：消耗品の場合（将来実装。Phase 10-3）
    - アイテムが0件の場合は「アイテムなし」と表示
- ステータス表示を2列化（縦幅を縮小）。素値・最終値の2列
- 最下行に「ログ」行を追加（「閉じる」行は廃止）
  - メンバー行にカーソル → 下部はステータス表示
  - ログ行にカーソル → 下部はメッセージログ表示（最新50件を保持）
  - ログ行で Z → スクロールモード（上下でスクロール、Esc/Z で戻る）
  - ログ閲覧中もゲーム進行はポーズしない
- 開発中は全ステータス項目を表示。配布前に再検討する

## アーキテクチャ方針
- キャラクターにPlayerController / AIControllerを差し替え可能な設計
- Partyクラスを最初から用意し、将来の複数パーティー連携に備える
- 仕様書はClaude Codeが作成・更新、人間が確認する運用

## 設計原則（2026-04-19 確立）
本日の大規模 legacy 一掃・データ構造整理を通じて確立された設計原則。今後の作業で迷ったときはここに立ち返る。

### コード衛生管理
- **「使っていないものは残さない」**：使われていない関数・定数・フィールドは物理削除する。コメントアウトや「将来のため」で残さない（残すなら理由と復活条件を明記）
- **段階的削除の流れ**：(1) 参照調査（grep で確認）→ (2) 分類（ブロッカー / 相互参照 / コメント言及 / dead）→ (3) レビュー → (4) 物理削除 → (5) docs 更新
- **legacy 互換フォールバック**：アセット側がクリーンならコード側も一掃する。アセット側で使われていない旧キーを「念のため」でコード側に残すのはアンチパターン

### データ管理（Source of Truth の一元化）
- **同じ情報を 2 箇所に持たない**：例：敵のステータスは `enemy_list.json` + class_stats から算出し、個別敵 JSON には持たせない
- **ルール / 個別データの分離**：ルール（全体方針）は Config Editor 可能に。個別データは Claude Code が生成。例：アイテムの base_stats（ルール）vs generated/*.json（個別データ）
- **JSON のキー保全**：編集時は `orig.duplicate(true)` で複製し、編集対象フィールドのみ上書き。他フィールドと登場順を保全

### 定数管理（Config Editor のカテゴリ分類）
- **ゲーム挙動・バランスに影響** → 担当クラス別カテゴリ（Character / PartyLeader / NpcLeaderAI / EnemyLeaderAI / UnitAI / SkillExecutor）
- **視覚演出・フィーリング調整** → Effect カテゴリ（ゲーム挙動に影響しない）
- **アイテム生成ルール** → Item カテゴリ
- 判断に迷うケース：ダメージ判定が演出と独立している値（PROJECTILE_SPEED 等）は Effect

### Config Editor の hidden フラグ
- **表示対象**：バランス調整中に触る可能性がある、または挙動を理解するために見えていたほうが良い定数
- **非表示対象**：一度決めたら触ることがほぼない定数（色定義、アイコンパス、UI レイアウト定数など）
- 非表示は「隠し項目も表示」チェックボックスで切り替え可能（薄いアルファでグレーアウト気味に表示）
- チェックボックスはセッション内のみ保持。Config Editor を開く度に OFF にリセットされ、ゲーム再起動時も必ず OFF で起動（誤操作防止）
- hidden フラグは `assets/master/config/constants_default.json` の各定数メタデータに `"hidden": true` を追加することで設定する。Config Editor からは変更不可
- 既設定済み：`CONDITION_COLOR_*`（スプライト/ゲージ/テキスト × 4 状態 = 12 個）

### 移動関連の二層構造（時間系ステータス）
移動・向き変更などの「時間系ステータス」は、**ベース値**（`GlobalConstants`）と**能力値ステータス**（`character_data`）の二層構造で管理する。`power` / `skill` / `hp` などダメージ・耐久系のように直接使用するのではなく、逆比例補正で実効値を算出する。

#### 算出式
```
実効値 = BASE × 50 / status
```
- 標準能力値 50 のキャラが取る実効値を「BASE」として GlobalConstants で定義
- 能力値（`move_speed` など）は 0-100 スケール。**高いほど速い**（大きいほど良い・直感的）
- 標準能力値 50 を基準とした逆比例補正で、能力値が 100 なら実効値半減（2 倍速）、25 なら 2 倍（半速）

#### 対象範囲
- 1 マス移動の時間：`BASE_MOVE_DURATION`（2026-04-20 導入・Character カテゴリ・`Character.get_move_duration()` で実効値化）
- 向き変更の時間：`BASE_TURN_DURATION`（仮称・Step 4 で導入予定）
- どちらも `move_speed` ステータスで補正（`turn_speed` ステータスは新設しない・移動速度に従う）

#### 設計判断
- **基準値 50 はハードコード**：設計の前提として扱い、Config Editor には出さない
- **下限クランプはハードコード**：実効値が小さくなりすぎないよう 0.10 秒等で打ち切る。これも調整対象外
- **適用範囲限定**：時間系ステータスのみ。`power` / `skill` / `hp` / 耐性などは従来どおり直接使用
- **`energy_recovery` は二層構造化しない**：現状の `ENERGY_RECOVERY_RATE`（全キャラ共通定数）のまま。個体差が必要になったら再検討
- **装備補正は将来検討**：現状 `move_speed` は装備補正の対象外。重装備で遅くなる等の追加余地あり

### アイテム生成
- **事前生成方式**：名前と補正値を一対一で固定する。同じ名前の装備は常に同じ stats（プレイヤーの記憶を助ける）
- **定数ベース総当たり**：2 ステータス × 3 段階 = 9 パターンを網羅（盾は 3 パターン）
- **フロア重み選択**：各フロアに基準段階を定め、距離重みで選択。境界フロアは隣接 2 帯の重みを合算
- **ルール変更時は手動再生成**：Config Editor でルール（base_stats）を変えても、個別データ（generated/\*.json）は自動更新しない。命名の整合性を保つため Claude Code に再生成を依頼する

### 画像サイズ（解像度追従）
- **GRID_SIZE は viewport から動的計算**：解像度が変わっても視野範囲（縦 11 タイル）は固定・GRID_SIZE が比例
- **画像元サイズを直書きで持たない**：(1) `tex.get_size()` で動的取得するか、(2) GRID_SIZE 比率として定義する
- アンチパターン：`SPRITE_REF_SIZE = 64.0`（固定 px）→ 高解像度で相対的に小さくなる。代わりに `GRID_SIZE × RATIO` を使う

### 命名制約
- **根拠はキャラ画像生成プロンプト**：武器・防具の命名（片手剣・両手弓・軽装服 等）は画像で決まる形状に合わせる。両手剣・サーベル・タワーシールド等は形状差異 NG
- **日本語・ダークファンタジー寄り**：漢字語彙で統一（カタカナ表記を避ける）。「ローブ」→「法衣」等
- **画像生成プロンプト変更時は命名も見直す**：将来プロンプトが変わる場合の依存関係を明記

### UI の表示原則
- **アイテム関連表示は閲覧キャラのクラスで絞らない**：他メンバーに渡す操作があるため、アイテムの全 stats / effect を常に表示する
- **stats 辞書は全キー反復**：固定キーリストでフィルタせず、将来の新ステータス追加に自動対応する

## パーティーシステムのアーキテクチャ

### 全体構造

```
PartyManager（パーティー管理。全パーティー種別で共通）
  ├── PartyLeader（リーダー意思決定の基底クラス）
  │     ├── PartyLeaderPlayer（プレイヤー操作パーティー用）
  │     └── PartyLeaderAI（AI自動判断）
  │           ├── EnemyLeaderAI（敵共通のデフォルト行動）
  │           │     ├── GoblinLeaderAI（種族固有の差分のみオーバーライド）
  │           │     ├── WolfLeaderAI
  │           │     ├── HobgoblinLeaderAI
  │           │     └── （将来の種族追加時もEnemyLeaderAIを継承）
  │           └── NpcLeaderAI（NPC固有のロジック）
  └── Character（味方・NPC・敵の全キャラクター共通）
        ├── PlayerController（プレイヤー操作時）
        └── UnitAI（AI操作時の個体行動。全パーティー種別で共通）
```

### PartyManager（管理層）
- パーティーのメンバーとリーダーを管理する
- `party_type`（`"enemy"` / `"npc"` / `"player"`）に応じてスポーン処理と PartyLeader サブクラスを切り替える
  - `"enemy"`: 敵JSONから読み込み → EnemyLeaderAI（種族別分岐）
  - `"npc"`: CharacterGeneratorでランダム生成 → NpcLeaderAI
  - `"player"`: スポーンなし（setup_adopted）→ PartyLeaderPlayer
- game_map からのデータ（friendly_list / enemy_list / floor_items / vision_system 等）を受け取り、PartyLeader に伝達する
- リーダー管理（初期設定またはリーダー死亡時に再選出）
- パーティー単位の情報共有・再評価通知
- 旧 NpcManager / EnemyManager の処理を統合済み（サブクラス不要）

### 戦略システムの設計原則（2026-04-21 確立）

`_party_strategy` / `party_fleeing` は**敵パーティー専用の概念**。味方（PartyLeaderPlayer / NpcLeaderAI）では使用しない。この原則は将来にわたって守る:

1. **`_party_strategy` は敵パーティー（EnemyLeaderAI 系）専用**
   - 味方側では計算・更新しない。基底 `_assign_orders()` は `_is_enemy_party()` ガードで味方では `_evaluate_party_strategy()` を呼ばない
   - 味方の戦略は `global_orders.battle_policy` を通じて**個別指示（combat / battle_formation 等）のプリセットとしてのみ**反映される（OrderWindow で書き換え・`_apply_battle_policy_preset` が各メンバーの `current_order` に流し込み）

2. **`party_fleeing` は敵メンバー専用の配布フラグ**
   - 基底 `_assign_orders()` は味方メンバーに対して `party_fleeing = false` 固定で配布
   - UnitAI 側の `_party_fleeing` 参照は味方では常に false・実質デッドパス（コード自体は敵用途で有効なので削除しない）
   - PartyStatusWindow のメンバー行 `P↓` フラグは敵メンバーのみ表示

3. **パーティー戦略はリーダー個人の属性ではない**
   - `_leader_ref._party_strategy` のようにメンバー側からリーダーの戦略 enum を取得する実装は禁止（**将来にわたって**）
   - 戦略情報を知りたい場合は：**敵なら `party_fleeing` フラグ**（receive_order 経由）／**味方なら `global_orders.battle_policy`**（Party 経由）を参照する

4. **探索モード・帰還モードはフック経由で分岐**
   - 基底 `_assign_orders()` の move 上書きは `_is_in_explore_mode()` / `_is_in_guard_room_mode()` フックで判定
   - 敵：`_party_strategy == EXPLORE / GUARD_ROOM` で判定（基底実装）
   - NPC：`_has_visible_enemy()` で explore を判定（NpcLeaderAI override・敵なし → 探索）
   - GUARD_ROOM は敵専用（縄張り概念は味方にない）

### PartyLeader（意思決定層の基底クラス）
- パーティー全体の戦略を決定し、各メンバーの UnitAI に指示を伝達する
- `_evaluate_strategic_status()`: 統合戦略評価ルーチン。戦力計算と戦況判断を 1 箇所に集約し、3 種類のメンバー集合で 1 度ずつ統計を算出する（重複計算なし）：
  - **full_party**：自パ全員（下層判定・絶対戦力用）
  - **nearby_allied**：自パ近接 + 同陣営他パ近接（戦況判断・味方連合）
  - **nearby_enemy**：近接敵（戦況判断）
  - 距離フィルタ：自パリーダーからマンハッタン `COALITION_RADIUS_TILES` マス以内（エリアベース `target_areas` 判定は廃止）
  - 敵の非対称設計：enemy パーティーは自軍戦力 = full_party（協力しない世界観）、味方 (player/npc) は nearby_allied（連合）
  - 戦力 = `(rank_sum + tier_sum × ITEM_TIER_STRENGTH_WEIGHT) × 平均HP充足率`
  - HP 率：自パ側は実 HP + ポーション、他パ・敵は condition ラベルから推定（敵ステータス直接参照禁止ルール準拠）
  - 結果は `_combat_situation` に格納・`_assign_orders()` → `receive_order()` でメンバーに伝達
- `_evaluate_party_strategy()`: 仮想メソッド。戦略決定（ATTACK / WAIT / FLEE / EXPLORE / GUARD_ROOM）。**敵系サブクラスのみ** override する（2026-04-21 以降）
- `_is_in_explore_mode()` / `_is_in_guard_room_mode()`: 仮想フック。`_assign_orders()` の move 上書き分岐用
- `_is_enemy_party()`: 先頭生存メンバーの `is_friendly` で判別
- `_select_target_for()`: 仮想メソッド。ターゲット選択。サブクラスがオーバーライドする
- `_assign_orders()`: 戦略に応じてメンバーの UnitAI に `receive_order()` で指示を伝達する（共通ロジック）
- `_apply_range_check()`: 縄張り・帰還判定（敵パーティーのみ適用。友好パーティーはスキップ）
- UnitAI の生成・管理（`_unit_ais` 辞書）

### PartyLeaderPlayer（プレイヤー操作パーティー用）
- PartyLeader を継承する。OrderWindow の指示（`global_orders`）でメンバーに個別指示を配布する
- **2026-04-21 改訂**：`_evaluate_party_strategy()` / `_party_strategy` は使わない（敵専用概念）
- 戦略系の挙動は `global_orders.battle_policy` の個別指示プリセット流し込み（`_apply_battle_policy_preset`）経由のみ。プレイヤーの指示は `party_fleeing` で上書きされない
- `_select_target_for()`: `global_orders.target` 設定に従う（nearest / weakest / same_as_leader / support）
- `_evaluate_strategic_status()` の結果を `receive_order()` でメンバーに渡す（AI操作メンバーの特殊攻撃判断等に使用）

### PartyLeaderAI（AI自動判断の基底クラス）
- PartyLeader を継承する。AI がパーティー全体の戦略を自動で判断する
- `_evaluate_party_strategy()`: デフォルト実装（WAIT を返す・基底と同じ）
- 再評価タイマーによる定期的な戦略再評価（1.5秒間隔）
- **2026-04-21 改訂後**：NpcLeaderAI はこの `_evaluate_party_strategy` を override しない（EnemyLeaderAI 系のみ戦略を持つ）

### EnemyLeaderAI（敵のデフォルト行動）
- PartyLeaderAI を継承する
- `_evaluate_party_strategy()` のデフォルト実装:
  - friendly（プレイヤー・NPC）が生存している → ATTACK
  - friendly がいない → WAIT
  - FLEE なし（デフォルトでは逃げない）
- `_select_target_for()` のデフォルト実装:
  - 最近傍の friendly を返す
- 種族固有の行動が不要な敵はEnemyLeaderAIをそのまま使用する

### 種族固有リーダーAI（EnemyLeaderAIを継承）
- EnemyLeaderAIを継承し、種族の特徴に応じた差分のみオーバーライドする
- 敵キャラクター一覧の自然言語の特徴（「臆病で逃げる」「狂暴で攻撃的」等）に基づいてClaude Codeが実装する
- 新しい敵種を追加する場合もEnemyLeaderAIを継承し、差分だけ実装する

### FLEE 時の逃走先決定ロジック（2026-04-21 ステップ 3 追加）

味方パーティーの FLEE 挙動は、二段階の協調ロジックで決定される。敵パーティーは現状スコープ外（旧 `_find_flee_goal_legacy`：脅威から 5 タイル離れる実装）。

#### 二段階構造

1. **リーダー層（戦略）**：パーティー全体の「推奨出口タイル」を決定 → 全メンバーに配布
   - `PartyLeader._update_flee_recommended_goal()` が `_assign_orders()` ごとに更新
   - `_determine_flee_recommended_goal()` が現エリアの全出口を評価し、最小コストの出口を選ぶ
   - 避難先：`MapData.get_refuge_area_ids(floor)` でフロア 0 = 安全部屋 / フロア 1 以降 = 上り階段エリア
   - 総合コスト = リーダー位置→出口の脅威コスト付き A* 到達コスト + 出口→避難先の BFS 距離 × `FLEE_AREA_DISTANCE_WEIGHT`
2. **メンバー層（戦術）**：各メンバーが自分の位置から全出口を評価し、リーダー推奨を軽いバイアスとして参照しつつ最適経路を選択
   - `UnitAI._find_flee_goal()` がメンバー自身の位置から各出口への脅威コスト付き A* 経路を計算
   - 推奨出口一致なら `bias = 0`、不一致なら `bias = FLEE_NON_RECOMMENDED_PENALTY`
   - 脅威コストが高ければ推奨に従わず別出口へ（統率と柔軟性の両立）

#### FLEE 種別と推奨バイアスの有無

- **パーティー FLEE**（味方 `battle_policy == "retreat"` / 敵 `_party_strategy == FLEE`）：リーダーが推奨出口を決定・全メンバーが推奨バイアス付きで選択（統率された集団逃走）
- **個体 FLEE**（`on_low_hp = "flee"` + 状態が `critical` でパーティーは平常時）：`_flee_recommended_goal == Vector2i(-1, -1)` で配布 → メンバーはバイアスなしで自律判断

#### 脅威コスト（`_calc_threat_cost`）

- 自分と対立陣営（`is_friendly != _member.is_friendly`）の生存キャラ・同フロアを対象
- 各敵について `max(0, FLEE_THREAT_RANGE - manhattan) × FLEE_THREAT_WEIGHT` を合計
- 敵ステータス直接参照禁止ルール準拠（位置と `is_friendly` のみ参照）

#### エリア変化時の即時再評価

- メンバーが現エリアから別エリアへ移動したら `UnitAI._notify_area_change_if_needed()` が発火
- リーダーの `on_member_area_changed()` を呼び、推奨出口を再計算 → 全メンバーに再配布
- `FLEE_REEVAL_MIN_INTERVAL`（既定 0.3 秒）で過剰再計算を抑制

#### 避難先到達後の挙動

- 避難先エリア（安全部屋 / 上り階段エリア）に到達したメンバーは `_is_in_refuge_area() == true` となり、`_generate_queue(strategy=FLEE)` は `{"action": "wait"}` を返す（FLEE 戦略中でも待機）

#### 関連定数（Config Editor UnitAI カテゴリ）

| 定数 | 既定値 | 説明 |
|---|---|---|
| `FLEE_THREAT_RANGE` | 5 | 敵から何マス以内を危険とみなすか |
| `FLEE_THREAT_WEIGHT` | 3.0 | 危険マス 1 つあたりのコスト加算量 |
| `FLEE_AREA_DISTANCE_WEIGHT` | 10.0 | 出口から避難先までの BFS 距離係数 |
| `FLEE_NON_RECOMMENDED_PENALTY` | 15.0 | 推奨外出口のペナルティ |
| `FLEE_REEVAL_MIN_INTERVAL` | 0.3 | エリア変化による再評価の最小インターバル（秒） |

#### MapData 側 API（2026-04-21 ステップ 3 追加）

- `get_refuge_area_ids(floor_id: int) -> Array[String]`：避難先エリア一覧（フロア 0 = 安全部屋群 / フロア 1 以降 = 上り階段エリア群）
- `get_area_distance(from_area_id: String, to_area_id: String) -> int`：エリア間の BFS 距離（到達不能 = -1・同一 = 0）
- `get_exit_tiles_from(area_id: String) -> Array[Vector2i]`：エリアの内側出口タイル一覧（4 近傍に別エリアがあるタイル）
- `get_adjacent_area_ids_of_exit(exit_tile: Vector2i) -> Array[String]`：出口タイルの向こう側エリア ID 一覧（複数可）

### NpcLeaderAI（NPC固有のロジック）
- PartyLeaderAI を継承する
- 自律的な探索・フロア移動判断・アイテム自動管理を行う
- **2026-04-21 改訂**：`_evaluate_party_strategy()` を廃止。戦略情報は保持しない
  - 敵検知は `_has_visible_enemy()` で単独判定（同フロア・訪問済みエリア内の敵）
  - 探索モードは `_is_in_explore_mode()` を override し `not _has_visible_enemy()` を返す（基底 `_assign_orders` の move 上書き分岐が発火）
- **2026-04-21（ステップ 2）**：戦況 CRITICAL / SAFE に応じて `_global_orders.battle_policy` を自動書き換え
  - `_evaluate_and_update_battle_policy()` が毎フレーム判定（安価な早期リターン）
  - CRITICAL（戦力比 < 0.5）→ `"retreat"` / SAFE（敵未検知）→ `"attack"`
  - 中間領域（DISADVANTAGE / EVEN / ADVANTAGE / OVERWHELMING）は現状維持（境界振動抑制）
  - クールダウン `GlobalConstants.NPC_POLICY_CHANGE_COOLDOWN`（3.0 秒）で短時間の連続切替を抑制
  - 書き換え時は基底 `apply_battle_policy_preset()` で個別指示プリセットを流し込み、`notify_situation_changed()` で即時伝達
  - 合流済みパーティー（`joined_to_player == true`）は対象外（プレイヤーが OrderWindow で手動管理）

### UnitAI（個体行動層）
- リーダーからの指示（`receive_order()`）で combat / on_low_hp / move / combat_situation 等を受け取る
- `_determine_effective_action()` で行動を最終決定する（ATTACK=0 / FLEE=1 / WAIT=2 / FALL_BACK=3 相当の int を算出）
  - 判定優先順位: パーティー撤退 → 種族自己逃走 → 種族攻撃可否 → 個別低HP → 戦況SAFE判定 → combat 方針
- 種族固有行動は以下のフックメソッドでオーバーライドする（旧 `_resolve_strategy()` を廃止）:
  - `_should_ignore_flee() -> bool`: FLEE / FALL_BACK を無視する種族（dark_knight 等）が true を返す
  - `_should_self_flee() -> bool`: 自己判断で逃走する種族（goblin 系: HP30%未満）が true を返す
  - `_can_attack() -> bool`: MP 不足等で攻撃不能な種族（mage 系）が false を返す
- ステートマシン・A*経路探索・アクションキュー管理
- 全パーティー種別で同じ UnitAI を使用する

#### 個体アクションの分類（2026-04-21 3 種分離）

UnitAI が生成・実行するキューアクションの意味論を分離し、PartyStatusWindow でのデバッグ性を向上させた。

| アクション | 日本語表示 | 発火条件 | 生成元 | 発生キャラ |
|---|---|---|---|---|
| `keep_distance` | 距離確保 | 射程維持のための戦術的後退（戦闘継続） | 種族 AI の `_generate_queue` override（ATTACK 戦略中に敵接近） | GoblinArcher / Salamander |
| `fall_back` | 後退 | 前線から下がる（戦闘継続・HP 低下時の選択肢） | 基底 `_generate_queue` の `strategy == _STRATEGY_FALL_BACK(3)` 分岐 | `on_low_hp = "fall_back"` 設定のメンバー（デフォルト・状態が `critical` 時） |
| `flee` | 逃走 | 戦闘から離脱する（パーティーから離れて安全な場所へ） | 基底 `_generate_queue` の `strategy == 1(FLEE)` 分岐（敵のみ）・味方は `move_to_explore` に変換 | `on_low_hp = "flee"` / `combat = "flee"` / 敵 `_party_strategy == FLEE` / ゴブリン系 HP < 30% 自己逃走 |

- **実行ロジック**（2026-04-24 深夜時点）：
  - `flee` → `_find_flee_goal()`（味方：リーダー推奨出口 + メンバー自律 A* / 敵：legacy 直線）
  - `fall_back` → `_find_fall_back_goal()`（味方：FLEE と同じ出口評価を共用する**軽量ラッパー** + 射程外判定 `_is_far_enough_from_threats()` で早期停止 / 敵：legacy 直線）
  - `keep_distance` → `_find_flee_goal()`（ゴブリンアーチャー等の現挙動維持。将来 attack_range 参照へ差別化予定）
- **fall_back の停止条件**：最近の脅威との距離 ≥ `attack_range + FALL_BACK_MARGIN`（既定 2）のとき停止。FLEE の `_is_in_refuge_area()` と対称の判定
- PartyStatusWindow の表示ラベル（`get_debug_goal_str`）は**別々に出し分け**：「距離確保」「後退」「逃走」
- 低詳細度の UnitAI フラグ行に `fb→(x,y)`（fall_back 推奨集合点・味方のみ）を追加表示。`flee→(x,y)` と並んでリーダー層の判断を可視化

#### `on_low_hp` の内部値リネーム（2026-04-21）

`on_low_hp` の選択肢「後退」の内部値を `"retreat"` → `"fall_back"` に変更。全体方針 `battle_policy = "retreat"`（撤退）との**内部名重複を解消**するため。UI 表示ラベル「後退」は変更なし。

- 選択肢：`"keep_fighting"` / `"fall_back"`（旧 `"retreat"`）/ `"flee"`
- デフォルト値：`"fall_back"`（`Character.current_order` / `Party.global_orders` / `UnitAI._on_low_hp` / `NpcLeaderAI` hint すべて更新済み）

### データの流れ

```
game_map
  └── PartyManager
        ├── PartyLeader（Player または AI）
        │     ├── _evaluate_strategic_status()  ← 統合戦力評価＋戦況判断（共通）
        │     ├── _evaluate_party_strategy()    ← 戦略決定（サブクラス固有）
        │     └── _assign_orders()              ← 指示伝達（共通）
        │           └── UnitAI.receive_order({
        │                 target, combat, on_low_hp, move,
        │                 battle_formation, leader, party_fleeing,
        │                 combat_situation, hp_potion, sp_mp_potion,
        │                 item_pickup
        │               })
        │                 └── _determine_effective_action() ← 行動最終決定
        └── Character
              ├── PlayerController（プレイヤー操作時）
              └── UnitAI（AI操作時。receive_order の内容から行動を決定）
```

### 実装状況

| クラス | ファイル | 状態 |
|--------|---------|------|
| PartyManager | `party_manager.gd` | ✅ 実装済み。party_type で敵/NPC/プレイヤーを統合管理。旧 NpcManager / EnemyManager を統合済み |
| PartyLeader | `party_leader.gd` | ✅ 実装済み。旧 PartyLeaderAI から共通ロジックを抽出 |
| PartyLeaderAI | `party_leader_ai.gd` | ✅ 実装済み。extends PartyLeader に変更済み |
| EnemyLeaderAI | `enemy_leader_ai.gd` | ✅ 実装済み。extends PartyLeaderAI |
| 種族固有AI | `goblin_leader_ai.gd` 等 | ✅ 実装済み。extends EnemyLeaderAI |
| NpcLeaderAI | `npc_leader_ai.gd` | ✅ 実装済み。extends PartyLeaderAI |
| PartyLeaderPlayer | `party_leader_player.gd` | ✅ 実装済み。hero_manager に接続済み（party_type="player" で PartyLeaderPlayer を生成） |
| `_evaluate_strategic_status()` | `party_leader.gd` | ✅ 実装済み（2026-04-19）。3 集合（full_party / nearby_allied / nearby_enemy）× 距離フィルタで戦力・戦況を一括算出する統合関数 |

## ゲームデザイン方針
- レベルアップなし。装備と仲間の強化が成長の主軸
- 武器はキャラ職業（クラス）に紐づく（剣士は剣のみなど）
- アイテムはフロア深度に応じた補正値でランダム生成。名前はClaude Codeがダンジョン生成時に作成（詳細は「アイテムシステム」節を参照）
- 敵リポップなし
- アイテム入手：過去の冒険者の装備をモンスターがため込んでいる設定
- ダンジョン攻略は国からの要請、複数パーティーが競争・協力して攻略
- 攻略成功で褒美・名誉が得られる

## クラスシステム

### クラス一覧
| クラス | ファイル名表記 | 武器タイプ | Z/A（攻撃） | 攻撃タイプ | V/Y（特殊攻撃） |
|--------|--------------|-----------|------------|----------|-----------------|
| 剣士 | fighter-sword | 剣 | 近接物理：斬撃 | melee | 突進斬り |
| 斧戦士 | fighter-axe | 斧 | 近接物理：振り下ろし | melee | 振り回し |
| 弓使い | archer | 弓 | 遠距離物理：速射 | ranged | ヘッドショット |
| 魔法使い(火) | magician-fire | 杖 | 遠距離魔法：火弾 | ranged | 炎陣 |
| 魔法使い(水) | magician-water | 杖 | 遠距離魔法：水弾 | ranged | 無力化水魔法 |
| ヒーラー | healer | 杖 | 支援：回復(単体・自己含む・全方向)／アンデッド特効 | heal | 防御バフ(単体・自己含む・全方向) |
| 斥候 | scout | ダガー | 近接物理：刺突 | melee | スライディング |

- 攻撃は Z/A の1ボタン。攻撃タイプ（melee/ranged）はクラスのスロット定義から自動判定
- スロット最大4（ZXCV）、ゲームパッド対応を考慮（X/B はガード）
- ヒーラーは通常の攻撃手段を持たない（支援専用）。ただし is_undead=true の敵はZ攻撃のターゲットに含めて魔法ダメージを与える（アンデッド特効）
  - 回復量の計算式：`heal_amount = power × Z_heal_mult`（`ATTACK_TYPE_MULT` 経由なし・耐性軽減なし）
  - アンデッドダメージの計算式：`base_damage = power × ATTACK_TYPE_MULT[magic] × Z_damage_mult`（他魔法クラスと同じフロー・`Z_damage_mult=2.0` で特効を表現）
  - アンデッド敵の `magic_resistance` が低めに設定されているため、倍率と合わせてさらに特効が強まる設計
- 将来拡張：魔法使いの属性分化（土・風）、支援系第2ジョブ、槍兵・飛翔系・両手武器系、状態異常回復（毒・麻痺実装後）
- スロット4枠を超えるスキルの管理方法（入替・キャラ別・系統別）は将来決定

### Vスロット特殊攻撃仕様
- **突進斬り（fighter-sword）**：向いている方向に最大2マス前進。経路上の敵全員にダメージ。次の空きマスに着地。壁・障害物で止まる。SP消費
  - AI発動条件（指示「強敵なら使う」等を満たした上で追加判定）：隣接8マスの敵が `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` 以上（近接3クラス専用）かつ 前方最大2マスに敵がいて着地可能な空きマスがある
- **振り回し（fighter-axe）**：周囲1マス（斜め含む隣接8マス）の敵全員に通常攻撃相当のダメージ。SP消費
  - AI発動条件：隣接8マスの敵が `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` 以上（近接3クラス専用）
- **ヘッドショット（archer）**：`instant_death_immune == false` の敵に即死。ボス級（`instant_death_immune == true`）には無効で通常の3倍ダメージ。SP消費大
- **炎陣（magician-fire）**：自分を中心に半径3マスに設置。設置直後から `slots.V.duration` 秒間燃え続け、`slots.V.tick_interval` 秒ごとにダメージ判定。敵のみ判定（巻き添えは将来課題）。MP消費大
  - AI発動条件（指示「強敵なら使う」等を満たした上で追加判定）：自分を中心に半径 `SPECIAL_ATTACK_FIRE_ZONE_RANGE` マス以内の敵が `SPECIAL_ATTACK_FIRE_ZONE_MIN_ENEMIES` 以上
- **無力化水魔法（magician-water）**：単体・射程あり・MP消費大。命中した対象の攻撃・移動を `slots.V.duration` 秒間完全停止（回転エフェクト）。全種族共通。被弾時ダメージは受けるが持続時間は変わらない。ボス級には持続時間を短縮（将来調整）
- **防御バフ（healer）**：単体・射程あり・MP消費（`buff_defense` アクション）。**自分自身も対象に含める・方向制限なし（全方向）**。`slots.V.duration` 秒間バフ状態。バフ中は半透明の緑色六角形バリアエフェクト（`BuffEffect.gd`）がキャラクターに重ねて表示される。バフ終了時に自動削除。重複付与時はタイマーリセット＋エフェクト再生成
- **スライディング（scout）**：向いている方向に3マス高速移動。移動中は無敵・敵をすり抜け可能。SP消費
  - AI発動条件：隣接8マスの敵が `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` 以上（近接3クラス専用・包囲脱出兼ダメージ）

#### Vスロット JSON パラメータ
- `slots.V.duration`：効果の持続秒数。無力化水魔法=スタン秒数、防御バフ=バフ秒数、炎陣=燃焼秒数（クラスごとに用途は異なるが、キーは統一）
- `slots.V.tick_interval`：継続ダメージ攻撃のダメージ判定間隔（秒）。現状は炎陣（magician-fire）のみで使用
- その他の用途固有パラメータは `slots.V` 直下の固有キーで表現（将来拡張）

#### 敵の V スロット発動方針
- **敵（`is_friendly=false`）は V スロット特殊攻撃を発動しない**。プレイヤー側の戦力分化を保つための設計判断
- 例：hobgoblin（`stat_type="fighter-axe"`）は振り回しを使わず、dark_priest（`stat_type="healer"`）は防御バフを使わない
- 実装：`UnitAI._generate_special_attack_queue()` と `_generate_buff_queue()` の冒頭で `_member.is_friendly == false` なら空配列を返す
- **例外**：dark-lord の炎陣は `_update_dark_lord_behavior()` によるキュー外処理のため、上記の抑止対象外（ボス専用演出として維持）
- ヒーラーの Z 行動（回復）や通常攻撃（Z スロット）は敵も使用可能

### 魔法使い（水）の仕様
- クラスID：`magician-water`
- 武器：杖 / 防具：ローブ / 盾：なし（`magician-fire` と同じ装備構成）
- 画風：青〜水色系（`magician-fire` の赤系・`healer` の白系と区別）
- Z/A：通常水弾（遠距離魔法・ダメージのみ）
- V/Y：無力化水魔法（上記Vスロット仕様参照）

## AI と実処理の責務分離方針

### 意思決定層と実処理層
- **意思決定層**（PartyLeader / UnitAI / PlayerController）
  - 「何をするか・誰を狙うか・いつ動くか」を決定する
  - ターゲット選択、行動タイミング、AI 判断（戦況評価等）
- **実処理層**（SkillExecutor〔未実装・推奨〕/ エフェクトクラス / Character）
  - 攻撃計算・ダメージ適用・エフェクト生成・位置変更
  - 計算式・ゲーム動作そのもの

### アーキテクチャの2系統（維持方針）
- **AI 側**（UnitAI）：キュー駆動
  - 時間ベース・事前にアクションシーケンスを構築
  - `_queue` に辞書形式のアクション（move / attack / heal / v_attack 等）を詰め、`_start_action` の match で分岐
- **Player 側**（PlayerController）：ステートマシン + 入力バッファ
  - イベント駆動・入力に応じて NORMAL → PRE_DELAY → TARGETING → POST_DELAY と遷移
  - 先行入力バッファ（`_move_buffer` / `_attack_buffer`）あり

この2系統は思想が異なるので、統一しない方針。Player は対話的（TARGETING 中のターゲット変更、X でキャンセル、ガードホールド等）で、キュー駆動は不向き。AI は思考サイクルの可視性のためにキュー駆動が適する。

### 実処理の共通化（完了）
Player と AI で同じ特殊行動（melee / ranged / heal / V 攻撃各種）の計算式が二重実装されていた問題を、SkillExecutor クラス（`scripts/skill_executor.gd`）への抽出で構造的に解消した。

**移行完了状況（2026-04-18）— 全10種類 ✅**:
- ✅ **heal（回復・アンデッド特効）** — ステージ1
- ✅ **melee / ranged（Z 通常攻撃）** — ステージ2
- ✅ **flame_circle / water_stun / buff（V 特殊攻撃・複雑3種）** — ステージ3a
- ✅ **rush / whirlwind / headshot / sliding（V 特殊攻撃・近接射撃4種）** — ステージ3b

Player 側は SkillExecutor を直接呼出（1 行ラッパ）。AI 側は `_synth_v_slot()` / `_synth_z_slot()` で CharacterData のフラットフィールドから slot 辞書を合成して渡す。移動アニメーション（rush / sliding）と攻撃モーションフラグ（whirlwind）だけは Player / AI でパラダイムが異なるため、SkillExecutor は着地位置算出・ダメージ適用・SE・メッセージまでを担い、実移動と `is_attacking` / `is_sliding` / `is_blocked` フラグは呼出側の責務として残す。

```
SkillExecutor（static メソッド群）
  ├── execute_melee(attacker, target, slot) -> void
  ├── execute_ranged(attacker, target, slot) -> void
  ├── execute_heal(caster, target, slot) -> void
  ├── execute_flame_circle(caster, map_node, slot) -> void
  ├── execute_water_stun(caster, target, slot) -> void
  ├── execute_buff(caster, target, slot) -> void
  ├── execute_rush(attacker, slot) -> void       （突進斬り）
  ├── execute_whirlwind(attacker, slot) -> void  （振り回し）
  ├── execute_headshot(attacker, target, slot) -> void
  └── execute_sliding(attacker, slot) -> void    （スライディング）
```

- 呼び出し側（UnitAI / PlayerController）は意思決定に専念し、ダメージ計算・エフェクト生成は SkillExecutor に委譲する
- slot 引数はクラス JSON の `slots.Z` / `slots.V` 辞書をそのまま渡す（`heal_mult` / `damage_mult` / `duration` / `tick_interval` / `cost` 等を参照）
- 乱数（クリティカル判定・命中判定）は SkillExecutor 内で解決する
- サウンド再生・メッセージログ出力もこの層で統一する（現状は UnitAI / PlayerController / Character に分散）

### エフェクト生成の方針（段階移行中）
- **現状**：視覚エフェクトの生成が 2 系統に分かれている
  - Character 経由で生成：`HitEffect` / `HealEffect` / `BuffEffect` / `WhirlpoolEffect` — それぞれ `Character._spawn_hit_effect` / `spawn_heal_effect` / `apply_defense_buff` / `apply_stun` が内包
  - SkillExecutor 内で直接 `.new()`：`FlameCircle`（1 箇所）/ `Projectile`（4 箇所）
  - `DiveEffect` は UnitAI 内に残留（dive は SkillExecutor 未移行のため）
- **将来方針**：エフェクト生成は SkillExecutor に集約する（または Character の薄いヘルパ経由で統一）。Projectile / FlameCircle のラッパを SkillExecutor に持たせるのが最短
- **未実装**。別タスクで段階的に移行する。現状でゲーム動作には影響なし

### 例外的実装（要整理）
- **dark-lord のワープ・炎陣**：キュー外で `_process` と並走（`UnitAI._update_dark_lord_behavior()` 相当）。通常のアクションキュー経由では時間粒度が合わないため分離されているが、SkillExecutor 導入時には JSON 駆動のスケジューラ化を検討する

### 設計原則
1. **計算ロジックの追加・変更は SkillExecutor に対して行う**（導入後）。UnitAI / PlayerController を個別に編集しない
2. **JSON 値（slot の heal_mult / damage_mult / duration 等）は必ず slot から読む**。ハードコード値を残さない
3. **Player / AI で同じスキルは同じ結果を返す**。テスト観点として「同一条件で同一ダメージ」を検証する
4. 新しいスキルを追加する場合、先に SkillExecutor に execute_XXX を実装し、UnitAI のキューアクションと PlayerController のステート遷移から呼び出す

### 参照
- `docs/investigation_class_structure.md` — クラス構成・役割分担の現状分析
- `docs/investigation_action_queue.md` — アクションキュー実装の詳細と移行難易度評価
- `docs/investigation_skill_executor_constants.md` — SkillExecutor で参照する定数・エフェクト実装の棚卸し

## キャラクター生成システム

- プレイヤー（主人公）含め全キャラクターがランダム生成
- グラフィック（画像セット）をあらかじめ複数用意。各セットに性別・年齢・体格・対応クラスが紐づく
- ゲーム開始時にグラフィックからランダム選出
- 名前は性別ごとのストック（assets/master/names.json）からランダム割り当て。グラフィックとは独立
- ランク（A/B/C）はグラフィックとは無関係にランダム割り当て（人間キャラクターは A 上限。S はダークロード等のボス専用）
- 当面は同一人種の人間のみ

### ステータス決定構造（味方・敵で共通）
```
最終値 = class_base + rank × class_rank_bonus + sex_bonus + age_bonus + build_bonus + randi() % (random_max + 1)
rank値: C=0, B=1, A=2, S=3
小数を含む場合は加算後に roundi() で整数化
```

- **味方・敵ともに同じ算出式を通る**（`CharacterGenerator._calc_stats()` が味方・敵の両方から呼ばれる）
- `attribute_stats.json`（sex / age / build の補正値と random_max）は**味方・敵で共用**
- 敵の sex / age / build は**画像フォルダ名から抽出**される（`apply_enemy_graphics()` が `enemy_type_{sex}_{age}_{build}_{id}/` 形式からパース）
- 味方と敵の違いは以下の **2 点のみ**：
  1. **ランク決定方法**：味方はランダム（`_random_rank_human()` で A〜C・S は生成しない）／敵は `enemy_list.json` で固定指定（C/B/A/S）
  2. **stat_bonus の有無**：敵のみ `enemy_list.json` の `stat_bonus` から個別補正（ステータス計算後に加算・100 クランプ）。味方は装備補正で個体差を表現（`equipped_*.stats` → `get_weapon_power_bonus()` 等のゲッター）のため、装備概念のない敵は `stat_bonus` で個体差を作る
- `character_data.stat_bonus` という**フィールドは存在しない**。敵用 `stat_bonus` は `apply_enemy_stats()` 内のローカル変数で処理後は破棄される。味方の装備補正と名前衝突なし
- すべての数値ステータス（vitality・energy・power・skill・physical_resistance・magic_resistance・defense_accuracy）は **0〜100 の範囲**に収まるよう設定
- 数値は設定ファイルで管理（`character_generator.gd` の `CLASS_STAT_BASES` 定数は廃止済み）

### ステータス設定ファイル
- **`assets/master/stats/class_stats.json`**：味方 7 クラスの base（ランクC時の基本値）と rank（1段階ごとの加算値）を定義
  - 対象ステータス: vitality / energy / power / skill / defense_accuracy / physical_resistance / magic_resistance / move_speed / leadership / obedience / block_right_front / block_left_front / block_front
- **`assets/master/stats/enemy_class_stats.json`**：敵固有 5 クラス（zombie / wolf / salamander / harpy / dark-lord）の base / rank を定義
  - 対象ステータス: vitality / energy / power / skill / defense_accuracy / physical_resistance / magic_resistance / move_speed / block_right_front / block_left_front / block_front
  - **leadership / obedience は定義しない**（仕様どおり）。敵 AI はこれらのステータスを参照しないため定義不要。敵の行動ロジックは従順度 100% 相当で動作する
- **`assets/master/stats/attribute_stats.json`**：性別・年齢・体格の補正値と各ステータスの random_max（0〜N の乱数幅）を定義。**味方・敵で共用**
- `CharacterGenerator._load_stat_configs()` が初回 `_calc_stats()` 呼び出し時に 3 ファイルをロードして静的キャッシュに保持。`class_stats` と `enemy_class_stats` は `_class_stats_cache` にマージされ、実行時は `stat_type` で一元引き可能

### vitality / energy の格納先
- `vitality`（0-100）→ `character_data.max_hp`（`hp` はゲーム開始時に `max_hp` で初期化）
- `energy`（0-100）→ 全クラス共通で `character_data.max_energy` に格納（`energy` はゲーム開始時に上限値で初期化）
- UI 表示は `CharacterData.is_magic_class()` で判定し、魔法クラスでは「MP」、非魔法クラスでは「SP」として表示する（内部データは同一）
- クラスJSON（`assets/master/classes/*.json`）の `"mp"` / `"max_sp"` フィールドは廃止（energy で代替・2026-04-18）

### move_speed の扱い（2026-04-20 Step 1-B〜）
- 0〜100 スコアで生成し、`character_data.move_speed` に**直接格納**（従来の事前変換は廃止）
- 実効値（1 マス移動の秒数）は `Character.get_move_duration()` が逆比例式で算出：
  ```
  duration = BASE_MOVE_DURATION × 50 / move_speed
  is_guarding なら × GUARD_MOVE_DURATION_WEIGHT（既定 2.0 = 50% 速度）
  下限 0.10 秒（ハードコード）
  ```
  - move_speed=25 → 0.80s/タイル（最遅）
  - move_speed=50 → 0.40s/タイル（標準・BASE_MOVE_DURATION そのもの）
  - move_speed=100 → 0.20s/タイル（最速）
- 呼出側は通常 `get_move_duration() / GlobalConstants.game_speed` で実時間に変換する（PlayerController の move_to duration 引数・UnitAI の `_get_move_interval()`）
- UnitAI 内の `_timer = get_move_duration()` は「ゲーム内秒」のまま（`delta * game_speed` で減算するため）

### obedience の変換
- 0〜100 の整数スコアで生成し `/ 100.0` で 0.0〜1.0 に変換して格納

| 要素 | 設定方法 | 方向性 |
|------|---------|--------|
| ランク（S〜C） | class_stats.json の rank × rank値（C=0, S=3） | クラスごとに rank 補正量を設定 |
| 性別（sex_bonus） | attribute_stats.json の sex セクション | 男性=威力・物理耐性高め、女性=技量・魔法耐性・統率力高め |
| 年齢（age_bonus） | attribute_stats.json の age セクション | 若年=威力・移動速度高め、壮年=バランス、老年=技量・魔法耐性高め |
| 体格（build_bonus） | attribute_stats.json の build セクション | 筋肉質=威力・物理耐性高め、細身=技量高め |
| ランダム（random_max） | attribute_stats.json の random_max セクション | ステータスごとに乱数幅を設定（0〜N） |

## NPC仕様

- ダンジョン内にNPCがパーティー単位で配置される
- 単独NPCも、スタート時から複数人でパーティーを組んでいるNPCもいる
- 行動生成は敵と同様にパーティー単位
- NPCは仲間に加入できる（加入の仕組みはPhase 6-2で実装予定）
- 加入形態：プレイヤーがリーダーのまま、相手パーティーを丸ごと引き入れる（1種類のみ）

### フロア間メンバー追従
- 移動方針が **`cluster` / `follow` / `same_room`** のメンバーは「リーダー追従系」とみなし、リーダーが別フロアに居る場合は `_generate_stair_queue(dir, ignore_visited=true)` で対応する階段を目指す
- `standby` / `explore` / `guard_room` はリーダーを追わない（自律行動を維持）
- 判定は `unit_ai.gd` の `_generate_move_queue()` 冒頭で行う（PartyLeader の `_assign_orders()` では move_policy を上書きしない）
- 合流済みパーティー（`joined_to_player=true`）は別途 `_generate_floor_follow_queue()` がヒーローを基準に追従する（`_generate_queue` 冒頭の早期分岐）

## ドキュメント運用
- CLAUDE.md：人間・AI共通の概要・方針・ゲーム仕様・フェーズ進捗サマリー。ここでの相談をもとに更新する
- docs/spec.md：AI管理用の詳細仕様・実装メモ。Claude Codeが作成・更新する
- docs/history.md：変更履歴・バグ修正記録。バグの原因と修正内容、設計変更の経緯、廃止した仕様の記録を残す

### CLAUDE.md のフェーズセクション記述ルール
- 完了済みPhaseは1〜2行のサマリーで「何を実現したか」をユーザー視点で書く（ファイル名や関数名は不要）
- 未完了Phaseは詳細を残してよい
- 実装の詳細（変更ファイル・関数名・内部ロジック）はspec.mdに書く
- バグ修正の詳細・設計変更の経緯・廃止した仕様の記録はhistory.mdに書く

### 新しいPhaseを完了したときの更新フロー
1. docs/spec.md に実装詳細を記録する
2. docs/history.md にバグ修正・設計変更・廃止仕様を記録する
3. CLAUDE.md のフェーズセクションに1〜2行のサマリーを追記する
4. CLAUDE.md の仕様セクション（フェーズセクション以外）に影響がある場合は該当箇所も更新する

## ツール運用
- claude.ai（チャット）：仕様の相談・設計の議論を行う。コードの実装・ファイルの編集は行わない
- Claude Code：CLAUDE.mdの更新・仕様書（docs/spec.md）の更新・GDScriptの実装・コミット/プッシュを行う
- 仕様相談はclaude.aiで行い、確定した仕様をもとに Claude Code が CLAUDE.md を更新してから実装する

## デバッグ用ロガー（DebugLog）
不具合調査のために Claude Code が一時的にログ出力を仕込むための仕組み。ゲームを実行 → ログファイルが書かれる → Claude Code がファイルを直接読んで解析する、という往復を想定する。問題解決後は DebugLog 呼び出しを削除する**使い捨て運用**（print デバッグと同じ感覚・ただし結果が残る）。

### 実装
- Autoload として登録（`scripts/logger.gd` / Autoload 名 `DebugLog`）
- API は 1 関数で開始：`DebugLog.log(message: String)`。将来タグ・レベル分けが必要になったら段階的に拡張
- 出力フォーマット：`[HH:MM:SS.mmm] メッセージ`
- 出力先（両方に出す）:
  1. Godot コンソール（`print`）
  2. `res://logs/runtime.log`（ファイル・プロジェクトルート配下の `logs/` フォルダ）
- ファイル仕様：毎起動でリセット（`FileAccess.WRITE`）・書き込みごとに `flush()`（クラッシュ時も直前行が残る）・Autoload 起動時にハンドルを開き `NOTIFICATION_WM_CLOSE_REQUEST` で明示クローズ
- `logs/` フォルダが存在しなければ `DirAccess.make_dir_recursive_absolute()` で自動作成
- `logs/` は `.gitignore` 済み（コミットしない）

### Autoload 名についての注意
当初は `Logger` という名前で Autoload を登録したが、Godot 4.6 には抽象クラス `Logger` が組み込まれており、`Logger.log(...)` の外部呼び出しが「`Static function "log()" not found in base GDScriptNativeClass`」エラーで失敗する問題があった。Autoload 名に `Logger` を使うと組み込みクラスと衝突して名前解決が壊れるため、`DebugLog` にリネームした。ファイル名は `logger.gd` のまま。

### 使用例
```gdscript
DebugLog.log("player hp=%d pos=%s" % [hero.hp, str(hero.grid_pos)])
DebugLog.log("stair enter floor=%d" % _current_floor_index)
```

### Phase 14（Steam 配布）に向けた TODO
`res://` への書き込みは**エディタ実行時のみ保証される**（Godot の仕様）。エクスポート後（Steam 配布ビルド）では `res://` は読み取り専用になるため、以下のいずれかの対応が必要：
- リリースビルドでは DebugLog 自体を無効化（`OS.has_feature("editor")` 等で分岐）
- 書き出し先を `user://` に切り替え

Phase 14 着手時に決定する。それまでの開発中は `res://logs/` への書き出しで運用。

## 定数管理（Config Editor）

ゲームバランス調整と定数の棚卸しを目的とした開発用UI。

### 起動
- F4キーで開閉（タイトル画面・ゲーム中の両方で動作）
- ゲーム中は他UI（OrderWindow / DebugWindow / PauseMenu / NpcDialogueWindow 等）が開いている時は F4 を無視
- 開いている間は時間停止（`world_time_running = false`）・閉じると元の状態に復帰

### ファイル構成
- `assets/master/config/constants.json` … ユーザー編集中の値（シンプル key:value）
- `assets/master/config/constants_default.json` … デフォルト値＋メタ情報（value / type / category / min / max / step / description）
- 定数は Character / PartyLeader / NpcLeaderAI / EnemyLeaderAI / UnitAI / SkillExecutor / Effect / Item の各タブに配置。NpcLeaderAI タブは 7 定数（`FLOOR_0_RANK_THRESHOLD`〜`FLOOR_4_RANK_THRESHOLD` / `FLOOR_RETREAT_RATIO` / `NPC_POLICY_CHANGE_COOLDOWN`）。UnitAI タブに FLEE 系 5 定数（`FLEE_THREAT_RANGE` / `FLEE_THREAT_WEIGHT` / `FLEE_AREA_DISTANCE_WEIGHT` / `FLEE_NON_RECOMMENDED_PENALTY` / `FLEE_REEVAL_MIN_INTERVAL`）が 2026-04-21 ステップ 3 で追加。未登録の定数が見つかった場合は運用ルール 1〜5 に従って追加する

### カテゴリ分類の原則
新しい定数をどのカテゴリに所属させるかは、**ゲーム挙動・バランスへの影響の有無**で判断する：

- **Character / PartyLeader / NpcLeaderAI / EnemyLeaderAI / UnitAI / SkillExecutor** → ゲーム挙動・バランスに影響する定数（HP 閾値・戦況判定比率・攻撃倍率・クリティカル率など）。担当クラスに応じて振り分け
- **Effect** → 視覚演出・フィーリング調整用の定数（ゲーム挙動に影響しない）。エフェクトの時間・サイズ・回転速度、操作感（TURN_DELAY 等）、飛翔体の表示速度・サイズなど。調整してもゲームバランスは変わらない

判断に迷うケース：**ダメージ判定が演出と独立しているもの**（例：PROJECTILE_SPEED は飛翔体が到着するより先に命中判定が確定しているため演出専用）は Effect。反対に、判定そのものに影響する値（例：CRITICAL_RATE_DIVISOR）は SkillExecutor 等の該当カテゴリ。

### トップレベルタブ
表示順（フラット 8 タブ）：`定数 | 味方クラス | 味方ステータス | 属性補正 | 敵一覧 | 敵クラス | 敵ステータス | アイテム`。味方系ブロック → 共通ルール（属性補正）→ 敵系ブロック → アイテムの流れ。
- **定数** — `constants.json` / `constants_default.json` を編集
- **味方クラス** — `assets/master/classes/` の人間系 7 ファイルを横断表で編集
- **味方ステータス** — `assets/master/stats/class_stats.json` を編集（味方 7 クラスの base / rank）。タブ名は UI 簡潔化のため「味方ステータス」と短縮表記だが、内部データとしては「味方クラスステータス」を指す
- **属性補正** — `assets/master/stats/attribute_stats.json` を編集（sex / age / build の補正値と random_max）。**味方・敵で共用のルール**のため、味方系と敵系の橋渡し位置に配置
- **敵一覧** — `enemy_list.json`（16 敵の stat_type / rank / stat_bonus）と個別敵 JSON のフィールド（name / is_undead / is_flying / instant_death_immune / behavior_description / chase_range / territory_range / projectile_type）を一括編集
- **敵クラス** — `assets/master/classes/` の敵固有 5 ファイル（zombie / wolf / salamander / harpy / dark-lord）を横断表で編集（味方クラスタブと同構造・同描画ロジックを流用）
- **敵ステータス** — `assets/master/stats/enemy_class_stats.json` を編集（敵固有 5 クラスの base / rank）。タブ名は UI 簡潔化のため「敵ステータス」と短縮表記だが、内部データとしては「敵クラスステータス」を指す。味方ステータスタブと同じ描画関数（`_build_class_stats_tab`）を流用し、対象 JSON パスと対象クラス ID 配列だけ差し替え。**leadership / obedience は敵クラス定義に存在しないため表示されない**（先頭クラスのキー順を行順として採用するため自然に除外される）
- **アイテム** — `assets/master/items/*.json` の `base_stats`（各アイテムタイプの補正ステータスルール）を編集。**1 行 1 タイプ形式**の横断表（9 行・敵一覧タブと同じ UI パターン）。各行は「タイプ名 / スロット 1〜4（OptionButton + max）/ 参考情報（category と allowed_classes）」で構成。保存完了後に「個別アイテム（generated/\*.json）は自動更新されない・Claude Code に再生成依頼」の告知ダイアログを表示

### 「定数」タブのカテゴリ
コード上のクラス名・用途で分類：

- Character / PartyLeader / NpcLeaderAI / EnemyLeaderAI / UnitAI / SkillExecutor / **Effect** / **Item** / Unknown（未分類検出用）
- タブ順は陣営・階層順（上位概念 → 下位概念）：リーダー層（PartyLeader → NpcLeaderAI → EnemyLeaderAI）→ 個体層（UnitAI）→ 実処理層（SkillExecutor）→ 視覚演出（Effect）→ アイテム生成方針（Item）
- **Effect カテゴリ**（2026-04-19〜）：視覚演出・操作感・視認性に影響する定数。エフェクトクラス（BuffEffect / WhirlpoolEffect 等）や操作系（TURN_DELAY / AUTO_CANCEL_FLASH / SLIDING_STEP_DUR / OUTLINE_WIDTH_* / TARGETED_MODULATE_STRENGTH / *_ROT_SPEED_DEG など）。バランスではなくフィーリング調整用
- **Item カテゴリ**（2026-04-19〜）：アイテム事前生成セットの選択方針と初期装備パラメータを制御する 11 定数。
  - bonus 比率 3 個：`ITEM_BONUS_LOW/MID/HIGH_RATIO`（各 bonus 段階の補正値比率・対 `_max`）
  - フロア基準 tier 3 個：`FLOOR_X_Y_BASE_TIER`（SpinBox・`0=none, 1=low, 2=mid, 3=high`）
  - 距離別重み 3 個：`FLOOR_BASE/NEIGHBOR/FAR_WEIGHT`
  - tier 導出 policy：`ITEM_TIER_POLICY`（OptionButton で "max"/"min"/"avg" 選択）
  - 初期ポーション個数 2 個：`INITIAL_POTION_HEAL_COUNT` / `INITIAL_POTION_ENERGY_COUNT`（全キャラ共通・再起動で反映）
  - 個別アイテムの編集はトップレベル「アイテム」タブで扱う（`base_stats` のルール編集）

タブ順は `config_editor.gd` の `TABS` 配列で定義。追加したい場合は配列末尾に追記する。

### 「味方クラス」「敵クラス」タブ
- **味方クラス**：7 クラス（fighter-sword / fighter-axe / archer / magician-fire / magician-water / healer / scout）を横に並べた横断表
- **敵クラス**：5 敵固有クラス（zombie / wolf / salamander / harpy / dark-lord）を横に並べた横断表。味方クラスタブと同構造・同描画関数（`_build_class_tab_common` / `_build_class_grid`）を流用し、対象クラス ID 配列だけ差し替え

### 「敵一覧」タブ
- 行 = 16 敵、列 = 敵ID（固定ラベル）/ **name** / rank / stat_type / is_undead / is_flying / instant_death_immune / behavior_description / chase_range / territory_range / **projectile_type** / stat_bonus × 6 枠
- **rank / stat_type / projectile_type / stat_bonus キー**は `OptionButton`（ドロップダウン）、**bool 3 フィールド**は `CheckBox`、**文字列・数値**（name / behavior_description / chase_range / territory_range）は `LineEdit`
- **name**：個別敵 JSON の `name` フィールド。プレイヤー向けの表示名（戦闘メッセージ・UI 等）。基本的に種族名の日本語表記（例：「ゴブリン」「ホブゴブリン」）。`Character._battle_name()` が参照する source of truth
- **projectile_type**：`""`（空文字列）= attack_type から自動判定、`"thunder_bullet"` = 雷弾（demon のみ）。UI 上は空文字列を "(自動)" と表示する（`PROJECTILE_TYPE_AUTO_LABEL`）。新しい弾種を追加した場合は `ENEMY_PROJECTILE_CHOICES` 配列に追記する
- stat_bonus は 6 枠（`ENEMY_STAT_BONUS_SLOTS`）。各枠はキー OptionButton ＋ 値 LineEdit の横並び。`---` 選択時は値編集欄を無効化
- 起動時に既存 stat_bonus を 6 枠の先頭から展開。保存時に `---` 以外の枠を辞書化して書き戻し
- **保存は 2 つのファイル系統に分かれる**：`enemy_list.json`（rank / stat_type / stat_bonus 用）と個別敵 JSON 16 ファイル（name / projectile_type / bool 3 / behavior_description / chase_range / territory_range）。dirty なファイルのみ書き戻し
- 個別敵 JSON への書き戻しは **元 JSON のフィールド有無を尊重**：元にあったフィールドは更新、元になかったフィールドはデフォルト値から変化した場合のみ追加（legacy フィールドの構造を壊さない）
- 新ステータス・新敵の追加は Config Editor の守備範囲外（コード変更を伴うため）
- **意図的に「敵一覧」タブで編集対象外としているフィールド**（個別敵 JSON にあるが表示しない）：
  - `id` — 識別子（Label として既に表示）
  - `sprites` — 画像パスの辞書構造。専用のアセット管理が必要で Config Editor の守備範囲外
- **2026-04-19 に物理削除した legacy フィールド**（個別敵 JSON から全 16 ファイル削除済み・コード側の読み込みも `CharacterData.load_from_json` から削除済み）：`hp` / `power` / `skill` / `physical_resistance` / `magic_resistance` / `rank`。これらは `apply_enemy_stats()` が `enemy_list.json` と `class_stats.json` / `enemy_class_stats.json` から毎回算出する仕組みのため、個別 JSON に持つ必要がなかった
- ネストされた `slots.Z.*` / `slots.V.*` は `Z_*` / `V_*` に平坦化して行に表示（保存時に元の階層へ戻す）。`slots.X` / `slots.C` は表示せず、保存時にそのまま維持
- パラメータのグループ分け（`CLASS_PARAM_GROUPS` 配列）：基本 / リソース / 特性 / Zスロット / Vスロット / その他
- 各セルは LineEdit（文字列入力）。保存時に元 JSON の値の型（int / float / bool / string）に合わせて変換。変換失敗時は保存を中止しエラー表示
- 変更されたセルは薄黄色ハイライト、変更があったファイルのみ書き戻す
- 「すべてデフォルトに戻す」「現在値をすべてデフォルト化」は**無効化**（デフォルト値を保持しない方針。復帰は git 履歴で管理）

### 操作
- 各定数を SpinBox（数値）または ColorPicker（色）で編集
- デフォルトと異なる行は背景薄黄色、そのタブ名末尾に `●` 付記
- 下部3ボタン：保存 / すべてデフォルトに戻す / 現在値をすべてデフォルト化
- 破壊的操作（リセット・デフォルト化）は確認ダイアログあり
- タブ切替：マウス、または Ctrl+Tab / Ctrl+Shift+Tab / Ctrl+PageUp / Ctrl+PageDown

### 反映
- 「保存」→ `constants.json` に書き込み → **ゲーム再起動で反映**（即時反映はしない方針）

### 定数追加時の運用ルール（「定数」タブ）
1. `GlobalConstants.gd` に `const`/`var` を追加するときは、`constants_default.json` にも同時に追加する
2. `category` フィールドは既存8タブ（Character / PartyLeader / NpcLeaderAI / EnemyLeaderAI / UnitAI / SkillExecutor / Effect / Item）のいずれかを指定
3. 上記7タブに属さない場合は `config_editor.gd` の `TABS` 配列にタブを追加することを検討
4. カテゴリ未定義・不明な値の定数は Unknown タブに自動振り分け（起動時に push_warning で警告）
5. 定期的に Claude Code に「外出しされていない定数」の棚卸し指示を出す
   - チェック観点：GlobalConstants 内に直書きされ `constants_default.json` に未登録の定数がないか

### 「味方クラス」編集時の運用ルール
1. クラス JSON に新パラメータを追加するときは、`config_editor.gd` の `CLASS_PARAM_GROUPS` の適切なグループにも追加する
2. 追加し忘れた場合は「その他」グループに自動集約されるため、起動時の push_warning で気付ける
3. Config Editor で編集した結果は `assets/master/classes/*.json` に直接書き戻されるので、そのまま git commit すれば差分管理できる

### 「味方ステータス」「敵ステータス」「属性補正」編集時の運用ルール
1. Config Editor は**既存ステータスの値編集のみ**。新ステータス追加・新クラス追加はコード変更（CharacterData / 生成ロジック等）を伴うので別タスクで実施
2. クラスステータス（味方ステータス / 敵ステータス）は「base / rank」を 2 つの LineEdit 横並びで編集。属性補正は 1 LineEdit / セル
3. 3 ファイル（`class_stats.json` / `enemy_class_stats.json` / `attribute_stats.json`）のクラス順・ステータス順は元 JSON のキー順を保持（`sort_keys=false`）
4. 味方ステータス・敵ステータスは同じ描画関数（`_build_class_stats_tab`）を共有し、対象 JSON パス・対象クラス ID 配列・source_id（"ally" / "enemy"）を引数で切り替え。保存・dirty 判定も source_id でフィルタする（味方を保存しても敵のハイライトは残る）
5. 敵ステータスタブに leadership / obedience が表示されないのは仕様どおり（敵クラス定義にこれらのキーが存在しないため）。敵 AI はこれらを参照しないため、敵の行動は従順度 100% 相当で動作する

### 「アイテム」タブ（2026-04-19〜）
- **目的**：各アイテムタイプが**どのステータスをどの範囲で補正するか**のルール（base_stats）を編集する。個別アイテム（`generated/*.json`）は編集対象外
- **UI 形式**：**1 行 1 タイプの横断表**（敵一覧タブと同じパターン）。9 行（sword / axe / dagger / bow / staff / armor_plate / armor_cloth / armor_robe / shield）。消耗品（potion_heal / potion_energy）は対象外
- **各行の列構成**：
  - タイプ名（Label）
  - スロット × 4 枠：それぞれ OptionButton（`---` または 13 ステータス）＋ max の LineEdit（`---` 選択時は無効化）
  - 参考情報（Label・編集不可）：`category / allowed_classes` を小さく表示
- **2026-04-19 に legacy 削除**：`{stat}_min` / `depth_scale` は現行生成仕様（`_max × tier_ratio`）で未参照のため物理削除。旧 UI にあった depth_scale 列と min 列は撤去済み
- **スロット 4 枠は仕様上の上限**、通常は 2〜3 までの運用を想定
  - 理由：登録数 N に対し、生成される組み合わせは `C(N, 2) × 9` パターン（N=2 で 9, N=3 で 27, N=4 で 54）
  - 同時補正数は**最大 2**（個別アイテム生成ロジック側の仕様・今回のスコープ外）
- **保存時の動作**：
  - dirty なサブタブのみ書き戻し（`assets/master/items/{item_type}.json` の `base_stats` を更新）
  - 他フィールド（`item_type` / `category` / `allowed_classes` / `depth_scale` / `effect` / `image` / `name`）は `orig.duplicate(true)` で保全
  - 保存成功時のみ「Claude Code に再生成を依頼」の告知ダイアログを表示
- **個別アイテムは自動更新しない**：命名の整合性を保つため、ルール変更時に `generated/*.json` の自動再生成はしない。Komuro が Claude Code に明示的に再生成を依頼する運用
- **定数 Item カテゴリとの役割分担**：
  - 定数タブ > Item カテゴリ（既実装・9 定数）：全体の生成方針（tier 比率・フロア基準段階・重み等）
  - トップレベル「アイテム」タブ（本タスク）：タイプ別のルール（base_stats）
  - 個別データ（generated/\*.json）：ルールから Claude Code が手動生成

### ConfigEditor 対象の `var` 化
- 対象の定数は `const` ではなく `var` で宣言する必要がある（Autoload 起動時に `_load_constants()` が外部 JSON から値を代入するため）
- `const` のまま外部化したい場合は先に `var` へ変換する

## フェーズ
- [x] Phase 1: 主人公1人の移動・画像表示・フィールド表示。グリッド移動・4方向スプライト切替・タイルマップ（FLOOR/WALL）・デッドゾーン方式カメラを実装
- [x] Phase 2: 戦闘基盤。HP等基本ステータス・敵配置（JSON読み込み）・ルールベースAI（A*経路探索・ステートマシン）・近接攻撃・方向ダメージ倍率を実装
- [x] Phase 3: フィールド生成。手作りダンジョンJSON管理・複数部屋＋通路構造・敵パーティー配置を実装
- [x] Phase 4: 攻撃バリエーション。PRE_DELAY→TARGETING→POST_DELAYの攻撃フロー・飛翔体エフェクト・飛行キャラ対応（melee/ranged/dive）を実装
- [x] Phase 5: グラフィック＆UI強化。トップビュー化・タイル画像・OBSTACLE/CORRIDORタイル・部屋単位の視界システム・3カラムUI（左=味方/中央=フィールド/右=敵）・メッセージウィンドウ・エリア名表示を実装
- [ ] Phase 6: 仲間AI・操作切替
  - [x] Phase 6-0: AIを2層構造（リーダーAI＋個体AI）にリファクタリング。7クラスのJSON定義・キャラクター自動生成・画像フォルダ新フォーマット移行を実施
  - [x] Phase 6-1: 仲間NPCの配置と基本AI行動。NpcManager/NpcLeaderAI/NpcUnitAIを実装し、パーティーカラー表示・初期3人パーティーでの開始を実現
  - [x] Phase 6-2: 仲間の加入。Aボタンで隣接NPCに話しかけて仲間にする会話システム（スコア比較方式の承諾判定・共闘/回復ボーナス・敵入室時の会話中断）を実装
  - [x] Phase 6-3: 操作キャラの切替。指示ウィンドウからパーティーメンバーへ操作を切り替え、旧操作キャラはAI制御に戻る仕組みを実装
- [x] Phase 7: 指示システム。全体方針7項目（移動/戦闘方針/ターゲット/低HP/アイテム取得/ヒールポーション/SP・MPポーション）と個別指示4列（隊形/戦闘/ターゲット/特殊攻撃、ヒーラーは+回復列）をチップ形式UIで実装。AIが指示に従って行動する仕組みを完成
- [x] Phase 8 Step 1: 飛行移動・攻撃タイプ（melee/ranged/dive）・MP・回復/バフ行動（ヒーラー・ダークプリースト）を実装
- [x] Phase 8 Step 2+3: 敵11種の種族別AI（ゴブリン系・ウルフ・ゾンビ・ハーピー・サラマンダー・暗黒系等）とマスターデータを実装。ダンジョンに全種を配置
- [x] Phase 8 バグ修正: 敵JSONの読み込み・ダンジョン構成（12部屋x4フロア+ボス1部屋）を整備
- [x] Phase 9: 操作感・表現強化
  - [x] Phase 9-1: 歩行アニメーション（walk1→top→walk2→topの4フレームループ）・位置補間・先行入力バッファ方式による滑らか移動を実装
  - [x] Phase 9-2: Xbox系ゲームパッド対応（全操作をキーボードとゲームパッドの並列登録）
  - [x] Phase 9-3: 飛翔体グラフィック（矢・火弾・雷弾の画像と飛行方向回転）を実装
  - [x] Phase 9-4: 効果音（Kenney CC0素材。攻撃・命中・被ダメージ・死亡・回復・入室の各SE）を実装
  - [x] Phase 9-5: 衝突判定改善（先着優先方式・abort_move）・スプライト回転アニメーション・味方の押し出しシステムを実装
- [ ] Phase 10: アイテム・装備システム
  - [x] Phase 10-1: アイテムマスターデータ（武器5種・防具4種・消耗品2種）定義・インベントリシステム・部屋制圧方式のドロップシステムを実装
  - [ ] Phase 10-2: 装備システム
    - [x] ドロップ処理（部屋制圧でアイテムが床に散布・踏んで自動取得）・OrderWindowアイテムUI（装備/渡す/3層UI）・操作体系刷新（1ボタン攻撃統合・メニュー共通ナビゲーション）を実装
    - [x] MessageLog（Autoload）新設・DebugWindow移行・全キャラクター常時行動化・会話UIのMessageWindow統合を実装
    - [x] 装備ステータス補正値反映・被ダメージ計算（防御判定・方向判定・耐性）・初期装備付与・装備補正値の仕様統一を実装
    - AI自動装備は将来実装（当面は拾って持つだけ）
    - [x] UI改善（クラス名日本語表示・装備可否色分け・隣接エリア先行可視化等）・主人公をランダム生成に変更
  - [x] Phase 10-3: HP/MP回復ポーション。C/X短押しでアイテム選択UI（使用/装備/渡す）を開く仕組みを実装。ConsumableBar UIで消耗品を常時表示
  - [x] Phase 10-4: OrderWindowに指示テーブル＋ステータス詳細（素値/補正値/最終値）＋装備欄＋所持アイテムを統合表示
- [x] Phase 11: フロア・ダンジョン拡張
  - [x] Phase 11-1: 階段タイル・フロア遷移（5フロア構成）を実装。フロアごとの敵/NPC管理・遅延初期化・各種バグ修正を含む
  - [x] Phase 11-2: 5フロア対応ダンジョン（フロア0:ゴブリン中心〜フロア4:ボス）とゲームクリア判定を実装
  - [x] Phase 11-3: MPバー表示（魔法クラスのみ）・攻撃時MP消費・アイテム一覧のグループ化表示を実装
  - [x] Phase 11-4: プレイヤー操作ヒーラーの回復行動（単体・射程あり・アンデッド特効）とコード描画による回復エフェクトを実装
  - [x] Phase 11-5: ガードシステム（X/Bホールドで正面防御100%成功・移動速度50%・向き固定・guard.pngスプライト）を実装
- [ ] Phase 12: ステージ・バランス調整
  - [x] Phase 12-1: MP/SPシステム（魔法クラス=MP・非魔法クラス=SP・自動回復・SPポーション）を実装
  - [x] Phase 12-2: 水魔法使いクラス（水弾・水流・無力化水魔法）とスタンシステム（行動停止＋スピン表現）・Vスロット基盤を実装
  - [x] Phase 12-3: アイテム画像をゲーム内に反映
  - [x] Phase 12-4: 全7クラスのVスロット特殊攻撃（突進斬り/振り回し/ヘッドショット/炎陣/無力化水魔法/防御バフ/スライディング）を実装。アイテム画像の床・UI表示も対応
  - [x] Phase 12-5: LB/RBでキャラ循環切り替え・C/X短押しでアイテム選択UIを開く操作体系に変更
  - [x] Phase 12-6: 防御バフの緑色六角形バリアエフェクト・LB/RBキャラ切り替え・C/Xアイテム選択UIを実装
  - [x] Phase 12-7: パーティーメンバーと未加入NPCのフロア遷移（個別階段使用・ランク和ベースの適正フロア判断）を実装。関連バグ修正を含む
  - [x] Phase 12-8: OrderWindow右キー動作修正・NPC会話専用ウィンドウ新設・各フロア階段3か所配置・別フロアキャラのブロック問題修正
  - [x] Phase 12-9: 左パネル12人対応・パーティー上限12人ガード・NPC配置をフロア0に集約（4部屋11人）
  - [x] Phase 12-10: attack.pngスプライト対応（攻撃中の専用画像）・プレイヤー/NPC全14キャラにimage_setを固定割り当て
  - [x] Phase 12-11: NPCの多層階探索（同フロア敵全滅で探索モード移行・視界ベース階段探索・フロア遷移後の自律行動）を修正
  - [x] Phase 12-12: アンデッド5種（skeleton/skeleton-archer/lich/demon/dark-lord）追加。ヒーラーのアンデッド特効・雷弾飛翔体・魔王のワープ＋炎陣を実装
  - [x] Phase 12-13: ダンジョン全面再生成（5フロア141体）・アウトラインシェーダー・射程オーバーレイ・各種バグ修正
  - [x] Phase 12-14: ステータス名統一（power/skill）・ガード防御改修・NPC会話をAボタン方式に変更・「一緒に行く」合流処理修正
  - [x] Phase 12-15: ステータス生成を設定ファイル方式に移行。全ステータス0-100スケール統一・vitality/energy追加・move_speed/obedience変換を実装
  - [x] Phase 12-16: クリティカルヒット（skill/3%の確率でダメージ2倍・二重エフェクト）を実装
  - [x] Phase 12-17: 敵16種のステータス生成を設定ファイル方式（enemy_class_stats.json/enemy_list.json）で実装
  - [x] Phase 12-18: フロア遷移時のfreedクラッシュ・新フロア敵未起動・LB/RBキャラ切り替え不具合・アウトライン残留バグを修正
  - [x] Phase 12-19: 装備補正値の仕様統一・敵ヒーラーの回復対象バグ・シェーダーmodulate無視バグ・freedキャストクラッシュを修正。旧敵画像を削除
- [x] Phase 13: タイトル画面・メインメニュー（セーブ3スロット・名前入力・オプション）・ポーズメニュー・セーブシステムを実装
- [x] Phase 13-1: MessageWindowをアイコン行方式に刷新。戦闘メッセージを自然言語化し、攻撃側/被攻撃側の顔アイコン＋左右上半身画像を表示
- [x] Phase 13-2: ダメージ倍率調整・NPC探索分散・部屋制圧に敵走離脱を追加・メッセージのグループ表示・リーダー方角インジケーターを実装
- [x] Phase 13-3: MessageWindowのスムーズスクロール（0.15秒補間・SubViewportによる上端クリッピング）を実装
- [x] Phase 13-4: ダンジョン全49部屋に非矩形形状（L字・T字・八角形等10種のパターン）と障害物タイルを配置
- [x] Phase 13-5: OrderWindow全体方針を6行個別設定に刷新・個別指示テーブル4列化（非ヒーラー:ターゲット/隊形/戦闘/特殊攻撃、ヒーラー:+回復）・選択肢をチップ形式で横並び表示
- [x] Phase 13-6: Phase 13-5の指示仕様をAIロジックに反映（ポーション自動使用・アイテムナビゲーション・follow追従・support援護ターゲット等）
- [x] Phase 13-7: 移動前に向きだけ変える回転操作を実装（移動方向が現在の向きと異なる場合、まず回転してから移動）
- [x] Phase 13-8: 未加入NPCパーティーのアイテム自動装備・ポーション自動受け渡しを実装。会話選択肢を「仲間にする/キャンセル」の2択に変更
- [x] Phase 13-9: OrderWindowステータス表示を2列化（左:攻撃系/右:防御系）・ヘッダーに名前+クラス+ランクを統合
- [x] Phase 13-9（戦闘方針・集結隊形）: 全体方針にbattle_policy（攻撃/防衛/撤退）を追加。gather隊形（パーティー重心付近に集結）を実装
- [x] Phase 13-10: 敵の縄張り・追跡システムを実装。chase_range/territory_rangeで追跡範囲を制限し、範囲外では帰還行動に切り替え
- [x] Phase 13-10 後続修正: ヒーラーの回復指示デフォルトを瀕死度優先に変更・非ヒーラー行の回復列にグレー「-」表示
- [x] Phase 13-11: フロア0をゴブリンのみに変更・NPCデフォルト指示をプレイヤーと整合・戦闘中のbattle_formation優先・follow追従ロジック改善
- [x] Phase 13-12: バグ修正完了（フロア2以降の敵が攻撃しない問題・未加入NPCがアイテムを素通りする問題）
- [x] 味方キャラ同士が重なる・味方を迂回できない問題を修正（`_link_all_character_lists` を全フロア走査に変更・フロア遷移/合流時の `_all_members` 更新漏れを修正・A* 1歩目の味方迂回フォールバック追加）
- [x] パーティーシステムリファクタリング: 敵リーダーAI継承構造リファクタリング（EnemyLeaderAI）・PartyLeader基底クラス抽出・NpcManager/EnemyManager廃止しPartyManagerに統合・パーティー戦力評価メソッド追加
- [x] ダンジョン再構成: 5フロア×20部屋構成に拡張。各フロア下り階段3部屋・上り階段3部屋（上り階段部屋は敵初期配置なし）。主人公1人スタート・NPC 8パーティー（1人×5+2人×2+3人×1=計12人）を全てフロア0に配置
- [x] 安全部屋の追加: フロア0中央に「安全の広間」（15×11、`is_safe_room`）を配置。上下左右4部屋と通路で接続。敵は通路までは来れるが部屋内に進入できない（MapData.is_safe_tile で敵AIのA*経路探索から除外）。主人公とNPC全8パーティーがここからスタート
- [x] UI・演出ブラッシュアップ（2026-04-16）:
  - ヒットエフェクトを3層プロシージャル（リング波紋＋光条＋パーティクル散布・加算合成）に刷新
  - OrderWindow レイアウト再構成（タイトル削除・ステータスヘッダー復活・ランク色付き・装備/所持アイテム2列化・全身画像拡大1:1維持・ログ行廃止）
  - OrderWindow チップ選択の左右キーは全列循環・上下移動時は列種類（pos）で対応づけ
  - メッセージウィンドウ刷新（右スティック上下でピクセル単位スムーズスクロール・R3/Homeで拡大トグル・背景半透明化・文字色分け segments 対応）
  - 状態ラベル4段階化（healthy/wounded/injured/critical）。スプライト色・テキスト色・HPゲージ色・DebugWindow を状態ラベル閾値に統一
  - 攻撃フロー改善（他ボタンで攻撃キャンセル＋機能切替・射程内対象なし時の自動キャンセル・ヒーラー360度射程オーバーレイ対応）
  - 安全部屋専用タイル画像（safe_floor.png）
  - `Character.joined_to_player` フラグ追加（パーティー所属判定用）
  - アイテム名称統一（ヒールポーション/MPポーション/SPポーション）
- [x] 近接3クラス（剣士/斧戦士/斥候）の特殊攻撃AI発動条件（隣接敵数・突進斬りの経路判定）を実装
- [x] 攻撃クールダウン（pre_delay / post_delay）の全面見直し：クラスJSONのスロット単位（Z/V）に一元化、プレイヤー/AIで同じ slots 参照、PRE_DELAY 中から射程オーバーレイ表示、game_speed 適用
- [x] HP状態ラベルの色と点滅を全UI要素で統一。色定数を `GlobalConstants` に集約（SPRITE/GAUGE/TEXT の3パレット）。wounded 以降はスプライト・顔アイコンで3Hz点滅。ゲージ・文字は静的
- [x] Config Editor（開発用定数エディタ）を実装。F4 でタイトル画面・ゲーム中ともトグル起動。5定数（Phase A）を外部 JSON（`assets/master/config/constants.json` / `constants_default.json`）化し、7 + Unknown タブでカテゴリ分け表示・保存・デフォルト復帰・デフォルト化に対応
- [x] Config Editor にトップレベルタブ構造（定数/味方クラス/敵/ステータス/アイテム）を導入し、「味方クラス」タブで 7 クラス JSON を横断表で編集できるよう実装（`slots.Z/V` 平坦化・LineEdit セル・元値型に合わせた書き戻し・キー順保持）
- [x] Config Editor「ステータス」タブを実装。`class_stats.json`（クラス × ステータス × base/rank の 2 LineEdit セル）と `attribute_stats.json`（属性補正表 + random_max 表）を直接編集可能
- [x] 敵データの構造整理：敵固有 5 クラス（zombie / wolf / salamander / harpy / dark-lord）の JSON を `assets/master/classes/` に新規作成。個別敵 JSON 16 ファイルから `attack_type` / `attack_range` / `pre_delay` / `post_delay` / `heal_mp_cost` / `buff_mp_cost` を除去し、クラス経由で注入する仕組みに統一。`healer.json` の top-level `heal_mp_cost` / `buff_mp_cost` も削除し、`slots.Z.mp_cost` / `slots.V.mp_cost` を正規化
- [x] Config Editor「敵クラス」タブを実装。味方クラスタブの描画関数を流用し、対象クラス ID 配列を差し替えて 5 敵固有クラスを横断表編集可能に。トップタブを「敵」→「敵クラス」「敵一覧」の 2 タブに分割
- [x] Config Editor「敵一覧」タブを実装。`enemy_list.json`（rank / stat_type / stat_bonus）と個別敵 JSON（is_undead / is_flying / instant_death_immune / behavior_description / chase_range / territory_range）を 1 つの横断表で編集。stat_bonus は 6 枠 UI で管理。保存は 2 系統のファイル（enemy_list.json + dirty な個別敵 JSON のみ）に分かれる
- [ ] Phase 14: Steam配布準備

## 装備システム

### 装備種類と補正パラメータ

| 装備 | 威力 | 右手防御強度 | 左手防御強度 | 両手防御強度 | 物理耐性 | 魔法耐性 |
|------|------|------------|------------|------------|---------|---------|
| 剣・斧・短剣 | 0〜30 | 0〜30 | — | — | — | — |
| 弓・杖 | 0〜30 | — | — | 0〜30 | — | — |
| 盾 | — | — | 0〜30 | — | — | — |
| 鎧 | — | — | — | — | 0〜30 | 0〜15 |
| 服 | — | — | — | — | 0〜15 | 0〜15 |
| ローブ | — | — | — | — | 0〜15 | 0〜30 |

- 射程補正は将来実装予定（弓・杖に追加予定）
- 空白のパラメータは補正対象外
- 補正対象の各パラメータは独立してランダムに決定する（0〜上限値の連続値）

### 装備の名前生成（定数ベース事前生成方式・2026-04-19〜）
**方針**：名前と補正値を一対一で固定する事前生成セット方式。ランタイムでは乱数生成せず、事前定義された候補から重み付き選択する。

**事前生成セットのデータ構造**（`assets/master/items/generated/{item_type}.json`）:
```json
{
  "sword": [
    { "name": "兵士の剣", "stats": { "power": 10, "block_right_front": 10 }, "tier": "low" },
    { "name": "断罪の魔剣", "stats": { "power": 30, "block_right_front": 10 }, "tier": "high" },
    ...
  ]
}
```

- **総当たり 9 パターン + tier 0 の 1 パターン**：各装備タイプは 2 ステータスを low/mid/high の 3 bonus 段階で組み合わせた 9 パターン ＋ 初期装備用の tier=0（none）エントリ 1 個。盾のみ単一ステータスで 3 + 1 パターン
- **bonus / tier の概念分離**（2026-04-19〜）：
  - **bonus 段階**（stats 内の各値の強さ）：`none / low / mid / high`（no_bonus / low_bonus / mid_bonus / high_bonus の略）
  - **tier**（装備全体の格付け・整数）：`0=none`, `1=low`, `2=mid`, `3=high`
- **tier 判定**：`ITEM_TIER_POLICY="max"` の場合、2 ステータスの bonus 段階の高い方を採用（power 中 × block 高 → tier 3）
- **bonus 値の計算**：`_max × ITEM_BONUS_{LOW|MID|HIGH}_RATIO`（デフォルト 0.33 / 0.67 / 1.0）
- **tier 0（none）は初期装備専用**：ドロップには出現しない（`ItemGenerator.generate()` の重み計算で除外）。`ItemGenerator.generate_initial(item_type)` 経由で取得
- **ランダム補正なし**：同じ名前の装備は常に同じ stats（プレイヤーが「鋭利な剣」を見つけたら値も固定）
- `category` フィールドは JSON に持たない（power と block の値から計算で判定可能・特殊ステータス追加時の柔軟性確保）

**命名の基準**（CLAUDE.md 初期仕様を維持）:
- 威力が防御強度の 2 倍以上 → 攻撃系（「鋭利な剣」「業物」）
- 防御強度が威力の 2 倍以上 → 防御系（「守りの剣」「頑丈な剣」）
- それ以外 → バランス系（「均整の剣」「騎士の剣」）
- 防具は物理耐性と魔法耐性の比率で同様に命名
- **命名制約の根拠**：キャラ画像生成プロンプトで決まる形状（片手剣／両手弓／軽装服 等）。両手剣・サーベル・タワーシールド等 NG。カタカナ表記を避ける（漢字語彙で統一）

**ランタイム選択ロジック**（`scripts/item_generator.gd`）:
- `ItemGenerator.generate(item_type, floor_index)` が tier≥1 の全エントリから重み付き選択（ドロップ用）
- `ItemGenerator.generate_initial(item_type)` が tier=0 エントリを返す（初期装備用・ポーションは `generate_consumable` に委譲）
- 重み = 「各フロア帯の基準 tier（`FLOOR_X_Y_BASE_TIER`・整数）からの距離」で計算（基準=`FLOOR_BASE_WEIGHT` / 隣接=`FLOOR_NEIGHBOR_WEIGHT` / 遠隔=`FLOOR_FAR_WEIGHT`）
- フロア境界（1 / 2）では隣接する 2 帯の重みを合算して滑らかな遷移を実現
- **装備アイテム戻り値に `tier` を含む**（2026-04-19〜）：`{ item_type, category, item_name, stats, tier }`。戦力計算（`party_leader._character_tier_avg()`）等が参照する。ポーションは tier を持たない（戦力評価対象外のため）

**マスター JSON との関係**：
- `assets/master/items/*.json` の `base_stats.{stat}_max` のみを段階値計算の参考に使う（ランタイムは非参照・Claude Code が生成セット作成時に参照）
- ~~`base_stats.{stat}_min`~~ と ~~`depth_scale`~~ は **2026-04-19 に物理削除済み**（ランタイム非参照のため legacy 扱い）
- 将来、特殊ステータス（skill / critical_rate 等）を追加する場合は `stats` 辞書に任意キーを追加できる（ItemGenerator は辞書ごとコピー）

### 装備の生成タイミングと強さ
- 敵配置時点ではアイテム種別のみ確定（`dungeon_handcrafted.json` の `enemy_party.items` は `item_type` 文字列リスト）
- 部屋制圧時に `ItemGenerator.generate(item_type, floor_index)` が呼び出されて具体値を生成
- フロア深度に応じて tier 1〜3（low/mid/high）の出現比率が変わる（序盤は低 tier 中心・終盤は高 tier 中心）
- tier 0（none）はドロップには出ない（初期装備専用）

### 初期装備
- `game_map.gd` の `_dbg_items` 辞書（クラス別の `item_type` 文字列リスト）と NPC 側の `npc_parties_multi.members[].items` が SoT
- 主人公・NPC 共通で `ItemGenerator.generate_initial(item_type)` が tier=0 エントリを返す
- 初期ポーションは `GlobalConstants.INITIAL_POTION_HEAL_COUNT` / `INITIAL_POTION_ENERGY_COUNT` の個数ぶん全キャラ一律に付与（Config Editor Item カテゴリで調整可能）

## アイテムシステム

### 装備品
| カテゴリ | 種類 |
|---------|------|
| 武器 | 剣・斧・弓・ダガー・杖 |
| 防具 | 鎧・服・ローブ・盾 |

### クラスと装備の対応
| クラス | 武器 | 防具 | 盾 |
|--------|------|------|-----|
| 剣士 | 剣 | 鎧 | ○ |
| 斧戦士 | 斧 | 鎧 | ○ |
| 弓使い | 弓 | 服 | ✕ |
| 斥候 | ダガー | 服 | ✕ |
| 魔法使い(火) | 杖 | ローブ | ✕ |
| 魔法使い(水) | 杖 | ローブ | ✕ |
| ヒーラー | 杖 | ローブ | ✕ |

- 戦士クラス（剣士・斧戦士）は盾を左手に持つ（グラフィック統一）
- 杖は魔法使い・ヒーラーで共用。`power` として魔法攻撃力・回復力の両方に効く

### アイテム所持の仕組み
- アイテムはキャラクター個人が所持する（パーティー単位のインベントリではない）
- 各アイテムは「装備中」と「未装備」の2状態を持つ
- 装備スロット：武器1 / 防具1 / 盾1（戦士クラスのみ）の3スロット
- **装備は外せない**（別アイテムで上書きのみ）。上書き時、旧装備は未装備品としてそのキャラの手元に残る
- OrderWindow 下部：装備スロット欄に装備中アイテムを表示、所持アイテム一覧に未装備品と消耗品のみ表示（重複表示しない）
- 未装備品はリーダー権限でパーティー内の他キャラに受け渡し可能

### 初期装備
- `dungeon_handcrafted.json` の `player_party` / `npc_parties` メンバーに `items` フィールドで初期装備を記述する
- 各クラスに応じた装備を持たせる（fighter-sword: 剣+鎧+盾、fighter-axe: 斧+鎧+盾、archer: 弓+服、scout: ダガー+服、magician-fire: 杖+ローブ、healer: 杖+ローブ）
- 初期装備は弱め（各補正値1〜3程度）
- 敵ドロップ品は部屋の奥に行くほど強くなる

### 装備の補正値
**2026-04-21 の設計統一**：装備補正は **13 ステータス全てに対応**（Config Editor アイテムタブ `ITEM_STAT_CHOICES` と一致）。

- **対象ステータス**：`power` / `skill` / `block_right_front` / `block_left_front` / `block_front` / `physical_resistance` / `magic_resistance` / `defense_accuracy` / `leadership` / `obedience` / `move_speed` / `vitality`（→ `max_hp`）/ `energy`（→ `max_energy`）。さらに武器の射程延長に `range_bonus` キーを使う
- 現行のアイテムマスター（`assets/master/items/generated/*.json`）が実際に使うキーは一部（主に `power` / `block_*` / `physical_resistance` / `magic_resistance` / `range_bonus`）。それ以外のキー（`skill` / `defense_accuracy` / `leadership` / `obedience` / `move_speed` / `vitality` / `energy`）は将来のアイテム拡張余地として対応済み
- 典型的な用途（現状の命名規則の根拠）：
  - **武器（剣・斧・短剣）**：`power`・`block_right_front`
  - **武器（弓・杖）**：`power`・`block_front`・`range_bonus`
  - **盾**：`block_left_front`
  - **防具（鎧）**：`physical_resistance` 0〜30・`magic_resistance` 0〜15
  - **防具（服）**：`physical_resistance` 0〜15・`magic_resistance` 0〜15
  - **防具（ローブ）**：`physical_resistance` 0〜15・`magic_resistance` 0〜30
- 実装面：`CharacterData.get_equipment_bonus(stat_name)` が全 equipped スロット（武器・防具・盾）の `stats.<name>` を合計する単一 API。旧 `get_weapon_power_bonus()` 等の個別 getter は 2026-04-21 に廃止・1 関数に集約

### ダメージ計算への装備補正反映
**2026-04-21 の設計統一**：ダメージ・戦闘計算・AI 判断は Character 側の**装備補正込みの最終値**（`Character.power` / `physical_resistance` 等）を直接参照する。`character_data.X + 装備補正` を毎回計算する方式は廃止。

- 最終値の保持：Character クラスが 13 ステータス分のフィールドを持つ（`max_hp` / `max_energy` / `power` / `skill` / `attack_range` / `block_right_front` / `block_left_front` / `block_front` / `physical_resistance` / `magic_resistance` / `defense_accuracy` / `leadership` / `obedience` / `move_speed`）
- 再計算タイミング：`Character.refresh_stats_from_equipment()` が 13 ステータス全てを一括再計算（初期化時・装備変更時に呼ぶ）
- 素値が欲しい場面では **`character_data.X`** を直接参照する（例：OrderWindow の「素値 / 装備補正 / 最終値」2 列表示）
- 耐性計算：`CharacterData.resistance_to_ratio(Character.physical_resistance)` / 同（magic）で 0〜1 の軽減率を算出（逓減カーブ `score / (score + 100)` 適用前の能力値は装備補正込み）
- 防御強度 3 フィールド：`Character.block_*` を直接参照し、`Character.defense_accuracy` でロール判定
- OrderWindow のステータス表示：3 防御強度すべて常時表示（素値 / 装備補正 / 最終値 3 列）。アイテム受渡し先で有効な補正値を見失わない配慮

### アイテム生成
- 補正値はランダム生成（フロア深度に応じた範囲内）
- 名前はClaude Codeがダンジョン生成時に補正値の強さ・フロア深度を考慮して作成
- グレードフィールドは持たない（補正値の強さがグレードを表す）
- アイテムマスターは `assets/master/items/` に種類ごとに定義

### 敵キャラクターとアイテムの関係
- 敵は装備の概念を持たない（現状のステータスがそのまま戦闘能力）
- 敵パーティーの所持アイテムはドロップ用にパーティー単位で保持するのみ

### アイテムのドロップ（部屋制圧方式）
- 部屋に配置された enemy_party の全員が**死亡 or 敵走離脱**したら「制圧完了」
- 制圧時、敵パーティーの所持アイテムが**部屋の床タイルにランダムに散らばる**（1マスに1個）
- 出現は1回きり（敵が戻っても再出現しない）
- **制圧判定の詳細**（`party_manager._check_room_suppression()`）：
  - 死亡 → 制圧対象
  - 部屋の外にいる かつ パーティー戦略が FLEE → 離脱扱い・制圧対象
  - 部屋の外にいる かつ FLEE 以外（追跡中など） → 制圧対象にしない
  - 部屋の中で生存 → 制圧対象にしない
  - 判定タイミング：メンバー死亡時（`_on_member_died`）
  - 二重発火防止：`party_wiped` 発火後に `_room_id` を空文字にクリア
- item_get 効果音を再生、メッセージウィンドウに通知（例：「アイテムが散らばった！」）
- 表示：アイテム種類別アイコン（`assets/images/items/{item_type}.png`。画像なし時は黄色マーカーにフォールバック）
- **取得方法**：同じマスに移動したら自動取得。拾ったキャラ個人の inventory に未装備品として入る
- プレイヤー操作キャラはフィルタなし（踏めば何でも拾う）
- AIキャラは item_pickup 指示に従う（指示システム節を参照）
- 敵パーティーの所持アイテムはClaude Codeがダンジョン生成時に種族構成を考慮して割り当て
- 複数パーティーによる協力撃破の分配は将来実装

### 消耗品
- ヒールポーション・MPポーション・SPポーション（上級ポーションは設けない）
- C/X短押しでフィールドからアイテム選択UIを開いて使用（ウィンドウ不要）
- 固定スロット管理なし。inventory内のアイテムを一覧表示（消耗品はグループ化）
- LB/RB（通常時）：パーティーメンバーを表示順で循環切り替え
- LB/RB（アイテムUI中）：アイテムカーソル循環
- LB/RB（TARGETING中）：ターゲット循環
- 左パネルのアクティブキャラ欄に `[C] アイテム名` を常時表示

## 戦闘仕様

### 視界システム
- Phase 5で部屋単位に実装済み
  - 現在いる部屋の敵のみ見える・アクティブ化（VisionSystem.gd）
  - 通路では敵が非表示（CORRIDORタイルにはエリアIDなし）
  - 部屋に入った瞬間に敵がアクティブ化、メッセージウィンドウに通知
- 将来：通常時は前方のみ、警戒時（攻撃を受けた・仲間がやられたなど）は全方位
- 不意打ちなどの演出に活用予定

### 情報管理
- 敵はパーティー単位で情報を共有（個別管理ではない）

### HP・状態
- 当面：敵味方ともに正確な数値を共有
- 将来：視界内の敵は大まかな状態のみ（healthy／wounded／critical）

### 戦況判断（CombatSituation）
- `_evaluate_strategic_status()` が統合的に戦力計算・戦況判断を行う（2026-04-19〜）
- **距離ベースの連合判定**：自パリーダーから **マンハッタン `COALITION_RADIUS_TILES` マス以内**（デフォルト 8 マス・同フロアのみ）に絞る。エリアベース判定は廃止
  - 旧設計の「右端にいるとき左部屋の奥まで含む」問題を解消
- 3 種類のメンバー集合で統計を算出：
  - `full_party`：自パ全員（下層判定・絶対戦力用）
  - `nearby_allied`：自パ近接 + 同陣営他パ近接（戦況判断・味方連合）
  - `nearby_enemy`：近接敵（戦況判断）
- **敵の非対称設計**：enemy パーティーの自軍戦力は `full_party` のみ（敵は協力しない世界観）。味方（player/npc）は `nearby_allied`（連合）で加算
- 戦力式：`(rank_sum + tier_sum × ITEM_TIER_STRENGTH_WEIGHT) × 平均HP充足率`
  - `ITEM_TIER_STRENGTH_WEIGHT`：Config Editor PartyLeader カテゴリ・デフォルト 0.33
- HP 率計算：
  - 自パ部分：実 HP + ヒールポーション回復量
  - 同陣営他パ部分：condition ラベルから推定（他パのポーション所持は把握不可）
  - 敵部分：condition ラベルから推定（敵ステータス直接参照禁止ルール）
- HpStatus（自軍 HP 充足率の段階）は**自パーティーのみ**で計算

| 戦況 | 戦力比 | NPC行動への影響 | アイテム拾い |
|------|--------|----------------|-------------|
| SAFE | 敵なし | 通常探索 | item_pickup 指示に従う |
| OVERWHELMING | ≥ 2.0 | 通常攻撃（余裕あり） | しない |
| ADVANTAGE | ≥ 1.2 | 通常攻撃 | しない |
| EVEN | ≥ 0.8 | 通常攻撃 | しない |
| DISADVANTAGE | ≥ 0.5 | 通常攻撃（特殊攻撃は指示「強敵なら使う」で発動） | しない |
| CRITICAL | < 0.5 | 撤退（部屋から離脱） | しない |

- アイテム取得ナビゲーションは `_is_combat_safe()` で判定（戦況 SAFE のときのみ item_pickup 指示に従う）
- SAFE 時の1マス移動完了ごとにアイテムチェックを実行（移動中に隣接のアイテムを見逃さない）
- 撤退後に敵がいなくなると SAFE に戻り、探索・アイテム取得に復帰する
- 目標フロアの再計算で HP チェックが×なら上の階に撤退する

### 戦力比（PowerBalance）
- ランク和のみで比較（HP を含めない純粋な戦力比較）
- 自軍側ランク和 = `nearby_allied`（自パ近接 + 同陣営他パ近接）の rank_sum。ただし enemy パーティーは `full_party` のみ（非対称設計）
- 敵がいない場合は OVERWHELMING

| 段階 | 自軍ランク和 / 敵ランク和 |
|------|--------------------------|
| OVERWHELMING | ≥ 2.0 |
| SUPERIOR | ≥ 1.2 |
| EVEN | ≥ 0.8 |
| INFERIOR | ≥ 0.5 |
| DESPERATE | < 0.5 |

### HP充足率（HpStatus）
- 自軍パーティー全体のHP充足率（ポーション込み）

| 段階 | 充足率 |
|------|--------|
| FULL | ≥ 0.75 |
| STABLE | ≥ 0.5 |
| LOW | ≥ 0.25 |
| CRITICAL | < 0.25 |

### 特殊攻撃の指示と発動条件

| 指示 | 発動条件 |
|------|---------|
| 積極的に使う | MP/SP が足りていれば常に使う |
| 強敵なら使う | PowerBalance が INFERIOR 以下かつ MP/SP が足りている |
| 劣勢なら使う | HpStatus が LOW 以下かつ MP/SP が足りている |
| 使わない | 使わない |

### ゲーム内閾値一覧

主要な閾値は `GlobalConstants` に定数として定義する。コード内に数値をハードコードしない。

#### HP系
| 用途 | 定数名 | 値 |
|------|-------|-----|
| 状態ラベル "wounded" の境界（HP%<この値で wounded 以下） | `CONDITION_WOUNDED_THRESHOLD` | 0.5 |
| 状態ラベル "injured" の境界（HP%<この値で injured 以下） | `CONDITION_INJURED_THRESHOLD` | 0.35 |
| 状態ラベル "critical" の境界（HP%<この値で critical） | `CONDITION_CRITICAL_THRESHOLD` | 0.25 |
| 種族固有自己逃走（ゴブリン系 `_should_self_flee`） | `SELF_FLEE_HP_THRESHOLD` | 0.3 |

#### AI 行動判定における状態ラベル経由の原則
AI の HP 基準行動判定（ポーション自動使用・on_low_hp 発動・ヒーラー回復対象選定など）は、HP率を直接 % で比較するのではなく、必ず `Character.get_condition()` が返す状態ラベル（healthy / wounded / injured / critical）経由で行う。これにより判定ロジックが二段階構造（HP率 → 状態ラベル → 行動割当）になり、閾値変更時の影響範囲が状態ラベル側に局所化される。

| トリガー | 発動条件 |
|---------|--------|
| HP ポーション自動使用（hp_potion="use" 設定時） | 状態ラベル `injured` または `critical` |
| NPC の HP ポーション自動受け渡し（`_auto_share_potions`） | 状態ラベル `injured` または `critical`（自動使用トリガーと揃える） |
| on_low_hp 発動（keep_distance / fall_back / flee） | 状態ラベル `critical` |
| ヒーラー `aggressive` モードの回復対象 | HP < max_hp（満タンでない全対象） |
| ヒーラー `lowest_hp_first` モードの回復対象 | HP 減少量 ≥ 期待回復量（`healer.power × z_heal_mult`） |
| ヒーラー `own_party_first` モードの回復対象 | 上記と同じ条件・自パのみ |
| ヒーラー `conservative` モードの回復対象 | 状態ラベル `healthy` 以外・自パのみ |

2026-04-23 改訂で `NEAR_DEATH_THRESHOLD` 定数を廃止し、4 トリガー（ポーション自動使用・受け渡し・on_low_hp・ヒーラー aggressive 旧判定）を状態ラベル経由に統一した。さらにヒーラー回復モードを 4 モード構成（aggressive / lowest_hp_first / own_party_first / conservative）に再設計し、`HEALER_HEAL_THRESHOLD` 定数も廃止。判定基準は「HP 減少量 ≥ 期待回復量」と「状態ラベル」の 2 軸に整理された。

#### MP/SP系
| 用途 | 定数名 | 値 |
|------|-------|-----|
| MP/SPポーション自動使用（sp_mp_potion="use" 設定時） | `POTION_SP_MP_AUTOUSE_THRESHOLD` | 0.5 |

#### パーティー系
| 用途 | 定数名 | 値 |
|------|-------|-----|
| パーティー逃走（ゴブリン/ウルフ：生存メンバー率がこれ未満で FLEE 戦略） | `PARTY_FLEE_ALIVE_RATIO` | 0.5 |
| 特殊攻撃の発動状況判定（隣接8マスの敵数・近接3クラス用） | `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` | 2 |
| 炎陣の発動判定範囲（自分中心の半径マス数・magician-fire専用） | `SPECIAL_ATTACK_FIRE_ZONE_RANGE` | 2 |
| 炎陣の発動に必要な範囲内の敵数（magician-fire専用） | `SPECIAL_ATTACK_FIRE_ZONE_MIN_ENEMIES` | 2 |

#### 戦況系
本セクション上部の「戦況判断（CombatSituation）」「戦力比（PowerBalance）」「HP充足率（HpStatus）」表の閾値は、それぞれ以下の定数で定義されている:
- `COMBAT_RATIO_OVERWHELMING / ADVANTAGE / EVEN / DISADVANTAGE` (2.0 / 1.2 / 0.8 / 0.5)
- `POWER_BALANCE_OVERWHELMING / SUPERIOR / EVEN / INFERIOR` (2.0 / 1.2 / 0.8 / 0.5)
- `HP_STATUS_FULL / STABLE / LOW` (0.75 / 0.5 / 0.25)

#### ヒーラー回復モードの選定ロジック（2026-04-23 再設計）
| モード | 対象 | 他パ対象 |
|--------|------|---------|
| `aggressive`（積極回復） | HP が満タン以外で最も HP 率が低い 1 人 | あり |
| `lowest_hp_first`（瀕死度優先） | HP 減少量 ≥ 期待回復量 のうち最も HP 率が低い 1 人 | あり |
| `own_party_first`（自パ優先） | HP 減少量 ≥ 期待回復量 のうち最も HP 率が低い自パの 1 人 | なし |
| `conservative`（温存） | 状態が `wounded` 以下（= `healthy` 以外）の自パで最も HP 率が低い 1 人 | なし |

期待回復量は `healer.power × slots.Z.heal_mult`（装備補正込み・乱数なし・最低 1）で動的に算出する。ヒーラーの `power` が高いほど「早めに撃って良い」判定になる。

**デフォルトは `lowest_hp_first`**：主人公 1 人スタート時に他パーティーのヒーラーから回復を受けられることが序盤の救済として重要なため、他パ対象ありのモードをデフォルトに採用する。自パ優先は戦術的選択肢として提供する。

**`heal_mult` の推奨レンジ**：`heal_mult` は「1 回の回復で `wounded` 境界（HP 率 50%）を跨がない」ように設定する。跨ぐと瀕死度優先モードが `conservative` と区別できなくなる（`heal_amount` が `max_hp × 0.5` を超えると、HP 率 50% 未満のターゲットは常に「HP 減少量 ≥ heal_amount」を満たすため）。

**旧モードの自動マップ**（セーブデータ互換）: `leader_first` → `own_party_first` / `none` → `lowest_hp_first`。`_find_heal_target()` 冒頭の `_migrate_heal_mode()` が読み込み時に変換する。

### キャラクターステータス
**2026-04-21 の設計統一**：数値系 13 ステータスは全て「素値（`character_data.X`）＋装備補正（`CharacterData.get_equipment_bonus(X)`）＝最終値（`Character.X`）」の二層構造。戦闘・AI 計算は Character 側の最終値を直接参照する。素値が必要な UI 表示（OrderWindow の 2 列）だけ `character_data.X` を直接参照する。

| ステータス | フィールド名（実装） | 説明 |
|-----------|-------------------|------|
| HP | `max_hp` / `hp` | ヒットポイント。`max_hp` は装備補正（`vitality` キー）対応 |
| エネルギー | `max_energy` / `energy` | 全クラス共通のリソース。UI 表示は `CharacterData.is_magic_class()` で魔法クラス→「MP」/ 非魔法クラス→「SP」に切替（内部データは同じ `energy`）。`max_energy` は装備補正（`energy` キー）対応 |
| 物理威力／魔法威力 | `power` | 攻撃ダメージ・回復量の共通値。UI 表示ラベルはクラスに応じて切替。装備補正対応 |
| 物理技量／魔法技量 | `skill` | 命中精度・クリティカル率の基礎値。UI 表示ラベルはクラスに応じて切替。装備補正対応（現状のアイテム生成規則では使用なし・将来拡張余地） |
| 物理攻撃耐性 | `physical_resistance` | 物理ダメージ軽減の能力値（整数）。軽減率 = 値/(値+100)。装備補正対応 |
| 魔法攻撃耐性 | `magic_resistance` | 魔法ダメージ軽減の能力値（整数）。軽減率 = 値/(値+100)。装備補正対応 |
| 防御技量 | `defense_accuracy` | 防御判定の成功率（%）。装備補正対応（現状のアイテム生成規則では使用なし・将来拡張余地） |
| 防御強度 | `block_right_front` / `block_left_front` / `block_front` | 防御成功時に無効化できるダメージ量。方向別に3フィールド。装備補正対応（武器=right_front or front / 盾=left_front）。OrderWindow で常時 3 行表示 |
| 射程 | `attack_range` | 攻撃射程（タイル）。装備補正キーは `range_bonus`（弓・杖のみ）|
| 移動速度 | `move_speed` | 0-100 スコア（高いほど速い・標準 50）。実効値は `Character.get_move_duration()` が `BASE_MOVE_DURATION × 50 / move_speed` で算出。装備補正対応（将来拡張余地） |
| 統率力（leadership） | `leadership` | NPC 合流交渉の説得力に寄与。装備補正対応（将来拡張余地） |
| 従順度（obedience） | `obedience` | 個体側（0.0〜1.0 スケール）。NPC 合流スコアに影響。装備補正対応（将来拡張余地） |
| 即死耐性 | `instant_death_immune` | bool。デフォルト false。ボス級は true（ヘッドショット無効・無力化水魔法短縮） |
| アンデッド | `is_undead` | bool。デフォルト false。skeleton / skeleton-archer / lich が true。ヒーラーの回復魔法が特効（回復量をダメージとして適用）。物理耐性極高・魔法はある程度有効 |
| 巻き添え | `friendly_fire` | bool。デフォルト false（将来実装。範囲攻撃が味方・他パーティーにも当たる仕様） |
| 状態ラベル | `get_condition()` | HP割合に基づく4段階ラベル（healthy/wounded/injured/critical）。AI の戦力評価で敵のHP推定に使用。閾値は GlobalConstants で管理 |

### 状態ラベルの色と点滅
- 閾値は `GlobalConstants.CONDITION_WOUNDED_THRESHOLD` (0.5) / `CONDITION_INJURED_THRESHOLD` (0.35) / `CONDITION_CRITICAL_THRESHOLD` (0.25)。命名は「この値を下回ったら該当状態に入る」を意味する
- 色は `GlobalConstants` に 3 系統のパレットで集約（SPRITE / GAUGE / TEXT）。各 UI は用途に応じてパレットを使い分ける
- 点滅は **スプライト・顔アイコン（左右パネル）のみ** に適用。wounded / injured / critical の 3 段階で 3Hz 点滅（`CONDITION_PULSE_HZ`）。ゲージ・文字・DebugWindow は静的色

| ラベル | HP閾値 | スプライト・アイコン | HPゲージ | テキスト | DebugWindow HP | 点滅 |
|---|---|---|---|---|---|---|
| healthy  | ≥50% | 白 | 緑 | 緑 | 白 | なし |
| wounded  | ≥35% | 黄 | 黄 | 黄 | 黄 | **あり** |
| injured  | ≥25% | 橙 | 橙 | 橙 | 橙 | **あり** |
| critical | <25% | 赤 | 赤 | 赤 | 赤 | **あり** |

- 色定数：`CONDITION_COLOR_{SPRITE|GAUGE|TEXT}_{HEALTHY|WOUNDED|INJURED|CRITICAL}`（全12定数）
- ヘルパー：`condition_sprite_modulate(cond)`（点滅あり）/ `condition_sprite_color(cond)`（静的）/ `condition_gauge_color(cond)` / `condition_text_color(cond)` / `ratio_to_condition(ratio)`
- 点滅実装：`_pulse_color(base)` が `sin(t*TAU*3)` で「色 ↔ 暗い同色（各成分×0.7）」を lerp

- 魔法命中精度は `skill` と共通（`power` 系は攻撃・回復とも同じ命中扱い）
- 回復魔法は必ず命中するため、ヒーラー（attack_type="heal"）には OrderWindow の魔法技量行を表示しない
- 耐性素値はクラスごとに設定（例：戦士クラスは物理耐性高め、魔法使いは魔法耐性高め）
- 耐性はステータス決定構造の加算式で決定（他のステータスと同じフロー）
- 軽減方式：逓減カーブ（軽減率 = 能力値 / (能力値 + 100)。100で50%、200で67%）
- OrderWindow では数値のみ表示（%表記はしない）

### energyシステム
- 全クラス共通で `energy` / `max_energy` を持つ（内部データは単一フィールド）
- UI 表示は `CharacterData.is_magic_class()` で魔法クラス→「MP」/ 非魔法クラス→「SP」として表示（ラベル色・バー色も切替）
- **魔法クラス**（`magician-fire` / `magician-water` / `healer`）：UI 表示は「MP」
- **非魔法クラス**（`fighter-sword` / `fighter-axe` / `archer` / `scout`）：UI 表示は「SP」
- バー表示（左パネル）：魔法クラス→濃い青・非魔法クラス→水色系。Vスロット特殊攻撃のコスト未満になるとバー色が紫系に変化（魔法=濃い紫・非魔法=明るい紫）
- 通常攻撃（Z）：全クラス微量消費（自動回復と相殺される程度）
- 特殊攻撃（V）：全クラス共通でエネルギー消費（クラス JSON の `slots.V.cost` で定義）
- ヒーラーのZ（回復）もエネルギー消費（クラス JSON の `slots.Z.cost`）
- 自動回復：エネルギーは時間経過でゆっくり回復（`Character.ENERGY_RECOVERY_RATE`）
- 回復アイテム：エナジーポーション 1 種に統合（使用キャラのクラス種別で MP/SP どちらとしてログ表示されるかが決まる）
- 敵キャラクターも energy を持つ（`apply_enemy_stats` が `max_energy = stats.energy` を設定）

### 命中・被ダメージ計算

**着弾判定**（命中精度）：攻撃が狙った対象に向かうか。`skill` が低いと別の敵・味方に誤射する可能性。

**攻撃タイプ別ダメージ倍率**（`GlobalConstants.ATTACK_TYPE_MULT`）:
- melee: × 0.2
- ranged: × 0.1
- dive: × 0.2
- magic: × 0.1
- ベースダメージ = `power × type_mult × damage_mult`（damage_mult はスロット定義値。通常攻撃は 1.0）
- **設計方針（2026-04-22 確立）**：近距離グループ（melee / dive）と遠距離グループ（ranged / magic）の比率を **2 : 1** に設計。旧値（1.5 : 1 相当）では遠距離が「安全なのに火力も高い」状態でリスク/リワード対応が崩れていたため、倍率差を広げて「リスクを取る見返り」を明確化。絶対値（0.2 / 0.1）は実プレイで即死問題がほぼ解消した値

**クリティカルヒット**:
- クリティカル率 = skill ÷ 3 %（例: skill=30 → 10%、skill=60 → 20%）
- クリティカル時: ベースダメージ × 2.0（power ステータス自体は変化しない）
- エフェクト・SE は既存アセット流用（HitEffect + hit_physical/hit_magic SE）

**被ダメージ計算フロー**（着弾後）:
1. **ベースダメージ算出**（`power × type_mult × damage_mult`）
2. **クリティカル判定**（skill からクリティカル率を算出。クリティカル時はベースダメージ × 2.0）
3. **防御判定**（3フィールド方式。各フィールドは独立してロール。背面攻撃は常にスキップ）
   - `block_right_front`：正面・右側面で有効　`block_left_front`：正面・左側面で有効　`block_front`：正面のみ有効
   - 成功したフィールドの合計値をダメージからカット
4. **耐性適用**（物理 or 魔法耐性の能力値から軽減率を算出して軽減。軽減率 = 能力値 / (能力値 + 100)）
   - 残ダメージ × (1 - 耐性%)
5. **最終ダメージ確定**（最低1）

**防御強度フィールドと有効方向**:

| フィールド | 有効方向 | 保有クラス例 |
|-----------|---------|------------|
| `block_right_front` | 正面・右側面 | 剣士・斧戦士・斥候・ハーピー・ダークロード |
| `block_left_front`  | 正面・左側面 | 剣士・斧戦士・ハーピー・ダークロード |
| `block_front`       | 正面のみ   | 弓使い・魔法使い・ヒーラー・ゾンビ・ウルフ・サラマンダー |

- 各フィールドは独立して `defense_accuracy` でロール（パーセント成功判定）
- 成功したフィールドの値の合計をダメージからカット
- 背面攻撃は常にすべてのフィールドをスキップ
- ガード中の正面攻撃：判定100%成功・全フィールドの合計をカット
- 方向判定ロジック：防御側の向き（facing）を基準に、攻撃者の相対位置から atan2 で角度を計算し4象限（90°ずつ）で判定
  - 正面 ±45° → 正面、背面 ±45° → 背面、それ以外 → 左側面 or 右側面
  - 近接攻撃・遠距離攻撃で共通のロジックを使用
- ダメージの方向倍率（旧1.0/1.5/2.0倍）は廃止。攻撃方向は防御可否のみに影響する

### 飛行キャラクター
- キャラクターデータに `is_flying` フラグを追加
- WALL・OBSTACLE・地上キャラ占有タイルを通過可能（飛行同士はブロックし合う）
- 攻撃の可否（攻撃タイプ別）

| 攻撃側 \ 対象 | 地上 | 飛行 |
|-------------|------|------|
| melee（地上） | 可 | 不可 |
| melee（飛行） | 不可 | 不可 |
| ranged | 可 | 可 |
| dive（飛行→地上） | 可 | — |

- 遠距離攻撃（ranged）：双方向で有効
- 降下攻撃（dive）：飛行キャラが地上の隣接対象のみ攻撃可。攻撃中も飛行扱いを維持

### 敵キャラクター一覧
- **クラスと個体の区別**：各敵は `enemy_list.json` の `stat_type` で「敵クラス」を参照する。「攻撃タイプ」や「攻撃間隔」はクラス側（`assets/master/classes/*.json`）で決まる
- 人間系クラス（fighter-sword / fighter-axe / archer / magician-fire / healer）は味方と共通の定義を流用。敵固有クラスは `zombie` / `wolf` / `salamander` / `harpy` / `dark-lord` の 5 種類
- **`behavior_description` は個別敵 JSON にのみ記述する**（種族単位の行動仕様として機能）。UnitAI 継承クラス（`GoblinUnitAI` 等）の実装時に Claude Code が参照する自然言語仕様として位置付ける。クラス側 JSON（味方クラス・敵固有クラス）には `behavior_description` を持たせない
- `is_flying` / `is_undead` / `instant_death_immune` / `chase_range` / `territory_range` / `projectile_type` も個体側

| 敵 | 攻撃タイプ | 特徴 |
|----|-----------|------|
| ゴブリン | 近接 | 集団行動。臆病で強い相手からすぐ逃げる |
| ホブゴブリン | 近接 | ゴブリンの強化版。数体を手下にする。狂暴で攻撃的 |
| ゴブリンアーチャー | 遠距離（弓） | 遠距離から弓で攻撃 |
| ゴブリンメイジ | 遠距離（魔法） | 遠距離から魔法で攻撃 |
| ゾンビ | 近接（つかみ） | 低速。近くの人間に向かってくる |
| ウルフ | 近接（かみつき＝つかみ効果） | 集団行動。高速移動 |
| ハーピー | 降下（dive） | 飛行（WALL・OBSTACLE・地上キャラを無視して移動）。飛行中は地上からの近接攻撃を受けない。地上の敵に隣接して降下攻撃を行う（攻撃中も飛行扱いを維持） |
| サラマンダー | 遠距離（炎＝魔法効果） | 遠距離から火を吐く |
| ダークナイト | 近接 | 人間型の強敵 |
| ダークメイジ | 遠距離（魔法） | 人間型。後方から魔法攻撃 |
| ダークプリースト | 支援（回復・バリア） | 人間型。後方で仲間を回復・強化 |
| スケルトン | 近接 | アンデッド（is_undead=true）。physical_resistance極高で物理攻撃ほぼ無効・魔法はある程度有効・ヒーラーの回復魔法が特効 |
| スケルトンアーチャー | 遠距離（弓） | アンデッド（is_undead=true）。スケルトンと同じ耐性特性。遠距離から弓で攻撃 |
| リッチ | 遠距離（魔法・火水交互） | アンデッド（is_undead=true）。火弾と水弾を交互に放つ。スケルトンと同じ耐性特性 |
| デーモン | 遠距離（魔法・thunder_bullet） | 飛行（is_flying=true）。雷属性魔法弾を使う強敵 |
| 魔王（ダークロード） | 遠距離（炎陣・範囲）＋ワープ移動 | ラスボス専用（フロア4のみ）。instant_death_immune=true。3秒間隔（game_speed除算）でランダムワープ移動。炎陣をAI側から呼び出して範囲攻撃 |

### 攻撃仕様
- 攻撃タイプ（CharacterData.attack_type）
  - melee（近接）: 隣接した地上の敵を攻撃。カウンター有効。飛行→飛行NG、地上→飛行NG
  - ranged（遠距離）: 射程内の全対象に飛翔体で攻撃。カウンター無効
  - dive（降下）: 飛行キャラが地上の隣接対象に降下攻撃。カウンター有効
- 種類：単体（当面。将来は範囲も追加）
- 属性タイプ：physical／magic（当面はphysicalのみ）
- クールタイム：事前（ため・詠唱）・事後（硬直）の両方あり
- 味方（クラス持ち）は `assets/master/classes/*.json` の **スロット単位**（`slots.Z` / `slots.V`）で `pre_delay` / `post_delay` を定義。プレイヤーも AI も `slots` から同じ値を参照する
- 敵は `assets/master/enemies/*.json` の**トップレベル** `pre_delay` / `post_delay`（スロット構造なし）
- pre_delay / post_delay は `game_speed` の影響を受ける（移動系と同じ。×2.0 で攻撃テンポも2倍）

### 攻撃フロー（一発一押下モデル：押下 → 離して発動）
プレイヤーから見える挙動は **「Z/A（V/Y）を押している間は射程表示・離して発動」** の一本化されたモデル。確定の二度押しは廃止。可視状態（マーカーの有無）と内部ステート、時間進行／停止が一致する設計。

#### 内部ステート（4 種）
1. **PRE_DELAY**（時間進行・**マーカー非表示**・LB/RB 無効・矢印キーは向き変更）
   - Z/A 押下直後。pre_delay タイマー消化中。射程オーバーレイのみ表示
   - **キャラの視覚補間（マス移動アニメーション）と並行進行**：移動中に攻撃ボタン押下 → PRE_DELAY 即開始・視覚補間は中断せず完了させる
2. **PRE_DELAY_RELEASED**（時間進行・操作不能。POST_DELAY と同等）
   - PRE_DELAY 中に Z/A を離した状態。残り pre_delay を時間進行で消化（マーカー非表示）→ Phase 2 で AUTO_CANCEL_FLASH 秒だけマーカー表示 → 攻撃発動 or 自動キャンセル
3. **TARGETING**（**時間停止**・**マーカー表示**・LB/RB 有効・矢印キーは向き変更）
   - PRE_DELAY 完了後、Z/A を押し続けてターゲット選定中。じっくり狙える
   - **突入条件：pre_delay タイマー完了 AND 視覚補間完了（`is_moving() == false`）の両方必須**
4. **POST_DELAY**（時間進行・操作不能）

#### 状態遷移
- NORMAL → **押下** → PRE_DELAY（視覚補間中でも即時・アニメ中断なし）
- PRE_DELAY → **解放**（pre_delay 完了前） → PRE_DELAY_RELEASED
- PRE_DELAY → **タイマー完了 AND 視覚補間完了** → TARGETING（どちらかが先でも両方満たしたフレームで遷移）
- PRE_DELAY_RELEASED → 残り pre_delay 完了 AND 視覚補間完了 → マーカー表示 AUTO_CANCEL_FLASH 秒 → 攻撃発動 / 自動キャンセル
- TARGETING → **解放** + 標的あり → 即攻撃発動 → POST_DELAY
- TARGETING → **解放** + 標的なし → AUTO_CANCEL_FLASH 秒後に自動キャンセル
- TARGETING → X/B（menu_back） → ノーコストキャンセル
- TARGETING → 他攻撃ボタン（Z 中の V／V 中の Z）→ スロット切替 → 新スロットの PRE_DELAY 突入

#### 設計原則
- **マーカー（カーソル＋アウトライン）の可視性 = ターゲット選択可能** = 時間停止 という三位一体を可視情報で揃える
- pre_delay 消化中はマーカー非表示（選択不可）。pre_delay 完了後にマーカーが現れる
- PRE_DELAY_RELEASED Phase 2 で完了後マーカーを一瞬表示するのは「マーカーは pre_delay 完了後に出る」という設計原則を保ちつつ、タップ操作に視覚フィードバックを与えるため
- TARGETING の時間停止は「ボタンホールド中のみ」。解放した瞬間（即発火 / AUTO_CANCEL 待機）は時間進行
- **TARGETING 突入時はキャラがマス中央に静止している**：pre_delay タイマーは移動中も並行消化する一方、TARGETING（時間停止）への遷移は視覚補間完了を必須条件とする。`abort_move()` による移動中断は行わず、自然完了を待つ

#### 共通仕様
- **押下中の矢印キー／左スティック／d-pad**：向きのみ変更（その場で即時回転・移動不可・pre_delay タイマーはリセットしない）。射程オーバーレイは向きに追従してリアルタイム更新。射程変化に応じて選択中ターゲットも次フレームで自動再評価される
- **LB/RB**：TARGETING（マーカー表示中）でのみターゲット循環。PRE_DELAY / PRE_DELAY_RELEASED では無効
- **AUTO_CANCEL_FLASH**：射程オーバーレイ＋マーカーを一瞬見せる演出時間。空振り時のキャンセル猶予と、PRE_DELAY_RELEASED Phase 2 のマーカー表示時間に共通使用
- **空振り判定**：pre_delay 中にターゲットが射程外に逃げた場合、`_confirm_target` 内の `_is_target_in_range` 再チェックで空振りキャンセル（既存）
- **V スロットのターゲット系**（headshot / water_stun / buff_defense）：同じ PRE_DELAY → TARGETING フローを共有

> **設計の経緯**：旧仕様は「Z/A 押下 → 離す → 確定のため再度 Z/A 押下」の 2 段階で、TARGETING 中は常に時間停止していた。中間案として「TARGETING も時間進行・解放で即発火」を試したが、pre_delay の長い遠距離キャラでじっくり狙う感覚が失われたため、本仕様（TARGETING 中はホールドしている間だけ時間停止）に落ち着いた

### 方向と防御
- 攻撃方向によるダメージ倍率は廃止。方向は防御判定の可否にのみ影響する（詳細は「命中・被ダメージ計算」節を参照）

## リポジトリ
- GitHub: https://github.com/komuro72/trpg
- ブランチ: master

## 作業ルール
- セッション終了時（「今日はここまで」など）にコミットを依頼された場合は、`git commit` に加えて `git push` まで行う
  - 理由：毎日新しいセッションで作業しており、別PCで作業再開することもあるため
- **画像ファイルを追加・更新したら、必ずその都度コミット＋プッシュまで行う**
  - 理由：画像はバイナリファイルのため差分が見えにくく、別PCで作業再開したときに古いままになりやすい
  - 対象：`assets/images/` 配下の全ファイル（キャラクター・敵・タイル・UI・飛翔体・エフェクトなど）
  - `.import` ファイルも一緒にコミットする（Godot がリソース解決に使用するため）
- Claude Code が新規ファイル・新規ディレクトリを作成した場合は、必ずコミット時に `git add` でステージングする
  - 対象：スクリプト（.gd）・シェーダー（.gdshader）・JSON・画像・シーン（.tscn）など Claude Code が作成した全ファイル
  - Godot が自動生成する `.import` / `.uid` ファイルはコミット不要（`.gitignore` 対象外だが追跡しない）
  - 新規ディレクトリ配下のファイルは `git status` で untracked になるため見落としやすい。意識的に確認する

## 敵キャラクターのステータス直接参照の禁止
- 敵キャラクターの正確なステータス（hp, max_hp, power, skill 等）をAIの判断ロジックで直接参照してはならない
  - 参照してよい情報：ランク、クラス（種族）、condition（状態ラベル）、位置、向き、is_alive、is_flying、is_undead など外見で判断できる情報
  - 理由：ゲーム仕様上、敵のステータスは不可視。将来的に情報制限を導入する前提で設計する
  - HP の推定は状態ラベル（condition: healthy/wounded/injured/critical）経由で行う
  - 戦力評価は `_evaluate_strategic_status()` を使う（返り値辞書の `full_party_*` / `nearby_allied_*` / `nearby_enemy_*` から必要な値を取り出す）
  - 種族固有リーダーAI（GoblinLeaderAI 等）でも同じルールを守ること
  - 自パーティーのメンバーのステータスは直接参照してよい
- **ただし開発用デバッグ UI（PartyStatusWindow）は本ルールの対象外**：F1 で開くデバッグウィンドウは「開発者が内部状態を確認するため」の機能のため、敵の hp / power / skill / _move_policy 等の内部状態を表示してよい。本ルールは「**AI の判断ロジック**が敵のステータスを参照すること」を禁じるもので、デバッグ表示（読み取り専用・ゲームプレイに影響しない）は対象外

## GDScript 警告の運用方針
- `warnings/inference_on_variant=1`（project.godot に設定済み）により、Variant 推論警告はエラー扱いせず警告として表示する
- 警告はビルドを通すが、放置はしない。コミットの節目に以下のコマンドで一覧を確認し、まとめて修正する：
  ```
  godot --headless --check-only 2>&1
  ```
- 典型的な修正パターン：`:=` による型推論 → `var x: 型 =` または戻り値に `as 型` を付けて明示

## 将来実装項目（未フェーズ）
- お金の概念・商店：アイテムシステム完成後に改めて設計
- 複数パーティーによるアイテム分配：現在は部屋制圧時にフィールドに散らばったアイテムを早い者勝ちで取得
- BGM
- 巻き添え（`friendly_fire`）：範囲攻撃（炎陣など）が味方・他パーティーにも当たる仕様。`CharacterData.friendly_fire: bool`（当面 false 固定）で管理し、将来切り替え可能にする
- 大型ボスの即死耐性設計：`instant_death_immune: bool`（ボス級は true）。ヘッドショット無効・無力化水魔法持続短縮。敵 JSON でフラグを設定できる設計にする
- ログ参照の改善（OrderWindowのログをより使いやすく）：現在は最新50件をそのまま表示するだけ。フィルタリング・検索・スクロール操作の改善を検討
- パーティーシステムの残作業：
  - [x] 戦況判断ルーチン（`_evaluate_strategic_status()`）の実装（PartyLeader の統合メソッド。3 集合 × 距離フィルタで戦力・戦況を返す）
  - [x] NpcLeaderAI の撤退ロジック追加（CombatSituation.CRITICAL 時に FLEE に切り替え。SAFE 復帰で EXPLORE に戻る）
  - [x] special_skill 指示のAI接続（strong_enemy / disadvantage 等の条件判定。PowerBalance / HpStatus で判定。_generate_special_attack_queue で発動）
- NpcLeaderAI のアイテム収集方針の動的切り替え：目標フロアに到達している場合（余裕がある状態）、item_pickup を "passive"（近くなら拾う）から "aggressive"（積極的に拾う）に切り替える。装備強化のために能動的にアイテムを回収する行動
- ✅ **アイテムのランダム生成機構**：2026-04-19 に完了（詳細は [docs/history.md](docs/history.md) 参照）
  - 最終採用方式：**定数ベース事前生成（総当たり 9 パターン）× フロア重み選択**
  - 各装備 9 パターン（盾は 3）を `assets/master/items/generated/*.json` に事前定義（計 75 エントリ）
  - `scripts/item_generator.gd` がフロアに応じた重み付き選択を実装
  - Config Editor「Item」カテゴリで 11 定数（bonus 比率・フロア基準 tier・距離重み・tier policy・初期ポーション個数）を調整可能
  - `effect` キー名の不整合（`restore_mp`/`restore_sp` 旧キー）も同時に一掃完了
- ✅ **Config Editor のアイテムタブ**：2026-04-19 に完了。ただし当初設計した「`generated/*.json` の個別エントリ編集 UI」から「タイプ別のルール（`base_stats`）編集 UI」に設計変更。個別アイテムは Claude Code が手動生成する運用（命名の整合性を保つため）。詳細は [docs/history.md](docs/history.md) 参照
- ✅ **「無」段階の導入**：2026-04-19 に完了。詳細は [docs/history.md](docs/history.md) 参照
  - 3 段階（low / mid / high）→ 4 段階（none / low / mid / high）に拡張。tier=0（none）エントリを各装備 9 タイプに 1 個ずつ追加（計 +9 エントリ）
  - 主人公初期装備（`game_map.gd:_dbg_items`）・NPC 初期装備（`dungeon_handcrafted.json:npc_parties_multi`）を `item_type` 文字列リスト化し、`ItemGenerator.generate_initial()` で統合生成
  - `dungeon_handcrafted.json:player_party.members[].items` は死にコードだったため物理削除
  - 初期ポーション個数（ヒール 5・エナジー 5）を Config Editor 化（`INITIAL_POTION_HEAL_COUNT` / `INITIAL_POTION_ENERGY_COUNT`）
  - **bonus / tier 概念分離**：`ITEM_TIER_*_RATIO` → `ITEM_BONUS_*_RATIO` リネーム。`FLOOR_X_Y_BASE_TIER` を String（"low/mid/high"）→ int（0〜3）に型変更
- **NPC フロア遷移判定のための戦況判断拡張（検討）**：`NPC_HP_THRESHOLD` / `NPC_ENERGY_THRESHOLD` 廃止により、現在は HpStatus のパーティー平均HP率で判定している。ただし元の「最低HP率」ベースや「エネルギー率」ベースの判定は NPC 行動として意味があるため、戦況判断（`_evaluate_combat_situation`）の副情報として最低HP指標・エネルギー指標を追加することを検討。別系統の判定を走らせず、戦況判断に一元化する設計方針を維持する。
- **完全リアルタイム化の検討**：当初は完全リアルタイム構想だったが操作が追いつかず半リアルタイムに後退した経緯がある。2026-04-20 の操作シンプル化（1 発 1 押下モデル）により障壁が下がったため再検討の余地あり。検討項目：プレイヤー待機中の時間停止廃止 / アイテム UI 中の時間停止扱い / NPC AI の再評価タイミングへの影響 / 学習曲線への配慮 / `game_speed` との関係整理
- **ポーション自動使用（プレイヤー操作キャラ）**：現状は AI 操作キャラ向けのみ自動使用機構あり。プレイヤー操作キャラにも同等の自動使用を導入（操作中も on_low_hp / sp_mp_potion 指示に従う）
- **他タブの hidden 候補棚卸し**：本日 Character タブの色定義 12 個を hidden 化したが、他タブ（PartyLeader / NpcLeaderAI / SkillExecutor / Effect / Item 等）にも非表示候補がないか棚卸し
- **装備品による `move_speed` 補正**：現状 `move_speed` は装備補正の対象外。将来「重装で遅くなる」「素足で速くなる」等の追加余地あり
- **`stat_bonus` の負値対応**：`enemy_list.json` の `stat_bonus` は加算のみ。敵個別調整で「base から減らしたい」要望が出たら負値許容を検討（現状は class_stats / enemy_class_stats のベース値を直接いじるしかない）
- **`energy_recovery` の個体差対応**：現状は `ENERGY_RECOVERY_RATE` 全キャラ共通定数。クラス・種族・ランクで個体差を出したくなったら二層構造化（`BASE_ENERGY_RECOVERY × status / 50`）を検討

### Phase 14 バランス調整の事前情報

バランス調整を開始する前に認識しておくべき、本日（2026-04-18）までのリファクタリングによる影響と観察事項：

#### 敵が盾で防御するようになった
- SkillExecutor 統一（2026-04-18 完了）により、Player 側でしか機能していなかった防御判定ロジックが AI 側でも正しく機能するようになった
- 結果として**敵が盾で攻撃を防ぐケースが増加** → 敵の生存率が上昇している可能性
- **バランス調整候補**：
  - 敵の `defense_accuracy`（防御判定成功率）を下げる
  - 敵の `block_*`（防御強度）を下げる
  - 味方の `power`（攻撃力）を上げる
  - 盾装備の補正値を見直す

#### Player / AI の計算式統一完了
- 2026-04-18 より前に調整した値は、片方でしか機能していない可能性がある（`damage_mult` / `duration` / `heal_mult` / AI の水弾未判定 等）
- **バランス調整は「統一後の値」を正として行う**
- 同じ条件で Player と AI で同じダメージが出ることを前提にできる

#### Config Editor で編集可能な主要定数（バランス調整の起点）
- **クラス単位**：各クラス JSON の `power` / `skill` / 各スロットの `damage_mult` / `heal_mult` / `duration` / `tick_interval` / `range` / `cost` 等（「味方クラス」「敵クラス」タブ）
- **`ATTACK_TYPE_MULT[melee/ranged/magic/dive]`**：定数タブ > Character カテゴリ
- **`CRITICAL_RATE_DIVISOR`**：定数タブ > SkillExecutor カテゴリ（`skill ÷ 300` が既定）
- **`PROJECTILE_SPEED`**：定数タブ > SkillExecutor カテゴリ（飛翔体演出速度）
- **`ENERGY_RECOVERY_RATE`**：定数タブ > Character カテゴリ（MP/SP 回復速度）
- **戦況評価閾値**：`HP_STATUS_*` / `COMBAT_RATIO_*` / `POWER_BALANCE_*`（定数タブ > PartyLeader カテゴリ）
- **属性・個別ステータス**：`assets/master/stats/class_stats.json` / `enemy_class_stats.json` / `attribute_stats.json` / `enemy_list.json`（味方ステータス・敵ステータス・属性補正・敵一覧タブ）

## 要調査・要整理項目
バグ可能性・構造整理・命名整理など、実装ではなく調査系のタスク。

### 優先度別インデックス（2026-04-21 時点）

FLEE 関連の派生課題は「次セッションで検討するタスク」→「FLEE 派生課題」に移動済み。以下は FLEE 以外の派生課題を優先度別にラベル付け：

**優先度：高**
- Phase 14 バランス調整の実プレイ検証（→「次セッション最優先」セクションで詳述・別途扱い）

**優先度：中**
- フロア基準値（`FLOOR_*_RANK_THRESHOLD` / `FLOOR_RETREAT_RATIO`）の実プレイ調整（後述「並行して継続するタスク」）

**優先度：低**
- 戦況判断と避難先計算の関数統合（FLEE 派生課題 5 を参照）
- 敵パーティーの FLEE 避難先情報表示（FLEE 派生課題 7 を参照）
- 敵メンバーへの `leader` 配布検討
- 生存数表示（x/y）の仕様確認（プレイヤー Party は adoption で動的変動するため現状 fallback_size）
- `_find_friendly_retreat_goal` 関数の削除（FLEE 派生課題 6 を参照・dead code）
- legacy フィールドの棚卸し継続
- 敵ヒーラー回復動作確認
- 「敵クラス」vs「種族」概念整理
- ファイル名ハイフン/アンダースコア統一
- `enemy_list.json` と `enemies_list.json` 命名の紛らわしさ
- Config Editor ツール等での設定変更 git 反映方針
- BUST_SRC_* の比率化
- エフェクト線幅の GRID_SIZE 連動
- dark-lord のワープ・炎陣を SkillExecutor 経由へ
- エフェクト生成の一系統化
- hero.json の整理
- `PlayerController._spawn_heal_effect` の実態確認
- 画像フォルダ名パース関数の共通化

**優先度：低（2026-04-23 ヒーラー回復モード再設計の派生）**
- `lowest_hp_first` で「満タンにしてくれない」現象の再評価：現状は仕様どおりだが、ゲーム体験として違和感が出るようなら判定条件の緩和（例：`missing_hp ≥ heal_amount × 0.5`）を検討
- 回復量計算の乱数・クリティカル対応：現状は期待値判定（乱数なし前提）。将来回復にバラつきを入れる場合、判定側の扱いを再検討

### 以下、個別項目の詳細記述：


- **戦況判断と避難先計算の関数統合**（優先度：低）
  - 現状：`_evaluate_strategic_status()`（戦況判断）と `_determine_flee_recommended_goal()`（避難先計算）が別関数・別データ
  - 目標：避難先情報も戦況判断の一部として統合し、receive_order 経由で `combat_situation` 辞書に含める形にする
  - 背景：リーダーが自律計算する情報は全て 1 箇所に集約するのが設計原則（2026-04-19 の `_evaluate_strategic_status()` 統合と同じ方針）
  - スコープ：PartyLeader の計算ロジック統合・receive_order 配布の整理

- **敵パーティーの FLEE 避難先情報表示**（優先度：低）
  - 現状：敵パーティーは避難先情報を保持しない（FLEE 実装が旧 `_find_flee_goal_legacy` のみ）
  - 将来の敵 FLEE 新ロジック実装時に、味方と同じ `避難先:xxx(d:n)@(x,y)` 表示を敵ヘッダーにも追加する
  - 敵種族ごとに避難先の意味が異なる可能性（縄張り戻り / 階段逃走など）の設計検討必要

- **敵メンバーへの `leader` 配布検討**（優先度：低）
  - 現状：敵メンバーは `leader = null` で配布されている（`_assign_orders` の `if member.is_friendly:` ガード内でのみ formation_ref が設定される）
  - これは「パーティー戦略はリーダー個人の属性ではない」という 2026-04-21 の設計原則とは独立した話で、「隊形計算などで敵でもリーダー参照が必要になる場面があれば `leader` 配布を検討する」という別課題
  - 敵側の `_party_strategy` enum 直接配布（`party_fleeing` 廃止）とは別タスクとして切り出し
- **legacy フィールドの棚卸し**（継続運用）：
  - ✅ 個別敵 JSON の `hp` / `power` / `skill` / `physical_resistance` / `magic_resistance` / `rank` → 2026-04-19 に物理削除完了（`CharacterData.load_from_json` の読み出しも同時削除）
  - 次の棚卸し候補：
    - **hero.json の扱い整理**：現行コードでは `CharacterGenerator.generate_character` が使われ、`load_from_json(hero.json)` 経由では読まれない。主人公の初期データとしてどう位置付けるか（完全に削除するか、`CharacterGenerator` のテンプレートにするか等）の方針決定
    - `assets/master/classes/*.json` に潜むかもしれない使われていない定義
    - クラス JSON / ステータス JSON / 個別敵 JSON の未参照キーがないか横断調査
  - 他にも潜んでいる可能性あり。定期的に Claude Code に全体棚卸しを依頼する運用
- **敵ヒーラー（dark_priest）の回復が機能しているか動作確認**：2026-04-18 の energy 統合で `apply_enemy_stats` が `max_energy = stats.energy` を設定するようになったため、dark_priest も通常の魔法クラス同様に回復・バフが撃てるはず。実機で確認したら本項目は削除
- **「敵クラス」vs「種族」の概念整理**：Excel 仕様書では「敵クラス」、コード／AI 実装では「種族」（GoblinLeaderAI 等）と呼んでいる。現状は動作に問題ないが用語の使い分けがあいまいで将来混乱の元になる可能性。整理したい
- **ファイル名のハイフン／アンダースコア統一**：個別敵 JSON は `dark_lord.json` 等アンダースコア、クラス JSON は `dark-lord.json` 等ハイフン。統一するなら個別敵 JSON をハイフンに寄せる。ファイル名変更はコード側の参照も書き換えが必要
- **`enemy_list.json` と `enemies_list.json` の紛らわしい命名**：役割が全く違う（前者はステータスタイプ参照マップ、後者は敵ファイルパス一覧）のにファイル名が酷似。片方リネーム候補
- **Config Editor やツール類での設定変更の git 反映方針**：JSON ファイル・画像素材などバイナリファイルの、自動 commit/push の是非を含めた運用ルール検討が必要
- ✅ **画像サイズ設計是正**：2026-04-19 に完了。詳細は [docs/history.md](docs/history.md) 参照
  - A1: `Projectile.SPRITE_REF_SIZE = 64.0` → `GlobalConstants.PROJECTILE_SIZE_RATIO = 0.67`（GRID_SIZE 比率・Config Editor Effect カテゴリ）
  - D1: `SPRITE_SOURCE_WIDTH` / `SPRITE_SOURCE_HEIGHT` dead constants を削除（未使用だった）
  - D2: `_crop_single_tile` 関数削除（実装が no-op で存在意義なし。呼び出し側で直接 tex を渡す）。git 履歴：2026-04-11 の Phase 13-6 コミット（f9162ff）で 1/4 切り出し → no-op に変更されていた
  - D3: `DiveEffect.RADIUS = 18.0` → `GlobalConstants.DIVE_EFFECT_RADIUS_RATIO = 0.2`（GRID_SIZE 比率・Config Editor Effect カテゴリ）
  - PROJECTILE_SPEED を SkillExecutor → Effect カテゴリに移動（演出専用と判明したため）
  - **設計原則の確立**：GlobalConstants は「画像元サイズと GRID_SIZE の関係を直書きで持たない」方針。必要な値は (1) `tex.get_size()` で動的取得、または (2) GRID_SIZE 比率として定義する
- **BUST_SRC_* の比率化（次回棚卸し候補・優先度低）**：`message_window.gd` の `BUST_SRC_X/Y/W/H = 256/0/512/512` は現状 1024x1024 前提で書かれており、`tex_size.x >= 1024` のガード付きで動作している。将来 2048x2048 のアセットを追加する場合に備えて比率（0.25 / 0 / 0.5 / 0.5）× tex_size に書き直すのが安全だが、現状問題なく動作するため優先度低
- **エフェクトの線幅系の GRID_SIZE 連動検討（次回棚卸し候補・優先度低）**：`HitEffect.RING_WIDTH = 2.5` / `HealEffect.RING_WIDTH = 2.5` / `BuffEffect.LINE_WIDTH = 2.0` などの「線の太さ px」が固定値で、4K 等の高解像度ディスプレイで相対的に細くなる。視覚的問題は小さいが気になる場合は GRID_SIZE 比率化を検討
- **Config Editor 全タブの表示フィールド棚卸し（定期運用）**：各タブ（定数 / 味方クラス / 敵クラス / 敵一覧 / ステータス）の表示対象が元データの全フィールドを網羅しているか、意図的に除外しているフィールドに理由付けがあるかを定期的に確認する。Config Editor の重要な役割の一つは「定数・データの重複や不足をチェックできるようにする」こと。Config Editor から不可視のフィールドは設定ミス・仕様変更の影響が見えにくくなる。2026-04-19 に「敵一覧」タブの棚卸しを実施（name / projectile_type を追加）。味方クラス・敵クラス・ステータス各タブは次回以降
- **Player 側と AI 側の計算ロジック統一（SkillExecutor 抽出）** — ✅ 完了（2026-04-18）
  全 10 種類の特殊行動を `SkillExecutor` クラス（`scripts/skill_executor.gd`）に集約済み。詳細は CLAUDE.md「AI と実処理の責務分離方針」→「実処理の共通化（完了）」セクションを参照。今後の新スキル追加時は SkillExecutor に `execute_*()` を実装し、Player / AI の両方から呼ぶこと。
  残課題：
  - **dark-lord のワープ・炎陣**：現状キュー外で動く例外的実装。将来 SkillExecutor 経由にリファクタする余地あり（CLAUDE.md の「例外的実装（要整理）」を参照）

- **エフェクト生成の一系統化**：視覚エフェクトの生成が「Character 経由」と「SkillExecutor 内で直接 `.new()`」の 2 系統混在。詳細は CLAUDE.md「AI と実処理の責務分離方針」→「エフェクト生成の方針（段階移行中）」セクションおよび `docs/investigation_skill_executor_constants.md` を参照。ゲーム動作には影響なし・別タスクで段階的に対応

- ✅ **Legacy LLM AI コードの棚卸し削除**：2026-04-19 に完了。以下 5 クラス（約 1,221 行）と関連 dead code を物理削除：
  - `BaseAI`（547 行）/ `EnemyAI`（401 行）/ `LLMClient`（109 行）/ `DungeonGenerator`（119 行）/ `GoblinAI`（45 行）
  - 併せて `CharacterData.create_hero()` / `create_goblin()` dead method も削除
  - 詳細は [docs/history.md](docs/history.md) の 2026-04-19 エントリを参照

- ✅ **向き変更コストの調査**：2026-04-20 完了。詳細は [docs/investigation_turn_cost.md](docs/investigation_turn_cost.md) 参照
  - 結論：コスト発生はプレイヤー通常移動の TURN_DELAY=0.15s のみ。AI と攻撃中は即時で完全非対称
  - dead code 2 件（`get_direction_multiplier` / `guard_facing` コメント）は 2026-04-21 に削除完了（`character.gd`）
- ✅ **移動関連定数の棚卸し**：2026-04-20 完了。詳細は [docs/investigation_movement_constants.md](docs/investigation_movement_constants.md) 参照
  - 重要発見：`character_data.move_speed` 完全 dead data / `MOVE_INTERVAL` の SoT が PlayerController と UnitAI に分裂 / game_speed 適用パターンが 4 種類混在 / Wolf・Zombie の game_speed 未適用バグ / DarkLordUnitAI の warp_timer 逆方向バグ
- ✅ **敵クラスステータスの利用状況調査**：2026-04-20 完了。詳細は [docs/investigation_enemy_class_stats.md](docs/investigation_enemy_class_stats.md) 参照
  - 重要発見：11 ステータス中 10 個は正常動作・move_speed のみ dead / 16 敵中 11 敵が人間 class_stats を借用 / `enemy_class_stats.json` が Config Editor で編集不可

- ✅ **敵クラスステータスの Config Editor 対応（Step 1-A）**：完了。詳細は [docs/history.md](docs/history.md) 参照
  - 事前調査（ステータス算出ロジック）でロジックは既に統一済みと判明。当初想定より小さい範囲で完了
  - Config Editor のトップタブをフラット 8 タブ構造（`定数 | 味方クラス | 味方ステータス | 属性補正 | 敵一覧 | 敵クラス | 敵ステータス | アイテム`）に再編
  - サブタブ構造（「ステータス」→ クラスステータス / 属性補正）を廃止しトップレベルに昇格。属性補正は味方・敵共通のルールなので味方ブロックと敵ブロックの橋渡し位置に独立タブとして配置
  - `_build_class_stats_tab(parent, tab_name, source_id, data, class_ids)` として描画関数を共通化。味方ステータスと敵ステータスで同じグリッドを再利用
  - 残る非対称項目：画像フォルダ名パース関数の共通化（`_parse_folder_name` / `_parse_enemy_folder_name`）は別タスク化（優先度低）

- **`PlayerController._spawn_heal_effect` の実態確認**：`docs/investigation_skill_executor_constants.md` の調査で、このメソッドがどこからも呼ばれていない可能性が指摘されている。SkillExecutor 移行後の残骸の可能性。参照調査して本当に未使用ならデッドコードとして削除

- **画像フォルダ名パース関数の共通化（優先度低）**：`CharacterGenerator._parse_folder_name`（味方・プレフィックスマッチ）と `_parse_enemy_folder_name`（敵・`_male_`/`_female_` 境界検出）が別実装。敵 ID にハイフンが含まれるため両者の戦略が異なるが、共通インターフェイスで統合できる余地あり。動作には問題なし

## 参照ファイル
- docs/spec.md：詳細仕様書（実装前に参照すること）
