# 変更履歴・バグ修正記録

> CLAUDE.md フェーズセクションの圧縮時に抽出した変更履歴。
> 正常に完了した新規実装の詳細は docs/spec.md を参照。

## 2026-04-24（fall_back 個体アクションの二段階協調実装）

### 概要

CLAUDE.md「FLEE 派生課題 4 個体アクションの実行ロジック差別化」のうち `fall_back` 部分を実装。`flee` / `keep_distance` と意味論的に分離されていた `fall_back` に、独自の目標タイル計算ロジック（リーダー推奨集合点への移動）を持たせた。FLEE の二段階協調（リーダー推奨 + メンバー自律選択）と対称な構造を維持しつつ、候補集合とコスト式だけを置き換える形で実装。

### 設計論点：重心方式 → weight 方式への転換

当初は「パーティー全員の重心付近に後退する」案だったが、複数の敵グループに挟まれたときに「重心 = 両グループの中間」という**最も危険な点**を推奨してしまう問題があった。そこで FLEE と同じ「脅威コスト付き A* で各候補を評価し最小コストを選ぶ」 weight 方式に転換。

- 重心は**目標を 1 箇所に集約する引力**として弱く加算する形に降格（重み 0.5）
- 代わりに**脅威コスト**（既存 `_calc_threat_cost`・敵から近いほど加算）をメインコストに据える
- リーダー距離はコンパクトな隊形を保つための弱い加算（重み 1.0）

これにより、敵が 2 方向から来る状況でも「脅威から離れつつ味方が集結できる点」が選ばれる。

### FLEE との対称性

| | FLEE | fall_back |
|---|---|---|
| 目的 | エリアから完全離脱（避難先まで） | 現エリア内で安全な集合点へ後退（戦闘継続） |
| 候補集合 | エリア出口タイル群 | リーダー周辺の歩行可能タイル群（マンハッタン半径 R） |
| 推奨キー | `flee_recommended_goal` | `formation_fallback_goal` |
| コスト式 | 脅威 A* + エリア距離 × w | 脅威 A* + リーダー距離 × w1 + 味方重心距離 × w2 |
| メンバー側 | 自律 A* 再評価 + 推奨バイアス | 推奨そのまま採用（軽量化） |
| 避難先到達後 | `wait` に落ちる | 通常の到達判定で完了 |

メンバー側で脅威コスト A* を再評価しない理由：fall_back は同エリア内の近距離目標なので、リーダー層で 1 回評価すれば十分。FLEE のように「メンバー位置によって最適出口が違う」問題は fall_back では起きない（集合点は共通でよい）。

### 実装ファイル

**新規/改修**:
- `scripts/global_constants.gd`：UnitAI カテゴリに `FALL_BACK_SEARCH_RADIUS` (6) / `FALL_BACK_LEADER_DISTANCE_WEIGHT` (1.0) / `FALL_BACK_ALLY_CENTROID_WEIGHT` (0.5) を追加。`CONFIG_KEYS` 配列にも追加（当初 `FALL_BACK_REEVAL_MIN_INTERVAL` も追加したが、後述のパフォーマンス修正で削除）
- `assets/master/config/constants.json` / `constants_default.json`：4 定数のエントリ追加
- `scripts/party_leader.gd`：
  - 状態変数 `_fallback_recommended_goal` 追加（当初 `_fallback_last_reeval_time` も追加したが、後述のパフォーマンス修正で削除）
  - `_update_fallback_recommended_goal()` / `_determine_fallback_recommended_goal()` / `_calc_ally_centroid()` / `get_fallback_recommended_goal()` 新設
  - `_assign_orders()` から `_update_fallback_recommended_goal()` を呼び、`formation_fallback_goal` キーを配布
  - `on_member_area_changed()` が FLEE と fall_back の両方を再評価（それぞれ独立クールダウン）
- `scripts/unit_ai.gd`：
  - 状態変数 `_formation_fallback_goal` 追加・`receive_order` で受信
  - `_find_fall_back_goal()` 新設（推奨採用 + legacy フォールバック）
  - `_start_action` / `_step_toward_goal` の `"flee" / "fall_back" / "keep_distance"` 分岐を分離（`fall_back` だけ別ロジックを呼ぶ）
- `scripts/party_status_window.gd`：
  - `VAR_PRIORITY` に `formation_fallback_goal: 2`（低）追加
  - `_build_ai_flag_parts()` に `fb→(x,y)` 表示追加（味方メンバー限定）

### スコープ外（派生タスク）

- **敵パーティーへの適用**：FLEE 派生課題 1（敵 FLEE の二段階化）と合流して対応予定。敵固有の「縄張り戻り」集合点をどう定義するかの設計が必要
- **「後衛が前に進む問題」の解決**：味方クラスへの `keep_distance` 適用＝派生課題 3。ATTACK 戦略中 + 敵接近時の自動発火機構は別タスク
- **`keep_distance` の差別化**：現状ゴブリンアーチャーの挙動が良好なので手を付けない。将来 `attack_range` を参照して「遠ざかりすぎない」ロジックに差別化予定

## 2026-04-24 深夜（fall_back を FLEE 計算結果の再利用方式に刷新：パフォーマンス根治）

### 背景：夕の頻度削減では不十分だった

2026-04-24 夕の修正（`on_member_area_changed` 経由の fall_back 再評価を削除）を適用しても、Komuro の実機確認で **「約 1.5 秒ごとに約 1 秒フリーズ」** が残存。頻度は `REEVAL_INTERVAL = 1.5s` に抑えたのに 1 秒止まる → **単発の計算コストが 1 秒近い**と推測され、前回の見積もり（1〜5ms）が 2 桁以上の過小評価だったことが濃厚に。

### Step A 静的再分析で判明した主因

Claude Code が計測コード埋め込みなしで静的分析に絞って再検証した結果、**`_calc_threat_cost` の A* 内ループ毎回呼び出し**が真のボトルネックと判明:

- `_determine_fallback_recommended_goal()` は 70 候補 × `_astar_with_cost` を実行
- A* 内で各ノード展開ごとに 4 近傍の `cost_fn.call(neighbor)`（= `_calc_threat_cost`）を呼び出す
- `_calc_threat_cost` は `_all_members` = **全フロア合計 ~150 体**を線形反復
- 1 回の `_determine_fallback_recommended_goal` あたり：
  - 候補 70 × 平均 12 iter × 4 近傍 = **~3,400 回の `_calc_threat_cost` 呼び出し**
  - 各呼び出しで 150 chars 線形反復 = **~510,000 chars 反復**
  - GDScript の Callable dispatch 込みで **~560ms / 呼び出し**

前回見積もりで見落としていた点：
1. `_all_members` は 5 フロア全敵・全 NPC を含む（~150 体・当初「50+」と見ていた）
2. GDScript の Callable dispatch が重い（1 呼び出し ~1-2μs）
3. A* の `open_set` が線形スキャン O(N²) 実装

### Step 1 調査で判明した FLEE の本質

対策検討の前に、既存 FLEE 実装を詳しく調査（`docs/investigation_flee_implementation.md` 相当の内容は本履歴と CLAUDE.md で代替）:

**FLEE は「避難先までの経路」を事前計算していない**:
- `_find_flee_goal()` は常に**現エリアの出口タイル**を返す（避難先内タイルではない）
- `_step_toward_goal()` で**毎ステップ `_goal` を再計算**する
- メンバーがエリアを跨ぐと、次ステップでは新エリアの出口が目標になる
- `_generate_queue` の冒頭で `_is_in_refuge_area()` 判定 → 到達済みなら wait に切替

つまり **FLEE = 「現エリアの最善出口」の局所最適チェイン**。一度の計算は軽量（候補 = エリア出口 2〜6 個のみ）。

### 設計転換：fall_back = FLEE の途中停止バージョン

FLEE 実装の本質を踏まえ、fall_back は **FLEE の計算結果をそのまま再利用し、停止条件だけ差別化**する形に再設計:

| | FLEE | fall_back（刷新後） |
|---|---|---|
| リーダー計算関数 | `_determine_flee_recommended_goal()` | **同関数を共用**（無変更） |
| 配布キー | `flee_recommended_goal` | **同キーを共用** |
| メンバー出口評価 | `_find_flee_goal()` | **同関数に委譲**（無変更） |
| 停止条件 | `_is_in_refuge_area()`（避難先エリア到達） | `_is_far_enough_from_threats()`（射程 + MARGIN 外） |

### リーダー層の変更（`scripts/party_leader.gd`）

**核心**：`_update_flee_recommended_goal()` のガードを `_is_party_fleeing()` から「敵パーティーでない + 敵検知中」に緩和。計算結果そのものは同一なので FLEE 挙動は不変。

```gdscript
# 変更前
func _update_flee_recommended_goal() -> void:
    if not _is_party_fleeing():
        return ...
    _flee_recommended_goal = _determine_flee_recommended_goal()

# 変更後
func _update_flee_recommended_goal() -> void:
    if _is_enemy_party():
        # 敵は legacy 維持（FLEE 中のみ）
        ...
        return
    # 味方は敵検知中なら FLEE/fall_back 問わず常時計算
    if _combat_situation.nearby_enemy_rank_sum <= 0:
        ...
        return
    _flee_recommended_goal = _determine_flee_recommended_goal()
```

同様に `on_member_area_changed()` の FLEE 中ガードも外し、敵検知中の味方で再評価が効くように戻した（夕の修正を部分的に戻す）。推奨出口は 2〜6 × A* の軽量計算なのでコスト許容範囲。

### メンバー層の変更（`scripts/unit_ai.gd`）

**`_find_fall_back_goal()` をラッパー関数に書き換え**:

```gdscript
func _find_fall_back_goal(threat) -> Vector2i:
    if not _member.is_friendly:
        return _find_flee_goal_legacy(safe_threat)  # 敵は legacy
    if _is_far_enough_from_threats():
        return _member.grid_pos  # 射程外で停止
    return _find_flee_goal(safe_threat)  # FLEE と同じ出口評価
```

**`_is_far_enough_from_threats()` 新設**：`_all_members` 150 体を早期 continue で反復（同フロア対立陣営のみ距離計算）・`attack_range + FALL_BACK_MARGIN` 以上なら true。~150μs / 判定。

**`_generate_queue(FALL_BACK)` の冒頭に wait 判定追加**：FLEE の `_is_in_refuge_area()` と対称の構造。射程外に到達していれば `[{wait}]` を返してキュー消化を終わらせる。

### 削除・追加まとめ

**削除**（計算コスト過大な旧実装を全廃）:
- 定数 3: `FALL_BACK_SEARCH_RADIUS` / `FALL_BACK_LEADER_DISTANCE_WEIGHT` / `FALL_BACK_ALLY_CENTROID_WEIGHT`
- PartyLeader 関数 3: `_determine_fallback_recommended_goal()` / `_calc_ally_centroid()` / `_update_fallback_recommended_goal()`
- PartyLeader state 1: `_fallback_recommended_goal`
- UnitAI state 1: `_formation_fallback_goal`
- receive_order キー 1: `formation_fallback_goal`
- PartyStatusWindow: `VAR_PRIORITY["formation_fallback_goal"]` と専用 fb→ ブランチ

**追加**:
- 定数 1: `FALL_BACK_MARGIN = 2`（`attack_range` に加算する停止余裕マス数）
- UnitAI 関数 1: `_is_far_enough_from_threats()`
- PartyStatusWindow `fb→` 表示：既存 `_flee_recommended_goal` を参照し、現在アクションが `fall_back` のときラベル切替

### 理論効果

- 1 パーティー単発 ~560ms → **~数ms**（FLEE と同等）
- 1.5 秒周期のパーティー同時発火時のフレームスパイクが解消
- 100 倍以上の高速化

### 設計原則の明文化

> FLEE と fall_back は「目標」が同じで「停止条件」だけが違う。リーダー層の推奨出口計算は共通化し、メンバー層のラッパー関数で違いを表現する。FLEE 実装を fall_back 用に変更しない（意味拡張はガード緩和のみ）。

### 学び（反省点）

- **見積もりの確信度を過信**：前回「1〜5ms」の見積もりを Komuro に報告しつつ修正方針を進めたが、実機フリーズで **100 倍の過小評価**と判明。定量計測を省略しないほうが良い場面だった
- **`_all_members` の真のサイズを軽視**：setUp 時点で 5 フロア全キャラを配布していることに気づかず、「50+」と過小評価。大規模データ反復があるコードは**所属データの全量**を確認する
- **GDScript の Callable dispatch コスト**：C++ 感覚で ops 換算すると 10-50 倍のズレが出る。ループ内 `cost_fn.call(...)` は常に警戒
- **設計の対称性が常に正しいわけではない**：FLEE と fall_back を「対称に作る」という発想は自然だが、頻度（FLEE は稀・fall_back は常時）や計算単価（出口 2-6 vs 候補 70+）が桁違いに異なる場合、**計算結果の再利用**のほうが対称性より重要

## 2026-04-24 深夜（脅威マップ事前計算による FLEE/fall_back 推奨出口計算の高速化）

### 背景：FLEE 再利用方式でも単発 50 ms のディレイが残った

fall_back を FLEE 再利用方式に刷新した後、Komuro 実機確認で「1 秒フリーズは解消したが、1.5 秒周期に視認できるディレイが残る」と報告。計測コード（`[EXIT_PERF]` / `[EXIT_FRAME]`）を仕込んで実測ログを取ったところ、以下が判明：

**単発 `_determine_flee_recommended_goal()` の実コスト**:
- 最小 25.6 ms / 最大 76.1 ms / 中央値 **~50 ms**
- 前回の見積もり「FLEE と同等 ~数 ms」は **10〜15 倍の過小評価**だった

**同時発火パターン**:
- 12:08:16 の 160 ms 窓に 8 パーティーが時間差発火 → 累積 **172 ms**
- 12:08:18 の 110 ms 窓に 5 パーティー → 累積 **209 ms**
- 12:08:19 の 156 ms 窓に 6 パーティー → 累積 **185 ms**
- 各パーティーの `_reeval_timer` が同位相で進むため、1.5 秒ごとにまとまって発火

→ **体感ディレイ = 単発 50 ms × 複数パーティーの集中発火**

### 原因特定

`_calc_threat_cost` を A* の内ループで毎回呼ぶ設計が主因:

- A* 1 回で 50〜100 ノード展開 × 4 近傍 = 200〜400 回の `_calc_threat_cost` 呼び出し
- 各呼び出しで `_all_members`（全フロア合計 150 体）を線形反復
- 出口 3〜4 個評価すると合計 **18〜24 万回のキャラ評価** / `_determine_flee_recommended_goal` 呼び出し
- GDScript の Callable dispatch コストを含め、単発 ~50 ms が妥当な実測値

### 対策：脅威マップを事前計算して cost_fn は辞書参照だけに

**発想**：同じタイルの脅威コストを何度も計算するのではなく、**敵から影響範囲タイルへの貢献を先に加算**した Dictionary を 1 回だけ構築する。A* は Dictionary 参照するだけ。

### 等価性の証明

`_calc_threat_cost(tile)` と `_build_threat_map(for_member).get(tile, 0.0)` は**数学的に等価**（加算順序の入れ替えのみ）:

- `_calc_threat_cost`: 各敵 e について `manhattan(tile, e.pos) < range_tiles` なら `(range_tiles - d) * weight` を加算
- `_build_threat_map`: 各敵 e の周囲 `dx,dy ∈ [-R+1, R-1] かつ |dx|+|dy| < R` のタイルに同じ contribution を加算

任意の tile で、集約されるコントリビューションの集合・値が同じことが証明可能（関数 doc に記載）。

### 実装

- 新設：`_build_threat_map(for_member: Character) -> Dictionary`（[party_leader.gd](../scripts/party_leader.gd)）
  - `_calc_threat_cost` と完全に同じフィルタ条件（陣営・フロア・HP）
  - 計算量：150 体 × ~41 マス影響範囲 = **~6,150 ops（~2 ms）**
- `_determine_flee_recommended_goal()` 内：
  ```gdscript
  # 旧
  var threat_fn: Callable = Callable(leader_ai, "_calc_threat_cost")
  # 新
  var threat_map: Dictionary = _build_threat_map(leader_char)
  var threat_fn: Callable = func(tile): return threat_map.get(tile, 0.0)
  ```
- `_astar_with_cost` / `_path_cost` は無変更（汎用性保持）
- `_calc_threat_cost` も無変更（他から呼ばれる可能性があるので残置・現状 PartyLeader 以外の呼び出しはなし）

### 理論効果

| 項目 | 旧方式 | 新方式 |
|---|---|---|
| 事前計算 | なし | 1 回 / 6,150 ops / ~2 ms |
| A* 内 cost_fn 1 回 | ~225 μs（150 体反復） | ~1 μs（辞書参照） |
| 1 A* の cost_fn 呼び出し | 200〜400 回 × 225 μs = 45〜90 ms | 200〜400 回 × 1 μs = 0.2〜0.4 ms |
| 3 出口評価の合計 | **~50 ms** | **~5〜10 ms** |
| **高速化倍率** | — | **40〜80 倍** |

### 副次効果

- FLEE にも自動適用（共通関数のため）。FLEE 連発シナリオでも効く
- パーティー同時発火の累積負荷も 10 倍以上軽減（210 ms → 20 ms 以下の見込み）
- 位相分散（`_reeval_timer` ランダム初期化）は**実施せず**。本対策で十分と判断。まだ重ければ次タスクで追加

### 学び

- **`_all_members` の 5 フロア合計 150 体**は見落としがちな大規模データ。ループ内で走査する関数は警戒が必要
- **GDScript の Callable dispatch は ~1 μs/回のオーバーヘッド**。ホットループ内の `cost_fn.call(...)` は注意
- **等価性の数学的証明をコメントに残す**：加算順序の入れ替えは見た目の差が大きいので、同じ結果になる根拠を明示しておくとレビュー・保守時の安心材料になる
- **計測は正義**：前回「FLEE と同等 ~数 ms」の見積もりは 10 倍以上外れていた。想像で判断せず実測する

## 2026-04-24 深夜（合流 NPC 追従バグ修正：explore 上書きに joined_to_player ガード追加）

### 発見経緯

fall_back 動作確認のため実機プレイ中、Komuro が「合流済み NPC がプレイヤーから離れていく」症状を発見。同時に PartyStatusWindow で同一キャラ（クレア）が「プレイヤー」と「NPC」の両セクションに表示される二重表示も見つけた。

### 調査結果（詳細は省略・要点のみ）

仲間システムの実装を調査したところ、2 つの独立した問題があることが判明：

1. **追従バグ（今回修正）**: 2026-04-23 commit `798d3cc`（ポーション修正）で `_assign_orders` が `_build_orders_part()` 経由に統一された際、NpcLeaderAI の `_build_orders_part()` が `_is_in_explore_mode()` 時に `move = "explore"` を上書きする処理が、合流済み NPC にも効くようになっていた

2. **二重表示（次タスク）**: `_merge_npc_into_player_party()` で元 NPC PartyManager を `_per_floor_npcs` から除去せず、メンバーも `_hero_manager._members` に追加しない。そのため Character 実体は 1 つだが、PartyStatusWindow が Party（プレイヤー）と `_per_floor_npcs`（NPC）の両方から列挙して二重表示される

### 修正：1 行ガード

`scripts/npc_leader_ai.gd` の `_build_orders_part()` 内:

```gdscript
# 旧
if _is_in_explore_mode():
    var pol := _get_explore_move_policy()
    hint["move"] = pol
    ...

# 新
if not joined_to_player and _is_in_explore_mode():
    var pol := _get_explore_move_policy()
    hint["move"] = pol
    ...
```

`joined_to_player` は PartyLeader 基底クラスの既存プロパティ（NpcLeaderAI に継承）。`_merge_npc_into_player_party()` で合流時に `nm.set_joined_to_player(true)` される。

### 効果

- 合流済み NPC：プレイヤーの `global_orders.move`（デフォルト `follow`）に従う → 追従回復
- 未加入 NPC：従来通り `explore` で自律行動（無回帰）
- 二重表示は残存（次タスク）

### 判断の根拠

**なぜ 1 行修正で済ませたか**:

- **二重表示はデバッグ表示の見た目問題**：ゲーム挙動には影響しない（管理主体は元 NpcLeaderAI のままだが、プレイヤー指示が `set_global_orders` 参照共有経由で届くので行動は正常）
- **根本対応（管理主体を `_hero_manager` に移管）は広範囲リファクタ**：PartyLeader.setup 再構築・UnitAI 再生成・戦況判断の `_party_ref` 経路・フロア遷移処理など多数の箇所に影響。今すぐやると fall_back 検証が止まる
- **最小変更で追従復旧 → fall_back 検証に戻る → その後に管理構造の整理** の順序が健全

### 学び

- **派生仕様の影響範囲を過小評価しない**：`_build_orders_part()` はポーション修正のために導入された後、「既定値の集約点」という位置付けが強化され、move 上書きロジックが結合されていた。後から見ると「joined 時にも効く」のは明白だが、単独の修正を見ている時点では気づきにくい
- **OrderWindow 配布経路とデバッグ表示の二重責務は事故のもと**：`_build_orders_part()` は当初デバッグ表示用の合成関数だったが、`_assign_orders()` の実動にも使われるようになったため、挙動変更の副作用が広がった

## 2026-04-24 深夜（パーティー加入処理の完全化・Step 1+2）

### 背景

合流 NPC 追従バグを 1 行ガードで応急処置した後、根本問題として残っていた「加入処理が不完全で二重管理になっている」を解消する本丸対応。

### 不完全だった旧実装

[game_map.gd:`_merge_npc_into_player_party`](../scripts/game_map.gd) は:
- `party.add_member(member)` — Party に追加（正しい）
- `nm.set_joined_to_player(true)` — フラグ設定（正しい）
- **しかし nm._members からメンバーを除去しない**（バグ）
- **nm._leader_ai._unit_ais からも除去しない**（バグ）
- **_hero_manager._members に追加しない**（バグ）
- **_per_floor_npcs から nm を erase しない**（バグ）

結果、同一 Character が nm と _hero_manager の両方から参照され、UnitAI は元 NpcLeaderAI 管理下で動き続ける状態だった。

### 設計：動的メンバー管理 API を導入

従来の PartyLeader は「setup() で一括初期化・以降はメンバー不変」想定だった。合流対応のため動的メンバー管理 API を新設:

```gdscript
# PartyLeader 基底
func adopt_member(member, unit_ai):
    _party_members.append(member)
    _unit_ais[member.name] = unit_ai
    if unit_ai.get_parent() != self:
        unit_ai.get_parent().remove_child(unit_ai)
        add_child(unit_ai)
    unit_ai._player = _player
    unit_ai.set_visited_areas(_visited_areas)
    unit_ai.set_follow_hero_floors(joined_to_player)
    unit_ai.set_all_members(_all_members)
    unit_ai.set_map_data(_map_data)
    for ua in _unit_ais.values():
        ua.set_party_peers(_party_members)
    _initial_count = _party_members.size()

func release_member(member) -> UnitAI:
    var unit_ai = _unit_ais.get(member.name)
    _party_members.erase(member)
    _unit_ais.erase(member.name)
    for ua in _unit_ais.values():
        ua.set_party_peers(_party_members)
    return unit_ai
```

PartyManager に薄いラッパー（Character.died シグナル切断・再接続を含む）。

### UnitAI 流用方式の採用

既存 UnitAI を破棄せず reparent で流用する方針（案 a）を採用:

- **状態保持**：`_queue` / `_state` / `_timer` / `_target` / `_flee_recommended_goal` / `_last_area_id` が維持される → 戦闘中の加入でも行動断絶しない
- **変更範囲が狭い**：新規生成は UnitAI 生成ロジックの複製になる
- **味方側は基底 UnitAI のみ使用**：GoblinArcherUnitAI 等のサブクラスが問題になる可能性なし
- **副作用への対応**：walker コンテキスト（`_player` / `_all_members` / `_map_data` / `_visited_areas`）を adopt 時に再設定

### `_merge_npc_into_player_party` の改修

既存の「add だけ」方式から「release → adopt + nm 解体」方式に変更。nm は `_per_floor_npcs` から erase・`queue_free()` で完全削除。

`_find_floor_of_nm()` ヘルパを新設（`_per_floor_npcs` のどのフロアに nm があるか検索）。

### Step 分割

Step 1（API 新設）と Step 2（merge 改修）を 1 commit で実装。Step 3（`_member_to_npc_manager` クリーンアップ）は別 commit に分離:
- Step 1 単独は挙動不変で検証価値が低い
- Step 3 はクリーンアップのみなので分離してロールバック容易性を確保

### Step 3 を前倒し実施（freed cast クラッシュ対応）

Step 1+2 適用後の実機動作確認で、フロア遷移時にクラッシュが発生:

```
E _link_all_character_lists: Trying to cast a freed object.
  game_map.gd:547 @ _link_all_character_lists()
  game_map.gd:2050 @ _transition_floor()
  game_map.gd:1959 @ _check_stairs_step()
```

原因：`_member_to_npc_manager` に `queue_free()` 済みの nm 参照が残っていた。`as PartyManager` キャストは freed object に対してはエラーを出す（`is_instance_valid` ガードは cast 後でないと効かない）。

「Step 2 後も `is_instance_valid` ガードで安全」という事前見積もりが甘かった。GDScript 4.x の `as` キャストは freed object に対して例外を投げる仕様で、`is_instance_valid` は cast **後**にしか機能しない。

対応：予定していた Step 3 を前倒しで即実施:

1. `_link_all_character_lists` の joined_nms ループを削除（クラッシュ発生箇所）
2. `_transition_member_floor` で `_member_to_npc_manager.get(ch)` → `_hero_manager.set_member_map_data(ch, new_map)` に置換
3. `_member_to_npc_manager` Dictionary 定義と `_merge_npc_into_player_party` 内の代入箇所を削除

全て同一コミット内に含める（ロールバック単位としては Step 1+2+3 が一体化）。

### 学び（追加）

- **GDScript の `as` キャストと freed object**：`is_instance_valid` は cast **前**に行わないと意味がない。cast 後にガードする形（`var x := y as Foo; if is_instance_valid(x):`）は freed object で既にエラーが発生する
- **Dictionary に Node 参照を保持する設計は退避戦略が必須**：所有者（この場合は nm）が解体されるとき、参照を持つ辞書も同時にクリーンアップしないと freed 参照が残る。`_member_to_npc_manager` のような間接参照マップは特に注意が必要だった
- **段階分割は理想だが一体化が必要なときもある**：Step 2 と Step 3 の分離は git 履歴の明瞭性のためだったが、Step 2 単体で freed cast が発生したため一体化せざるを得なかった。次回の同種リファクタでは「所有権移転 + 参照クリーンアップ」はセットで行う

### 学び

- **「setup() で全メンバー確定」モデルは動的変化に弱い**：RTS 系・パーティー加入系のゲームでは初期化時の完全確定を前提にしないほうが柔軟
- **UnitAI reparent 方式は意外に素直**：Godot の Node reparent は signal も維持されるので、状態保持して管理主体だけ変えるパターンが自然
- **シグナル再接続の idempotent 化**：`is_connected` / `disconnect` / `connect` を毎回ガードすることで二重接続・freed 接続の事故を防ぐ

## 2026-04-24 夕（fall_back パフォーマンス修正：更新頻度の削減）

### 背景

上記 `fall_back` 実装を取り込み直後の動作確認で、ゲーム全体が顕著に重くなる現象が発生した。実装機能としては意図通り動いていたので、**計算コストがフレームタイムに悪影響**という性能問題として切り出した。

### 原因特定プロセス（静的分析のみで完結）

計測コードを埋め込む前に、まず Claude Code が静的分析で以下を確認：

1. **呼び出し経路の grep**：`_determine_fallback_recommended_goal` / `_assign_orders` の呼出チェーンを全て洗い出し
2. **呼出頻度の整理**：`_assign_orders` の発火源を 4 種類に分類（`_reeval_timer` 定期 / `notify_situation_changed` / `on_member_area_changed` / リーダーフロア変化）
3. **計算量の上限見積もり**：候補タイル数（R=6 → 最大 85・フィルタ後 40〜70）× `_astar_with_cost`（max_iter=400・open_set 線形スキャンで O(N²) 相当）× `_calc_threat_cost`（`_all_members` 50+ を線形反復）

この時点で**主因がほぼ確定**したため、計測ステップは省略し直接修正方針に進んだ。

### 特定された主因

**`on_member_area_changed()` を味方パーティー全般に広げた改修が頻度を爆発させた**：

- 2026-04-24 の当初実装では「味方パーティーでも `_fallback_last_reeval_time` クールダウン 0.3 秒で `_assign_orders()` を発火」としていた
- `_notify_area_change_if_needed()` は `UnitAI._process()` 毎フレーム呼ばれ、メンバーがエリア境界を跨ぐたびに発火
- フロア 0 に 8 NPC パーティー（合計 12 人）＋プレイヤー 1 パが居る状況では、どこかのメンバーが常に部屋↔通路を行き来する → **各パーティーで 0.3 秒ごとに重い計算が連打**される
- 改修前の `on_member_area_changed` は `_is_party_fleeing()` 中のみ発火していたので問題にならなかった（FLEE は稀な状態）

副因として、単一呼び出しの単価も重い：候補 70 タイル × A*（線形 open_set + 全員スキャン `_calc_threat_cost`） ≈ 数百万 ops。ただし頻度を抑えれば許容範囲。

### 修正方針：頻度のみ下げる（A1 案）

単価側には手を入れず、**頻度だけを改修前の水準に戻す**最小修正を採用。

- `on_member_area_changed()` の fall_back ブランチを削除（FLEE 時のみ再評価する改修前の状態に戻す）
- `_fallback_last_reeval_time` 状態変数を削除
- `FALL_BACK_REEVAL_MIN_INTERVAL` 定数を削除（GlobalConstants・constants.json・constants_default.json の 3 箇所）
- `PartyLeader._process()` の `REEVAL_INTERVAL = 1.5s` 周期だけで fall_back 推奨を更新

### 採用しなかった案

- **推奨 B（発火条件厳格化：HP critical メンバー存在時のみ計算）**：将来 `keep_distance` でも `formation_fallback_goal` を流用する設計のため、HP 状態に依存させない
- **候補数削減（`FALL_BACK_SEARCH_RADIUS` 6 → 4）**：頻度が主因なので効果限定的。後退範囲を狭めたくない
- **A2 案（fall_back 専用長周期・例 5 秒）**：A1 で体感確認して、まだ重ければ次タスクで導入

### 設計原則の明文化

> fall_back は「大まかな後退集合点」であり、メンバーがエリア境界を跨いだ瞬間に陳腐化する種類の情報ではない。FLEE のように「リアルタイムな経路追従」が必要な情報とは性質が異なるため、`REEVAL_INTERVAL = 1.5s` の定期再評価のみで十分。`on_member_area_changed` による即時再評価は FLEE 時のみとする。

この判断は fall_back と FLEE の「情報の陳腐化速度」の違いを切り出したもので、将来 `keep_distance` を同じ配布機構に乗せる際も同じ方針（定期のみ）で進める。

### 学び

- **「FLEE と対称に作る」という設計思想は正しいが、呼出頻度まで対称にすべきかは別判断**：出口候補数（2〜6）と集合点候補数（40〜70）の桁違いの差を見落としていた
- **計測前に静的分析で主因が特定できる場合は、計測を省略して構わない**：ただし「静的分析だけで確信できるか」の判断は慎重に（頻度 × 単価の両方が桁違いに変化している場合は見積もりの確度が高い）

## 2026-04-23（TARGETING 時間停止リーク修正 + デバッグログ検出機構整備 + 回転 Tween ガード）

### 概要

2026-04-22 夕方以降に持ち越されていた「TARGETING ホールド中にアウトラインされた敵が動く」問題を、デバッグログの再投入 → Komuro による実機再現 → ログ解析で根本原因を特定し、修正。主因は `game_map.gd` の周期処理の未ガードだったが、その修正後に Komuro が「たまに向きだけ変わる敵を見る」と報告 → 2 段目の修正として Godot Tween の time stop 非対応も修正した。あわせて同種バグの再発検知のための永続ログ機構を整備した。

### 1. 原因特定（ログ解析）

`res://logs/runtime.log` に、TARGETING ホールドが始まって約 2.7 秒後に以下が記録された:

- `[08:56:08.555] [TGT-HOLD] false → true mode=TARGETING`（ホールド開始）
- `[08:56:11.278〜11.062]` の約 0.1 秒間に **100 件の `[CHAR.sync_position] … (during TARGETING hold!)` ログが連続発火**
- グリッド座標が y=10,19,28,37,46 × x=11,13,22,24,33,35,44,46 の整然とした格子を描く → 新フロアの敵初期配置
- 各キャラ 2 回ずつ（`Character._ready()` 内の `sync_position()` と、スポーン関数から明示的に呼ぶ `sync_position()` の重複）
- 敵 ≈ 40 体 + 味方 ≈ 12 体 = 100 件強

この期間中、`[MODE]` / `[WT]` 遷移ログが 1 件も出ていない（3.7 秒の巨大な空白）。これは `_update_world_time` が呼ばれていない = フレームが飛んでいる＝ **time stop 中に game_map の重い処理が走ってフリーズしていた**ことを示す。

### 2. 根本原因

[game_map.gd:_process()](scripts/game_map.gd:196) の以下 5 つの周期処理が `world_time_running` ガードを持たず、time stop 中も走り続けていた:

- `_activate_enemies_on_npc_floors()` — 敵アクティブ化
- `_check_item_pickup()` — 床アイテム拾得
- `_check_stairs_step()` — 操作キャラの階段踏み
- `_check_party_member_stairs()` — パーティーメンバーの階段踏み
- `_check_npc_member_stairs()` — **未加入 NPC の階段踏み（今回の犯人）**

NPC リーダーが階段タイル上に立った状態で TARGETING ホールドに入ると、`_check_npc_member_stairs` が `_transition_npc_floor` を発火 → 新フロアがまだ初期化されていなければ `_setup_floor_enemies` / `_setup_floor_npcs` 実行 → 各キャラ `add_child` で `Character._ready` → `sync_position()` + 明示 `sync_position()` の 2 回連打 → ターゲットのアウトラインが貼られたキャラ含め位置が再計算される。

### 3. 修正

上記 5 関数の冒頭に `if not GlobalConstants.world_time_running: return` を追加。各関数に「2026-04-23 判明」のコメントを残し、将来また外そうとする人への保険とする。

### 4. デバッグログ検出機構の整備

原因特定のため仕込んだデバッグログを 2 系統に分離:

**永続保持**（回帰防止の検出機構として残す）:
- `Character` 側 5 系統：`[CHAR.move_to]` / `[CHAR.abort_move]` / `[CHAR.sync_position]` / `[CHAR._update_visual_move]` / `[CHAR.grid_commit(half|end)]`
- すべて `GlobalConstants.debug_targeting_hold == true` のときだけ発火（通常プレイのログ氾濫なし）
- 将来 `game_map.gd` 等に新しい未ガード周期処理が追加されると即検知できる

**一時保持**（原因特定用・実機検証完了後に削除）:
- `PlayerController` 側：`[MODE]` / `[WT]` / `[TGT-HOLD]` / `[TGT-SET]` / `[CURSOR]`
- 削除時は `_dbg_prev_*` 変数 4 つも一式削除
- `debug_targeting_hold` フラグの維持ロジックは永続保持組が参照するため残す

新規追加:
- [global_constants.gd](scripts/global_constants.gd) に `var debug_targeting_hold: bool = false` を追加
- [player_controller.gd:_update_world_time()](scripts/player_controller.gd) がこのフラグを維持（TARGETING ホールド中は true、それ以外は false）

### 5. 関連する未解決（実機検証項目）

- **「射程表示中に被弾すると攻撃がキャンセルされるように見える」問題**：同根の疑いがあったので、本修正で解消するか実機確認が必要
- `runtime.log` に `[CHAR.*]` 系の `"during TARGETING hold!"` が 1 件も出ないこと（出たらそれが新たな未ガード経路）

### 6. 2 段目の修正：回転 Tween の time stop ガード（A 案）

**症状**：game_map.gd 側の 5 関数にガードを入れた後、実機再現テストで Komuro から「だいぶ改善したが、たまにアウトライン中の敵が向きだけ変える現象がある」と報告。

**ログ検証**：
- 166 回の TARGETING ホールド中、`[CHAR.sync_position]` / `[CHAR.move_to]` / `[CHAR.grid_commit]` 等の位置変化ログは **0 件**
- ホールド中の `[TGT-SET]` / `[CURSOR]` 変化：**0 件**
- つまり位置・ターゲット集合は完全に凍結しているが、Komuro は「向き変更」を目視している

**原因**：[Character.start_turn_animation()](scripts/character.gd:549) が生成する rotation Tween は Godot の SceneTreeTween。これは `_process` の実行と独立して走るため、`world_time_running` でガードできない。`_update_visual_move` は [character.gd:_process()](scripts/character.gd:216) でガードされて停止するが、Tween だけは継続する。

**タイミング**：
1. AI が `move_to()` を呼んで移動開始 → 内部で `start_turn_animation` が回転 Tween（duration ≈ 0.4 秒）を生成
2. 移動開始直後（Tween 進行中）にプレイヤーが攻撃ボタンを押下 → PRE_DELAY → TARGETING 突入
3. 位置補間は凍結するが、Tween は残り時間分だけ回転し続ける
4. ユーザー視点：「同じマスに立ったまま向きだけ変わる」

**修正（A 案・侵襲小）**：[character.gd:_process()](scripts/character.gd:216) で以下の分岐を追加
```gdscript
var should_process_visuals := GlobalConstants.world_time_running or is_player_controlled
if _turn_tween != null and _turn_tween.is_valid():
    if should_process_visuals:
        if not _turn_tween.is_running():
            _turn_tween.play()
    else:
        if _turn_tween.is_running():
            _turn_tween.pause()
```

- 回転 Tween が位置補間 `_update_visual_move` と同じガード条件で動く対称構造になった
- 回転の新規開始は `move_to()` 経由か PlayerController 経由のみで、どちらも `should_process_visuals == true` のキャラでしか発生しないため、新規 Tween が time stop 中に始まるケースはない。既存実行中 Tween の継続のみ対処すれば十分

**B 案検討**（不採用）：Tween をやめて `_update_visual_rotation()` として `_process` 内で手動補間する案もあったが、コード変更量が多く、Tween の ease/trans 機能を失うため見送り。「時間系二層構造」の整理と合わせた別タスクにするのが綺麗、という判断。

### 7. 3 段目の修正：PRE_DELAY → TARGETING 同一フレーム race

**症状**：turn_tween 修正後もなお「アウトラインが一瞬出て消える」現象が長押しテストで再現された。検出ログ `[CHAR.*]` / `[PLAYER-TURN]` / `[CURSOR] ≈ (same instance moved)` はどれも 0 件で、検出器の死角に潜んでいた。

**検出強化**（診断のため追加）：
- `[PLAYER-TURN]`：TARGETING ホールド中のプレイヤー向き変更を記録
- `[TGT-SET]` 差分表示：追加・削除された敵とその現在 grid_pos を記録（`instance_from_id` で freed 判定も）
- `[CURSOR] ≈ ... (same instance moved!)`：同一インスタンスでカーソル対象の grid_pos が変化したら記録
- `_exit_targeting` で `_dbg_prev_valid_target_ids` / `_dbg_prev_cursor_target_id` / `_dbg_prev_cursor_grid` をリセット（連続 TARGETING 間で重複抑制されないように）

**診断結果**：追加ログでも `[CHAR.*]` 0 件、`[PLAYER-TURN]` 0 件。ホールド内の mid-hold 変化も 0 件。ただし TARGETING 間で archer が (10, 19) ↔ (9, 19) を往復している事実は判明。

**ログに出ない理由（検出死角）**：
- `[CHAR.grid_commit]` 等は `GlobalConstants.debug_targeting_hold == true` を条件に発火する
- `debug_targeting_hold` は `_update_world_time()` が維持（TARGETING ホールド中に true、他で false）
- PRE_DELAY → TARGETING 遷移のフレーム N では：
  - フレーム頭で _update_world_time が走る時点では mode=PRE_DELAY → `debug_targeting_hold = false`
  - `_process_pre_delay` 内で mode=TARGETING に遷移するが、`debug_targeting_hold` の再計算は行われない
  - 以降このフレーム内で走る Character._process は `debug_targeting_hold == false` を見る → 検出ログは出ない
- Character._process は `world_time_running` を見て visual_move を実行する。フレーム頭では wt=true だったので visual_move が進む → `grid_pos` を新位置にコミット可能
- フレーム N+1 の _update_world_time で初めて mode=TARGETING が反映され wt=false になるが、既に commit 済み

**根本原因（race 条件）**：
1. Character._process 等の他 node が Godot のツリー順で PlayerController._process より**後に**走る場合（今回の実測配置）、同一フレーム内でタイミングが複雑化
2. 実際の observed ケース：
   - フレーム N 頭：wt=true（フレーム N-1 末の値・PRE_DELAY 最後のフレーム）
   - フレーム N：PlayerController._process → _update_world_time (wt=true) → _process_pre_delay → _start_targeting → _set_mode(TARGETING) → _setup_targeting_cursor で archer@(10, 19) をアウトライン
   - フレーム N 残：wt はまだ true のまま（_update_world_time 再呼出なし）
   - フレーム N+1 頭：wt=true（フレーム N 末から引き継ぎ）
   - フレーム N+1：hero/enemies/npcs._process → wt=true → archer の visual_move が進行 → t>=0.5 で grid_pos を (9, 19) にコミット → PlayerController._process → _update_world_time (wt=false) → _refresh_targets で archer 射程外 → アウトライン除去
3. ユーザー視点：フレーム N でアウトライン出現 → フレーム N+1 で除去（実時間 16ms）→ 「一瞬表示されて消えた」

**修正（侵襲小）**：[_start_targeting()](scripts/player_controller.gd:723) 内で `_set_mode(Mode.TARGETING)` の直後に `_update_world_time()` を**もう一度**呼ぶ:

```gdscript
_set_mode(Mode.TARGETING, "pre_delay complete")
# 同一フレーム内 race 防止
_update_world_time()
_setup_targeting_cursor()
```

これによりフレーム N の時点で `world_time_running = false` / `debug_targeting_hold = true` が確定。フレーム N+1 の Character._process が wt=false を見て visual_move を止めるため、grid_pos がコミットされず、_refresh_targets で同じ target が維持される。

**副次効果**：将来、別の race ケースが発生した場合、`debug_targeting_hold` が正しく true になるため `[CHAR.*]` 系検出器が正常機能するようになる。

### 8. 4 段目の修正：解放後の新規入り敵を攻撃しない（Option A）

**症状**：同フレーム race 修正後、「アウトラインが一瞬表示されて消える」問題は解消。しかし別の症状が実機で観測された:「アウトラインが表示されないのに攻撃が発動する」。

**ログから読み解いた原因**（`[CHAR.*]` 検出ログは依然 0 件）:

```
Line 125  TGT-HOLD false → true         ホールド開始
Line 126  CURSOR cleared (no valid targets)  archer は射程外・アウトライン非表示
Line 127  TGT-SET size=0 -[archer@(25, 19)]
...（hold 1.2 秒）...
Line 128  WT false → true TARGETING released  リリース・wt=true
Line 130  TGT-SET size=1 +[archer@(26, 19)]    数フレーム後に archer が射程内へ入る
Line 131  CURSOR → archer@(26, 19)
Line 132  MODE TARGETING → POST_DELAY          攻撃発動
```

ホールド中は archer が (25, 19) で凍結していたが、hold 前の PRE_DELAY / NORMAL 中に archer が move_to を開始しており `_visual_elapsed` が t<0.5 の状態でフリーズされていた。リリース後 wt=true で visual_move 再開 → 数フレーム後に `grid_pos` が (26, 19) にコミット → 射程内に入った → 攻撃発動。

**根本原因（設計レベル）**：[_process_targeting()](scripts/player_controller.gd:608) は解放後も毎フレーム `_refresh_targets()` を走らせ、`_valid_targets` が非空になった瞬間に `_confirm_target()` を発火する構造だった。この結果「リリース時点では射程外だった敵がリリース後に射程内に入る」と攻撃が発動する。

プレイヤー視点では「狙えていない状態で攻撃ボタンを離した＝キャンセルしたつもり」なのに攻撃が発動 → 「アウトライン表示されないのに攻撃する」症状になる。

**修正（Option A）**：`_released_without_target: bool` フラグを [player_controller.gd:133](scripts/player_controller.gd:133) 付近に追加。

`_process_targeting` の解放分岐を以下の順序で評価:
1. `holding` なら従来通り auto_cancel をリセット + フラグを false に
2. `_released_without_target == true` なら auto_cancel countdown のみ消化（`_valid_targets` 再評価をスキップ）
3. `_valid_targets` 非空なら `_confirm_target()`（従来の攻撃発動）
4. 空なら `_released_without_target = true` にセットして auto_cancel countdown 開始

フラグの初期化：
- `_enter_pre_delay()`：新攻撃サイクル開始時に false（次の解放判定をフレッシュに）
- `_exit_targeting()`：TARGETING 抜けに false（次サイクルに残さない）

**セマンティクス**：「プレイヤーがリリースした瞬間に見えていたターゲット（射程内の敵）のみを攻撃対象とする。リリース後に射程に入ってきた敵は無視」。これは「What You See Is What You Attack」の原則。

**対象範囲**：`_process_targeting()` のみ修正。`_process_pre_delay_released()`（クイックタップ経路）は別セマンティクス（「タップしたから早く撃ってほしい、ターゲットは遅れて現れてもよい」）のため変更なし。

### 9. 5 段目の修正：射程オーバーレイが PRE_DELAY 中のキャラ位置変化に追従しない

**症状**：プレイヤーが移動中（`_visual_duration > 0` の視覚補間中）に攻撃ボタンを押すと、射程オーバーレイが攻撃ボタン押下時点のグリッド座標で表示され、PRE_DELAY 中にキャラの `grid_pos` が次マスにコミットしてもオーバーレイが古い位置に残る。

**原因**：[game_map.gd:_process()](scripts/game_map.gd:196) の redraw トリガー:

```gdscript
var now_windup := player_controller != null and player_controller.is_in_attack_windup()
if now_windup != _was_targeting:
    _was_targeting = now_windup
    queue_redraw()
```

「`is_in_attack_windup()` の状態切替時のみ再描画」という設計で、windup 中のキャラ位置変化（特に移動中の `grid_pos` コミット）を捕捉していなかった。

[game_map.gd:2358](scripts/game_map.gd:2358) 付近の射程オーバーレイ描画は `ch.grid_pos` を参照しており、`grid_pos` が変わっても `_draw()` が再実行されないため古い位置のままになる。

**修正**：windup 中（PRE_DELAY / PRE_DELAY_RELEASED / TARGETING）は毎フレーム `queue_redraw()` するように変更:

```gdscript
var now_windup := player_controller != null and player_controller.is_in_attack_windup()
if now_windup != _was_targeting:
    _was_targeting = now_windup
    queue_redraw()
elif now_windup:
    queue_redraw()  # windup 中は毎フレーム描画してキャラ位置に追従
```

**副作用**：windup は短時間（pre_delay 0.15〜0.5 秒 + targeting ホールド）に限定されるため、パフォーマンス影響は無視できる。

### 10. 6 段目の修正：移動中攻撃入力の PRE_DELAY 並行消化を明示的に仕様化

**背景**：
移動中（`is_moving() == true`）に攻撃ボタンを押下した際の挙動が明示的に設計されていなかった。プロジェクト設計者 Komuro の当初想定は「PRE_DELAY タイマーは移動中から並行消化、TARGETING 突入時はマス中央に静止している」だったが、コードは片手落ちだった:
- ✅ PRE_DELAY は並行進行（[player_controller.gd:450](scripts/player_controller.gd:450) の `_enter_pre_delay()` が即呼ばれる・`is_moving()` 無関係）
- ❌ TARGETING 突入は視覚補間と無関係（pre_delay タイマーだけで `_start_targeting()` が走る）

後者の欠落により、pre_delay が短いクラスでは「TARGETING に入ったときキャラがまだマスの途中を動いている」「時間停止中なのにプレイヤー視覚は動く」という設計原則違反が発生しうる状態だった。

**設計原則（本日明文化）**：
1. PRE_DELAY タイマーは移動中から並行消化（既存）
2. TARGETING 突入は「タイマー完了 AND 視覚補間完了（`is_moving() == false`）」の両方を要件とする
3. `abort_move()` による視覚中断は呼ばず、自然完了を待つ（理由：`abort_move` はマス中央へのスナップバックを起こすため視覚的に不自然）
4. pre_delay タイマー完了後、視覚補間完了までの間は「PRE_DELAY の延長」として扱う（射程オーバーレイは表示継続・マーカー非表示維持）

**実装変更**：

1. [_process_pre_delay()](scripts/player_controller.gd:533) の TARGETING 突入条件:
   ```gdscript
   # 修正前
   if _pre_delay_remaining <= 0.0:
       _start_targeting()
   # 修正後
   if _pre_delay_remaining <= 0.0 and not character.is_moving():
       _start_targeting()
   ```

2. [_process_pre_delay_released()](scripts/player_controller.gd:565) の Phase 2 突入条件:
   Phase 判定ロジックを `_pre_delay_remaining > 0.0` から `_cursor != null` に変更（より明示的）。Phase 2 突入条件に `is_moving()` ガードを追加:
   ```gdscript
   if _cursor == null:
       # Phase 1
       if _pre_delay_remaining > 0.0:
           _pre_delay_remaining -= delta * GlobalConstants.game_speed
       if _pre_delay_remaining <= 0.0 and not character.is_moving():
           _pre_delay_remaining = 0.0
           _setup_targeting_cursor()
           _auto_cancel_remaining = GlobalConstants.AUTO_CANCEL_FLASH
       return
   # Phase 2: （既存のマーカー表示 + AUTO_CANCEL_FLASH 計測）
   ```

3. [_process_guard_and_move()](scripts/player_controller.gd:470) の dead code 削除:
   ```gdscript
   # 削除前（dead code）:
   if Input.is_action_just_pressed("attack"):
       _attack_buffer = true
   elif Input.is_action_just_released("attack"):
       _attack_buffer = false
   ```
   攻撃入力は `_process_normal` line 450 で先に捕捉されて `_enter_pre_delay()` が即呼ばれる構造のため、`_process_guard_and_move` 内の `_attack_buffer = true` 設定は到達不能だった（POST_DELAY 中の攻撃バッファリングは `_process_post_delay` 側に別途残存）。

**影響**：
- pre_delay > 視覚補間残り時間：従来どおり pre_delay 完了 → TARGETING
- pre_delay < 視覚補間残り時間：pre_delay 完了後、視覚補間完了を待って TARGETING（射程オーバーレイは表示継続）
- 攻撃ボタン押下から攻撃発動までの総時間：`max(pre_delay, 視覚補間残り時間) + ホールド時間` + POST_DELAY

**CLAUDE.md 更新**：
- 「攻撃フロー（一発一押下モデル）」セクションの内部ステート記述に「視覚補間と並行進行」を追記
- 状態遷移の PRE_DELAY → TARGETING 遷移条件に「タイマー完了 AND 視覚補間完了」を明記
- 設計原則に「TARGETING 突入時はキャラがマス中央に静止」を追加

### 11. 派生タスク（別セッション）

[game_map.gd:_process()](scripts/game_map.gd:196) 内でインラインに減算されているタイマー 3 種（`_stair_cooldown` / `_member_stair_cooldown` / `_npc_enemy_activate_timer`）は time stop 中も進行している。他のキャラタイマー（stun / buff / energy 回復）が `world_time_running` で停止するのと対称性が取れていない。`game_speed` 適用パターンの 4 分類混在問題（[investigation_movement_constants.md](investigation_movement_constants.md)）と合わせて整理するのが自然。今回の TARGETING 問題の主因ではないが、次に手を付けるならここ。

---

## 2026-04-22 夕方以降（ガード中歩行アニメ修正 + 向き変更バグ修正）

本日夕方以降のセッションで、Step 1-B 実装後に持越しとなっていた 2 件のバグを解決。あわせて「射程表示中に被弾すると攻撃がキャンセルされる」問題の原因調査を実施したが、同時に観察された別問題（TARGETING ホールド中にアウトラインされた敵が動く現象）の原因が完全には特定できず、次回セッションへ持越し。

### 変更サマリ

1. **ガード中移動時の歩行アニメ欠落を修正**（解決済み）
2. **向き変更中に攻撃ボタンを押すと TARGETING 時間停止が無効化されるバグを修正**（解決済み）
3. `_set_mode()` ヘルパー関数新設（リファクタリング）
4. `get_current_target()` の freed 参照クラッシュを修正（副次対応）

### 1. ガード中移動時の歩行アニメ欠落を修正

**症状**：プレイヤー操作キャラがガード（X/B ホールド）中に移動すると、guard.png で静止したまま 1 マス移動してしまい、歩行アニメ（walk1/walk2）に切り替わらない。Step 1-B（2026-04-20）実装後に観察された 4 つの挙動変化のうちの 1 つ。

**原因**：[`scripts/character.gd`](../scripts/character.gd) の `_update_visual_move()` 内、スプライトフレーム切替条件に `is_guarding` が含まれており（line 703 相当）、ガード中は全てのフレーム切替（walk1 → top → walk2 → top）が抑制されていた。該当条件は 3 箇所：

- `abort_move()`（衝突アボート時の top.png 復帰）
- `_update_visual_move()` のフレーム切替本体
- `_update_visual_move()` の移動完了時の top.png 復帰

いずれも「ガード中は静的に guard.png を保ちたい」意図で `is_guarding` が追加されていたが、移動中も同様に抑制されていたのが不具合。

**仕様（確定）**：「歩行中は walk1/walk2/top の通常サイクル、静止中のみ guard.png」に統一。

**修正**：
- フレーム切替条件から `is_guarding` を除外（歩行中は通常サイクルを通す）
- `abort_move()` / 移動完了時は `if is_guarding: _update_ready_sprite()` を追加し、ガード中なら guard.png に復帰させる（`_update_ready_sprite()` は既に guard > attack > ready > top のフォールバックを実装済み）
- 関連コメント 2 箇所を仕様に合わせて更新

**アニメ切替周期**：[`player_controller.gd`](../scripts/player_controller.gd) で `move_to(new_pos, character.get_move_duration() / GlobalConstants.game_speed)` を呼んでおり、ガード中の 2.0 倍（`GUARD_MOVE_DURATION_WEIGHT`）も duration に反映されている。4 フレーム切替は `_visual_elapsed / _visual_duration` に追従する設計なので自動的に正しい周期で再生される。周期側の修正は不要。

**影響範囲**：
- ガード中移動：歩行アニメ再生・停止時に guard.png 復帰 ← 今回の修正対象
- ガード中静止：`is_guarding` セッター → `_update_ready_sprite()` で guard.png（既存動作・変更なし）
- ガード解除：セッターが `_update_ready_sprite()` を呼んで top.png 復帰（既存動作・変更なし）
- AI：`unit_ai.gd` に `is_guarding` 代入なし。AI はガードしない仕様が守られているので影響なし

### 2. 向き変更中攻撃による TARGETING 時間停止無効化バグ

**症状**：攻撃ボタンをホールドし続けているのに、TARGETING 状態でアウトラインが点灯している間も敵が動き回り、射程外に出てターゲットロスト → 攻撃不発。

**調査の経緯**：この症状の原因特定には 3 回の調査を要した。

- 第 1 回：TARGETING 中は `world_time_running = false` で敵は動かないはず（結論：コード上矛盾なし）→ 観察と一致せず
- 第 2 回：PRE_DELAY_RELEASED Phase 2 の 0.25 秒間にアウトラインが ON でかつ時間進行中という設計上の例外を発見 → 仮説提示。ただし Komuro は「ホールドし続けている」と複数回確認しており Phase 2 突入条件を満たさない
- 第 3 回：デバッグログ機構を仕込んで実機ログ取得 → 原因を確定

**デバッグログ仕込み**：原因特定のため以下の計測機構を一時的に追加：
- `_set_mode(new_mode, reason)` ヘルパー：全 `_mode =` 代入を一元化し、遷移時にログ出力（7 箇所全て置換）
- `_set_wtr(val, reason)` ヘルパー：`_update_world_time()` の全 return を経由させ、状態変化時のみ差分ログ
- `_setup_targeting_cursor()` 冒頭に `[OUTLINE]` ログ
- `_refresh_targets()` 冒頭に `[RT]` ログ（TARGETING / PRE_DELAY_RELEASED 中のみ）
- [`scripts/character.gd`](../scripts/character.gd) の `set_outline` / `clear_outline` に `[SHADER]` ログ（状態変化時のみ）
- 併せて差分検出用メンバ変数 `_prev_mode_for_log` / `_prev_wtr_for_log` を追加

**決定的な証拠**（Komuro が取得した実機ログ `logs/runtime.log` の line 191〜256）：

```
04.592: [WT] mode=NORMAL wtr=true reason=turning hold=false     ← 向き変更開始
04.683: [MODE] NORMAL → PRE_DELAY (reason=enter_pre_delay, hold=true)  ← 0.09s 後に攻撃
04.699: [WT] mode=PRE_DELAY wtr=true reason=turning hold=true   ← reason が "turning" のまま
04.894: [MODE] PRE_DELAY → TARGETING (reason=pre_delay complete, hold=true)
04.894: [OUTLINE] setup mode=TARGETING hold=true targets=1
04.894: [SHADER] ゴブリンアーチャー outline=ON wtr=true
04.912: [WT] mode=TARGETING wtr=true reason=turning hold=true   ← ★ TARGETING なのに wtr=true
04.912〜06.158: [RT] mode=TARGETING hold=true ... wtr=true      ← 約 1.25 秒間、時間進行継続
05.175: [SHADER] ゴブリンアーチャー outline=OFF                 ← 敵が射程外へ
06.158: [MODE] TARGETING → NORMAL (reason=exit_targeting, hold=false)
```

**根本原因**：

[`player_controller.gd`](../scripts/player_controller.gd) の `_update_world_time()` で、`_is_turning` 判定が `_mode == TARGETING` 判定より先にあった：

```gdscript
if _is_turning:
    _set_wtr(true, "turning")
    return                    ← ★ ここで return → TARGETING 判定に到達しない
...
if _mode == Mode.TARGETING:
    _set_wtr(not _is_in_attack_hold(), ...)
```

加えて `_turn_timer` を減算する箇所が `_process_guard_and_move()` 内のみで、この関数は `_process_normal()` からしか呼ばれない。攻撃ボタン押下で `_mode = PRE_DELAY` になった瞬間、`match _mode` は `_process_pre_delay` へ分岐するので `_process_guard_and_move()` は一切呼ばれなくなる → `_turn_timer` は永遠に減らない → `_is_turning` は永遠に true のまま。

結果、向き変更中（`TURN_DELAY = 0.15` 秒以内）に攻撃ボタンを押すと `_is_turning = true` が PRE_DELAY / TARGETING / POST_DELAY を通じて固定化し、`_update_world_time()` が `turning` ガードで時間停止を上書きし続ける。

**仕様（確定）**：**向き変更時間を pre_delay に含める（並行消化）**。押下時点で向き変更中でも PRE_DELAY は即座に開始。向き変更 timer と pre_delay timer は並行して減算される。プレイヤー体感「押してから TARGETING までの時間 = pre_delay の長さ」が一定。通常 pre_delay (0.3〜0.5 秒) のほうが TURN_DELAY (0.15 秒) より長いので、向き変更は pre_delay 消化中に完了する。

**修正**：

1. **`_turn_timer` の一元管理**：[`player_controller.gd:_process()`](../scripts/player_controller.gd:357) の `_update_world_time()` 直後に減算ブロックを追加。`world_time_running && _is_turning` の条件で mode 問わず毎フレーム減算。完了時は `complete_turn()` を呼び `_is_turning = false` に。
2. **`_process_guard_and_move()` の重複減算を削除**：既存の `if _is_turning: _turn_timer -= ... if <= 0: complete_turn ...` ブロックを `if _is_turning: return`（入力ブロックのみ）に縮小。turn 完了後のキー継続移動は次フレームの通常経路で処理される。
3. **`_update_world_time()` の判定順変更**：`_mode == TARGETING` 判定を `_is_turning` 判定より先に評価。TARGETING ホールド中は turning に関わらず時間停止。
4. **`_start_targeting()` で残留 turning を強制完了**：安全網として、PRE_DELAY → TARGETING 遷移時に `_is_turning` が残っていたら `complete_turn()` を呼び強制完了。将来 pre_delay が TURN_DELAY より短いクラスが追加された場合の備え。

**位置付け**：これは「要調査・要整理項目」の **Step 4「向き変更コストの完全対称化」の一部先取り**。Step 4 完了時に `BASE_TURN_DURATION` を導入して `move_speed` で補正する際、この一元管理ロジックを流用する。

### 3. `_set_mode()` ヘルパー関数を新設

原因調査の過程で仕込んだデバッグログ用ヘルパーは、修正完了後に削除したが、`_set_mode()` は薄いラッパとして残存させた：

```gdscript
## _mode 代入を一元化するヘルパー。将来 _mode 遷移のトラッキングが必要になったら
## この関数内に DebugLog.log を仕込むだけでよい（全代入箇所がここを通るため）
func _set_mode(new_mode: int, _reason: String) -> void:
    _mode = new_mode as Mode
```

全 `_mode = Mode.XXX` 代入（7 箇所）はこのヘルパー経由に統一済み：

| 箇所 | reason 文字列 |
|---|---|
| `_process_pre_delay` の解放検知 | `"pre_delay button released"` |
| `_process_post_delay` の完了処理 | `"post_delay complete"` |
| `_enter_pre_delay` 本体 | `"enter_pre_delay"` |
| `_start_targeting` 本体 | `"pre_delay complete"` |
| `_exit_targeting` 本体 | `"exit_targeting"` |
| `_enter_post_delay` dur<=0 分岐 | `"enter_post_delay dur<=0"` |
| `_enter_post_delay` 本体 | `"enter_post_delay"` |

将来 `_mode` 遷移のデバッグが必要になったら、この関数内に `DebugLog.log("[MODE] %s → %s (reason=%s)" % [Mode.keys()[_mode], Mode.keys()[new_mode], _reason])` を 1 行追加するだけで全遷移を追える。

### 4. `get_current_target()` の freed 参照クラッシュを修正

**症状**：`RightPanel._draw_content: Invalid type in function '_draw_char_row' in base 'CanvasLayer (RightPanel)'. The Object-derived class of argument 6 (previously freed) is not a subclass of the expected argument class.`

**原因**：[`scripts/right_panel.gd:122`](../scripts/right_panel.gd:122) `_draw_char_row` 第 6 引数 `current_target` は [`scripts/player_controller.gd:200`](../scripts/player_controller.gd:200) `get_current_target()` から取得されるが、`_valid_targets[_target_index]` を validity チェックせず返していた。ターゲット敵がフレーム内で倒されて freed になった場合、型付き引数（`Character`）のチェックで freed 参照の受け渡しがエラーになる。

**修正**：`get_current_target()` 末尾で `is_instance_valid(t)` チェックを追加し、freed なら null を返す。`_draw_char_row` 側の `current_target == c` 比較は null 受け取りで正常動作。

### 5. 未解決：TARGETING ホールド中に敵が動く現象（向き変更非関与ケース）

上記 2 の修正で `_is_turning` 経路は潰したが、Komuro の実機再現では**向き変更を伴わないケースでも**アウトラインされた敵が動く現象が依然として発生している。

すなわち、本日の調査で発見した経路とは**別経路**がまだ存在する。前回調査「TARGETING ホールド中に敵が動く経路はない」の結論は誤りで、マトリクスに更に抜けがある。

**同一原因の疑い**：元々の発端である「射程表示中に被弾すると攻撃がキャンセルされるように見える」問題とも同根の可能性が高い（敵が動いて射程外に出ることで `_valid_targets` が空になりターゲットロスト）。

次回セッションの最優先課題として CLAUDE.md「次セッションで検討するタスク」に記載済み。着手時はデバッグログ機構の再仕込みから始めるのが効率的（`_set_mode()` ヘルパーは残っているので、その内部に 1 行ログを足すのが最速）。

---

## 2026-04-22（ダメージ倍率調整 + HP/MP/SP ゲージ表示刷新 + ダメージログラベル修正）

実プレイ検証を経て、バランス・可読性・表示スケールの 3 つに跨る小規模変更を実施。いずれも挙動または表示のみの変更で、計算ロジックや内部データ構造は未変更。

### 変更サマリ

1. **ダメージ計算ログのラベル「スキル」→「クラス補正」にリネーム**
2. **左パネルの HP/MP/SP ゲージを絶対値 100 スケールに変更**
3. **`ATTACK_TYPE_MULT` 調整：近接/降下 0.3→0.2・遠距離/魔法 0.2→0.1（比率を 1.5:1 → 2:1 に設計変更）**
4. **Config Editor 変更セルのハイライト背景色を暗色化（可読性改善）**

### 1. ダメージ計算ログのラベル「スキル」→「クラス補正」

**背景**：ダメージ計算ログ `ベースダメージ 8（威力 47 × 遠距離 0.2 × スキル 0.89）` の「スキル」表記が Character の `skill` ステータス（クリティカル率計算 `skill ÷ 3 %` 用）と命名衝突しており、読者の混乱を招いていた。実体はスロット JSON の `damage_mult` を逆算した値（int 切り捨て 2 回の誤差で 0.9→0.89 と表示される）。計算自体は仕様どおりで、ラベル名のみの問題。

**調査**：[`docs/investigation_damage_formula_skill_label.md`](investigation_damage_formula_skill_label.md) に詳細。逆算ロジック（`inferred_dmg_mult = raw / type_base`）・2 段階 int 切り捨てによる誤差・spec.md との整合性チェックを記録。

**変更**：[`scripts/character.gd`](../scripts/character.gd) の `_log_damage()` 内 4 箇所（L1189 / L1200 / L1203 / L1205）でラベル「スキル」を「クラス補正」に置換。計算式・変数名・逆算ロジックは未変更（端数誤差はデバッグ用途で許容）。

**確認**：`grep -rn "スキル" scripts/` で 7 件ヒットのうち、ダメージ計算ログ由来の 4 件のみ変更。他 3 件（`character_data.gd` の「回復スキル」「バフスキル」・`global_constants.gd` の「各スキル」）は一般名詞としての用法のため据え置き。

### 2. 左パネル HP/MP/SP ゲージを絶対値 100 スケールに変更

**背景**：従来の実装はキャラ個別の `max_hp` / `max_energy` に対する割合表示で、「HP 50 でゲージ半分」という見た目が「HP が半分しかない」という不安感を誘発。また、キャラ個性（max HP の高低）がゲージから判別できない状態だった。

**変更**：[`scripts/left_panel.gd:289-292`](../scripts/left_panel.gd:289) の `HP_REF` / `MP_REF` / `SP_REF` を全て `100.0` に変更（旧 HP=300 / MP=120 / SP=120）。

既存の描画ロジック（`hp_cur_r = min(c.hp / HP_REF, 1.0)` / `hp_max_r = min(c.max_hp / HP_REF, 1.0)`）は未変更。HP_REF の値が変わるだけで自動的に要件を満たす：

- HP=100 でバー全幅・HP=50 で半分・HP=25 で 1/4
- `max_hp` も絶対値 100 基準で描画（max_hp > 100 は右端で頭打ち）
- MP / SP も同じロジックで絶対値 100 スケール化

**設計判断（意図的な非実装）**：

- **HP 上限 100 キャップは実装していない**。描画レイヤーのみの変更で、内部データ（`hp` / `max_hp` / `energy` / `max_energy`）の意味・計算は従来どおり。ダメージ計算・戦況判断には影響しない
- 「余計な操作を入れない」方針：本質（表示スケール）と無関係な変更（上限キャップ）を混ぜない

**スコープ**：左パネルのみ。他の HP 表示箇所（PartyStatusWindow は HP 数値のみ・HP ゲージなし）は対象外。

### 3. `ATTACK_TYPE_MULT` 調整（1.5:1 → 2:1）

**背景**：実プレイで即死問題（味方が 2〜3 発で死ぬ）が観察されており、Phase 14 最優先の検証課題となっていた。倍率構成は従来 melee/dive=0.3・ranged/magic=0.2 で「近距離：遠距離 = 1.5:1」相当。遠距離が「安全なのに火力も高い」状態で、リスクとリワードの対応が崩れていた。

**変更**（[`assets/master/config/constants.json`](../assets/master/config/constants.json)）：

| 攻撃タイプ | 旧 | 新 |
|---|---|---|
| melee | 0.3 | **0.2** |
| dive | 0.3 | **0.2** |
| ranged | 0.2 | **0.1** |
| magic | 0.2 | **0.1** |

**設計思想（確立）**：

- **近距離グループ（melee / dive）: 遠距離グループ（ranged / magic）= 2 : 1**
- 倍率差を 1.5:1 → 2:1 に広げることで「リスクを取る見返り（近接の高火力）」を明確化
- 絶対値（0.2 / 0.1）は実プレイで即死問題がほぼ解消した値として確定

**実プレイ結果**（Komuro 確認）：

- 即死問題はほぼ解消
- FLEE システムが活かされる前提となる耐久性が確保された
- 次セッションで戦闘テンポ・味方火力バランス等の継続検証が必要

### 4. Config Editor 変更セルのハイライト色を暗色化

**背景**：`HIGHLIGHT_BG_COLOR = Color(1.0, 1.0, 0.8)`（薄黄色）が、暗いパネル（`Color(0.10, 0.10, 0.14)`）に対する明るいクリーム色系の文字色と衝突し、変更済みセルの文字が読めない状態だった。

**変更**（[`scripts/config_editor.gd:19`](../scripts/config_editor.gd:19)）：`HIGHLIGHT_BG_COLOR` を `Color(1.0, 1.0, 0.8)` → `Color(0.40, 0.32, 0.08)`（ダーク・マスタード）に変更。「黄色ハイライト」の意味合いを残しつつ明るい文字色とのコントラストを確保。

### ドキュメント更新

- [`CLAUDE.md`](../CLAUDE.md)：「最近の大きな変更」に 2026-04-22 セクションを追加・「命中・被ダメージ計算」節の ATTACK_TYPE_MULT 値を更新・「次セッションで検討するタスク」に実プレイ再検証タスクを記録
- [`docs/spec.md`](spec.md)：「攻撃タイプ別ダメージ倍率」表を新値に更新・「設計思想」注記を追加・「LeftPanel」節に HP/MP/SP 絶対値 100 スケールの記述を追加
- [`docs/investigation_damage_formula_skill_label.md`](investigation_damage_formula_skill_label.md)：ログラベル「スキル」の正体調査（新規）

---

## 2026-04-21（デバッグウィンドウ表示改善・Character ステータス設計統一・味方側 _party_strategy 廃止・dead code 整理）

本日は「PartyStatusWindow（F1 デバッグウィンドウ）の表示改善」を中心に、関連する調査・設計統一・dead code 削除を大量に実施。主要な変更は以下：

- **DebugWindow の F1/F2 分離**：上下 2 つの独立ウィンドウへ（F1=PartyStatusWindow / F2=CombatLogWindow）
- **DebugLog Autoload 新設**：`DebugLog.log()` 経由で `res://logs/runtime.log` に出力。旧 F2「デバッグ情報コンソール出力」機能は廃止（当初 Autoload 名 `Logger` で実装したが、Godot 4.6 組込 `Logger` クラスとの名前衝突で `Static function "log()" not found in base GDScriptNativeClass` エラーが出たため `DebugLog` にリネーム）
- **PartyStatusWindow 詳細度トグル（F3）**：3 段階循環・横一列流しレイアウト・クラス名のメンバー行移動
- **敵固有表示グループの新設**：動的判断（`種: sflee / nomp / lich:X`）・静的属性（`ignfle / undead / flying / immune / proj / chase / terr`）
- **敵の指示体系表示を一掃**：リーダー行の仮想ヒント（`mv=/battle=/tgt=/hp=`）を `strategy=<ENUM>` に刷新、メンバー行の指示ライン（M/C/F/L/S/HP/E/I）を削除
- **Character ステータス設計統一**：13 ステータス全てを Character 最終値フィールドに保持・装備補正取得を単一 API に集約
- **味方側 `_party_strategy` / `party_fleeing` 廃止（ステップ 1）**：敵専用概念に変更・プレイヤー個別指示が `party_fleeing=true` で上書きされる仕様違反を解消
- **F7 PartyStatusWindow スナップショット機能を新設**：全パーティー状態を `res://logs/snapshot_<timestamp>.log` に個別ファイルとして書き出し（詳細度最大固定・ウィンドウ非表示でも動作・ConfigEditor 開時は無効・`runtime.log` には押下マーカー 1 行のみ）
- **個体アクション `flee` を 3 種に分離（`keep_distance` / `fall_back` / `flee`）**：PartyStatusWindow の表示が「HP 低下逃走・パーティー撤退・種族カイティング」で全て「逃走」になっていた問題を解消
- **`on_low_hp` の内部値 `"retreat"` → `"fall_back"` にリネーム**（UI 表示「後退」は維持・全体方針 `battle_policy = "retreat"` との内部名重複解消）
- **ステップ 2 完了：NpcLeaderAI CRITICAL 時 `battle_policy` 自動書き換え**：ステップ 1 で失われた NPC の自動 FLEE を別経路で復活（`_global_orders["battle_policy"] = "retreat"` ベース・PartyLeaderPlayer と同じ経路）
- **ステップ 3 完了：FLEE 時の逃走先決定ロジック**：味方パーティーに二段階方式（リーダー推奨出口 + メンバー自律選択）を実装・脅威コスト付き A* + エリア BFS 距離の複合評価
- **PartyStatusWindow の FLEE 時避難先情報表示**：ヘッダーの戦況判断ブロック末尾に `避難先:<area_id>(d:<n>)@(<x>,<y>)` / フォールバック時 `避難先:!fb@(<x>,<y>)` を追加（味方パーティー限定）
- **dead code 削除**：`Character.get_direction_multiplier()`
- **調査ドキュメント 5 件新規作成**：`investigation_debug_variables.md` / `investigation_enemy_order_system.md` / `investigation_enemy_order_effective.md` / `investigation_receive_order_keys.md` / `investigation_party_strategy_ally_removal.md`

---

### 味方側 `_party_strategy` / `party_fleeing` 廃止（ステップ 1）

**背景**：プレイヤー操作パーティーでは OrderWindow の個別指示（`combat` / `battle_formation` 等）が最終指示のはずだが、既存実装では `PartyLeaderPlayer._evaluate_party_strategy()` が `global_orders.battle_policy` を Strategy enum に変換し、`Strategy.FLEE` 時に `party_fleeing = true` をメンバーに配布していた。UnitAI 側では `_party_fleeing` フラグが個別指示より優先されるため、プレイヤーの細かな指示が意図せず上書きされる。NpcLeaderAI も同様の構造で、CombatSituation.CRITICAL 時に FLEE 戦略に切り替わる副作用があった。

**設計原則（2026-04-21 確立）**：

1. `_party_strategy` は**敵パーティー（EnemyLeaderAI 系）専用**の概念。味方では計算・保持しない
2. `party_fleeing` は**敵メンバー専用の配布フラグ**。味方メンバーには常に false を配布
3. パーティー戦略はリーダー個人の属性ではない。`_leader_ref._party_strategy` 経由の取得は**将来にわたって禁止**
4. 味方の戦略は `global_orders.battle_policy` を通じた**個別指示のプリセット流し込み**（OrderWindow の `_apply_battle_policy_preset`）経由のみで反映する

**実装変更**：

- **`scripts/party_leader.gd`** に基底フックを追加：
  - `_is_enemy_party() -> bool`：先頭生存メンバーの `is_friendly` で判別
  - `_is_in_explore_mode() -> bool`：EXPLORE 相当。基底実装は `_party_strategy == EXPLORE`
  - `_is_in_guard_room_mode() -> bool`：GUARD_ROOM 相当。基底実装は `_party_strategy == GUARD_ROOM`
  - `_assign_orders()` で `_is_enemy_party()` ガード下でのみ `_evaluate_party_strategy()` / `_apply_range_check()` / `_log_strategy_change` を実行
  - `party_fleeing = is_enemy_party and _party_strategy == FLEE` に変更
  - EXPLORE / GUARD_ROOM 分岐を `_is_in_explore_mode()` / `_is_in_guard_room_mode()` 経由に変更
- **`scripts/party_leader_player.gd`**：`_evaluate_party_strategy()` override を物理削除
- **`scripts/npc_leader_ai.gd`**：
  - `_evaluate_party_strategy()` override を物理削除
  - 敵検知ロジックを `_has_visible_enemy()` として抽出（同フロア・訪問済みエリアの生存敵チェック）
  - `_is_in_explore_mode()` を override：`not _has_visible_enemy()` を返す
  - `get_global_orders_hint()` から `match _party_strategy` 分岐を削除し `_is_in_explore_mode()` 経由に変更
  - `_get_strategy_change_reason()` を `super` 呼出のみに簡素化（`_log_strategy_change` は敵のみ発火するため NPC では使われない）
  - `is_in_combat()` を `_has_visible_enemy()` に変更
- **`scripts/party_status_window.gd`**：`_build_ai_flag_parts(ai, m)` に member 引数を追加し、`m.is_friendly` なら `P↓` 表示をスキップ
- **`scripts/party_manager.gd`**：`_check_room_suppression()` にコメント追加（敵専用動作であることを明示）

**一時的に失われる挙動（ステップ 2 で復活予定）**：

- NpcLeaderAI の CombatSituation.CRITICAL 時自動 FLEE（パーティー単位での撤退切替）
  - 個別指示 `on_low_hp = "flee"` による個人逃走は従来どおり発動
  - ステップ 2 で `_global_orders["battle_policy"] = "retreat"` への自動書き換え方式で復活予定
  - それまでの期間、CRITICAL 時は戦闘継続するが個別 HP 低下メンバーのみ逃走

**関連調査**：

- [`docs/investigation_receive_order_keys.md`](investigation_receive_order_keys.md)：receive_order ペイロード全 12 キーの棚卸し（指示 9 / パーティー文脈 2 / 戦況判断 1・dead transmission なし）
- [`docs/investigation_party_strategy_ally_removal.md`](investigation_party_strategy_ally_removal.md)：影響範囲調査（参照 40 箇所・変更 5 ファイル）

---

### F7 PartyStatusWindow スナップショット機能

**背景**：静止画スクリーンショットは情報密度が低く、バランス調整・戦略切替の時系列追跡に不向き。PartyStatusWindow の表示内容（パーティー戦略・戦況・メンバーステータス・指示・敵固有フラグ等）をテキストで残せると、戦略切替・FLEE 発動・戦力比変化などのデバッグが容易になる。

**実装**：

- [`scripts/party_status_window.gd`](../scripts/party_status_window.gd) に `snapshot_to_log()` 新設
- F7 押下時に現在の全パーティー状態を `res://logs/snapshot_<timestamp>.log` に個別ファイルとして書き出す
- **ファイル命名**：`snapshot_YYYYMMDD_HHMMSS_mmm.log`（ミリ秒まで含めて短時間の重複押下でも衝突回避）
- **ファイル管理**：毎起動リセットしない（履歴として蓄積）・手動削除で整理する。将来「最新 N 件のみ保持」等の自動整理機構を追加する余地あり
- **マーカー行**：`res://logs/runtime.log` に `F7 snapshot → snapshot_<timestamp>.log` の 1 行を `DebugLog.log()` で記録。「いつ F7 を押したか」と対応ファイル名を runtime.log から辿れる
- **詳細度は常に最大**：`_detail_level` を一時的に 2 に切り替えてヘルパー群を呼び、終了時に復元。画面の F3 設定には影響しない
- **ウィンドウ独立**：PartyStatusWindow が閉じていても F7 単独で動作（`game_map.gd:_input` で F7 を受信）
- **ConfigEditor（F4）開時は無効**：誤動作防止
- 画面描画の文字列ヘルパー（`_format_action_body` / `_build_orders_field_list` / `_build_char_stat_parts` 等）を再利用し、表示と記録の一貫性を保つ
- 1 メンバー 1 行にフラット化（画面は折返しあり・スナップショットは `|` 区切りで折返しなし）

**出力構造（snapshot ファイル本体）**：

```
================================================================
PartyStatusWindow Snapshot
================================================================
時刻: 2026-04-21 14:32:15.123
フロア: 2
操作キャラ: 主人公（剣士）
ゲーム速度: 1.0x
----------------------------------------------------------------
[プレイヤー]  生存:3/3  戦況:安全 ...
  ★主人公[A](剣士) HP:50/50 SP:20/20 ... | →... | 指示:M:follow C:attack ... | pow:70+4 ...
  ...
[NPC]  生存:2/2  ...
  ...
[敵]  生存:4/4  戦況:互角 ... strategy=ATTACK
  ...
================================================================
```

**runtime.log 側のマーカー例**：

```
[14:32:15.123] F7 snapshot → snapshot_20260421_143215_123.log
```

**設計経緯（2026-04-21 個別ファイル化改訂）**：当初は `runtime.log` に直接多行ダンプしていたが、「瞬間の状態記録」という独立した単位として個別ファイルに分離した。通常ログと混在すると可読性が低く、また多行スナップショットが runtime.log を埋めて他のログが見づらくなる問題を解消した。

---

### 個体アクション `flee` を 3 種に分離（`keep_distance` / `fall_back` / `flee`）

**背景**：F7 スナップショットで `strategy=ATTACK` なのに敵メンバーが「逃走」と表示される現象があり、調査の結果 GoblinArcher の射程維持カイティング（`_generate_queue` で `{"action": "flee"}` を ATTACK 戦略中にキュー投入する仕組み）が表示に反映されていると判明。「HP 低下逃走」「パーティー FLEE 撤退」「種族カイティング」の 3 コンテキストで同じ `flee` アクションが使われており、PartyStatusWindow で意味を区別できなかった。

詳細調査は [`docs/investigation_unit_ai_actions.md`](investigation_unit_ai_actions.md) 参照（アクション総数 13 種・重複用途 1 種・_generate_queue override 2 種族）。

**設計方針**：

1. 個体アクションを意味論的に分離：
   - `keep_distance`（距離確保）：射程維持のための戦術的後退（戦闘継続）
   - `fall_back`（後退）：前線から下がる（戦闘継続・HP 低下時の選択肢）
   - `flee`（逃走）：戦闘から離脱する（パーティーから離れて安全な場所へ）
2. 個別指示 → 個体アクションの対応を明確化：
   - `on_low_hp = "fall_back"` + HP 低下 → `{"action": "fall_back"}`
   - `on_low_hp = "flee"` + HP 低下 → `{"action": "flee"}`
   - `combat = "flee"` → `{"action": "flee"}`
   - `keep_distance` は個別指示から独立（種族 AI 専用の自動発火）
3. 実行ロジックは当面 3 種とも同じ（`_find_flee_goal()` で脅威から離れる方向に移動）。差別化は将来タスク
4. 内部名リネーム：`on_low_hp = "retreat"` → `"fall_back"`（全体方針 `battle_policy = "retreat"` との内部名重複を解消・UI 表示「後退」は維持）

**実装変更**：

- **[`scripts/unit_ai.gd`](../scripts/unit_ai.gd)**：
  - `const _STRATEGY_FALL_BACK := 3` 新設（UnitAI 内部専用の戦略値・PartyLeader.Strategy とは独立）
  - `_determine_effective_action()`：`"fall_back"` ケースを `_STRATEGY_FALL_BACK`（3）を返すよう変更（旧：WAIT=2 を返していた）。`_should_ignore_flee()` で DarkKnight 等の「逃げない」種族は fall_back も無視
  - `_generate_queue()`：strategy == 3（FALL_BACK）の分岐を新設。5x `{"action": "fall_back"}` を生成
  - 実行ディスパッチ（`_start_action` / `_step_toward_goal`）：`"flee"` / `"fall_back"` / `"keep_distance"` の 3 アクション全てで `_find_flee_goal()` を呼ぶ共通実装
  - `get_debug_goal_str()`：`"fall_back" → "後退"` / `"keep_distance" → "距離確保"` のラベルを追加
- **[`scripts/goblin_archer_unit_ai.gd`](../scripts/goblin_archer_unit_ai.gd)**：`_generate_queue` のカイティングキュー `{"action": "flee"}` → `{"action": "keep_distance"}` にリネーム
- **[`scripts/salamander_unit_ai.gd`](../scripts/salamander_unit_ai.gd)**：同上
- **[`scripts/party_leader.gd`](../scripts/party_leader.gd)**：`on_low_hp == "retreat"` の cluster 上書きを撤去（fall_back が専用 strategy を持つため不要に）・`on_low_hp` デフォルト値を `"fall_back"` に変更
- **on_low_hp 値リネーム（`"retreat"` → `"fall_back"`）** の影響ファイル：
  - [`scripts/character.gd`](../scripts/character.gd)（`current_order` デフォルト）
  - [`scripts/party.gd`](../scripts/party.gd)（`global_orders` デフォルト）
  - [`scripts/order_window.gd`](../scripts/order_window.gd)（`GLOBAL_ROWS` の on_low_hp options）
  - [`scripts/global_constants.gd`](../scripts/global_constants.gd)（`GLOBAL_LOW_HP`）
  - [`scripts/left_panel.gd`](../scripts/left_panel.gd)（表示ラベル辞書）
  - [`scripts/unit_ai.gd`](../scripts/unit_ai.gd)（デフォルト・receive_order）
  - [`scripts/npc_leader_ai.gd`](../scripts/npc_leader_ai.gd)（NPC hint デフォルト）

**`"retreat"` を保持した箇所**：
- `battle_policy` の選択肢（全体方針「撤退」の内部値）は変更せず
- `order_window.gd:BATTLE_POLICY_PRESET` の `"retreat":` キー（battle_policy 値）
- `unit_ai.gd:_find_friendly_retreat_goal()` 関数名とローカル変数 `var retreat`（意味的に正しい命名）

**一時的な挙動保証**：

- 3 アクションの実行ロジックは同一（`_find_flee_goal()`）のため、表面上の移動挙動は変わらない
- PartyStatusWindow の表示ラベルのみ「距離確保」「後退」「逃走」に分離され、デバッグ時の意図識別が可能に
- DarkKnight / Zombie 等「逃げない種族」は fall_back も無視（`_should_ignore_flee()` ガード）。従来 `retreat=WAIT+cluster` で実質その場に留まっていた挙動を保持

**将来の差別化予定**（「次セッションで検討するタスク」項目 5）：
- `keep_distance`：射程内を保つ（遠ざかりすぎない）
- `fall_back`：リーダー後方 or 射程外まで下がる
- `flee`：安全な場所へ完全離脱（ステップ 3 の `flee_recommended_goal` 実装で対応予定）

---

### ステップ 2：NpcLeaderAI CRITICAL 時 `battle_policy` 自動書き換え

**背景**：ステップ 1（味方側 `_party_strategy` / `party_fleeing` 廃止）で `NpcLeaderAI._evaluate_party_strategy()` を削除した結果、「戦況 CombatSituation.CRITICAL 時の自動 FLEE」が一時的に失われていた。復活させる必要があるが、旧実装（`_party_strategy = Strategy.FLEE` に切り替える）ではなく、**NpcLeaderAI が自分の `_global_orders.battle_policy` を `"retreat"` に書き換える**方式で実装することで、PartyLeaderPlayer と同じ経路（OrderWindow 経由プリセット流し込みと等価）で FLEE を発動させる形に統一する。

**設計方針**：

1. `_evaluate_party_strategy()` は復活させない（味方は `_party_strategy` を使わない原則を維持）
2. NpcLeaderAI が自分の `_global_orders["battle_policy"]` を自動書き換え
3. CRITICAL → `"retreat"` / SAFE → `"attack"` の 2 閾値切替。中間領域は現状維持（境界振動抑制）
4. プリセット流し込み機構を共通化（PartyLeader 基底 → NPC / プレイヤー共通経路化）
5. クールダウンで短時間の連続切替を抑制

**実装変更**：

- **[`scripts/party_leader.gd`](../scripts/party_leader.gd)** に `apply_battle_policy_preset(policy: String)` 公開メソッド新設
  - OrderWindow の `_apply_battle_policy_preset` と同等ロジックを PartyLeader 基底に持たせる
  - `OrderWindow.BATTLE_POLICY_PRESET`（クラス別 × 方針別）を再利用・ヒーラーは専用プリセット
  - `_party_members` を対象にメンバーの `current_order` を一括更新
- **[`scripts/npc_leader_ai.gd`](../scripts/npc_leader_ai.gd)**：
  - `_evaluate_and_update_battle_policy()` 新設（毎フレーム判定・安価な早期リターン付き）
  - `_last_policy_change_time: float = -INF` 変数追加（クールダウン管理）
  - `_combat_situation_label()` ヘルパー追加（ログ用）
  - `_process(delta)` で `super._process(delta)` 後に上記関数を呼ぶ（`joined_to_player` 中は対象外）
  - 書き換え時は `_global_orders["battle_policy"] = new_policy` → `apply_battle_policy_preset(new_policy)` → `notify_situation_changed()` で即時伝達
  - `[NPC戦況判断]` ログを `MessageLog.add_ai()` に出力
- **[`scripts/global_constants.gd`](../scripts/global_constants.gd)**：`NPC_POLICY_CHANGE_COOLDOWN = 3.0`（float）追加・Config Editor NpcLeaderAI カテゴリに登録
- **[`assets/master/config/constants_default.json`](../assets/master/config/constants_default.json)**：`NPC_POLICY_CHANGE_COOLDOWN` メタ情報追加（min=0.0 / max=30.0 / step=0.5）

**OrderWindow 側のプリセット流し込みは変更なし**：プレイヤー側は従来どおり `OrderWindow._apply_battle_policy_preset` で `Party.members` を直接更新する。PartyLeader 基底の `apply_battle_policy_preset` は NPC 用に新設した同等処理。軽い重複はあるがスコープ分離優先（プレイヤー OrderWindow vs NPC 自律判断）。

**動作観察**：

- NPC 交戦中に戦力比 < 0.5（CRITICAL）になると battle_policy が `attack → retreat` に切り替わり、各メンバーの `combat = "flee"` / `battle_formation = "gather"`（近接クラス）/ `rear`（後衛クラス）へプリセット流し込まれる
- メンバーが逃走キュー（UnitAI の `{"action": "flee"}` 5 個）を取得して脅威から離脱
- 敵から離れて戦況 SAFE に戻ると `battle_policy = attack` に復帰・通常行動再開
- 境界値で戦況が振動しても 3 秒間は再切替しない（`NPC_POLICY_CHANGE_COOLDOWN`）

**敵パーティーへの非影響**：敵は `_party_strategy`（enum）ベースの FLEE 判定を維持。NpcLeaderAI のロジックは party_type="npc" 限定。

**プレイヤーパーティーへの非影響**：プレイヤーは OrderWindow 経由の手動設定のみ反映。NpcLeaderAI のロジックは PartyManager.party_type による分岐で発火しない。

---

### ステップ 3：FLEE 時の逃走先決定ロジック（二段階方式）

**背景**：ステップ 1・2 で味方 FLEE の発火経路（`battle_policy = "retreat"` + メンバー個別指示プリセット）は整ったが、実際の逃走先決定は旧実装（`_find_friendly_retreat_goal`：単純な最近安全タイル + `_find_flee_goal_legacy`：脅威から 5 タイル離れる）で、脅威を考慮しない・避難先への経路を考えない粗い実装だった。

新設計は「リーダー層（戦略）がパーティー全体の推奨出口を決定 → メンバー層（戦術）が自分の位置から全出口を評価・推奨バイアス付きで選択」の二段階協調ロジック。

**設計方針**：

1. **二段階構造**：リーダー推奨出口 + メンバー自律選択（統率と柔軟性の両立）
2. **出口タイル定義**：現エリア内のタイルで 4 近傍に別エリアがあるタイル（「内側出口」）。A* ゴールが現エリア内で完結
3. **A* 探索範囲は現エリア内に限定**：計算量抑制 + 脅威情報の精度保証
4. **避難先は複数候補対応**：フロア 0 = 複数の安全部屋 / フロア 1 以降 = 複数の上り階段エリア。各候補への最小 BFS 距離を取る
5. **個体 FLEE / パーティー FLEE で推奨バイアスを切替**：パーティー FLEE = バイアスあり（統率）、個体 FLEE = バイアスなし（自律）
6. **`flee_recommended_goal` はパーティー文脈情報として配布**：receive_order の辞書に追加（Vector2i(-1, -1) = 推奨なし）
7. **敵ステータス直接参照禁止ルール準拠**：脅威コストは位置と `is_friendly` のみ参照・HP や power は見ない
8. **敵パーティーは現状スコープ外**：敵は `_find_flee_goal_legacy`（従来実装）のままで動作

**実装変更**：

- **[`scripts/map_data.gd`](../scripts/map_data.gd)** に 4 API 新設：
  - `get_refuge_area_ids(floor_id: int) -> Array[String]`：避難先エリア ID 一覧（フロア 0 = `_safe_tiles` から導出 / フロア 1 以降 = `find_stairs(STAIRS_UP)` から導出・重複排除）
  - `get_area_distance(from, to) -> int`：エリア間の BFS ホップ数（`_adjacent_areas` を使用・到達不能 = -1・同一 = 0）
  - `get_exit_tiles_from(area_id) -> Array[Vector2i]`：エリアの内側出口タイル一覧
  - `get_adjacent_area_ids_of_exit(exit_tile) -> Array[String]`：出口タイルの向こう側エリア ID 一覧
- **[`scripts/unit_ai.gd`](../scripts/unit_ai.gd)** 拡張：
  - `_flee_recommended_goal: Vector2i` 変数追加（receive_order で受信）
  - `_last_area_id: String` 変数追加（エリア変化検知用）
  - `_astar_with_cost(start, goal, cost_fn, area_limit_id)` 新規：タイルコスト関数 + エリア制限対応の A*（既存 `_astar` は非破壊で維持）
  - `_calc_threat_cost(tile) -> float`：脅威コスト計算（対立陣営の生存キャラについて `max(0, FLEE_THREAT_RANGE - manhattan) × FLEE_THREAT_WEIGHT` を合計）
  - `_path_cost(path, threat_fn) -> float`：経路の合計コスト（1 ステップあたり 1.0 + 脅威コスト）
  - `_find_flee_goal()` を新ロジックに更新（味方のみ・敵は `_find_flee_goal_legacy` へ）
  - `_find_flee_goal_legacy(threat)`：旧実装を改名（敵 / 孤立エリアフォールバック用）
  - `_is_in_refuge_area()`：現エリアが避難先エリアかの判定
  - `_notify_area_change_if_needed()`：`_process` 内で毎フレーム呼ばれ、エリア変化時にリーダー通知
  - `_generate_queue` の味方 FLEE 分岐を変更：`move_to_explore`（最近安全タイル直行）→ `{"action": "flee"}` × 5（新ロジックで段階的に避難先へ）
  - 避難先到達時は `{"action": "wait"}` を返す
- **[`scripts/party_leader.gd`](../scripts/party_leader.gd)** 拡張：
  - `_flee_recommended_goal: Vector2i` / `_flee_last_reeval_time: float` 変数追加
  - `get_flee_recommended_goal() -> Vector2i`：外部公開 getter
  - `_is_party_fleeing() -> bool`：味方（`battle_policy == "retreat"`）/ 敵（`_party_strategy == FLEE`）の統一判定
  - `_update_flee_recommended_goal()`：`_assign_orders()` から毎回呼ばれて推奨出口を更新
  - `_determine_flee_recommended_goal()`：現エリアの全出口を評価 → 最小コストの出口を返す（リーダー UnitAI インスタンスで `_astar_with_cost` を呼ぶ）
  - `_get_first_alive_leader() -> Character`：生存メンバー取得ヘルパー
  - `on_member_area_changed(member, new_area)`：メンバー UnitAI からの通知受けて推奨出口再計算（`FLEE_REEVAL_MIN_INTERVAL` クールダウン付き）
  - `_assign_orders()` の receive_order 辞書に `flee_recommended_goal` キーを追加
- **[`scripts/party_status_window.gd`](../scripts/party_status_window.gd)**：
  - `_build_ai_flag_parts(ai, m)` に `flee→(x,y)` 表示を追加（詳細度「低」・味方メンバー限定）
  - VAR_PRIORITY に `flee_recommended_goal = 2` を登録
- **[`scripts/global_constants.gd`](../scripts/global_constants.gd)**：5 定数新設（UnitAI カテゴリ・Config Editor 対応）
  - `FLEE_THREAT_RANGE = 5` / `FLEE_THREAT_WEIGHT = 3.0` / `FLEE_AREA_DISTANCE_WEIGHT = 10.0` / `FLEE_NON_RECOMMENDED_PENALTY = 15.0` / `FLEE_REEVAL_MIN_INTERVAL = 0.3`
- **[`assets/master/config/constants_default.json`](../assets/master/config/constants_default.json)**：上記 5 定数のメタ情報追加

**A* 呼び出し構造**：PartyLeader から A* を呼ぶ際は、リーダーの UnitAI インスタンスを経由する（walker コンテキスト = `is_friendly` / `is_flying` / `_move_policy` 等が必要なため）。`_unit_ais.get(leader.name)._astar_with_cost(...)` の形で呼ぶ。

**デッドコード候補**：`UnitAI._find_friendly_retreat_goal()` は今回の改訂で呼び出し元が消失した。dead code として次の棚卸しで物理削除予定。

**派生課題**：

- **敵パーティーへの同ロジック適用**（優先度：中）：現状、敵の `flee` は `_find_flee_goal_legacy`（脅威から 5 タイル離れる）のまま。味方と同じ二段階ロジックを敵にも適用する。避難先は敵種族ごとに異なる可能性（縄張り戻り / 階段逃走など）の設計検討が必要
- **`_find_friendly_retreat_goal` 削除**（優先度：低・dead code）
- **戦況判断と避難先計算の関数統合**（優先度：低）：`_evaluate_strategic_status()` と `_determine_flee_recommended_goal()` を統合し、避難先情報も `combat_situation` 辞書に含める

---

### PartyStatusWindow FLEE 時避難先情報表示

**背景**：ステップ 3 で FLEE 時の推奨出口タイル（`_flee_recommended_goal`）はメンバー行に `flee→(x,y)` として表示されたが、「パーティー全体として目指している避難先エリア」と「そこまでの BFS 距離」がログから追えなかった。リーダーが自律計算する高次の戦略意図（どのエリアを目指しているか）を可視化する。

**設計方針**：
1. 表示位置は**戦況判断ブロック末尾**（`HP:満` の直後）。`battle=撤退` は全体指示（プレイヤー設定値）なので触らず、避難先情報は「戦況判断の派生情報」として独立扱い
2. **パーティー FLEE 中のみ表示**（`_is_party_fleeing() == true`）・通常時は非表示でヘッダーの形を変えない
3. **味方パーティー限定**（敵は FLEE 実装が別タスク）
4. フォールバック状態を明示（`!fb` マーカー）

**実装変更**：

- **[`scripts/party_leader.gd`](../scripts/party_leader.gd)**：
  - 避難先情報の保持変数 3 つ追加：`_flee_refuge_area_id: String` / `_flee_refuge_distance: int` / `_flee_is_fallback: bool`
  - `_update_flee_recommended_goal()`：FLEE でないときに全 4 変数をクリア
  - `_determine_flee_recommended_goal()` 刷新：
    - 開始時に 3 変数をリセット
    - 各出口ループ内で `exit_refuge_area` / `exit_refuge_dist` を追跡（選ばれた出口の対応避難先を記録）
    - フォールバック条件を明示：MapData 不在・リーダー不在・エリア空・出口なし・避難先エリア一覧空・選択出口から避難先到達不能 → `_flee_is_fallback = true`
    - 選ばれた出口の `best_refuge_area` / `best_refuge_dist` を 3 変数に記録
  - 公開 getter 3 つ追加：`get_flee_refuge_area_id()` / `get_flee_refuge_distance()` / `is_flee_fallback()`
- **[`scripts/party_status_window.gd`](../scripts/party_status_window.gd)**：
  - ヘルパー関数 `_format_flee_refuge_suffix(pm)` 新設
    - 味方パーティー限定（`party_type == "enemy"` は空文字）
    - `goal == Vector2i(-1, -1)` は空文字
    - フォールバック時：`  避難先:!fb@(x,y)`
    - 通常：`  避難先:<area_id>(d:<n>)@(x,y)`
    - 情報欠損時もフォールバック扱い（防御的）
  - `_draw_party_block` / `_draw_player_party` ヘッダーに suffix を追加（`_format_leader_extras` の前）
  - snapshot 版 `_snapshot_player_party_lines` / `_snapshot_party_block_lines` にも同じ suffix 追加（F7 出力に自動反映）

**出力例**：

```
# 通常（FLEE 中・避難先あり）
[NPC]  生存:2/2  戦況:劣勢 戦力:劣位 F(4+0.0)4.0 C(4+0.0)4.0 E(6+0.0)6.0 HP:満  避難先:area_safe_00(d:3)@(44,13)  mv=追従  battle=撤退 ...

# フォールバック（避難先不明 or 到達不能）
[NPC]  生存:2/2  戦況:劣勢 ... HP:満  避難先:!fb@(44,13)  mv=追従  battle=撤退 ...

# 通常時（FLEE でない）
[NPC]  生存:2/2  戦況:安全 ... HP:満  mv=追従  battle=攻撃 ...
```

**派生課題**（要調査項目に記録）：
- 戦況判断（`_evaluate_strategic_status`）と避難先計算（`_determine_flee_recommended_goal`）の関数統合（将来的に `combat_situation` 辞書に避難先情報を含める）
- 敵パーティーの避難先表示対応（将来の敵 FLEE 新ロジック実装時）

**動作観察**：

- 味方 NPC が交戦中に CRITICAL → `battle_policy = "retreat"` に切り替わる（ステップ 2）
- リーダーが現エリアの全出口を評価し、最も安全かつ安全部屋に近い出口を `_flee_recommended_goal` に設定
- 各メンバーは自分の位置から全出口を評価・リーダー推奨なら bias=0、不一致なら +15 のペナルティ
- 脅威コストが高い経路（敵集団が待ち構える出口など）は自然に避けられる
- メンバーがエリアをまたぐたびにリーダーが推奨出口を再計算・次の出口を配布
- PartyStatusWindow（F1 + F3 で詳細度「高+中+低」）のメンバー行に `flee→(x,y)` 表示

**用途例**：

- 敵パーティーが FLEE に入った瞬間の記録
- プレイヤーが特定装備を変更する前後の戦力値比較
- NPC の探索モード判定の結果確認
- Step 1 廃止の動作検証（`strategy=FLEE` / 敵メンバー行 `P↓` が記録されるか）

---

### DebugWindow の上下 2 ウィンドウ分離（F1 / F2）

旧 DebugWindow（上 55% パーティー状態 + 下 45% combat/ai ログ）を 2 つの独立した CanvasLayer に分離。

- **`scripts/party_status_window.gd`** 新設（`class_name PartyStatusWindow`・F1）：パーティー状態表示
- **`scripts/combat_log_window.gd`** 新設（`class_name CombatLogWindow`・F2）：combat/ai ログ表示
- **旧 `scripts/debug_window.gd` を物理削除**
- 相互排他トグル：両方が同時表示されることはない（F1 表示中に F2 で切替、F1 で閉じると全閉 等）
- 各ウィンドウは画面中央 85%×85%・完全透過・layer=15
- 既存機能維持：0.2 秒ごとの更新・MessageLog.debug_log_added シグナル・リーダー選択・カメラ追跡
- F3 選択リセット・F2 切替時の `_restore_hero_floor_view()` 呼出しは PartyStatusWindow に紐付く

### デバッグ用 DebugLog Autoload 新設

`scripts/logger.gd`（Autoload 名 `DebugLog`）を新設。デバッグ目的の一時的なログ出力を「コード編集 → 実行 → Claude Code がファイル直読」のフローに置き換える。

- API：`DebugLog.log(message: String)` 1 関数（将来タグ・レベル拡張の余地あり）
- フォーマット：`[HH:MM:SS.mmm] メッセージ`
- 出力先 2 系統：Godot コンソール（`print`）+ `res://logs/runtime.log`（毎起動リセット・`FileAccess.WRITE`・書込ごとに `flush()`・`NOTIFICATION_WM_CLOSE_REQUEST` で明示クローズ）
- `logs/` フォルダが無ければ `DirAccess.make_dir_recursive_absolute()` で自動作成
- `.gitignore` に `logs/` を追加
- Steam 配布時の TODO：`res://` はエクスポート後読み取り専用のため、Phase 14 でリリースビルド無効化 or `user://` 切替が必要

**Autoload 名のリネーム（Logger → DebugLog）**：
- 当初は `Logger` という名前で Autoload を登録したが、Godot 4.6 には抽象クラス `Logger` が組み込みで存在し、`Logger.log(...)` の外部呼び出しが「`Static function "log()" not found in base GDScriptNativeClass`」エラーで失敗する問題があった
- 組込クラスと同名の Autoload は名前解決が壊れるため `DebugLog` にリネームした。ファイル名は `logger.gd` のまま
- 発覚：F7 スナップショット機能実装時に外部から初めて呼び出したタイミングで検知

**旧 F2 機能（`user://debug_floor_info.txt` 書き出し）の廃止**：
- `game_map._print_debug_floor_info()` 関数（約 90 行）を物理削除
- F2 キーバインドから外し、新規の F2 = CombatLogWindow トグルに割り当て
- 代替は DebugLog Autoload（必要になれば DebugLog 経由で再実装）

### PartyStatusWindow の表示拡充（F3 詳細度トグル・横一列化・クラス名移動）

F3 キーで詳細度を 3 段階循環（高のみ → 高+中 → 高+中+低）。セッション内のみ保持・再起動で「高のみ」にリセット。旧 F3「無敵モード」は F6 に移動。

**詳細度マッピング**：`PartyStatusWindow.VAR_PRIORITY: Dictionary` に変数名→優先度レベル（0=高 / 1=中 / 2=低）の単一の真実源を定義。新しい変数追加・優先度微調整はここだけ触る。

**横一列流しレイアウト改訂**（旧：強制 1〜3 行/メンバー）：
- メンバー情報（行動 / 指示 / ステータス）を 1 メンバー 1 論理行に集約
- 幅超過時のみセグメント境界で自然折返し
- セグメント単位で色分け（行動ボディ=HP 色 / 目的=シアン / 指示=黄緑 / 状態・ステータス=茶系）
- 継続行ではセグメント先頭の空白を削除して左端から描画

**クラス名の表示位置変更**：
- リーダー行から**リーダー名・クラス名を除去**（`[プレイヤー] 生存:4/4 ...` のみ）
- クラス名は各メンバー行に移動（`★名前[C](ヒーラー) HP:... mv=... →目的`）
- 識別は `[種別]` + 色分け + メンバー行の `★` / `(クラス)` の組み合わせで行う運用

**行動ラインに energy 表示を追加**：`MP:x/y` / `SP:x/y` をクラスに応じて切替（`CharacterData.is_magic_class()`）。`max_energy == 0` のキャラは省略

**詳細度「低」でフラグライン拡張**：UnitAI 側フラグ（P↓ / F↑ / warp）＋ Character 12 ステータスを `abbr:base+bonus` 形式で一列表示
- Character ステータス略称表：`pow` / `skl` / `rng` / `br` / `bl` / `bf` / `pr` / `mr` / `da` / `ld` / `ob` / `mv_s` + `fac` / `leader`
- `abbr:base+bonus` 形式（装備補正非 0 時）・`abbr:base` 形式（補正 0 時）
- 素値・補正ともに 0 のフィールドは省略（弓使いの `br/bl` など）

**敵固有表示グループを新設**：
- 動的判断（中）：`種: sflee nomp lich:水`（`_should_self_flee` / `_can_attack` / LichUnitAI._lich_water）
- 静的属性（低）：`ignfle undead flying immune proj:<type> chase:N terr:N`（`_should_ignore_flee` / is_undead / is_flying / instant_death_immune / projectile_type / chase_range / territory_range）
- 味方メンバーでは本グループは空配列を返す（`m.is_friendly` ガード）
- 敵メンバーでは「指示ライン」の代替表示として位置付け

---

### 敵メンバー行の指示ラインを削除（リーダー行廃止と同じ論理）

前段で敵リーダー行の仮想ヒント（`mv=... battle=... tgt=... hp=...`）を廃止したのと同じ論理で、**敵メンバー行の指示ライン**（`指示: M:... C:... F:... L:... S:... HP:... E:... I:...`）も削除。

#### 再検証結果（前回調査書との整合）
実装前に 8 項目 × 敵実動経路を再検証し、前回調査書と矛盾しないことを確認：
- `_move_policy="spread"`（敵固定）：`_generate_move_queue()` には "spread" 分岐なし → `_` デフォルト（formation/wait）。`_formation_satisfied()` / `_target_in_formation_zone()` の "spread" 分岐は存在するが、値が変化しないため decision を生まない
- `_combat="attack"`（敵 Character デフォルト）：`_determine_effective_action()` L2191 の `match _combat` で `"attack"` ブランチに着地 → 固定 ATTACK
- `_battle_formation="surround"`（敵 Character デフォルト）：L760 / L2239 の match `_` デフォルト → 標準攻撃フロー。値が変化しない
- `_on_low_hp="retreat"`（敵 Character デフォルト）：L2179 の match `"retreat"` ブランチ → 固定 WAIT。値が変化しない
- `_special_skill`：`_generate_special_attack_queue()` L1859 と `_generate_buff_queue()` L1806 の冒頭 `if not _member.is_friendly: return []` で参照される前に空配列返却
- `_hp_potion="never"` / `_sp_mp_potion="never"`：`if _hp_potion == "use"` / `if _sp_mp_potion == "use"` の条件式が成立せず、潜在的に呼ばれる経路でも何も起きない
- `_item_pickup="passive"`：敵の `_is_combat_safe()` が真になるケースが稀・敵はそもそも inventory 管理を持たないため実質無効

全 8 項目とも敵実動に影響しないことを確認。前回調査書の分類（(A) 4 件 / (B) 3 件 / (C) 1 件）と整合。

#### 変更内容
1. **`party_status_window.gd` `_draw_member_block()` 指示グループに `m.is_friendly` ガードを追加**：敵メンバーでは指示グループを出力しない
2. 敵固有・動的判断グループ（`種: sflee nomp lich:水`）は 2026-04-21 に追加済みのため変更不要。敵メンバーの指示スロットの代替表示として位置付け
3. **CLAUDE.md「デバッグウィンドウ」節の指示グループ項目**に「味方メンバーのみ」の注記を追加

#### 仮想ヒント生成コードの扱い
`PartyLeader.get_global_orders_hint()` の `match _party_strategy` 仮想ヒント生成は、前段（同日・敵リーダー行 `strategy=<ENUM>` 化）で既に物理削除済み。本変更で新たに削除するコードはない。

#### 維持するコード
`_assign_orders()` が敵 UnitAI にも `_combat` / `_battle_formation` / `_on_low_hp` 等を渡す部分は削除しない。味方では有効に機能するため、フローを統一した方が保守性が高い。UnitAI 側で敵の該当フィールドを参照する match 分岐も残す（値が固定のため no-op だが、`is_friendly` 分岐を増やすと複雑化するため維持）。

---

### 敵リーダー行の仮想ヒント表示を廃止し `strategy=<ENUM>` 直接表示に

#### 背景
PartyStatusWindow の敵リーダー行に表示されていた `mv=密集 battle=攻撃 tgt=最近傍 hp=戦闘継続` は、2 段階の調査で「UnitAI 実動と連動していない誤解を招く表示」だと判明した：

1. [`docs/investigation_enemy_order_system.md`](investigation_enemy_order_system.md)（2026-04-21）：敵 PartyManager の `_global_orders` は常に空辞書であり、`_assign_orders` は敵には `_move_policy="spread"` 固定を渡す。UnitAI の指示フィールドは敵では Character デフォルト（`_combat="attack"` 等）のまま参照されない
2. [`docs/investigation_enemy_order_effective.md`](investigation_enemy_order_effective.md)（2026-04-21）：敵リーダー行の `mv=密集 battle=攻撃 tgt=最近 hp=戦闘継続` は `PartyLeader.get_global_orders_hint()` が `_party_strategy` から合成した**仮想ラベル**であり、`_global_orders` でも `current_order` でもない第 3 のデータソース。UnitAI 側の実動（種族フック + ハードコード）とは完全に切り離されている

7 フィールド（mv / battle / tgt / hp / item / hp_potion / sp_mp_potion）全てが「(A) 表示だけで意味なし」判定。敵の指示体系は味方と**完全に異なる**ため、味方と同じ `mv=... battle=...` 形式での表示は続けるべきではないと結論。

#### 変更内容
1. **敵リーダー行のヘッダーフォーマットを変更**（`party_status_window.gd` `_draw_party_block()`）
   - 旧：`[敵] 生存:2/2 戦況:優勢 戦力:... HP:満  mv=密集 battle=攻撃 tgt=最近傍 hp=戦闘継続`
   - 新：`[敵] 生存:2/2 戦況:優勢 戦力:... HP:満  strategy=ATTACK`
   - `strategy=` の値は `_party_strategy` enum を**英字のまま**（`ATTACK` / `FLEE` / `WAIT` / `DEFEND` / `EXPLORE` / `GUARD_ROOM`）表示し、「素の内部変数」であることを視覚的に明示。日本語化が必要な UI 用途では `PartyLeader.get_current_strategy_name()` を使う
   - 味方（プレイヤー・NPC）のヘッダーは変更なし（`mv / battle / tgt / hp / item` は `_global_orders` の実値で動的）
2. **仮想ヒント合成コードを物理削除**（`party_leader.gd` `get_global_orders_hint()`）
   - 旧：`match _party_strategy` で `ATTACK → {"move": "cluster", "battle_policy": "attack", ...}` 等の仮想ラベル辞書を生成
   - 新：`_global_orders` が空なら単に空辞書を返す（`combat_situation` / `power_balance` / `hp_status` / 戦力内訳キーは従来通り付与）
   - grep 確認：敵リーダー行の旧描画以外に `hint.get("move")` 等の参照なし（味方は `_global_orders.duplicate()` パス、NPC は `npc_leader_ai.gd` 側のオーバーライドを通るため、基底の match 分岐は到達不能だった）
3. **`_strategy_enum_name_for()`** ヘルパを `party_status_window.gd` に追加（`PartyLeader.Strategy` enum → 英字名への変換。日本語化用の `_strategy_to_preset_name()` とは別用途）
4. **CLAUDE.md「デバッグウィンドウ」節**を更新：味方と敵のヘッダーフォーマットが異なる旨を明記・調査ドキュメントへのリンクを追加



### Character ステータスの最終値保持に統一（13 ステータス）

#### 背景
- Config Editor のアイテムタブでは 13 ステータス全てに装備補正を設定可能（`ITEM_STAT_CHOICES` 配列が `power / skill / block_* / physical_resistance / magic_resistance / defense_accuracy / leadership / obedience / move_speed / vitality / energy`）
- 一方 Character クラスが「装備補正込みの最終値」として独自フィールドを持っていたのは `power` / `attack_range` / `max_hp` / `max_energy` の 4 項目のみ（`skill` フィールドも存在したが装備補正なしの素値コピー）
- 残り 9 ステータスはダメージ計算・AI 判断のたびに `character_data.X + character_data.get_X_bonus()` を計算する非対称な設計で、DRY 違反かつバグ温床

#### 変更内容
- **Character に 10 フィールド追加**：`skill` / `block_right_front` / `block_left_front` / `block_front` / `physical_resistance` / `magic_resistance` / `defense_accuracy` / `leadership` / `obedience` / `move_speed`。全て「装備補正込みの最終値」として保持
- **`CharacterData.get_equipment_bonus(stat_name: String) -> float`** を新設（全 equipped スロットの `stats.<name>` を合計する統一 API）
- **旧 7 個別 getter を物理削除**：`get_weapon_power_bonus` / `get_weapon_range_bonus` / `get_weapon_block_right_bonus` / `get_weapon_block_front_bonus` / `get_shield_block_left_bonus` / `get_total_physical_resistance_score` / `get_total_magic_resistance_score` / `get_total_physical_resistance` / `get_total_magic_resistance`
  - `resistance_to_ratio(score)` static メソッドは残置（純粋な計算ユーティリティ）
- **`Character.refresh_stats_from_equipment()` を統一**：13 ステータス全てを 1 関数で再計算。アイテムキー名→Character フィールド名のマッピング（`vitality`→`max_hp` / `energy`→`max_energy` / `range_bonus`→`attack_range`）を内包
- **`Character._init_stats()` を簡素化**：素値コピーを廃止し `refresh_stats_from_equipment()` に一本化（装備補正と非装備補正の初期化経路を統一）

#### 呼び出し側の修正
- `Character.take_damage()`：`character_data.get_total_*_resistance()` → `CharacterData.resistance_to_ratio(self.physical_resistance|magic_resistance)`
- `Character._calc_block_power_front_guard()` / `_calc_block_per_class()`：`cd.block_* + cd.get_*_bonus()` → `self.block_*` 直接参照
- `Character.get_move_duration()`：`character_data.move_speed` → `self.move_speed`
- `UnitAI._generate_heal_queue()`：`_member.character_data.power` → `_member.power`
- `UnitAI._find_undead_target()`：`_member.character_data.attack_range` → `_member.attack_range`
- `NpcLeaderAI`：合流交渉スコア計算で `ch.character_data.leadership` → `ch.leadership`、`m.character_data.obedience` → `m.obedience`（装備補正込みの最終値を使うように）
- `PlayerController` 3 箇所：`character.character_data.get_weapon_range_bonus()` → `int(character.character_data.get_equipment_bonus("range_bonus"))`（スロット射程計算は slot.range + bonus の独立ロジックのため個別に修正）
- `OrderWindow._get_stat_rows()`：2 列表示の `bonus` 列を全て `cd.get_equipment_bonus("X")` 経由に統一。`統率力` / `従順度` 行も装備補正対応に拡張。`射程` 行は `Character.attack_range`（最終値）を表示するよう変更

#### 設計原則
- **最終値参照**：戦闘計算・AI 判断は Character 側のフィールド（`self.power` / `self.physical_resistance` 等）を直接参照する
- **素値参照**：素値が欲しい UI 表示（OrderWindow の 2 列）だけ `character_data.X` を直接参照する
- **装備補正取得**：単一 API `CharacterData.get_equipment_bonus(stat_name)` に集約（個別 getter 群は廃止）

#### CLAUDE.md の記述修正
以下の記述は Config Editor の仕様（全ステータス補正可）と矛盾していたため書き換え：
- 「防御技量 `defense_accuracy` | キャラ固有の素値（装備による変化なし）」→「装備補正対応」
- 「防御強度 `block_*` | クラス固有値（装備補正なし）」→「装備補正対応」
- 「補正がかからないもの：defense_accuracy / move_speed / leadership / obedience / max_hp / max_mp」→ リストごと削除（全ステータス補正対応のため）
- 「統率力 | 当面は値のみ保持」→「装備補正対応（将来拡張余地）」

### dead code 削除：`Character.get_direction_multiplier()`

2026-04-20 の `docs/investigation_turn_cost.md` 調査で確認済みの dead code を物理削除。

- `scripts/character.gd` から `static func get_direction_multiplier(attacker, target) -> float` を削除（11 行）
- 廃止済みの `1.0倍 / 1.5倍 / 2.0倍` 方向ダメージ倍率関数。現行ダメージ計算（`_apply_block_directional` + 耐性軽減）で方向は**防御可否のみに影響**する仕様で、倍率は適用されない（CLAUDE.md「命中・被ダメージ計算」節どおり）
- grep 確認：`scripts/` 配下に呼び出し箇所なし・doc コメントのみ残存していた
- あわせて `move_to()` 内コメント「`guard_facing を維持`」を「`facing を維持`」に修正（`guard_facing` は存在しない変数・コメント残骸）

## 2026-04-20（攻撃操作 1 発 1 押下化・Config Editor hidden フラグ・移動関連調査）

本日のセッションは「操作性改善」と「次の大規模リファクタの前提整備（調査）」の二本立て。

### 1. 攻撃操作の 1 発 1 押下化（TARGETING 時間停止仕様の再設計）

#### 設計過程
ユーザーからの操作改善要望を 5 段階に分けて反復的に実装した：

1. **Step 1：PRE_DELAY 中の向き変更追加**
   - 当初仕様：「PRE_DELAY 中に矢印キーで向き変更可」
   - 実装：`_process_pre_delay` 内に `face_toward()` 即時呼び出しを追加
   - 即時回転を選択（射程オーバーレイの追従との視覚一致を優先）

2. **Step 2：トリガーをモード判定からボタン押下判定に変更**
   - ユーザー指摘：「PRE_DELAY 中かどうかはプレイヤーから見えない」
   - 修正：`Input.is_action_pressed(attack_action)` で押下中のみ向き変更が効くよう変更
   - これでタップ時には向き変更が起きず、ホールド時のみ効くようになった

3. **Step 3：TARGETING でも同じ仕組みを適用**
   - ユーザー指摘：「PRE_DELAY 終了後 TARGETING に入ると向きが変えられなくなる」
   - 修正：TARGETING 中もボタン押下時は矢印キー＝向き変更（循環抑止）に変更
   - LB/RB は専用循環ボタンとして常時有効を維持
   - ヘルパー `_is_in_attack_hold()` / `_try_facing_change_from_input()` を抽出

4. **Step 4：自動キャンセルタイマーの再評価機構**
   - ユーザー指摘：「最初は射程内に敵がいるが、向きを変えて射程外になっても解放後にキャンセルされない」
   - 修正：`_process_targeting` 冒頭で `_valid_targets` の有無に応じてタイマーを再起動／リセットするロジックに変更

5. **Step 5：1 発 1 押下化（中間案を経て最終仕様へ）**
   - 中間案：TARGETING 全体で時間進行・解放即発火モデル
   - ユーザー再指摘：「pre_delay の長い遠距離キャラで『じっくり狙う感覚』が失われた」
   - 最終仕様：4 ステート構造に再設計
     - `PRE_DELAY`：時間進行・マーカー非表示・LB/RB 無効・矢印は向き変更
     - `PRE_DELAY_RELEASED`：pre_delay 完了前に解放したときの遷移先。残 pre_delay 消化（マーカー非表示）→ Phase 2 でマーカーを `AUTO_CANCEL_FLASH` 秒表示 → 攻撃発動 / 自動キャンセル
     - `TARGETING`：pre_delay 完了後にボタン押下継続中。**時間停止**・マーカー表示・LB/RB 有効
     - `POST_DELAY`：従来通り
   - 「マーカー可視性 = ターゲット選択可能 = 時間停止」を可視情報で揃える設計原則を確立

#### 実装変更
- [scripts/player_controller.gd](../scripts/player_controller.gd)
  - `enum Mode` に `PRE_DELAY_RELEASED` を追加
  - `is_in_attack_windup()` / `get_current_target()` を 3 ステート対応に拡張
  - `_input()` で PRE_DELAY_RELEASED の LB/RB を抑止
  - `_process_pre_delay()` でボタン解放を検出 → PRE_DELAY_RELEASED へ遷移
  - 新設 `_process_pre_delay_released()`：Phase 1 残 pre_delay 消化 + Phase 2 マーカーフラッシュ + 発動 / キャンセル
  - 新設 `_setup_targeting_cursor()`：`_start_targeting()` から抽出（PRE_DELAY_RELEASED Phase 2 で再利用）
  - `_update_world_time()` を「TARGETING + ホールド中のみ時間停止」のロジックに変更
  - `_process_targeting()` の release-to-fire ロジック・auto-cancel タイマー追従ロジック

#### Komuro 確認項目
- 連打時のテンポが現状と変わらないこと
- pre_delay の長い遠距離キャラで pre_delay 完了後にじっくり狙える感覚
- 向き変更と LB/RB ターゲット切替の両方が pre_delay 完了後に機能すること
- pre_delay 中（マーカー非表示）と完了後（マーカー表示）の切り替わりが視認できること

---

### 2. Config Editor の hidden フラグ導入

#### 背景
Config Editor が色定義など「一度決めたら触らない」項目で埋まっており、バランス調整で頻繁に触る項目が見にくい状態。

#### 仕様
- 各定数のメタデータに `hidden: bool`（デフォルト false）を追加
- デフォルトで Config Editor から非表示
- 「隠し項目も表示」チェックボックスを下部ボタン列右端に追加
- セッション内のみ保持：`open()` ごとに OFF へリセット、ゲーム再起動時も OFF で起動（誤操作防止）
- 表示時は薄いアルファ（`HIDDEN_ROW_ALPHA = 0.45`）でグレーアウト気味に

#### 実装変更
- [assets/master/config/constants_default.json](../assets/master/config/constants_default.json)
  - 既存の色関連 12 項目（`CONDITION_COLOR_SPRITE/GAUGE/TEXT × HEALTHY/WOUNDED/INJURED/CRITICAL`）に `"hidden": true` を一括追加
- [scripts/config_editor.gd](../scripts/config_editor.gd)
  - 状態変数 `_show_hidden: bool = false` / `_chk_show_hidden: CheckBox`
  - 下部ボタン列に CheckBox 追加
  - `_build_row()` でメタから `hidden` を読み取り `_row_widgets[key].hidden` に記録
  - `open()` で `_show_hidden = false` リセット + `set_pressed_no_signal(false)` で UI 同期
  - 新設 `_on_show_hidden_toggled()` / `_apply_row_visibility()`：全行を走査して `panel.visible` と `panel.modulate.a` を設定。可視行 0 のタブはプレースホルダー表示

#### CLAUDE.md への反映
- 設計原則「Config Editor の hidden フラグ」セクションを新設

---

### 3. バグ修正：`PartyLeader._calc_hp_status_for` freed クラッシュ

#### エラー
```
E PartyLeaderPlayer._calc_hp_status_for: Trying to cast a freed object.
party_leader.gd:929 @ _calc_hp_status_for()
party_leader.gd:836 @ _evaluate_strategic_status()
```

#### 原因
Godot 4 では freed オブジェクトに対する `as Character` キャストがクラッシュする（`is_instance_valid()` は安全だが `as` 演算子は不可）。`_evaluate_strategic_status()`（2026-04-19 新設）から呼ばれる 3 関数で同じパターンの問題が顕在化。

#### 修正
[party_leader.gd](../scripts/party_leader.gd) の 3 箇所すべてを「キャスト前に `is_instance_valid(mv)` を確認」のパターンに統一：
- `_calc_stats()` (line 692〜)
- `_get_my_combat_members()` (line 909〜)
- `_calc_hp_status_for()` (line 928〜)

#### 設計上の経緯
本パターンは Phase 12-18 / 12-19 でも複数箇所で同じ修正をしている既知の問題。`_evaluate_strategic_status()` 経由で新たに 3 箇所が顕在化した形。新設関数では「キャスト前 `is_instance_valid` ガード」を必ず入れるルールが必要。

---

### 4. 移動関連の包括調査（3 件）

次セッション以降の「移動関連の二層構造」設計確定の前提として、現状把握の調査ドキュメントを 3 件作成。

#### 4-1. [docs/investigation_turn_cost.md](investigation_turn_cost.md)
**向き変更コストの現状調査**
- 結論：コスト発生はプレイヤー通常移動の `TURN_DELAY=0.15s` のみ
- 角度依存性なし（90° / 180° で時間差なし。経由ルートだけ視覚的に変わる）
- 集約状況：Character クラス内の `face_toward()` / `move_to()` / `start_turn_animation()` / `complete_turn()` の 4 つに分散。`set_facing()` 的な汎用ヘルパーなし
- **非対称性（プレイヤー不利）**：プレイヤー TURN_DELAY 中は論理 facing が古い値のまま 0.15 秒残る → 防御判定で旧向きが使われる窓
- dead code 2 件：`get_direction_multiplier`（廃止済みの 1.0/1.5/2.0 倍関数）/ `guard_facing` コメント残骸
- 統一設計案 4 つを提示

#### 4-2. [docs/investigation_movement_constants.md](investigation_movement_constants.md)
**移動・時間系定数の全洗い出し**
- 全 38 定数を表形式で網羅（定義場所・値・Config Editor カテゴリ・game_speed 適用パターン）
- **最重要発見**：`character_data.move_speed` が完全 dead data
  - `CharacterGenerator._convert_move_speed()` でスコア 0-100 を秒/タイルに変換し格納
  - しかしコード上どこからも読まれていない（grep で確認）
  - 実際の移動時間は `MOVE_INTERVAL` 定数のみで決まる：プレイヤー 0.30s / AI 0.40s 固定
  - ステータス UI に表示される値が実挙動と完全に乖離
- **構造的問題 6 つ**：
  - `MOVE_INTERVAL` の SoT 分裂（PlayerController と UnitAI に同名・別値・別ファイルで const 定義）
  - game_speed 適用パターン 4 種類混在（pre-scaled / post-scaled / 未適用 / 逆方向バグ）
  - Wolf / Zombie の `_get_move_interval()` オーバーライドが game_speed 未適用（バグ）
  - `DarkLordUnitAI._warp_timer -= delta / game_speed` が逆方向（高速設定でボスが遅くなる）
  - REEVAL_INTERVAL が PartyLeader と UnitAI で重複（値は同じ 1.5 秒）
  - エネルギー回復・スタン・バフ・自動キャンセルが game_speed の影響を受けない
- 解像度別 Config Editor カテゴリ提案を含む

#### 4-3. [docs/investigation_enemy_class_stats.md](investigation_enemy_class_stats.md)
**敵クラスステータスの利用状況**
- 結論：11 ステータス中 10 個は正常動作・`move_speed` のみ dead
- ロード経路：`PartyManager._spawn_enemy_member()` → `apply_enemy_graphics()` → `apply_enemy_stats()` → `_calc_stats()` で味方と同じ式（base + rank × rank_bonus + 属性補正 + random）
- **重要発見**：
  - `enemy_class_stats.json` を使うのは 5 種だけ（zombie / wolf / salamander / harpy / dark-lord）
  - 16 敵中 11 敵が人間 class_stats を借用（skeleton → fighter-sword 等）
  - `enemy_class_stats.json` は Config Editor で**完全に編集不可**（「ステータス」タブは class_stats / attribute_stats のみ、「敵クラス」タブはクラス JSON の攻撃定義のみ）
  - 敵にも属性補正（sex/age/build）・ランダム補正は適用されている（attribute_stats を共有）
- move_speed 有効化時の影響：Wolf は現状 0.27s → 設計値 0.53s（**遅くなる**）、Zombie はほぼ同じ

---

### 5. CLAUDE.md 更新

- 「最近の大きな変更」に 2026-04-20 セクション追加
- 「次セッションで検討するタスク」を全面差し替え（Step 1-A 〜 Step 5 の構造化タスクリストへ）
- 「設計原則」に「移動関連の二層構造（時間系ステータス）」を新設（`実効値 = BASE × 50 / status` の逆比例補正方式）
- 「設計原則」に「Config Editor の hidden フラグ」を新設
- 「将来実装項目」に追記：完全リアルタイム化検討 / プレイヤー操作キャラのポーション自動使用 / 他タブの hidden 候補棚卸し / 装備品による move_speed 補正 / stat_bonus の負値対応 / energy_recovery の個体差対応
- 「要調査・要整理項目」に本日完了 3 件を ✅ 追記
- 「攻撃フロー（一発一押下モデル）」セクションは PRE_DELAY_RELEASED 4 ステート構造で書き直し済み
- 「キー操作」表の攻撃行を「一発一押下」表記に更新

---

### 設計確定事項（次セッション以降の前提）

1. **時間系ステータスは二層構造で管理**：`実効値 = BASE × 50 / status`
2. **時間系ステータス以外（power / skill / hp / 耐性）は従来通り直接使用**
3. **`turn_speed` ステータスは新設しない**：向き変更コストも `move_speed` で補正
4. **基準値 50 はハードコード・下限クランプもハードコード**：Config Editor に出さない
5. **`energy_recovery` は二層構造化しない**：現状の全キャラ共通定数を維持

---

## 2026-04-20（Step 1-B：`move_speed` 有効化＋ガード WEIGHT 定数化）

「移動関連の二層構造」設計原則（2026-04-20 策定）の段階的適用第 2 ステップ。`character_data.move_speed` を live data 化し、移動時間を「ベース値 × 能力値補正」の逆比例式で算出する方式に移行した。

### 経緯と狙い

事前調査（[docs/investigation_movement_constants.md](investigation_movement_constants.md)）で以下が判明していた：
- `character_data.move_speed` が完全 dead data（`_convert_move_speed` で秒数に変換・格納されるが、どこからも参照されていなかった）
- `MOVE_INTERVAL` の SoT が `PlayerController`（0.30s）と `UnitAI`（0.40s）に**分裂**しており同名別値が混在
- `Wolf` / `Zombie` の `_get_move_interval()` オーバーライドで種族差を表現していたが、`enemy_class_stats.json` の `move_speed` 値は全く使われていなかった

本タスクでこれら 3 つの問題を同時に解消した。

### 設計：移動関連の二層構造

時間系ステータスを「ベース値（GlobalConstants）× 能力値（character_data）」の逆比例補正で管理する。

```
実効値 = BASE_MOVE_DURATION × 50 / move_speed
  ガード中なら × GUARD_MOVE_DURATION_WEIGHT
  下限 0.10 秒（ハードコード）
```

- 標準能力値 50 を基準（BASE_MOVE_DURATION そのものが実効値）
- 能力値が高いほど速い（直感的）
- 装備補正は対象外（Step 4 以降で検討）

### 実装変更

#### 1. 新規定数（Character カテゴリ・Config Editor 対象）

[scripts/global_constants.gd](../scripts/global_constants.gd)
```gdscript
var BASE_MOVE_DURATION: float = 0.40         # 1 マス移動のベース時間（秒）
var GUARD_MOVE_DURATION_WEIGHT: float = 2.0  # ガード中の移動時間倍率（2.0 = 50% 速度）
```

[assets/master/config/constants_default.json](../assets/master/config/constants_default.json)：Character カテゴリに 2 エントリ追加（description / min / max / step 完備）

#### 2. `Character.get_move_duration()` 新設

[scripts/character.gd](../scripts/character.gd)（`walk_in_place` の直後・`move_to` の直前）
```gdscript
func get_move_duration() -> float:
    var move_speed := 50.0
    if character_data != null and character_data.move_speed > 0.0:
        move_speed = float(character_data.move_speed)
    var duration := GlobalConstants.BASE_MOVE_DURATION * 50.0 / move_speed
    if is_guarding:
        duration *= GlobalConstants.GUARD_MOVE_DURATION_WEIGHT
    return maxf(0.10, duration)
```

返り値は**論理時間**（game_speed=1.0 時の秒数）。呼出側が `/ GlobalConstants.game_speed` で実時間化する。

#### 3. `_convert_move_speed()` 廃止

[scripts/character_generator.gd](../scripts/character_generator.gd)：関数ごと削除。2 つの呼出側（`generate_character` / `apply_enemy_stats`）は以下に変更：
```gdscript
data.move_speed = float(stats.move_speed)  # 0-100 スコアを直接格納
```

`character_data.move_speed` のデフォルト値を `0.4` → `50.0` に変更（コメントも更新）。

#### 4. MOVE_INTERVAL の SoT 統合

**PlayerController**（`const MOVE_INTERVAL: float = 0.30` 廃止）
- 4 箇所の `MOVE_INTERVAL / GlobalConstants.game_speed` → `character.get_move_duration() / GlobalConstants.game_speed`
- 通常移動 2 箇所の `if character.is_guarding: duration *= 2.0` は get_move_duration() 内に統合したため削除
- 再帰押し出し（`_try_push`）は「プレイヤーと同じ速度で同時アニメーション」の意図を維持するため、プレイヤーの `character.get_move_duration()` を押し出されるキャラに渡す

**UnitAI**（`const MOVE_INTERVAL := 0.40` 廃止）
- MOVING 状態の `_timer = MOVE_INTERVAL` → `_timer = _member.get_move_duration()`（論理時間・game_speed で減算されるため）
- `_get_move_interval()` デフォルト実装を `_member.get_move_duration() / GlobalConstants.game_speed` に変更

#### 5. Wolf / Zombie オーバーライド削除

[scripts/wolf_unit_ai.gd](../scripts/wolf_unit_ai.gd) / [scripts/zombie_unit_ai.gd](../scripts/zombie_unit_ai.gd) の `_get_move_interval()` オーバーライドを削除。`enemy_class_stats.json` の `wolf.move_speed=40` / `zombie.move_speed=10` が初めてゲーム挙動に反映されるようになった。

### 挙動変化（スケール校正は Komuro の実プレイで実施）

| 対象 | 旧値 | 新値（計算） | 差 |
|------|------|------------|----|
| Wolf | 0.268s/タイル（MOVE_INTERVAL × 0.67） | 約 0.50s（0.40 × 50 / 40） | **遅くなる** |
| Zombie | 0.80s/タイル（MOVE_INTERVAL × 2.0） | 約 2.00s（0.40 × 50 / 10） | **さらに遅くなる** |
| 人間キャラ（move_speed ≈ 50） | 0.30s（Player） / 0.40s（AI） | 0.40s（双方） | Player は遅くなる・AI は同等 |

現状の Wolf は想定より速すぎた状態だったことが判明（MOVE_INTERVAL=0.40 の 2/3 で 0.268s だったが、設計値では 50 スコア基準の逆比例で 0.50s）。Zombie は 0.80s → 2.00s でかなり遅くなる。`game_speed` で調整可能とはいえ、スケール校正は実プレイで要確認。

### Step 2-5 に回した項目（本タスクのスコープ外）

- **`DarkLordUnitAI._warp_timer` 逆方向バグ**：Step 2 で対応
- **スタン・バフ・エネルギー回復の `game_speed` 未適用**：Step 3 で統一
- **向き変更コストの非対称解消**：Step 4 で `BASE_TURN_DURATION` 導入時に対応
- **装備補正対応**：将来検討（CLAUDE.md 「移動関連の二層構造」設計判断どおり）

### ドキュメント更新

- **CLAUDE.md**：「次セッションで検討するタスク」Step 1-B を完了マーク（✅）・「設計原則 > 移動関連の二層構造」から「仮称・Step 1-B で導入予定」を除去・「キャラクター生成システム > move_speed の扱い」節を新方式で書き換え・「キャラクターステータス」テーブルの move_speed 行を更新・「本日の成果」に追記
- **docs/spec.md**：「move_speed の変換」節を「move_speed の扱い（Step 1-B〜）」に刷新・`CharacterData.move_speed` フィールド定義行を更新・「game_speed による速度制御」テーブルを新方式に書き換え
- **docs/history.md**：本エントリ

### Komuro への動作確認依頼

- Wolf の動きが遅くなりすぎていないか（約 0.50s/タイル・game_speed=1.0 時）
- Zombie の動きが遅すぎてゲーム性を損ねていないか（約 2.00s/タイル）
- 人間キャラのランダム生成で移動速度の個体差が適切に出ているか（DebugWindow または Config Editor で move_speed 値を確認）
- ガード中の移動速度が期待どおり（50% 速度）か
- 違和感があれば `BASE_MOVE_DURATION`（Config Editor / Character カテゴリ）または敵個別の `enemy_class_stats.json` の `move_speed` を調整

---

## 2026-04-20（Step 1-A：敵ステータスの Config Editor 対応 + タブフラット化）

Step 1-B（`move_speed` 有効化）の前提整備。`enemy_class_stats.json` を Config Editor で編集できるようにし、あわせてタブ構成をフラット 8 タブに再編した。

### 経緯：調査で判明した「当初想定より小さい範囲で完了できる」構造

事前調査（ステータス算出ロジックの現状把握）を行ったところ、以下が確認できた：

- ステータス算出ロジック（`CharacterGenerator._calc_stats`）は既に味方・敵で**統一済み**
- `attribute_stats.json`（sex/age/build 補正・random_max）は味方・敵で**共用済み**
- 敵の sex/age/build は `apply_enemy_graphics()` が敵画像フォルダ名（`{enemy_type}_{sex}_{age}_{build}_{id}/`）からパース → `character_data` に格納 → その後の `apply_enemy_stats` → `_calc_stats` で attribute_stats が適用される
- `_load_stat_configs()` が `class_stats.json` と `enemy_class_stats.json` を `_class_stats_cache` にマージするため、実行時は stat_type（味方 or 敵固有クラス）を問わず一元引きできる

つまり**ロジック改修は不要**、Config Editor UI の対応漏れ（`enemy_class_stats.json` の編集 UI がなかった）を補うだけで済むと判明。

あわせて、「`stat_bonus` は敵専用概念」であることも確認：
- 味方の `character_data` に `stat_bonus` フィールドは**存在しない**
- 味方の装備補正は `equipped_*.stats` の辞書から `get_weapon_power_bonus()` 等のゲッター経由で動的に参照
- 敵の `stat_bonus` は `enemy_list.json` の一時辞書から `apply_enemy_stats()` 内のローカル変数として受け取り、計算後に加算・破棄されるのみ
- → 名前衝突なし・非対称ではあるが設計として妥当（装備概念のない敵の個体差表現手段）

### タスク 1：タブ構成のフラット化

**旧構成（2026-04-17〜2026-04-19）**：
```
定数 | 味方クラス | 敵クラス | 敵一覧 | ステータス(サブタブ:クラスステータス/属性補正) | アイテム
```

**新構成（2026-04-20〜）**：
```
定数 | 味方クラス | 味方ステータス | 属性補正 | 敵一覧 | 敵クラス | 敵ステータス | アイテム
```

設計判断：
- 味方系ブロック（味方クラス + 味方ステータス）→ 属性補正（共通ルール・橋渡し）→ 敵系ブロック（敵一覧 + 敵クラス + 敵ステータス）→ アイテム
- **属性補正を独立トップタブに昇格**した理由：味方・敵の両方から参照される共通ルールであり、サブタブではなくフラットな独立タブとして並べる方が関係性が見える
- **タブ名の略称について**：
  - 「味方ステータス」= 本来「味方クラスステータス」（class_stats.json）
  - 「敵ステータス」= 本来「敵クラスステータス」（enemy_class_stats.json）
  - UI 簡潔化のため短縮表記を採用。内部データとの対応は CLAUDE.md / docs/spec.md に明記

### タスク 2：描画関数の共通化

`_build_class_stats_sub_tab` を `_build_class_stats_tab(parent, tab_name, source_id, data, class_ids)` に改名・一般化：

```gdscript
func _build_class_stats_tab(parent: TabContainer, tab_name: String, source_id: String,
		data: Dictionary, class_ids: Array[String]) -> void:
```

- `source_id ∈ {"ally", "enemy"}` で味方・敵を切り分け
- ウィジェット key を 3 パーツ（`class_id|stat|sub_key`）から **4 パーツ**（`source_id|class_id|stat|sub_key`）に拡張
- `_class_stats_cell_widgets` / `_class_stats_cell_styles` は味方・敵で共用（key 先頭の source_id で区別）
- 下流の全関数（`_build_class_stats_row` / `_add_class_stats_cell` / `_on_class_stats_cell_changed` / `_class_stats_orig_text` / `_class_stats_has_any_diff` / `_apply_class_stats_edits`）を `source_id` 引数対応に

呼び出し側：
```gdscript
_build_class_stats_tab(parent, TOP_TAB_ALLY_STATS,  "ally",  _class_stats_data,       CLASS_IDS)        # 味方
_build_class_stats_tab(parent, TOP_TAB_ENEMY_STATS, "enemy", _enemy_class_stats_data, ENEMY_CLASS_IDS)  # 敵
```

### タスク 3：敵ステータスタブの実装

- 対象ファイル：`assets/master/stats/enemy_class_stats.json`（5 敵固有クラス）
- 行順は先頭クラス（zombie）のキー順を採用。zombie には leadership / obedience が定義されていないため、敵ステータスタブではこれらの行が**自然に表示されない**
- これは仕様どおり：敵 AI はこれらのステータスを参照しないため（敵は従順度 100% 相当で動作）
- 保存対象 state を追加：
  - `_enemy_class_stats_data: Dictionary`
  - `_enemy_class_stats_dirty: bool`
- `_save_stats_files()` 拡張：3 つのファイル（class_stats / enemy_class_stats / attribute_stats）をそれぞれ dirty 時のみ書き戻し
- `_clear_class_stats_styles_for(source_id)` を新設：保存後に該当 source のセルだけハイライト解除（味方保存時に敵セルを触らない、逆も同様）

### 属性補正タブの独立化

旧構成では `_build_attr_stats_sub_tab` が「ステータス」トップタブ内のサブタブとして実装されていた。サブタブ構造を廃止したため、新しい `_build_top_tab_attr_stats` に中身を直接インライン化。`_build_attr_table` / `_build_random_max_table` / `_build_attr_group_separator` などの下位関数は変更なしで流用。

### タブ切替ハンドラの更新

- 旧：`TOP_TAB_STATS` 単一タブ
- 新：`TOP_TAB_ALLY_STATS` / `TOP_TAB_ATTR_STATS` / `TOP_TAB_ENEMY_STATS` の 3 タブを同じ処理ブロックに含める
- `_on_top_tab_changed` / `_on_save_pressed` / `_on_reset_pressed` / `_on_commit_pressed` / `_on_commit_confirmed` を該当箇所で 3 タブまとめて match

### 廃止したシンボル

- `const TOP_TAB_STATS: String = "ステータス"`
- `const STATS_SUB_TABS: Array[String] = ["クラスステータス", "属性補正"]`
- `func _build_top_tab_stats(...)`
- `func _build_class_stats_sub_tab(...)`
- `func _build_attr_stats_sub_tab(...)`

### ドキュメント更新

- **CLAUDE.md**：
  - 「トップレベルタブ」セクションを新 8 タブ構成に書き換え
  - 「キャラクター生成システム > ステータス決定構造」を「味方・敵で共通の算出式」として明記。違いは「ランク決定方法」と「stat_bonus の有無」の 2 点のみ
  - 「ステータス設定ファイル」セクションに `enemy_class_stats.json` を追加、leadership / obedience が敵クラスに定義されていないのは仕様であることを明記
  - 「要調査・要整理項目」に画像フォルダ名パース関数共通化（優先度低）を追加
  - 「本日の成果」2026-04-20 に本タスクを追記
- **docs/spec.md**：Config Editor「ステータス」タブセクションに 2026-04-20 の変更履歴・新構成・共通化構造を記載
- **docs/history.md**：本エントリ

### 残る非対称項目（別タスク化）

- **画像フォルダ名パース関数**：`_parse_folder_name`（味方・プレフィックスマッチ）と `_parse_enemy_folder_name`（敵・`_male_`/`_female_` 境界検出）が別実装。敵 ID にハイフンが含まれるため戦略が異なるが、共通インターフェイスで統合できる余地あり
- **ファイル名のハイフン／アンダースコア統一**：個別敵 JSON は `dark_lord.json`、クラス JSON は `dark-lord.json`（既存項目・継続）

---

## 2026-04-19（FLOOR_RANK / FLOOR_RETREAT_RATIO の Config Editor 化）

### 背景・目的
装備 tier 戦力反映（本日実装）により、NPC の下層降下判定で参照する `FLOOR_RANK` の感覚が変わっている可能性がある。従来は純粋 rank_sum ベース（`{0:0, 1:8, 2:13, 3:18, 4:24}`）だが、tier 寄与が加算されて同じ基準値でも降下しやすくなっているはず。実プレイで調整可能にするため Config Editor に外出しする。

あわせて、ハードコードだった「退避閾値」`FLOOR_RANK[current] / 2.0` の `/2.0` 部分も定数化する。

### 実装変更
- **`const FLOOR_RANK: Dictionary` 削除**：Dictionary は Config Editor 非対応のため、5 個の `var` 定数に分解
- **新規定数（NpcLeaderAI カテゴリ・計 6 個）**：
  - `FLOOR_0_RANK_THRESHOLD` = 0
  - `FLOOR_1_RANK_THRESHOLD` = 8
  - `FLOOR_2_RANK_THRESHOLD` = 13
  - `FLOOR_3_RANK_THRESHOLD` = 18
  - `FLOOR_4_RANK_THRESHOLD` = 24
  - `FLOOR_RETREAT_RATIO` = 0.5（現フロア基準の半分未満で退避）
- **npc_leader_ai.gd**：
  - `_get_floor_threshold(floor_index) -> int` ヘルパ新設
  - `_get_target_floor()` の基準値参照を全て `_get_floor_threshold()` 経由に変更
  - `/ 2.0` ハードコードを `* GlobalConstants.FLOOR_RETREAT_RATIO` に置換
- **Config Editor NpcLeaderAI タブ**：以前は定数 0 個のプレースホルダーだったが、6 定数で実体化

### 値は据え置き
本タスクは Config Editor 化のみ。**値は従来と完全に同じ**で挙動変化なし。実プレイベースの調整は次セッションで行う。

### Komuro への動作確認依頼
- F4 > NpcLeaderAI カテゴリに 6 定数が表示される
- DebugWindow で NPC の `mv=stairs_down(Fx)` 表示が従来通り動作する
- 下層降下挙動が変化なし（値据え置きのため）

---

## 2026-04-19（戦力計算と戦況判断の統合・距離ベース連合・_all_members 伝播バグ修正）

### 背景
装備 tier 反映実装後、DebugWindow でプレイヤーの R 値が異常に大きい（R:45）問題が顕在化。調査で以下が判明：
1. 戦力計算 `_evaluate_party_strength_for()` と戦況判断 `_evaluate_combat_situation()` が重複計算していた
2. エリアベース判定（`target_areas` = リーダーのエリア + 隣接エリア）が粗く、右端で左部屋の奥まで含む問題
3. 敵同士の連合加算は世界観（敵は協力しない）と不整合
4. `_all_members` が NPC / 敵マネージャーのリーダー AI に伝わっていない未伝播バグ（`PartyLeader.setup()` が受け取った `all_members` を `_all_members` に代入していなかった）

### 設計変更

#### 統合関数 `_evaluate_strategic_status()`
旧 `_evaluate_party_strength()` / `_evaluate_party_strength_for()` / `_evaluate_combat_situation()` を 1 関数に集約。3 集合で統計を 1 度ずつ算出する：
- `full_party`：自パ全員（下層判定・絶対戦力用）
- `nearby_allied`：自パ近接 + 同陣営他パ近接（戦況判断・味方連合）
- `nearby_enemy`：近接敵（戦況判断）

#### 距離ベース連合（エリアベース廃止）
基準点：自パリーダーのグリッド座標
範囲：マンハッタン `COALITION_RADIUS_TILES` マス以内（同フロアのみ）
- 旧 `target_areas = エリア + 隣接エリア` 判定は完全廃止
- 部屋の隅にいても連合範囲が意図通りに絞られる

#### 敵の非対称設計（世界観整合）
- enemy パーティー：自軍戦力 = `full_party` のみ（協力しない）
- 味方（player/npc）：自軍戦力 = `nearby_allied`（連合加算）
- 相手側は両陣営とも `nearby_enemy`（視点側から見た脅威）

#### HP 率計算の 3 層ルール
- 自パ部分：実 HP + ポーション回復量（`(sum_hp + sum_potion) / sum_max_hp`）
- 同陣営他パ部分：condition ラベルから推定（他パのポーション所持は把握不可）
- 敵部分：condition ラベルから推定（敵ステータス直接参照禁止ルール）

### 実装変更

#### 新規定数
| 定数名 | デフォルト | カテゴリ | 説明 |
|---|---|---|---|
| `COALITION_RADIUS_TILES` | 8 | PartyLeader | 連合・近接敵の最大マンハッタン距離 |

#### party_leader.gd
- `_evaluate_strategic_status()` 新設（主関数）
- `_calc_stats()` / `_calc_stats_mixed()` ヘルパ新設
- `_within_coalition_radius()` 距離判定ヘルパ新設
- 旧関数削除：`_evaluate_party_strength()` / `_evaluate_party_strength_for()` / `_evaluate_combat_situation()` / `_calc_rank_sum()` / `_calc_tier_sum()`
- **バグ修正**：`setup()` に `_all_members = all_members` 1 行追加（NPC / 敵のリーダー AI に伝播するよう修正）

#### npc_leader_ai.gd
- `_calc_party_hp_ratio()` 削除（統合関数の `full_party_hp_ratio` で代替）
- `_get_target_floor()` を `_combat_situation["full_party_strength"]` / `["full_party_hp_ratio"]` 参照に書き換え
- `get_global_orders_hint()` は **NPC 固有差分のため残存**（target_floor キー・NPC デフォルト方針）。新しい 3 集合キーを追加
- **付随バグ修正**：2026-04-18 の tier 実装時に NpcLeaderAI.get_global_orders_hint() の tier キー（`my_tier_sum` / `enemy_tier_sum`）追加が漏れていた。今回の完全置換（`nearby_allied_tier_sum` / `nearby_enemy_tier_sum`）で副次的に修正

#### debug_window.gd
戦力表示を 3 点フォーマットに拡張：
```
PB F(R+T)s C(R+T)s E(R+T)s
```
- F = full_party / C = nearby_allied / E = nearby_enemy
- 各括弧内：R = rank_sum / T = tier 平均の和 / 末尾 s = strength
- 敵視点では F と C は同値（非対称設計）
- 凡例はファイル冒頭コメントに記載

### 新旧キー名対応表
| 旧キー | 新キー |
|---|---|
| `my_rank_sum` | `nearby_allied_rank_sum`（味方視点）/ `full_party_rank_sum`（敵視点） |
| `enemy_rank_sum` | `nearby_enemy_rank_sum` |
| `my_tier_sum` | `nearby_allied_tier_sum` / `full_party_tier_sum` |
| `enemy_tier_sum` | `nearby_enemy_tier_sum` |

旧キーは完全削除。後方互換エイリアスは残していない（将来の混乱回避）。

### Komuro への動作確認依頼
- F1 DebugWindow 戦力表示が `PB F(R+T)s C(R+T)s E(R+T)s` 形式になる
- プレイヤー行で F と C が自然な値を取る（R:45 バグが解消）
- 敵パーティー視点で F と C が同値表示される（協力しない世界観の可視化）
- NPC の階段移動中に `mv=stairs_down(F2)` の target_floor 表示が正しく出る
- NPC デフォルト指示（follow / same_as_leader / retreat / passive）が初期状態で反映される
- 散開中のメンバーが距離フィルタで nearby_allied から除外される
- F4 > PartyLeader カテゴリに `COALITION_RADIUS_TILES` が表示・編集可能

---

## 2026-04-19（戦力計算への装備 tier 反映）

### 背景・目的
従来の戦力式は `rank_sum × HP充足率` のみで、装備の強さが戦力評価に反映されていなかった。低層でアイテムを集めて装備を強化しても、リーダーAIが下層へ進む判断をしなかったため、装備 tier を戦力式に組み込む。

2026-04-19 に tier が整数化（0=none, 1=low, 2=mid, 3=high）されたことが前提条件。

### 新しい戦力式
```
character_tier_avg(c) = 装備中アイテム（武器・防具・盾）の tier の平均。装備なしなら 0
party_tier_sum       = Σ character_tier_avg(m) for m in members
strength_base        = rank_sum + party_tier_sum × ITEM_TIER_STRENGTH_WEIGHT
strength             = strength_base × 平均HP充足率
```

- `ITEM_TIER_STRENGTH_WEIGHT = 0.33`（Config Editor PartyLeader カテゴリ・既定値）
- 装備 1 セット（3 スロット・tier 3 平均）≒ ランク 1 段階（3 × 0.33 ≈ 1）となる設定

### 設計判断
- **平均化する理由**：クラスごとに装備スロット数が違う（戦士=3、弓/斥候/魔/ヒーラー=2）。合計ではなくスロットあたりの平均で正規化し、クラス間公平を保つ
- **敵側は従来挙動維持**：敵は装備を持たないため `character_tier_avg = 0`・`party_tier_sum = 0`・結果として `rank_sum × HP` と一致
- **ポーション寄与は HP 充足率側のみ**：装備と重複してカウントしない

### 実装変更

#### 関連バグ修正：ItemGenerator 戻り値の tier 漏れ
2026-04-19 の事前生成機構実装時に、`ItemGenerator.generate()` / `generate_initial()` の戻り値に `tier` フィールドを含めていなかった（source のエントリには tier があるが戻り値にコピーしていなかった実装漏れ）。戦力計算で tier を参照するにあたり本漏れを修正：
- `generate()` 戻り値：`tier: int(picked.tier)` 追加
- `generate_initial()` 戻り値：`tier: TIER_NONE` 追加
- `generate_consumable()` は tier を持たない（ポーションは戦力評価対象外）

#### 定数追加
- `ITEM_TIER_STRENGTH_WEIGHT`（float・デフォルト 0.33・PartyLeader カテゴリ）

#### party_leader.gd 拡張
- `_character_tier_avg(Character) -> float` 新設：装備中 tier の平均（武器・防具・盾のうち実装備のみ）
- `_calc_tier_sum(Array) -> float` 新設：メンバーの `character_tier_avg` の合計
- `_evaluate_party_strength_for()` 式を `rank_sum` → `rank_sum + tier_sum × WEIGHT` に更新
- `_combat_situation` / `get_global_orders_hint()` に `my_tier_sum` / `enemy_tier_sum` 追加

#### DebugWindow 表示拡張
戦力表示を `PB(X/Y)` → `PB(R:X+T:Y.Y/E:Z+t:z.z)` 形式に拡張：
- `R` = 自軍 rank_sum / `T` = 自軍 tier 平均の和
- `E` = 敵 rank_sum / `t` = 敵 tier 平均の和（通常 0）
- 凡例はファイル冒頭のコメントに記載

### セーブデータ互換性
- 旧セーブで tier フィールドがない装備でも、`.get("tier", 0)` でデフォルト 0 フォールバックするためクラッシュしない
- 旧セーブロード時は戦力寄与が 0 になるだけで従来挙動と一致

### Komuro への動作確認依頼
- F1 DebugWindow で戦力表示が `PB(R:X+T:Y.Y/E:Z+t:z.z)` 形式になる
- 初期装備（全 tier=0）のうちは T:0.0 となり、戦力は従来値と一致
- ドロップ装備を拾って装備すると T の値が上がる
- 敵パーティーの戦力表示は `t:0.0`（装備を持たないため）
- F4 > PartyLeader カテゴリに `ITEM_TIER_STRENGTH_WEIGHT` が表示される

---

## 2026-04-19（「無」段階導入・bonus/tier 概念分離・初期装備の統合生成）

### 背景・目的
CLAUDE.md 要調査項目「無段階の導入」の実装。事前生成機構の 3 段階（low/mid/high）に「無（none）」を加えて 4 段階化する。

主たる目的：
1. **「最大 2 補正」仕様の自然な表現**：装備のスロット数と同じ次元で語れる（残りスロット = 「無」）
2. **初期装備の統合生成**：ベイク済み辞書 → `ItemGenerator.generate_initial()` 経由の統一ルートへ移行（single source of truth）
3. **bonus と tier の概念分離**：名称の不整合を整理

### 概念整理

| 概念 | 値 | 役割 |
|---|---|---|
| **bonus 段階**（stats 内の各値の強さ） | `none / low / mid / high` | `*_bonus` の略。stats 辞書内の各値の強さを表す |
| **tier**（装備全体の格付け・整数） | `0 / 1 / 2 / 3` | フロア選択用。`0=none, 1=low, 2=mid, 3=high` |

- 「none/low/mid/high」は「no_bonus/low_bonus/mid_bonus/high_bonus」の略
- tier は bonus から `ITEM_TIER_POLICY`（max/min/avg）で導出される
- 以前は両概念とも文字列 "low/mid/high" で同じ値を取り、混同しやすかった

### 実装変更

#### 定数リネーム（bonus 比率）
| 旧名 | 新名 |
|---|---|
| `ITEM_TIER_LOW_RATIO` | `ITEM_BONUS_LOW_RATIO` |
| `ITEM_TIER_MID_RATIO` | `ITEM_BONUS_MID_RATIO` |
| `ITEM_TIER_HIGH_RATIO` | `ITEM_BONUS_HIGH_RATIO` |

`ITEM_TIER_POLICY` は「bonus から tier を導出する policy」なのでそのまま維持。

#### tier 数値化（String → int）
- `FLOOR_0_1_BASE_TIER` / `FLOOR_1_2_BASE_TIER` / `FLOOR_2_3_BASE_TIER` を String（"low"/"mid"/"high"）→ int（1/2/3）に変更
- `constants_default.json` の `type` を `"string"` → `"int"`、`choices` 削除、`min/max/step` 追加
- Config Editor の UI：OptionButton → SpinBox（同じ仕組みで int 表示）
- `generated/*.json` の全エントリ（75 エントリ）の `tier` フィールドを文字列 → 整数化

#### ItemGenerator 修正（`scripts/item_generator.gd`）
- `TIER_ORDER = ["low","mid","high"]` を廃止。tier は整数で直接比較
- `generate(item_type, floor_index)`：`tier == 0` エントリを重み計算から除外（weight=0）
- **新設**：`generate_initial(item_type)`：装備タイプなら tier=0 エントリを返す。`potion_*` なら `generate_consumable()` に委譲

#### 生成セット拡張（+9 エントリ）
各装備 9 タイプに tier=0 エントリを 1 個ずつ追加（stats={}）：
- sword: 朽ちた片手剣 / axe: 欠けた斧 / dagger: 錆びた短剣
- bow: 古びた弓 / staff: 粗末な杖
- armor_plate: 擦り切れた革鎧 / armor_cloth: 擦り切れた布服
- armor_robe: 褪せた法衣 / shield: 朽ちた木盾

命名方針：朽ちた・古びた・粗末な・擦り切れた等のダークファンタジー寄り漢字語彙。キャラ画像生成プロンプトで許容される形状制約（片手剣 / 両手弓 / 軽装服 等）を維持。

#### 初期装備の統合生成
- `game_map.gd:_setup_hero` の `_dbg_items` を辞書ベイク → `item_type` 文字列リストに置換
- `game_map.gd:_build_initial_items()` 新設：文字列リストを受けて `ItemGenerator.generate_initial` で実体化。末尾に `INITIAL_POTION_*_COUNT` 個数分のポーションを付加
- `party_manager.gd:_build_npc_initial_items()` 新設：NPC 側も同じロジックで組み立て
- 主人公・NPC 両方で共通のルートから初期装備が出る（DRY）

#### dungeon_handcrafted.json の書式変更
- `player_party.members[].items`：**物理削除**（`_dbg_items` が SoT となったため死にコード）
- `npc_parties_multi.members[].items`：辞書リスト → **item_type 文字列リスト**（12 メンバー対応）
  - ポーションは書かない（全 NPC 一律に `INITIAL_POTION_*_COUNT` で自動付与）

#### 初期ポーション個数の Config Editor 化
新規定数 2 個を `Item` カテゴリに追加：
- `INITIAL_POTION_HEAL_COUNT`（デフォルト 5・min 0 / max 20）
- `INITIAL_POTION_ENERGY_COUNT`（デフォルト 5・同上）

以前はハードコード（`_setup_hero` 内に `range(5)` ベタ書き）だったため、バランス調整のため外出し。主人公・NPC ともに同じ値を参照する。

### 設計判断の記録

- **tier=0 エントリはドロップに出ない**：フロア重み計算で weight=0 に固定し、重み合計が 0 の場合はピック候補に入らない（`_weighted_pick` 内部で分岐）
- **ポーションを `generate_initial` の責務に含める**：単一 API で呼出側が装備・消耗品を意識しなくて済むように。`potion_*` プレフィックスで内部分岐
- **`_dbg_items` を残した理由**：主人公のクラスランダム化はデバッグ用途だが、現状ゲームスタート時の多様性として機能している。`dungeon_handcrafted.json` の player_party 初期装備は実質死にコードだったので削除

### スコープ外・注記
- 既存 tier 1〜3 エントリの `name` / `stats` は変更していない（命名の安定性維持）
- 重み計算ロジック（`FLOOR_BASE_WEIGHT` / `NEIGHBOR` / `FAR`）はそのまま
- `_bands_for_floor()` の 2 帯合算設計も維持（文字列→数値への置換のみ）

### Komuro への動作確認依頼
- ゲーム開始時：主人公・各 NPC（12 人）の初期装備がクラスに応じて正しく付与される（tier=0 の素朴な名前）
- ポーションを 5 / 5 個ずつ所持している
- OrderWindow で tier=0 装備を見たとき、補正値行が表示されない（stats={}）
- フロア移動後、ドロップするアイテム（tier≥1）に tier=0 名が混ざらない
- F4 → Item カテゴリに `INITIAL_POTION_*_COUNT`（2 個）・`ITEM_BONUS_*_RATIO`（3 個）が表示される
- `FLOOR_*_BASE_TIER` が SpinBox（数値入力）として編集可能

---

## 2026-04-19（Config Editor「アイテム」タブ実装）

### 背景
CLAUDE.md 要調査項目「Config Editor のアイテムタブ」の実装。アイテム事前生成機構（同日実装）に続くフェーズ2 として、トップレベル「アイテム」タブを追加する。

### 設計変更の経緯

当初は「**個別アイテム（`generated/*.json`）の編集 UI**」として味方クラス・敵クラスタブと同じ横断表形式で実装する想定だった。

しかし Komuro との議論で以下の問題が浮上：
1. 個別アイテムは **Claude Code が命名と値を対で生成**する（事前生成方式の核）
2. Config Editor で値だけ編集すると、命名との対応が崩れる（「兵士の剣」の power が変わっても名前は据え置き）
3. 命名の整合性を保つには、ルール変更時に Claude Code が一貫した命名セットを再生成する必要がある

**結論**：アイテムタブは「**アイテムタイプごとの生成ルール**（`base_stats`）を編集する UI」にする。

### 役割分担（確定）

| レイヤー | 対象 | 編集方法 |
|---|---|---|
| 方針（全体） | 定数タブ > Item カテゴリ（9 定数） | Config Editor |
| ルール（タイプ別） | `assets/master/items/*.json` の `base_stats` | **本タスクで追加：アイテムタブ** |
| 個別データ | `assets/master/items/generated/*.json` | Claude Code が手動生成（Config Editor 対象外） |

### 実装仕様

#### UI 構造（[scripts/config_editor.gd](scripts/config_editor.gd)）
- トップタブ「アイテム」内に 9 サブタブ（武器 5 + 防具 3 + 盾 1・消耗品は対象外）
- 各サブタブ冒頭に対応 JSON の参考情報（category / depth_scale / allowed_classes）を表示
- 補正ステータススロット × **4 枠**（仕様上の上限・通常は 2〜3 の運用）
  - OptionButton: `---` + 13 ステータス（power / skill / block_* / *_resistance / defense_accuracy / leadership / obedience / move_speed / vitality / energy）
  - min LineEdit（`---` 時は無効化）
  - max LineEdit（同上）

#### スロット 4 枠の運用注意
- 登録数 N に対して個別アイテム生成時の組み合わせは `C(N, 2) × 9` パターン
  - N=2: 9 パターン
  - N=3: 27 パターン
  - N=4: 54 パターン（通常運用では避ける）
- 同時補正数は**最大 2**（個別アイテム生成ロジック側の仕様）

#### 新規定数（定数追加なし・ハードコード）
```gdscript
const ITEM_TYPE_IDS: Array[String] = [9 タイプ]
const ITEM_BASE_DIR: String = "res://assets/master/items/"
const ITEM_BASE_SLOTS: int = 4
const ITEM_STAT_CHOICES: Array[String] = ["---", 13 ステータス]
const ITEM_SLOT_KEY_W: int = 180 / MIN_W / MAX_W: 70
```

#### データ記憶変数
- `_item_base_data: Dictionary` — item_type → 元 JSON Dict 全体（他フィールド保全用）
- `_item_base_dirty: Dictionary` — item_type → bool
- `_item_widgets: Dictionary` — `"{item_type}|slot_{N}|{key|min|max}"` → Control
- `_item_cell_styles: Dictionary` — LineEdit ハイライト用 StyleBoxFlat

#### 新規関数（10 個）
- `_build_top_tab_item` / `_load_item_base_files` / `_build_item_sub_tab` / `_build_item_slot_row` / `_add_item_hdr` / `_expand_base_stats_to_slots`
- ハンドラ: `_on_item_slot_key_changed` / `_on_item_slot_val_changed`
- dirty 判定: `_item_has_diff` / `_item_slot_orig_val` / `_build_item_base_stats_from_slots`
- タブインジケータ: `_update_item_tab_indicator`
- 保存: `_save_item_base_stats_tab` / `_apply_item_edits` / `_clear_item_cell_highlights`
- 告知: `_show_item_regeneration_notice`

#### 起動時の展開ロジック
- 各アイテム JSON の `base_stats`（フラットキー `{stat}_min` / `{stat}_max`）を 4 スロットに展開
- 同じ stat の `_min` と `_max` をペアとして扱い、元 JSON のキー登場順を尊重
- 余った枠は `---`（無選択）

#### 保存時の動作
- dirty なサブタブのみ書き戻し（他タイプは触らない）
- 他フィールド保全: `orig.duplicate(true)` で複製 → `base_stats` のみ UI から再構築して上書き
- **保存成功時のみ再生成依頼ダイアログ**を表示：
  > ルールが変更されました。
  >
  > 個別アイテムデータ（assets/master/items/generated/*.json）は
  > まだ古いルールで生成されたままです。
  >
  > Claude Code に「generated/*.json を再生成」を依頼してください。

#### 保存ディスパッチ
- `_on_top_tab_changed`：TOP_TAB_ITEM でも「保存」ボタン有効化
- `_on_save_pressed`：TOP_TAB_ITEM ケース追加。保存成功時に `_show_item_regeneration_notice()` 呼び出し

### スコープ外・次タスク候補
- **「無」段階の導入**：3 段階（low/mid/high）→ 4 段階（none を追加）への仕様変更。初期装備を tier="none" で統合し、`dungeon_handcrafted.json` のベイク初期装備を廃止する方針（別タスク）
- **消耗品の編集 UI**：potion_heal / potion_energy は装備の base_stats とは性格が違う（effect 辞書）。別タスクで検討
- **自動再生成機能**：ルール変更時に `generated/*.json` を自動書き換え → 命名の整合性を壊すため意図的に実装しない（Claude Code への手動再生成依頼フローを採用）

### Komuro への動作確認依頼
- F4 → トップレベル「アイテム」タブが表示される
- 9 サブタブ（sword / axe / dagger / bow / staff / armor_plate / armor_cloth / armor_robe / shield）がある
- 各サブタブで既存の `base_stats` が 4 スロットに正しく展開される（例：sword なら power / block_right_front の 2 スロット、残り 2 スロットは `---`）
- OptionButton でステータス選択・min/max LineEdit で値編集が可能
- `---` 選択時に min/max 欄が無効化される
- 変更後、タブ末尾に `●` インジケータが付く
- 「保存」ボタンで `assets/master/items/*.json` が更新される
- 保存成功時に再生成依頼ダイアログが表示される
- 他フィールド（item_type / category / allowed_classes / depth_scale / effect / image / name）は保存後も保持される
- 保存後、個別データ（generated/*.json）は**自動更新されない**ことを確認

### 更新ドキュメント
- CLAUDE.md トップレベルタブ説明（「アイテム」行をプレースホルダーから機能説明に更新）
- CLAUDE.md に「『アイテム』タブ（2026-04-19〜）」セクションを新設（目的・サブタブ構造・スロット運用・保存動作・役割分担を記述）
- CLAUDE.md 要調査項目「Config Editor のアイテムタブ」を ✅ 完了に変更。代わりに「無」段階導入タスクを次タスク候補として追加

### UI 形式の変更（同日・初回実装直後）

#### 変更理由
初回実装は「タイプごとのサブタブ方式」（9 サブタブ）で完成したが、以下の問題が判明：
- 横方向にスペースが大きく余っている（画面幅の 1/3 程度しか使っていない）
- タイプ間の比較がしにくい
- サブタブ切替の操作が煩雑

敵一覧タブと同じ「1 行 1 種」形式に変更することで、全 9 アイテムタイプを 1 画面で一覧できる・敵一覧タブと UI パターンが一貫する・タイプ間の比較がしやすくなる。

#### 変更内容
- **サブタブ方式を撤廃**（9 サブタブ削除）
- **1 つの横断表**（9 行）にすべてを表示
- 列構成：タイプ名 / depth_scale / stat1〜4 （OptionButton + min + max）/ 参考情報（category / allowed_classes）
- `ScrollContainer` で横スクロール対応
- **depth_scale を編集対象に昇格**（当初はヘッダーの参考情報として表示していたが、編集可能な列に変更）

#### 実装詳細
- `_build_top_tab_item` を単一 ScrollContainer + VBox + ヘッダー行 + 9 データ行に書き換え
- `_build_item_sub_tab` → `_build_item_list_row` に置換
- `_build_item_slot_row` → `_add_item_slot_cells`（親 HBox に add）に変更
- `_add_item_depth_field` / `_on_item_depth_changed` を新設
- `_item_has_diff` / `_apply_item_edits` に depth_scale 比較・書き戻しロジック追加
- セル幅調整：`ITEM_TYPE_COL_W = 100` / `ITEM_DEPTH_COL_W = 70` / `ITEM_SLOT_KEY_W = 130` / `ITEM_SLOT_MIN_W = 55` / `ITEM_SLOT_MAX_W = 55` / `ITEM_INFO_COL_W = 220`

#### CLAUDE.md 追記
- トップレベルタブ「アイテム」の説明を「1 行 1 タイプ形式」に更新
- 「『アイテム』タブ」セクションを「UI 形式：1 行 1 タイプの横断表」に書き換え・列構成を詳述

### アイテムマスター JSON の legacy フィールド削除（同日・UI 変更後）

#### 削除対象
アイテムタブ UI の変更完了後、以下の legacy フィールドが**現行のアイテム生成仕様で未参照**であることを再確認し、物理削除した：
- `base_stats.{stat}_min`（武器・防具・盾 9 ファイル・計 19 フィールド）
- `depth_scale`（全 11 ファイル・消耗品含む）

#### 事前確認結果
**ランタイム参照箇所：ゼロ**
- `scripts/item_generator.gd` は `_max × tier_ratio` のみ使用（`_min` / `depth_scale` 非参照）
- `scripts/item_generator.gd` コメントに「depth_scale は使用しない（設計判断）」と明示済み
- `scripts/config_editor.gd` のみで UI 表示用に参照されていた（今回 UI 側も同時撤去）
- `ITEM_DEPTH_SCALE_*` のような定数は**存在しない**

#### 実装

**JSON 削除**（Python スクリプトで一括処理）：
- 11 ファイル（sword / axe / dagger / bow / staff / armor_plate / armor_cloth / armor_robe / shield / potion_heal / potion_energy）
- 計 30 フィールド削除（19 `_min` + 11 `depth_scale`）
- キー順は OrderedDict で保持・2-space インデント

**UI 更新**（`scripts/config_editor.gd`）：
- `ITEM_DEPTH_COL_W` / `ITEM_SLOT_MIN_W` 定数を削除
- depth_scale 列および `_add_item_depth_field` / `_on_item_depth_changed` 関数を削除
- 各スロットから `min LineEdit` を削除（`max LineEdit` のみに）
- `_expand_base_stats_to_slots`: `_max` キーのみを対象に簡素化
- `_build_item_base_stats_from_slots`: `_max` のみ書き出し
- `_item_slot_orig_val` → `_item_slot_orig_max` にリネーム・簡素化
- `_on_item_slot_val_changed` → `_on_item_slot_max_changed`
- `_item_has_diff`: depth_scale 差分チェックを削除
- `_apply_item_edits`: depth_scale 書き戻しを削除

#### 削除後の列構成（10 列）
`タイプ | stat1 | max1 | stat2 | max2 | stat3 | max3 | stat4 | max4 | 備考`

旧 15 列 → 10 列。さらにスッキリ。

#### 安全性の根拠
1. ランタイム未参照（grep で確認済み）
2. CLAUDE.md 「アイテム事前生成機構」セクションにも「ランタイム未参照」と明記されていた状態
3. 今日の「legacy 一掃」タスク群（個別敵 JSON legacy・LLM AI コード・effect キー互換 等）と一貫した方針
4. 将来の「無」段階導入（次タスク）時に備えて、UI / データ構造をシンプルに保つ

#### 今日の legacy 一掃の総括（2026-04-19 のまとめ）
本日は以下の legacy 一掃が連続して完了：
1. 個別敵 JSON の 6 フィールド（hp / power / skill / physical_resistance / magic_resistance / rank）× 16 ファイル
2. Legacy LLM AI コード 5 クラス（BaseAI / EnemyAI / LLMClient / DungeonGenerator / GoblinAI）約 1,221 行 + dead method
3. CLAUDE.md の LLM 参考仕様 3 セクション
4. GlobalConstants の dead constants（SPRITE_SOURCE_WIDTH/HEIGHT）
5. `_crop_single_tile` 関数（no-op 化されていた stale 関数）
6. effect キー legacy フォールバック（restore_mp/sp × 5 ファイル）+ dead accessor 3 個
7. **アイテムマスター JSON の `{stat}_min` / `depth_scale`（本エントリ）**

---

## 2026-04-19（アイテム事前生成機構の実装と legacy キー一掃）

### 背景
`assets/master/items/*.json` のマスターデータ（`base_stats._min/_max` / `depth_scale`）は用意されていたがランタイム未参照だった。「アイテムのランダム生成機構」の実装と、調査過程で判明した「effect キー名の不整合」（コード側の legacy フォールバック）を合わせて解消する。

### 方針の変遷
本実装は 1 日の議論を通じて 3 段階で方針転換した：

1. **当初案：ランタイム生成方式**（`base_stats._min/_max` で乱数生成 + 名前プール）
   - 却下理由：CLAUDE.md 854-859「補正値を決定した後、その特徴を反映した名前を付ける」仕様に合致しない。名前と補正値の結びつきが緩くなる（「鋭利な剣」の stats が毎プレイ違う）

2. **第 2 案：事前生成セット方式**（Claude Code が手作業で (名前, 補正値, depth_range) のトリプルを定義）
   - 一部実装（sword / axe / dagger の 45 エントリ作成）
   - 部分的に却下：Komuro が生成ロジックに関与できない／値と名前の対応が暗黙的

3. **最終案：定数ベース事前生成（総当たり方式）** ← 採用
   - 2 ステータスを低・中・高の 3 段階で組み合わせた 9 パターンを網羅（盾のみ 3 パターン）
   - 段階値は `_max × ITEM_TIER_{LOW|MID|HIGH}_RATIO` で定数駆動計算
   - フロア出現重みも定数駆動（`FLOOR_X_Y_BASE_TIER` と距離別 weight）
   - **決定的な論点**：Komuro が Config Editor から生成ロジックに関与できる設計であること

### 実装

#### 段階 A: legacy キー一掃（先行完了）
コード側の legacy 互換コードを全削除。アセットは既にクリーンだったためコード側のみの作業：
- `character.gd:703` / `consumable_bar.gd:390,502` / `player_controller.gd:1686,1812,1907` / `npc_leader_ai.gd:420` / `unit_ai.gd:2121` の `restore_mp`/`restore_sp` フォールバック削除
- `character_data.gd:275-278` の `get_weapon_power_bonus` 内 `attack_power`/`magic_power` フォールバック削除
- `order_window.gd:1337-1338` の `_effect_label` legacy エントリ削除
- `global_constants.gd:107-110` の `STAT_NAME_JP` legacy エントリ削除
- dead accessor 3 個削除：`get_weapon_skill_bonus()` / `get_weapon_block_power()` / `get_shield_block_power()`

#### 段階 B: Config Editor「Item」カテゴリ新設
- `scripts/config_editor.gd` の `TABS` 配列末尾に `"Item"` 追加
- **`"string"` 型サポートを新規追加**：`meta.choices`（Array）があれば `OptionButton`、なければ `LineEdit`。将来の他文字列定数にも応用可
- ハンドラ：`_on_string_choice_changed` / `_on_string_text_changed`
- `_refresh_all` で OptionButton / LineEdit の値反映にも対応

#### 段階 C: 9 定数を GlobalConstants に追加
| 定数 | 型 | デフォルト | 用途 |
|---|---|---|---|
| `ITEM_TIER_LOW_RATIO` | float | 0.33 | 段階「低」の比率（対 _max） |
| `ITEM_TIER_MID_RATIO` | float | 0.67 | 段階「中」の比率 |
| `ITEM_TIER_HIGH_RATIO` | float | 1.0 | 段階「高」の比率 |
| `FLOOR_0_1_BASE_TIER` | string (enum) | "low" | フロア 0〜1 の基準段階 |
| `FLOOR_1_2_BASE_TIER` | string (enum) | "mid" | フロア 1〜2 の基準段階 |
| `FLOOR_2_3_BASE_TIER` | string (enum) | "high" | フロア 2〜3 の基準段階 |
| `FLOOR_BASE_WEIGHT` | int | 5 | 基準段階の重み |
| `FLOOR_NEIGHBOR_WEIGHT` | int | 2 | 基準 ±1 段階の重み |
| `FLOOR_FAR_WEIGHT` | int | 0 | 基準 ±2 以上離れた段階の重み |
| `ITEM_TIER_POLICY` | string (enum) | "max" | 段階判定方針（max/min/avg） |

`constants_default.json` に `category: "Item"` 付きで登録。`CONFIG_KEYS` にも追加。

#### 段階 D: 事前生成セット 9 ファイル作成（計 75 エントリ）
`assets/master/items/generated/` 新設ディレクトリに以下の JSON を配置：
- `sword.json` / `axe.json` / `dagger.json`：power + block_right_front（各 9 個）
- `bow.json` / `staff.json`：power + block_front（各 9 個）
- `armor_plate.json` / `armor_cloth.json` / `armor_robe.json`：physical_resistance + magic_resistance（各 9 個）
- `shield.json`：block_left_front のみ（3 個）

**JSON 構造**（`category` フィールドは持たない・stats 辞書のキーは任意で柔軟）：
```json
{ "name": "兵士の剣", "stats": { "power": 10, "block_right_front": 10 }, "tier": "low" }
```

**命名制約**：
- 日本語・ダークファンタジー寄り
- カタカナ表記を避ける（漢字語彙で統一）
- **グラフィック制約の根拠はキャラ画像生成プロンプト**（両手剣・サーベル・ロングボウ・タワーシールド等の形状差異 NG）
- 将来的にキャラ画像プロンプトが変更される場合、命名も見直しが必要

#### 段階 E: ItemGenerator 実装
新規ファイル `scripts/item_generator.gd`（約 170 行・static class）：
- `generate(item_type, floor_index) -> Dictionary`：装備を生成（消耗品は `generate_consumable()` に分岐）
- `generate_consumable(item_type) -> Dictionary`：ポーション（depth_scale 非使用・設計判断）
- `_weighted_pick`：全エントリの重みを計算して累積選択
- `_bands_for_floor`：フロアが所属する基準段階帯のリストを返す（境界フロアでは隣接 2 帯の重みを合算して滑らかな遷移）
- `_entries_cache` / `_master_cache`：JSON 読み込みをキャッシュ

#### 段階 F: dungeon_handcrafted.json の簡素化と呼び出し接続
- Python スクリプトで 136 個のドロップアイテムを `{ item_type, category, item_name, stats }` → `"sword"` 等の文字列に簡素化
- `game_map._on_enemy_party_wiped()` 内に `_normalize_drop_item(raw, floor_idx)` を新設
  - String → `ItemGenerator.generate()`
  - Dictionary with only `item_type` → 同上
  - Dictionary with `stats` / `effect` → そのまま（後方互換）
- 部屋制圧時にフロア深度に応じた具体値が生成される流れを実現
- 主人公・NPC の初期装備はベイク維持（タスク指示通り。弱い固定値で済むため生成不要）

### 主要な設計判断

#### `category` フィールドを JSON に持たない
- 冗長：power と block の値から attack/defense/balanced は計算判定可能
- 将来柔軟性：特殊ステータス（skill / critical_rate 等）追加時、固定 category では表現できなくなる

#### `ITEM_TIER_POLICY = "max"` を選択理由
- 2 ステータスの高い方を採用
- 9 パターンの tier 分布：low × 1 / mid × 3 / high × 5
- 終盤フロア（基準=high）で多様性が増す設計（5 種類の high 装備から選ばれる）

#### ランダム補正なし（同じ名前 = 同じ stats）
- プレイヤーが「鋭利な剣 = power 20 / block 10」と覚えやすい
- 将来 `VARIANCE` 定数を追加して微小なブレを入れられる余地は残す（現状は 0 相当）

#### ポーションは depth_scale 非使用
- 在庫管理問題の回避：フロアごとにポーションの効果が変わると、溜め込み戦略と噛み合わない
- `ItemGenerator.generate_consumable` はマスター JSON の effect をそのまま固定値で返す

#### range_bonus を今回含めなかった
- CLAUDE.md 819・873 行で「射程補正は将来実装予定」＝仕様未確定
- bow / staff も sword / axe と同じ 2 ステータス構造で生成
- 仕様確定時に別タスクで対応

#### フロア帯の重複（floor 1, 2）の扱い
- `FLOOR_0_1 / FLOOR_1_2 / FLOOR_2_3` の定義域は境界フロアで重複
- 実装：重複するフロア（1 と 2）では隣接 2 帯の重みを**合算**する
- 結果：フロア 1 は { low:7, mid:7, high:2 }、フロア 2 は { low:2, mid:7, high:7 }。滑らかな遷移

### ドキュメント更新
- CLAUDE.md「装備の名前生成」セクションを事前生成方式に書き換え（ランタイム選択ロジック・マスター JSON と生成セットの役割分担・命名制約の根拠）
- CLAUDE.md Config Editor カテゴリ説明に Item カテゴリを追加（8 タブ構成）
- CLAUDE.md 要調査項目のアイテム機構を ✅ 完了記録に更新。アイテムタブ（フェーズ2）は「ルール（Item カテゴリ）vs 個別データ（トップレベルタブ）」の役割分担を明記

### 将来の拡張性（記録）
- **VARIANCE**（ランダム補正幅）定数を将来追加可能：現状 0 相当、プレイフィードバック次第で定数追加
- **特殊ステータス追加**：`stats` 辞書は任意キー対応のため、skill / critical_rate 等の追加は JSON 更新のみで対応可
- **ITEM_TIER_POLICY の切り替え**："min"（低い方採用）や "avg"（平均）への切り替えもプレイ感で判断可能
- **画像サイズ設計是正と同世代の方針**：定数を外出しし、Komuro が Config Editor から調整できることを優先する思想

### Komuro への動作確認依頼
- **Config Editor F4 → Item タブ**：9 定数が表示され、float / int / string(OptionButton) それぞれ編集可能
- **フロア 0〜3 の戦闘・制圧**：敵パーティー全滅時にアイテムが床に散布される
- **段階分布**：フロア 0 では「兵士の剣」等の low 段階中心、フロア 3 では「断罪の魔剣」「均整の剣」等の high 段階中心
- **一対一対応**：「兵士の剣」は常に power=10 / block=10
- **定数変更**：`FLOOR_0_1_BASE_TIER` を "high" に変えて再起動すると、フロア 0 で高段階装備が出るようになる
- **起動時**：コンソールに JSON パースエラー / class_name 解決エラーがない

### 残作業（フェーズ2 として分離）
- Config Editor トップレベル「アイテム」タブ（個別エントリ編集 UI）
- 味方クラス / 敵クラスタブと同じ横断表形式で、生成セット JSON を直接編集できるようにする
- 定数 Item カテゴリ（方針）とトップレベル「アイテム」タブ（個別データ）の役割分担

### 追加バグ修正（同日・動作確認後の指摘）

#### 症状
守りの剣（stats: power=10, block_right_front=20）を sword 装備不可クラスが拾った際、OrderWindow の所持アイテム一覧では `[威力+10]` のみ表示され、`右手防御+20` が欠落していた。アイテムウィンドウ（ConsumableBar、X ボタンで開く）では正しく `[威力+10, 右手防御+20]` の両方が表示されていた。

#### 原因
OrderWindow の装備補正値表示 3 箇所（装備スロット行 / 所持アイテム一覧 / アイテム選択サブメニュー）が、stats 辞書を**固定キーリストでフィルタ**していた：
```gdscript
for k: String in ["power", "skill", "defense_strength",
        "physical_resistance", "magic_resistance"]:
```
この配列に `block_right_front` / `block_left_front` / `block_front` / `range_bonus` が含まれておらず、これらのキーを持つアイテムの補正値が非表示だった。

併せて発見した副次的バグ：OrderWindow ステータス表示の「右手/左手/両手防御強度」3 行も「キャラ素値 > 0 または装備補正 > 0」の条件で表示を絞っており、装備不可クラスで該当装備を持っているケースで情報が欠落していた。

#### 修正
**[scripts/order_window.gd](scripts/order_window.gd)**:
- 3 箇所のフィルタを **`stats` 辞書の全キーを反復**する方式に変更（将来の新ステータス追加にも自動対応）
- ステータス表示の 3 防御強度行の条件分岐を撤廃し、**常に全 3 行を表示**
- コメントで「アイテムを他メンバーに渡す操作があるため、閲覧中キャラのクラスで表示キーを絞らない」理由を明記

**[scripts/global_constants.gd](scripts/global_constants.gd)** `STAT_NAME_JP`:
- `block_right_front: "右手防御"` / `block_left_front: "左手防御"` / `block_front: "両手防御"` / `range_bonus: "射程"` を追加
- 未使用の legacy key `defense_strength` を削除

#### 設計原則として明文化
既に `consumable_bar.gd` / `player_controller.gd` の item detail 表示で採用されていた原則「**アイテムを他メンバーに渡す操作があるため、閲覧中キャラのクラスで表示キーを絞らない**」を、OrderWindow の関連箇所にも適用・統一した。

過去の類似論点：ポーション表示で「MP/SP 回復」と両併記する設計（CLAUDE.md 268 行目）と同じ原則系譜。

#### 動作確認結果
守りの剣（power=10, block_right_front=20）を archer / magician 等の sword 非装備クラスが所持時：
- 修正前: `🗡 守りの剣 [威力+10]`
- 修正後: `🗡 守りの剣 [威力+10, 右手防御+20]` ✓

---

## 2026-04-19（画像サイズ設計是正）

### 背景
エフェクト定数棚卸しの追加調査で、「画像元サイズと GRID_SIZE の関係がコード内に直書き定数として散在している」ケースを発見。棚卸しの結果：
- A1: `Projectile.SPRITE_REF_SIZE = 64.0`（固定 px で解像度追従しない）
- D1: `SPRITE_SOURCE_WIDTH = 512` / `SPRITE_SOURCE_HEIGHT = 1024`（未使用の dead constants）
- D2: `_crop_single_tile` 関数（コメントは「1/4 切り出し」だが実装は `return tex` の no-op）
- D3: `DiveEffect.RADIUS = 18.0`（固定 px で解像度追従しない）

CLAUDE.md 設計方針「GRID_SIZE は起動時に動的計算・高解像度ディスプレイで自動追従」との一貫性を保つため、これら 4 項目を一括是正した。

### 実装

#### A1: 飛翔体サイズの GRID_SIZE 比率化
- `GlobalConstants.PROJECTILE_SIZE_RATIO: float = 0.67` を Effect セクションに追加
- `scripts/projectile.gd` から `SPRITE_REF_SIZE` 定数を削除
- スケール計算: `SPRITE_REF_SIZE / img_size` → `(GlobalConstants.GRID_SIZE × GlobalConstants.PROJECTILE_SIZE_RATIO) / img_size`
- 現状の 1920x1080 での見た目（約 65px）を維持。4K（GRID_SIZE≈196）では約 131px に比例拡大される

#### D1: dead constants 削除
- `scripts/global_constants.gd` から `const SPRITE_SOURCE_WIDTH = 512` / `const SPRITE_SOURCE_HEIGHT = 1024` を削除
- どこからも参照されていなかった完全な dead code
- `docs/spec.md` の 72-75 行目（Phase 1-2 セクション内の歴史的記述）は取り消し線＋削除注記で残す（当時は縦長 1:2 比率 512x1024 スプライト素材だった事実の保全）

#### D2: `_crop_single_tile` 関数削除
- `scripts/game_map.gd` から関数と呼び出し 2 箇所を削除（呼び出し側で直接 `load(path) as Texture2D` を使う）
- コメント「1024x1024 の 1/4 切り出し」を説明する doc 文も削除（実装されていなかった内容を残す意義がないため）
- **git 履歴調査結果**：
  - 初期実装（2026-04-02, commit `1fe203b`「タイル画像フォーマット導入」）で「1/4 切り出し」として実装された
  - その後 2026-04-11 の commit `f9162ff`（Phase 13-6 AI 行動指示システム実装）で `return tex` の no-op に変更されていた
  - コミットメッセージには明示的な記載がなく、Phase 13-6 のバンドル変更として埋もれていた
  - 結果、コメントと実装が 8 日間乖離した状態だった

#### D3: 降下エフェクトの GRID_SIZE 比率化
- `GlobalConstants.DIVE_EFFECT_RADIUS_RATIO: float = 0.2` を Effect セクションに追加
- `scripts/dive_effect.gd` から `const RADIUS = 18.0` を削除
- `_draw()` 内で `base_r = GRID_SIZE × DIVE_EFFECT_RADIUS_RATIO` を計算して使用
- 現状の 1920x1080 での見た目（約 19.6px）を維持。4K では約 39.2px に比例拡大

#### PROJECTILE_SPEED のカテゴリ移動（SkillExecutor → Effect）
- ダメージ判定は攻撃の瞬間に確定しており、飛翔体の移動速度は「演出速度」にのみ影響するため、バランス調整カテゴリ（SkillExecutor）ではなく演出カテゴリ（Effect）に所属すべきと判断
- `constants_default.json` の category フィールドを "SkillExecutor" → "Effect" に変更
- `GlobalConstants` 内の定義位置も新規 2 項目と隣接する Effect セクション末尾に移動
- `CONFIG_KEYS` 配列も Effect タブの末尾に再配置

### カテゴリ分類原則の明確化（新規）
本タスクを通じて、定数カテゴリ分類の原則を統一した。CLAUDE.md 「定数管理」セクションに明記：

- **Character / PartyLeader / NpcLeaderAI / EnemyLeaderAI / UnitAI / SkillExecutor** → ゲーム挙動・バランスに影響する定数。担当クラスに応じて振り分け
- **Effect** → 視覚演出・フィーリング調整用の定数（ゲーム挙動に影響しない）

判断に迷うケースの指針：**ダメージ判定が演出と独立している値**（PROJECTILE_SPEED 等、飛翔体到着前に命中判定が確定しているもの）は Effect。判定そのものに影響する値（CRITICAL_RATE_DIVISOR 等）はバランスカテゴリ。

### GlobalConstants 設計原則の明確化（新規）
「画像元サイズと GRID_SIZE の関係を直書きで持たない」方針を確立：
1. 画像の物理サイズが必要な処理（スケール計算等）は `tex.get_size()` で動的取得する
2. 「表示したいサイズ」は GRID_SIZE 比率（`GRID_SIZE × RATIO`）として定義する
3. 画像のソースサイズ（512・1024 等）を定数として持つのはアンチパターン

この原則により、高解像度ディスプレイでも自動的に追従し、アセット差し替え時のコード変更が不要になる。

### 定数タブの状態（2026-04-19 実装後）
- 総数：約 46 → **約 48**（+2: PROJECTILE_SIZE_RATIO / DIVE_EFFECT_RADIUS_RATIO）
- SkillExecutor：2 → **1**（PROJECTILE_SPEED が Effect へ移動し、CRITICAL_RATE_DIVISOR のみ残る）
- Effect：8 → **11**（+3: PROJECTILE_SPEED 移動 / PROJECTILE_SIZE_RATIO 新規 / DIVE_EFFECT_RADIUS_RATIO 新規）

### 今回スコープ外（記録）
以下は CLAUDE.md「要調査・要整理項目」に次回棚卸し候補として記録済み：
- **C1: BUST_SRC_* の比率化**（優先度低）— `message_window.gd` の `BUST_SRC_X/Y/W/H = 256/0/512/512` は 1024x1024 前提。現状ガード付きで動作しているが、将来 2048x2048 アセット追加時に備えて比率化が望ましい
- **D4: エフェクトの線幅系**（優先度低）— `HitEffect.RING_WIDTH = 2.5` 等の「線の太さ px」が固定値で、4K 等で相対的に細くなる。視覚的問題は小さい

### Komuro への動作確認依頼
- **1920x1080**：飛翔体・降下エフェクトの見た目が従来と変わらないこと
- **解像度変更テスト（任意）**：`project.godot` を一時的に 3840x2160 等に変更して、飛翔体・降下エフェクトが比例して大きくなることを確認
- **タイル描画**：`draw_texture_rect` によるタイル表示が従来と同じ見た目（`_crop_single_tile` 削除の副作用がないこと）
- **Config Editor F4**：
  - Effect カテゴリに `PROJECTILE_SPEED` / `PROJECTILE_SIZE_RATIO` / `DIVE_EFFECT_RADIUS_RATIO` が表示され調整可能
  - SkillExecutor カテゴリから `PROJECTILE_SPEED` が消え、`CRITICAL_RATE_DIVISOR` のみ残る
- **起動時**：コンソールに `class_name 解決エラー` / `preload 失敗` / JSON パース失敗がないこと

---

## 2026-04-19（エフェクト定数の棚卸しと Effect カテゴリ新設）

### 背景
2026-04-18 の定数タブ大再編で約 38 個の定数が Config Editor 対象となったが、エフェクト関連は `PROJECTILE_SPEED` のみで、他のエフェクトクラス内部の直書き定数・操作感定数が未外出しだった。Config Editor の役割「データの重複・不足をチェック」と一貫性を保つため、エフェクト関連定数を棚卸しし、Effect カテゴリを新設した。

### 事前確認結果

#### 確認1: WhirlpoolEffect の画像使用状況
`assets/images/effects/whirlpool.png`（1.85 MB）が実在し、実ランタイムは `_use_sprite = true` 経路で Sprite2D 表示。プロシージャル `draw_polyline` は画像非存在時のフォールバックのみ。棚卸し報告内で「プロシージャル描画クラス」と表現したのは不正確だったが、定数の棚卸し自体は網羅済み（VORTEX_COLOR も「フォールバック描画用」と記述済み）。CLAUDE.md 144 行目「渦: whirlpool.png」は正しい。

#### 確認2: HitEffect の画像使用状況
`hit_0*.png` は `assets/` 配下に不在、コード内にも `hit_01〜06` / `kenney` 参照なし。HitEffect は 100% プロシージャル。CLAUDE.md 112 行目の「Kenney Particle Pack（hit_01〜06.png）」記述は実装と乖離していたため、本タスクで修正（取り消し線＋移行注記）。

### 「アセット」の定義の明文化
CLAUDE.md「使用アセットとライセンス」セクション冒頭に定義を追加：
> 「アセット」の掲載対象は**ネット取得素材・サードパーティ製シェーダー**など Komuro 管理範囲外の外部成果物に限る。プロシージャル描画クラスや自作シェーダー（outline.gdshader）は自作コードなので対象外。

これにより「棚卸しの管理範囲」と「アセット表の範囲」が明確化された。

### A 分類（Config Editor 対象・Effect カテゴリ 8 項目）

| # | 定数名 | 現行値 | 単位 | 用途 |
|---|---|---|---|---|
| 1 | `TURN_DELAY` | 0.15 | 秒 | 向き変更 tween 時間（操作感） |
| 2 | `AUTO_CANCEL_FLASH` | 0.25 | 秒 | ターゲット自動キャンセル時フラッシュ |
| 3 | `SLIDING_STEP_DUR` | 0.12 | 秒 | スライディング 1 歩の演出秒数 |
| 4 | `OUTLINE_WIDTH_FOCUSED` | 2.5 | screen px | フォーカス中ターゲットのアウトライン太さ |
| 5 | `OUTLINE_WIDTH_UNFOCUSED` | 1.0 | screen px | 非フォーカス候補のアウトライン太さ |
| 6 | `TARGETED_MODULATE_STRENGTH` | 1.5 | 倍率 | ターゲット選択時の発光強度 |
| 7 | `BUFF_EFFECT_ROT_SPEED_DEG` | 60.0 | 度/秒 | バフバリア（緑六角形）の回転速度 |
| 8 | `WHIRLPOOL_ROT_SPEED_DEG` | 270.0 | 度/秒 | 無力化水魔法スタン渦の回転速度 |

すべて `GlobalConstants` に `var` として追加し、`CONFIG_KEYS` 末尾に追加、`constants_default.json` に `category: "Effect"` のメタ情報付きで定義。

### B 分類（GlobalConstants 集約・UI 非公開）

- `STUN_PULSE_HZ: float = 3.0` — スタン時のスプライト脈動周波数（`character.gd:245` の直書き 3.0 を置換）
  - `CONDITION_PULSE_HZ = 3.0` と値は同じだが仕様上独立（HP 状態点滅とスタン点滅は別概念）。将来別値にしたくなった時のために分離
  - UI 非公開（`CONFIG_KEYS` に入れない・`constants_default.json` に入れない）

他の B 候補（各エフェクトクラスの LINE_WIDTH / RING_COUNT / RING_WIDTH / REFERENCE_DAMAGE / MIN_SCALE 等）は **GlobalConstants に集約しない**方針とした。理由：
- 各エフェクトクラスにのみローカルで意味を持つ値
- 他クラスから参照されない
- GlobalConstants に持ち込むと逆に見通しが悪くなる
- 各クラス内で `const` として名前付け済みなので可読性は確保されている

### Projectile を棚卸し対象に含めた経緯
当初の棚卸し報告では Projectile は「画像アセット使用」として対象外にしていたが、事前確認のレビューで「Projectile も管理範囲内」として戻された。B 分類（ローカル const 化）で対応：
- `SPRITE_REF_SIZE = 64.0`（+ TODO コメント：将来 GRID_SIZE から導出すべき）
- `SPRITE_ROTATION_OFFSET = PI / 2.0`
- `FALLBACK_RADIUS = 5.0`
- `FALLBACK_COLOR_THUNDER / WATER / FIRE / ARROW`

これらは Projectile クラス内にのみ意味を持つため GlobalConstants に持ち込まない。

### 演出色を GlobalConstants に集約しない方針
Komuro からの指示で、エフェクト色（渦のシアン・バフの緑・炎の橙・Projectile フォールバック色等）は**各クラス内の `const COLOR_*` として残す**。理由：
- 「画風統一」を意図した決め打ち値
- GlobalConstants に持ち込んで ColorPicker UI 対応にするとアクシデンタルな変更で画風が崩れる
- 同じ色が複数クラスで使われない（クラス単位で独立）

HP 状態色（`CONDITION_COLOR_*`）は既に ColorPicker 対応しているが、それは「HP 状態の 4 段階は多くの UI で共有される」ため。エフェクト色とは性質が異なる。

### 「本来参照すべき値から独立している定数」の記録（次タスク向け）
Komuro からの指摘で `Projectile.SPRITE_REF_SIZE = 64.0` は「本来 GRID_SIZE から動的に導出すべき値が独立定数になっている」ケース。今タスクのスコープでは設計是正を行わず、TODO コメントを残した：
```
## スプライト基準サイズ（飛翔体として適切なサイズ）
## TODO: 将来は GlobalConstants.GRID_SIZE から動的に導出すべき（現状は独立した直書き定数）
const SPRITE_REF_SIZE: float = 64.0
```

他のエフェクトクラスでは `gs * 0.55` 等「GRID_SIZE に対する比率」として書かれている箇所は設計として正しい方向。次タスク「画像サイズ設計是正」で、直書きになっている値を洗い出して GRID_SIZE 比率に置き換える。CLAUDE.md「要調査・要整理項目」に追記済み。

### スコープ外（記録）
- `outline.gdshader` のユニフォーム値（D 分類・シェーダー側管理）
- Kenney 等のネット取得素材（アセット表に記載）
- 削除候補（E 分類）：0 項目（明確な dead は無し）

### 実装ファイル

#### `scripts/global_constants.gd`
- 新規 var 9 個（A 分類 8 + `STUN_PULSE_HZ`）を「Effect 関連」セクションに追加
- `CONFIG_KEYS` 末尾に A 分類 8 項目を追加

#### `scripts/buff_effect.gd`
- `const ROT_SPEED = PI / 3.0` を削除し、`_process()` 内で `deg_to_rad(GlobalConstants.BUFF_EFFECT_ROT_SPEED_DEG)` を参照
- コメント更新

#### `scripts/whirlpool_effect.gd`
- `const ROT_SPEED = PI * 1.5` を削除し、`_process()` 内で `deg_to_rad(GlobalConstants.WHIRLPOOL_ROT_SPEED_DEG)` を参照
- コメント更新

#### `scripts/character.gd`
- `Color(1.5, 1.5, 1.5, 1.0)` → `GlobalConstants.TARGETED_MODULATE_STRENGTH` を使った動的色
- `sin(t2 * TAU * 3.0)` → `sin(t2 * TAU * GlobalConstants.STUN_PULSE_HZ)`

#### `scripts/player_controller.gd`
- `const TURN_DELAY` 削除 → `GlobalConstants.TURN_DELAY` 参照
- `const AUTO_CANCEL_FLASH` 削除 → `GlobalConstants.AUTO_CANCEL_FLASH` 参照
- sliding step_dur 直書き `0.12` → `GlobalConstants.SLIDING_STEP_DUR`
- `set_outline(..., 1.0)` × 2 箇所 → `GlobalConstants.OUTLINE_WIDTH_UNFOCUSED`
- `set_outline(..., 2.5)` → `GlobalConstants.OUTLINE_WIDTH_FOCUSED`

#### `scripts/projectile.gd`
- 直書き `64.0` / `PI / 2.0` / `5.0` / 4 色を名前付き `const` に昇格
- `SPRITE_REF_SIZE` に TODO コメント追加

#### `scripts/config_editor.gd`
- `TABS` 配列末尾に `"Effect"` を追加

#### `assets/master/config/constants_default.json`
- A 分類 8 項目を `category: "Effect"` で追加（min / max / step / description）

### CLAUDE.md 更新
- 「使用アセットとライセンス」にアセット定義を追加。Kenney Particle Pack の行を取り消し線＋移行注記
- 「セッション開始時のガイド」（18 行目）の定数タブ構成を「6 タブ → 7 タブ」「約 38 個 → 約 46 個」に更新
- 「定数」タブのカテゴリ説明に Effect カテゴリを追加
- 定数追加時の運用ルールを「6 タブ → 7 タブ」に更新
- 「要調査・要整理項目」に「画像サイズ設計是正（次タスク候補）」を追加

### Komuro への動作確認依頼
- **Config Editor (F4)**：定数タブに「Effect」カテゴリが表示される
- **操作感系 6 項目の調整**：ツマミで値を変更 → 保存 → 再起動 → 以下が変わることを確認
  - 向き変更の遅延（TURN_DELAY）
  - ターゲット自動キャンセル時のフラッシュ長（AUTO_CANCEL_FLASH）
  - スライディング速度（SLIDING_STEP_DUR）
  - アウトライン太さ（OUTLINE_WIDTH_FOCUSED / UNFOCUSED）
  - ターゲット発光の強度（TARGETED_MODULATE_STRENGTH）
- **視認性系 2 項目**：バリア回転速度（BUFF_EFFECT_ROT_SPEED_DEG）・スタン渦回転速度（WHIRLPOOL_ROT_SPEED_DEG）
- **デフォルト値に戻す**：元の挙動に戻る
- **Projectile の動作**：飛翔体が従来通り表示・移動する（64px スケール・回転補正が変わっていないこと）

---

## 2026-04-19（Legacy LLM AI コードと dead code の物理削除）

### 背景
Phase 2-3 でルールベース AI に移行した際、LLM 駆動 AI 時代の 5 クラス（約 1,221 行）がコードベースに残存していた。`docs/investigation_class_structure.md` の調査で「完全未使用」と判定されていたが、未削除のまま Config Editor や CLAUDE.md 内の棚卸し項目として追跡されていた。「今使っていないものは残さない」方針で物理削除する。併せて、概念的に同世代（Phase 1-2 時代）の dead code である `CharacterData.create_hero()` / `create_goblin()` も削除する。

### 削除したファイル（5 ファイル × .gd + .uid = 10 ファイル）
- `scripts/base_ai.gd` + `.uid`（547 行・BaseAI クラス）
- `scripts/enemy_ai.gd` + `.uid`（401 行・EnemyAI クラス・LLM 駆動敵 AI）
- `scripts/llm_client.gd` + `.uid`（109 行・LLMClient クラス・LLM API 呼び出し）
- `scripts/dungeon_generator.gd` + `.uid`（119 行・DungeonGenerator クラス・LLM によるマップ生成）
- `scripts/goblin_ai.gd` + `.uid`（45 行・GoblinAI クラス・BaseAI サブクラス）

### 削除した dead code
- `CharacterData.create_hero()`（`load_from_json("res://assets/master/characters/hero.json")` ラッパ）
- `CharacterData.create_goblin()`（`load_from_json("res://assets/master/enemies/goblin.json")` ラッパ）
- どちらも Phase 1-2 時代の名残。現行コードからは一切呼ばれていない

### 参照調査結果

#### A. ブロッカー（削除すると壊れる）: **0 件**
- `project.godot` の Autoload 登録: なし
- `.tscn` の script アタッチ: なし
- 5 ファイル外からの `preload` / `load` / `extends` / 型注釈: なし
- `create_hero` / `create_goblin` の呼び出し: なし（定義のみ孤立）
- `character.gd:143` に `EnemyAI` コメントがあったが実行時非依存

#### B. 削除対象同士の相互参照: 3 箇所（一緒に消えるので安全）
- `enemy_ai.gd` の `LLMClient` 参照（3 行）
- `dungeon_generator.gd` の `LLMClient` 参照（3 行）
- `goblin_ai.gd` の `extends BaseAI`

#### C. ドキュメント言及（削除時に更新済み）
- `CLAUDE.md` 1384 行目の削除タスクを ✅ 完了記録に変更
- `docs/investigation_class_structure.md` の Legacy セクションを「削除済み」に更新（ファイル一覧を取り消し線で残し、日付を明記）
- `docs/spec.md` は「現行仕様として誤読される箇所」のみ更新、「Phase 2-3 当時の仕様」として明示されている歴史的記述はそのまま残す（分類サマリーは下記）

#### D. その他
- `.godot/global_script_class_cache.cfg` / `.godot/editor/*.cfg` にキャッシュが残っていたが、Godot エディタ起動時に自動再スキャン・再構築されるため手動介入不要（commit 対象外）

### docs/spec.md 分類サマリー

約 20 箇所の参照のうち、**更新した 9 箇所 / 残した 11 箇所**：

#### 更新した箇所（「現行仕様」として誤読される可能性あり）
1. Line 514-524「AIアーキテクチャ仕様」配下のファイル構成：legacy 2 ファイルを削除し、削除済みの注記を追加
2. Line 669-670「旧クラスとの対応」表：`BaseAI` / `GoblinAI` の「状態」列を「残存」→「**2026-04-19 に物理削除済み**」
3. Line 684 Phase 3 ファイル構成の `dungeon_generator.gd` / `llm_client.gd` 行：「将来削除対象」→「2026-04-19 に物理削除済み」
4. Line 688 同上
5. Line 694「### DungeonGenerator」節見出し：「将来削除対象」→「2026-04-19 に物理削除済み」
6. Line 741「### LLMClient の変更点」節見出し：同上
7. Line 1036 `is_attacking` setter コメント：`EnemyAI` → `UnitAI`
8. Line 1129 DebugWindow セクション：`BaseAI.get_debug_info()` → `UnitAI.get_debug_info()`
9. Line 1144 同上・返却形式の表題と Strategy 列挙値のクラス名を `UnitAI` に更新

#### 残した箇所（「Phase 2-3 当時の仕様」として明示されており歴史的記述として正しい）
- Line 319-320, 341-344, 347-352, 402-403, 421, 430, 462-463, 474, 505: Phase 2-2 / Phase 2-3 セクション内部の実装詳細（当時の仕様として正しい）
- Line 511 パーティーシステム移行の冒頭記述
- Line 584, 612, 644-647, 676: UnitAI / 後方互換セクションの「旧 BaseAI と比較」する記述（移行の文脈で有用な比較情報）
- Line 936, 973, 990: Phase 4/5 セクションの過去の変更ファイルリスト
- Line 1399: 2026-04 パーティーリファクタリング総括の記述
- Line 2093-2094: `attack` → `attack_power` リネーム記録（歴史的事実）
- Line 3701, 3754, 4664: 過去のリファクタリング時に「レガシー・未使用のため触らず」と明記した記録

### 実装した変更

#### 削除
- 5 ファイル × 2 (.gd + .gd.uid) = 10 ファイル
- `CharacterData.create_hero()` / `create_goblin()` 静的メソッド（9 行）

#### 更新
- `scripts/character.gd:143`：コメント `EnemyAI` → `UnitAI`
- `CLAUDE.md`：1384-1391 行目のタスクを ✅ 完了記録に変更。1367 行目の「次の棚卸し候補」から `hero.json` を dead code 合流から分離して独立候補化
- `docs/investigation_class_structure.md`：ファイル一覧テーブル・推奨しないもの・Legacy セクションの 3 箇所を「削除済み」に更新
- `docs/spec.md`：上記 9 箇所を更新
- `docs/history.md`：本エントリを追加

### 安全判断の根拠
1. Autoload 登録ゼロ（`project.godot` クリーン）→ 起動時強制ロードなし
2. シーンファイル script アタッチゼロ（`.tscn` クリーン）
3. 5 クラス外からの依存ゼロ（preload / load / extends / 型注釈なし）
4. 相互参照はすべて削除対象同士（B 分類 3 件が一緒に消える）
5. `create_hero` / `create_goblin` は完全孤立（定義のみ・呼び出しなし）
6. `--check-only` で削除後に新規警告・エラーなし

### Komuro への動作確認依頼
以下のチェックリストで実機確認してください：
- **ゲーム起動**：タイトル画面が正常に表示される。コンソールに `class_name 解決エラー` / `preload 失敗` / `script not found` が**ない**こと
- **ニューゲーム開始**：タイトル → ニューゲーム → 名前入力 → フロア 0 の流れが動作する
- **フロア 0 戦闘**：近接（剣士）・遠距離（弓）・回復（ヒーラー）の各行動が正常に動作する（V スロット含む）
- **フロア遷移**：階段でフロア 0 → 1 → 2 への遷移が動作する
- **Config Editor（F4）**：正常に開き、「定数」「味方クラス」「敵クラス」「敵一覧」「ステータス」の全タブがエラーなく表示される
- **`godot --headless --check-only`**：新規の warning / error が発生しないこと（既存の Variant 推論警告は許容）
- **エディタ再起動**：Godot エディタを一度閉じて開き直したとき、削除した `base_ai.gd` 等に関する「スクリプトが見つからない」警告が**出ない**こと（`.godot/global_script_class_cache.cfg` が自動再構築される）

### 追加作業（同日・Komuro 動作確認後）：CLAUDE.md の LLM 参考仕様セクション削除
コード削除と整合性を保つため、CLAUDE.md 本体に残っていた「参考仕様・未使用」とマークされた 3 セクション（約 60 行）を削除した：
- 「LLMへ渡すデータ構造（参考仕様・未使用）」（状況 JSON サンプル）
- 「LLMの返答形式（参考仕様・未使用）」（アクションシーケンス JSON サンプル・relative_position 種類）
- 「LLM呼び出し方針（参考仕様・未使用）」（非同期呼び出し・キュー置換方式・強制再生成トリガー等）

削除位置：「### 方向と防御」節の直後、「## リポジトリ」節の直前。削除後、両節が空行 1 つを挟んで自然に繋がることを確認済み。

歴史的経緯の保全：削除した 3 セクションの設計方針は [docs/spec.md](spec.md) の Phase 2-3 セクション（337-349 行目付近・当時の LLMClient / DungeonGenerator 実装記録）および本 2026-04-19 エントリ冒頭の背景記述でカバーされているため、別途サマリーを追記する必要なしと判断。CLAUDE.md 内に残る唯一の LLM 参照は「要調査・要整理項目」の ✅ 完了記録のみ（正当な履歴記述）。

---

## 2026-04-19（個別敵 JSON の legacy フィールド物理削除）

### 背景
Config Editor「敵一覧」タブへの name / projectile_type 追加（同日）の際、棚卸しで「legacy 扱いで実質未使用」のフィールドが個別敵 JSON に残っていることを確認。`apply_enemy_stats()` が `enemy_list.json` + `class_stats.json` / `enemy_class_stats.json` から毎回ステータスを再算出する設計のため、個別敵 JSON の数値ステータスは保持しておく意味がない。
「今使っていないものは残さない」方針で物理削除する。

### 削除対象（6 フィールド × 16 ファイル = 計 96 エントリ）
`hp` / `power` / `skill` / `physical_resistance` / `magic_resistance` / `rank`

### 事前調査（参照分類）
- **A. 実行時ステータスアクセス**（`character.hp` 等の runtime フィールド）：影響なし。個別敵 JSON を読まない
- **B. `CharacterData.load_from_json` 内の 6 行の `d.get("hp" / ...)`** ：削除対象。JSON から legacy 値を読んでいたが、直後の `apply_enemy_stats()` が必ず上書きするため死に読み。`CharacterData` の default 値（max_hp=1 / power=1 / skill=0 / rank="C" / physical_resistance=0 / magic_resistance=0）が安全側のため、削除しても敵生成経路では一切表面化しない
- **C. `apply_enemy_stats` 内の参照**：`entry.get("rank")` は `enemy_list.json` 側、`stats.get("power" / ...)` は `_calc_stats()` 戻り値。どちらも個別敵 JSON 非経由。影響なし
- **D. その他**：`config_editor.gd` は個別敵 JSON からこれらのキーを読まない（rank は `enemy_list.json` の `list_entry` 経由）。`enemy_ai.gd`（legacy LLM AI）は `enemy.hp`（runtime）参照のみ

### 「こっそり使っている」箇所の有無確認
**なし**。`party_manager._spawn_enemy_member()`（敵生成の唯一のライブパス）は `load_from_json()` → `apply_enemy_graphics()` → `apply_enemy_stats()` の順で、legacy 値を参照する処理が間に挟まらない。`CharacterData.load_from_json()` の他の呼び出し元（`create_hero()` / `create_goblin()`）は dead code で未使用

### 友好キャラ用経路の最終確認
`CharacterData.load_from_json` を live で呼んでいるのは [party_manager.gd:265](scripts/party_manager.gd:265)（敵生成）のみ。友好キャラは `CharacterGenerator.generate_character(class_id)` で生成するため load_from_json 経路を通らない。削除による友好キャラへの影響なし

### 実装
#### 個別敵 JSON（16 ファイル）
Python スクリプトで一括処理：
- `goblin.json` / `goblin_archer.json` / `goblin_mage.json` / `hobgoblin.json`
- `zombie.json` / `wolf.json` / `harpy.json` / `salamander.json`
- `dark_knight.json` / `dark_mage.json` / `dark_priest.json` / `dark_lord.json`
- `skeleton.json` / `skeleton_archer.json` / `lich.json` / `demon.json`

全 16 ファイルから上記 6 フィールドを削除。キー順は `OrderedDict` で元順保持。2-space インデント。

#### `scripts/character_data.gd`
`load_from_json()` から以下の読み出しコードを削除（約 15 行）：
- `data.max_hp = int(d.get("hp", 1))` 行
- `data.power` の読み出しチェーン（新 "power" → 旧 "attack_power"/"attack"/"magic_power" フォールバック・約 7 行）
- `data.skill = int(d.get("skill", d.get("accuracy", 0)))` 行
- `data.rank = d.get("rank", "C")` 行
- `data.physical_resistance = int(d.get("physical_resistance", 0))` 行
- `data.magic_resistance = int(d.get("magic_resistance", 0))` 行

代わりに「数値ステータスは個別敵 JSON からは読まない。敵は `apply_enemy_stats()` が算出、味方は `CharacterGenerator.generate_character()` で生成する」旨のコメントを残す

### CLAUDE.md 更新
- ファイル構成セクション（130 行目付近）：`hp` / `power` / `skill` 等の記述を「2026-04-19 物理削除済み」に書き換え
- Config Editor「敵一覧」タブの「意図的に編集対象外」注記：legacy フィールド 6 個の記述を削除し、現在の状態（id / sprites のみ除外）に更新
- 物理削除履歴を注記として追加
- 「要調査・要整理項目」の legacy 棚卸し項目を「✅ 完了」＋「次の棚卸し候補」リストに更新

### 運用ルールとの整合性
- 「今使っていないものは残さない」方針に沿って、JSON とコード両方を同時削除
- `CharacterData` の default 値は安全側（max_hp=1・power=1 等）のため、削除による表面化リスクなし
- 将来友好キャラ JSON を直接ロードする経路が必要になった場合は、そのとき必要な形で再実装する（既存の default 値が安全なので再実装コストは小さい）

### Komuro への動作確認依頼

以下のチェックリストで実機確認してください：

- **敵ダメージ・HP**：フロア 0〜4 の全敵種（16 種）と戦闘し、ダメージ・HP が削除前と同じ（体感で大きな差がない）こと
  - 特に削除フィールドが保持していた値が大きい敵：`hobgoblin`（hp=45, power=12, skill=14）/ `dark_knight` / `dark_lord` / `demon`
  - `apply_enemy_stats` で `enemy_list.json` の rank / stat_bonus から再算出されるため、同じ数値になるはず
- **敵の特殊挙動**：
  - ゴブリン系の臆病撤退（HP < 30%）
  - ウルフの高速移動
  - サラマンダーの炎攻撃
  - ハーピーの降下攻撃（飛行）
  - ダークプリーストの回復
  - dark-lord のワープ＋炎陣（ボス）
  - デーモンの雷弾（`projectile_type="thunder_bullet"`）
  - リッチの火水交互魔法
  - スケルトン系のアンデッド耐性（ヒーラー回復魔法が特効）
- **Config Editor**：
  - F4 で「敵一覧」タブが起動時エラーなく開く
  - 「敵一覧」の各欄（name / rank / stat_type / 3 つの bool / behavior / chase / territory / projectile / stat_bonus × 6）が正しく表示される
  - 値を変更→保存→再起動後に反映される
- **起動時ログ**：コンソールに JSON 関連の warning / error がないこと（`push_warning` / `push_error` は出ないはず）

---

## 2026-04-19（Config Editor「敵一覧」タブへのフィールド追加）

### 背景・動機
同日のバグ修正（戦闘メッセージの敵表示名が「斧戦士」等のクラス日本語名になっていた）の原因調査で、個別敵 JSON の `name` フィールドが Config Editor から不可視だったことがミス発見を遅らせた要因の一つと判明した。Config Editor の重要な役割の一つである「データの不足・乖離をチェックできるようにする」ことが損なわれていたため、「敵一覧」タブの表示フィールドを棚卸しし、欠落を補う。

### 棚卸し結果（個別敵 JSON・16 ファイル）

#### A. 既に編集可能
id（Label）/ rank / stat_type / is_undead / is_flying / instant_death_immune / behavior_description / chase_range / territory_range / stat_bonus × 6

#### B. 追加した（本タスク）
- **`name`**（全 16 ファイル）：プレイヤー向け表示名（戦闘メッセージ・UI）。基本的に種族名の日本語（「ゴブリン」「ホブゴブリン」等）。`Character._battle_name()` が参照する source of truth
- **`projectile_type`**（demon のみ）：飛翔体の種別切替。`""` = attack_type から自動判定、`"thunder_bullet"` = 雷弾。UI 上は `""` を「(自動)」と表示

#### C. 意図的に除外（docs 化）
- `id` — 識別子（Label として表示）
- `hp` / `power` / `skill` / `physical_resistance` / `magic_resistance` — legacy。`apply_enemy_stats()` が stat_type / rank / stat_bonus から毎回算出・上書きするため、ここでの編集値は効果を持たない
- `rank`（個別 JSON 内）— legacy。`enemy_list.json` が source of truth（そちらで編集可能）
- `sprites` — 画像パスの辞書構造。専用のアセット管理が必要で Config Editor の守備範囲外

### 実装（`scripts/config_editor.gd`）

#### 定数追加
- `PROJECTILE_TYPE_AUTO_LABEL: String = "(自動)"` — UI 表示用ラベル
- `ENEMY_PROJECTILE_CHOICES: Array[String] = ["(自動)", "thunder_bullet"]` — 新弾種追加時はここに追記
- `ENEMY_NAME_COL_W: int = 100` / `ENEMY_PROJECTILE_COL_W: int = 130` — 列幅

#### 列順
`敵ID → name → rank → stat_type → undead → flying → 死耐性 → behavior → chase → territory → projectile → stat_bonus × 6`

#### 関数追加
- `_add_enemy_projectile_option()`：projectile_type 用 OptionButton（PanelContainer 包みでハイライト対応）
- `_proj_choice_to_value()` / `_proj_value_to_choice()`：表示ラベル `"(自動)"` ↔ 保存値 `""` の双方向変換
- `_on_enemy_projectile_changed()`：OptionButton 変更ハンドラ（dirty 再評価・セルハイライト更新）

#### 関数修正
- `_build_enemy_list_row()`：name LineEdit と projectile OptionButton の追加
- `_build_enemy_list_header()`：列ヘッダーに name / projectile を追加
- `_enemy_indiv_orig_text()`：name の元値取得を追加
- `_enemy_indiv_has_any_diff()`：name の LineEdit ループに追加。projectile OptionButton の比較を独立ブロックで追加
- `_reset_enemy_list_tab()`：name を LineEdit リセットループに追加。projectile_type OptionButton のリセット処理を追加
- `_apply_enemy_indiv_edits()`：name の書き戻し（元 JSON フィールド有無を尊重）・projectile_type の書き戻し（"(自動)" → "" 変換）を追加

### CLAUDE.md 更新
- 「敵一覧」タブセクションの列一覧を name / projectile_type を含む形に更新
- name の意味（Character._battle_name 参照の source of truth）と projectile_type の選択肢・UI ラベル変換を注記
- **意図的に編集対象外としているフィールド**の一覧（上記 C 分類）を追記。将来の棚卸し時の参考
- 「要調査・要整理項目」に「Config Editor 全タブの表示フィールド棚卸し（定期運用）」を追加。味方クラス・敵クラス・ステータス各タブは次回以降で実施

### 動作確認観点
- Config Editor（F4）→「敵一覧」タブで name 列が表示・編集できる
- 例：goblin の `name` を「テストゴブリン」に変更→保存→再起動→フロア0 のゴブリンと戦ってメッセージに反映される→元に戻す
- demon の `projectile_type` を「(自動)」↔「thunder_bullet」で切り替えて、雷弾 / 火弾グラフィックの切替を確認
- セルのハイライト・タブ末尾の ● インジケータ・リセット挙動が既存フィールドと同じく機能する

### 運用ルールとの整合性
- 「新ステータス・新敵の追加は Config Editor の守備範囲外」（CLAUDE.md）は維持。本タスクは既存フィールドの編集範囲拡張であり、この方針に抵触しない
- 「元 JSON のフィールド有無を尊重」ルール（legacy フィールドの構造保全）に従って、name / projectile_type ともに元にない＋デフォルト値のままなら追加しない実装

---

## 2026-04-19（バグ修正：敵のVスロット特殊攻撃抑止・戦闘メッセージの敵表示名）

### 問題
2026-04-17 のデータ構造整理（Phase B 下準備）で `apply_enemy_stats()` が敵の `class_id` を `stat_type`（"fighter-axe" 等）に設定するようになった副作用で、以下の 2 つの問題が発生していた：

1. **敵が V スロット特殊攻撃を発動**：`UnitAI._generate_special_attack_queue()` の `match cd.class_id` が敵にもマッチし、hobgoblin（stat_type="fighter-axe"）が振り回しを、dark_priest（stat_type="healer"）が `_generate_buff_queue()` で防御バフを発動していた。仕様上、敵は V スロット特殊攻撃を使わない想定（dark-lord の炎陣だけはキュー外動作の例外）
2. **戦闘メッセージで敵がクラス日本語名で表示**：`Character._battle_name()` が敵に対して `CLASS_NAME_JP.get(class_id)` を返していたため、「ホブゴブリン」と表示すべき場面で「斧戦士」と表示されていた。`class_id` が空だった Phase B 以前は `character_name`（=個別敵 JSON の `name`）にフォールバックしていたが、`class_id` 設定後は誤ったルートに入っていた

### 修正

#### `scripts/unit_ai.gd`
- `_generate_special_attack_queue()` 冒頭に `if not _member.is_friendly: return []` を追加
- `_generate_buff_queue()` 冒頭にも同じガードを追加
- コメントに「敵（is_friendly=false）は V スロット特殊攻撃を発動しない。dark-lord の炎陣は `_update_dark_lord_behavior()` のキュー外動作のため対象外」と明記

#### `scripts/character.gd`
- `_battle_name()` を味方／敵で分岐せず、どちらも `character_data.character_name` を返すよう簡略化
- 敵の `character_name` は個別敵 JSON の `name`（種族名、例：「ホブゴブリン」）
- 空の場合のみ `character_id` にフォールバック
- `CLASS_NAME_JP` の敵向け参照を撤去

#### `CLAUDE.md`
- 「メッセージ表記方針」に「表示名の規則」小項目を追加（味方＝個別名、敵＝種族名、どちらも `character_name` 参照）
- 「Vスロット特殊攻撃仕様」に「敵の V スロット発動方針」小項目を追加（dark-lord の炎陣は例外として明記）

### 動作確認観点
- フロア0（ゴブリンのみ）：「ゴブリンが…」と表示され、V 特殊攻撃は発動しない
- ホブゴブリン（fighter-axe 系）：振り回しを使わず、通常攻撃のみで戦う
- dark_priest：バフを使わず、回復（Z スロット）のみを行う
- フロア4 dark-lord：炎陣とワープが従来通り動作（キュー外実装に非介入）
- 味方の特殊攻撃：従来通り発動
- 味方の名前表示：従来通り個別名で表示

---

## 2026-04-18 の大規模リファクタリング総括

本日のセッションは Phase 13 → 14 の橋渡しとなる「節目」の日。多数の設計整理・計算統一・定数外出し・調査を連続して実施した。以下は全体を俯瞰する総括。個別の詳細は同日付の後続エントリ参照。

### 主な完了項目

#### 1. Config Editor の大再編
- 従来 5 タブ（Character / PartyLeader / NpcLeaderAI / EnemyLeaderAI / UnitAI）→ 6 タブ（+ SkillExecutor）へ拡張
- 約 35 → 約 38 個の定数が Config Editor から編集可能
- チェックボックスハイライト・リセット/コミット動作のバグを修正
- 「敵クラス」タブ・「敵一覧」タブの新設（敵固有 5 クラス × 16 敵個体）

#### 2. データ構造の整理
- MP / max_mp / sp / max_sp → `energy` / `max_energy` に統合（内部データ単一化・UI 表示は魔法クラスで MP / 非魔法クラスで SP）
- `base_defense` / `defense` フィールドの廃止
- ポーション名統一（ヒールポーション / エナジーポーション）
- 敵固有 5 クラス JSON の新設（`assets/master/classes/zombie.json` 等）。個別敵 JSON からクラス項目を除去し、クラス経由で注入する構造へ
- legacy フィールド（個別敵 JSON の `hp` / `power` / `skill` 等）は保持したまま段階整理

#### 3. SkillExecutor 抽出完了（全 10 種）
Player / AI で二重実装されていたスキル計算式を `scripts/skill_executor.gd` に集約：
- ステージ1: heal
- ステージ2: melee / ranged
- ステージ3a: flame_circle / water_stun / buff
- ステージ3b: rush / whirlwind / headshot / sliding

#### 4. ハードコード定数の外出し
- `ATTACK_TYPE_MULT[melee/ranged/magic/dive]` を Config Editor 可能に
- `CRITICAL_RATE_DIVISOR`（skill / 300 → `GlobalConstants` 参照）
- `PROJECTILE_SPEED`（2000 px/s → `GlobalConstants` 参照）
- `ENERGY_RECOVERY_RATE`（3.0/秒 → `GlobalConstants` 参照）
- `DEFENSE_BUFF_DURATION` フォールバックを撤廃（slot.duration を単一の真実に）
- Vスロット `V_duration` / `V_tick_interval` への統一（旧 `V_stun_duration` / `V_buff_duration` は廃止）

#### 5. 設計方針の明文化（CLAUDE.md 更新）
- 「AI と実処理の責務分離方針」セクションを新設（意思決定層・実処理層・2 系統アーキテクチャ維持方針・エフェクト生成の段階移行方針）
- 「セッション開始時のガイド」を新設
- 「Phase 14 バランス調整の事前情報」を新設

#### 6. 調査ドキュメント作成（7 本）
`docs/investigation_*.md`：
- `investigation_healer_structure.md`
- `investigation_base_defense.md`
- `investigation_mp_max_sp_divergence.md`
- `investigation_healer_undead_damage.md`
- `investigation_enemy_v_slot.md`
- `investigation_class_structure.md`
- `investigation_action_queue.md`
- `investigation_skill_executor_constants.md`

### 発見・修正されたバグ（乖離バグが連鎖的に発覚）

- **AI ヒーラーの `heal_mult` 未適用**：Player は適用・AI は raw power で回復（約 3.4× 強い回復）
- **AI の `water_stun` 二重ダメージ**：Projectile の damage と直接 `take_damage` の両方で適用されていた
- **AI の `flame_circle` / `water_stun` / `buff_defense` で JSON 値を無視しハードコード**：`damage_mult` / `duration` が slot から読まれていなかった
- **AI 操作 magician-water の水弾未判定**：`_get_is_water_shot()` の基底実装が false を返すため火弾画像になっていた
- **Player の `projectile_type` 未参照**：demon の thunder_bullet が Player 側では反映されない（実害なし）
- **headshot 非免疫時の処理分岐**：Player は Projectile 経由 99999 ダメージ / AI は直接 `hp=0+die()` と実装が分かれていた
- **メッセージ重複**（複数件）：回復メッセージの白文字系と色付き系が重複表示
- **Config Editor 各種バグ**：チェックボックスハイライト未反応 / リセット/コミット動作不全 / 「現在値をすべてデフォルト化」がタブ限定になっていた
- **ラベル露出**：プレイヤー向け UI に「エネルギー」という内部用語が露出 → 「MP/SP」固定表記に修正

### 次セッションに持ち越された課題

- **実機動作確認**：SkillExecutor の全 10 種スキルの Player/AI 実機動作・ダメージ一貫性・飛翔体・エフェクト・SE
- **Legacy LLM AI コードの削除**（BaseAI / EnemyAI / LLMClient / DungeonGenerator / GoblinAI = 約 1221 行）
- **`PlayerController._spawn_heal_effect` のデッドコード判定と削除**
- **エフェクト生成の一系統化**（Character 経由と SkillExecutor 直 new の 2 系統混在）
- **dark-lord のワープ・炎陣のキュー外処理**を SkillExecutor 経由にリファクタ
- **Phase 14 バランス調整**：敵の防御判定が正常機能するようになったことによる敵生存率上昇への対応
- **敵ヒーラー（dark_priest）の実機動作確認**（energy 統合後）
- **用語整理**：「敵クラス」vs「種族」、`enemy_list.json` vs `enemies_list.json`、ハイフン/アンダースコア統一

### 今日の教訓・学び

1. **計算ロジックの重複は乖離バグの温床**：Player と AI で同じ計算式を別々に実装していたため、調整が片方にしか反映されない事故が連続して発生。SkillExecutor 抽出により構造的に解消。
2. **JSON 駆動の徹底**：AI 側がクラス JSON を「読まずにハードコード」している箇所が複数発覚。slot を Dictionary として渡し、slot.get(key, fallback) で統一することで JSON を単一の真実に。
3. **調査ドキュメントの先行作成が効いた**：`investigation_*.md` を書いてから実装に入ることで、無駄な手戻りが減った。特に `investigation_class_structure.md` / `investigation_action_queue.md` / `investigation_skill_executor_constants.md` は設計判断の根拠として今後も参照価値が高い。
4. **段階移行の有効性**：SkillExecutor 抽出を 4 ステージに分けたことで、各段階で動作確認の単位を小さく保てた。全 10 種を一度に移行するよりリスクが低い。
5. **内部用語と UI 用語の分離**：`energy` は内部実装、`MP / SP` は UI 表示、と明確に分離することで多クラス対応（魔法/非魔法）を内部では単一フィールドで扱える。

---

## 2026-04-18（Config Editor に SkillExecutor タブ新設・関連定数を外出し）

### 変更内容
- **GlobalConstants 追加（3 定数）**：
  - `CRITICAL_RATE_DIVISOR: float = 300.0` — クリティカル率除数。`critical_rate = skill / CRITICAL_RATE_DIVISOR`。SkillExecutor カテゴリ
  - `PROJECTILE_SPEED: float = 2000.0` — 飛翔体の移動速度（px/秒）。SkillExecutor カテゴリ
  - `ENERGY_RECOVERY_RATE: float = 3.0` — エネルギー自動回復速度（/秒）。Character カテゴリ（個体のステータス回復速度）
- **Config Editor タブ追加**：`TABS` 配列に `"SkillExecutor"` を追加（`"UnitAI"` の後・陣営階層順）。`constants_default.json` に 3 定数のメタ情報（min/max/step/description）を追加。
- **ハードコード撤去**：
  - `character.gd:58` `const ENERGY_RECOVERY_RATE: float = 3.0` を削除 → `GlobalConstants.ENERGY_RECOVERY_RATE` 参照に変更
  - `character.gd:786` クリティカル判定 `float(atk_skill) / 300.0` を `GlobalConstants.CRITICAL_RATE_DIVISOR` 参照に変更
  - `projectile.gd:8` `const SPEED := 2000.0` を削除 → `GlobalConstants.PROJECTILE_SPEED` 参照に変更
- **`DEFENSE_BUFF_DURATION` を削除**：Character 内 `const DEFENSE_BUFF_DURATION: float = 10.0`（slot.duration が 0 時のフォールバック値）を撤廃。`apply_defense_buff(duration)` は duration ≤ 0 のとき早期 return（バフを付与しない）に変更。slot.duration を単一の真実として扱う設計に統一。
  - 削除前の参照箇所確認：唯一の呼出は `SkillExecutor.execute_buff` のみ。`slot.get("duration", 0.0)` で 0.0 フォールバックが入るが、`healer.json` V スロットは `duration: 10.0` を明示しているため、通常フローで 0.0 が渡ることはない。削除しても機能喪失なし。

### CLAUDE.md 更新
- 「AI と実処理の責務分離方針」に「エフェクト生成の方針（段階移行中）」セクションを追記。2 系統混在（Character 経由 / SkillExecutor 直 new）の現状と将来の一系統化方針を明文化。
- 「実処理の共通化（完了）」に SkillExecutor 抽出完遂を反映。
- 「Config Editor」節のカテゴリ一覧に SkillExecutor を追加（6 タブ体制）。外出し済み定数数を 35 → 38 に更新。
- 「要調査・要整理項目」に「エフェクト生成の一系統化」を追加（ゲーム動作には影響なし・段階対応）。

### 決定事項
- **DEFENSE_BUFF_DURATION 削除**：フォールバックチェーン（slot.duration → 0.0 → DEFENSE_BUFF_DURATION=10.0）を 1 段短縮。slot.duration が未設定なら「バフを付けない」ことを明示的な失敗として扱う。healer.json に duration=10.0 が常に設定されているため現行挙動は変化なし。
- **ENERGY_RECOVERY_RATE を Character タブ**（SkillExecutor タブでなく）：回復速度は個体のステータス特性として扱う方が直感的。各 skill の cost 値とセットで調整する際も Character タブ内で完結できる。
- **CRITICAL_RATE_DIVISOR / PROJECTILE_SPEED を SkillExecutor タブ**：どちらも計算式・演出に直接効く値で、バランス調整時に SkillExecutor 関連としてまとめて扱うのが自然。

### 動作確認
- `godot --headless --check-only` でスクリプトのパース成功を確認（エラー 0 件）。
- 実機動作確認（クリティカル率・飛翔体速度・エネルギー回復・防御バフ持続時間・Config Editor の SkillExecutor タブ表示）は次回セッションで実施予定。

## 2026-04-18（SkillExecutor 抽出・ステージ3b：rush / whirlwind / headshot / sliding 移行・全10種完了）

### 変更内容
- **SkillExecutor 追加メソッド**：残り4種類を追加し、全10種類の抽出が完了。
  - `execute_rush(attacker, slot, map_data, potential_targets=[]) -> Dictionary`: 向いている方向に最大3マス走査。step 1〜2 の敵にダメージを与え、空きマスを着地位置として返す。`{"landing_pos": Vector2i, "hit_count": int}` を返す。空振り時は自然言語メッセージを出す。移動は呼出側の責務（Player は `move_to` アニメ、AI は `grid_pos` 瞬間移動）。
  - `execute_whirlwind(attacker, slot, potential_targets=[]) -> int`: 隣接8マスの敵全員にダメージ。命中数を返す。命中ごとに segments 付きバトルメッセージを出す。空振り時も専用メッセージ。
  - `execute_headshot(attacker, target, slot) -> bool`: target.instant_death_immune を判定し、免疫あり→×3ダメージ、なし→即死。視覚用の飛翔体（damage=0）を発射した上で、ダメージ/即死は直接適用する方式に統一（従来 Player は projectile 99999 damage で間接的に、AI は `hp=0+die()` で直接的にと実装が分かれていた）。segments 付きバトルメッセージ＋combat ログ。
  - `execute_sliding(attacker, slot, map_data, potential_targets=[]) -> Vector2i`: 向いている方向に最大3マス走査。敵味方ともすり抜ける着地位置を返す。ダメージなし。segments 付きバトルメッセージ＋SE。移動と無敵フラグ管理は呼出側の責務。
- **SkillExecutor ヘルパー追加**：`_find_hostile_at()`（rush / whirlwind 用）/ `_find_any_occupant_at()`（sliding 用）/ `_emit_v_skill_battle_msg()`（V 攻撃のダメージログ共通フォーマット）。
- **player_controller.gd**:
  - `_execute_rush` / `_execute_whirlwind` / `_execute_sliding`: SkillExecutor 呼出＋move_to アニメ＋フラグ管理のみに縮小。
  - `_execute_headshot`: 1 行ラッパに縮小。
  - 不要になったヘルパー削除：`_emit_v_skill_battle_msg`、`_find_character_at`。
- **unit_ai.gd**:
  - `_v_rush_slash` / `_v_whirlwind` / `_v_headshot` / `_v_sliding`: SkillExecutor 呼出＋瞬間移動のみに縮小。`_synth_v_slot()` で slot 辞書を合成。
  - 不要になったヘルパー削除：`_v_name` / `_v_tgt_name` / `_emit_v_skill_battle_msg`。

### 修正された乖離バグ
- **headshot 非免疫ターゲット処理の不一致**：旧 Player は projectile 経由で `99999` ダメージ（防御で理論的に減算される余地があった）、旧 AI は `hp=0+die()` で直接即死。SkillExecutor では両者とも「projectile は視覚のみ（damage=0）、即死は直接 `hp=0+die()`」に統一。
- **rush / whirlwind / sliding のメッセージ多重化**：Player と AI で微妙に異なる segments 構造のメッセージを個別実装していた。SkillExecutor 内の `_emit_v_skill_battle_msg` で単一フォーマットに統一。

### 決定事項
- **移動アニメの扱い**：Player は `character.move_to(pos, dur)` で滑らかに、AI は `_member.grid_pos = pos; sync_position()` で瞬間移動、というパラダイムの違いは温存。SkillExecutor は着地位置のみ計算して返し、実移動は呼出側が行う。AI キュー進行を阻害しないためこの分離が必要。
- **攻撃モーションフラグ**：`is_attacking` / `is_sliding` / `is_blocked` は Player 固有の UI ロック機構なので SkillExecutor に取り込まない。呼出側で設定・解除する。
- **ヘッドショット即死の SE**：Player の `SoundManager.play(ARROW_SHOOT)` を `play_from(ARROW_SHOOT, attacker)` に変更（空間フィルタ対応）。Player は自身が listener のため挙動同じ。

### 動作確認
- `godot --headless --check-only` でスクリプトのパース成功を確認（エラー 0 件）。
- 実機動作確認（全4クラスの V 特殊攻撃・Player/AI 一貫性・非免疫敵への即死・免疫敵への3倍ダメージ・スライディング時の無敵）は次回セッションで実施予定。

### SkillExecutor 抽出の完了サマリ
本日（2026-04-18）のセッションで、全 10 種類の特殊行動を 3 ステージ（ステージ1: heal / ステージ2: melee+ranged / ステージ3a: flame_circle+water_stun+buff / ステージ3b: rush+whirlwind+headshot+sliding）に分けて `SkillExecutor` に抽出完了。Player / AI の計算式乖離バグを構造的に解消。残りは dark-lord のキュー外処理のリファクタリングのみ（別タスク）。

## 2026-04-18（SkillExecutor 抽出・ステージ3a：flame_circle / water_stun / buff 移行）

### 変更内容
- **SkillExecutor 追加メソッド**：`scripts/skill_executor.gd` に V 特殊攻撃の複雑 3 種を追加。
  - `execute_flame_circle(caster, slot, potential_targets=[]) -> bool`: 自分中心の半径 `range` マスに炎ゾーンを設置。`damage_mult` / `duration` / `tick_interval` を slot から参照。`FlameCircle.setup` 呼出＋battle/combat ログ。
  - `execute_water_stun(caster, target, slot) -> bool`: 水弾（Projectile）を発射。`damage_mult` / `duration`（スタン秒数）を slot から参照。**Projectile の stun_duration 機能を活用し、着弾時にダメージ＋スタンを一括適用**（従来 AI 側は直接 take_damage + apply_stun を呼んで二重ダメージになっていたバグを修正）。
  - `execute_buff(caster, target, slot) -> bool`: 対象に防御バフを付与。`apply_defense_buff(duration)` 呼出＋HealEffect（cast/hit）＋combat ログ。
- **CharacterData 追加フィールド**：`v_damage_mult`（`1.0` 既定）/ `v_range`（`0` 既定）。AI 側が slots.V 辞書を保持しないため、`character_generator.gd` の味方・敵両方の生成パスで slots.V から読み込んでキャッシュする。
- **player_controller.gd**: `_execute_water_stun` / `_execute_buff` / `_execute_flame_circle` を 1 行ラッパに縮小。
- **unit_ai.gd**:
  - `"buff":` 分岐を SkillExecutor 呼出に置換。slot 辞書は `buff_cost` / `v_duration` から合成。
  - `_v_flame_circle` / `_v_water_stun` を SkillExecutor 呼出に置換。cost は呼出側で事前に支払い、SkillExecutor には `cost=0` の slot を渡して二重消費を防止。
  - ヘルパー `_synth_v_slot()` を追加（CharacterData から V スロット辞書を合成）。

### 修正された乖離バグ
- **AI 側の水魔法二重ダメージバグ**：旧 AI 実装は Projectile で damage を適用した上で、直後に `_target.take_damage(raw_damage, ...)` を呼んで二重ダメージを与えていた。SkillExecutor では Projectile の `stun_duration` 機能を使って damage と stun を着弾時に一括適用する Player 側の正しい実装に統一。
- **AI 側の flame_circle / water_stun ハードコードバグ**：旧 AI 実装は `damage_mult=0.8 / 0.5`、`radius=3`、`duration` のフォールバック 2.5 をコード内ハードコードしていた。SkillExecutor では全て slot 経由で取得し、JSON を変更すれば反映される構造に。
- **Player 側の flame_circle battle メッセージ欠落**：旧 Player 実装は combat ログのみだった。SkillExecutor 内で battle メッセージ（自然言語・segments 色分け）を追加し、MessageWindow に表示されるようにした。

### 決定事項
- **dark-lord の炎陣・ワープはスコープ外**：現状キュー外で動いているため触らない。ただし `execute_flame_circle` の引数設計（`caster: Character` + `slot: Dictionary` + `potential_targets: Array`）は汎用的にしてあり、将来 dark-lord からも呼び出せる。
- **メッセージ形式**：`execute_flame_circle` で segments 付き battle メッセージを追加。`execute_water_stun` の battle メッセージは Projectile 着弾時に `apply_stun` 内で生成されるため重複しないよう抑制（従来 Projectile 側の `suppress_battle_msg` が機能）。
- **効果音の空間フィルタ**：従来 Player は `play(...)`、AI は `play_from(...)`。`play_from` に統一（Player はリスナー自身なので常に再生）。

### 動作確認
- `godot --headless --check-only` でスクリプトのパース成功を確認（エラー 0 件）。
- 実機動作確認（Player/AI 両方の炎陣・水魔法・防御バフ、dark_priest のバフ）は次回セッションで実施予定。

## 2026-04-18（SkillExecutor 抽出・ステージ2：melee / ranged 移行）

### 変更内容
- **SkillExecutor 追加メソッド**：`scripts/skill_executor.gd` に `execute_melee(attacker, target, slot) -> bool` と `execute_ranged(attacker, target, slot, opts={}) -> bool` を追加。
  - `execute_melee`: `power × ATTACK_TYPE_MULT[melee] × damage_mult` でダメージ算出。`face_toward` + `play_attack_from` + `take_damage` + `play_hit_from`。
  - `execute_ranged`: `power × ATTACK_TYPE_MULT[ranged] × damage_mult` でダメージ算出。`face_toward` + `play_attack_from` + `_spawn_projectile`。
  - `opts["is_water"]`: Lich の火/水交互切替用オーバーライド。省略時は `class_id == "magician-water"` で自動判定。
  - `projectile_type`（demon の `thunder_bullet` 等）は `character_data.projectile_type` から自動取得。
- **player_controller.gd**: `_execute_melee` / `_execute_ranged` を 1 行ラッパに縮小（`SkillExecutor.execute_melee / execute_ranged` 呼出のみ）。
- **unit_ai.gd**: `_execute_attack` 内の `"ranged"` / `"magic"` / melee（default）分岐を SkillExecutor 呼出に置き換え。新ヘルパー `_synth_z_slot(atype)` で CharacterData のフラットフィールドから slot 辞書を合成（`damage_mult` / `type` / `cost`）。Lich は `opts["is_water"] = _get_is_water_shot()` で交互切替を維持。
- **dive（降下攻撃）はステージ2 対象外**。UnitAI 側でハーピーの降下攻撃ロジック（`take_damage` + `_spawn_dive_effect`）はそのまま維持。

### 修正された乖離バグ
- **AI 側の `damage_mult` 未適用**：Player は `slot.damage_mult` を掛けていたが、AI 側は Z 通常攻撃で常に 1.0 扱いだった。両クラス JSON の Z スロットが `damage_mult: 1.0` を明示しているため現状は値一致しているが、将来 Z スロット倍率を変更した際に Player / AI で乖離する構造を排除。
- **AI 側の magician-water 水弾未判定**：Player は `class_id == "magician-water"` で水弾を出していたが、AI 側の基底 `_get_is_water_shot()` は false を返すため、AI 操作の水魔法使いは火弾の画像で発射されていた。SkillExecutor 側で class_id 自動判定に統一して解消。
- **Player 側の `projectile_type` 未参照**：Player の `_spawn_projectile` は `projectile_type` を渡していなかった（プレイヤーは demon でないため実害なし）。SkillExecutor で統一的に `character_data.projectile_type` を渡すよう改修。

### 決定事項
- **効果音**：`play_attack_from` / `play_hit_from`（空間フィルタあり）に統一。Player は常にリスナー自身なので `_is_audible` が常に true を返すため従来の `play_attack` / `play_hit` と等価。
- **slot 合成（AI 側）**：クラス JSON の slots.Z を保持しないため、CharacterData から `z_damage_mult` と `attack_type` → `type` 変換で最小限の slot 辞書を作る。コストは 0（Lich は `_on_after_attack` で MP 消費するため SkillExecutor 内コスト消費とは独立）。
- **debug print 削除**：Player 側の `print("[Player] %s → %s ...")` は削除（load-bearing でない）。

### 動作確認
- `godot --headless --check-only` でスクリプトのパース成功を確認（エラー 0 件）。
- 実機動作確認（全クラスの Z 攻撃・同条件での Player/AI ダメージ一貫性・飛翔体生成）は次回セッションで実施予定。

## 2026-04-18（SkillExecutor 抽出・ステージ1：heal 移行）

### 背景
- Player / AI で同じ特殊行動（heal / melee / ranged / V 攻撃各種）の計算式が二重実装されており、乖離バグが本セッションで連続発覚（AI ヒーラーの `heal_mult` 未適用、`water_stun` / `flame_circle` / `buff_defense` のハードコード等）。
- CLAUDE.md に「AI と実処理の責務分離方針」セクションを追加し、SkillExecutor クラス抽出方針を明文化。

### 変更内容
- **新規ファイル**: `scripts/skill_executor.gd` を作成。`class_name SkillExecutor extends RefCounted` の static メソッド集約クラス。
- `SkillExecutor.execute_heal(caster, target, slot) -> HealResult` を実装。Player 側 `_execute_heal` / AI 側 `"heal":` 分岐の計算式を統合：
  - エネルギー消費（`_slot_cost` で `cost` / `mp_cost` / `sp_cost` フォールバック）
  - `face_toward` + キャスト側 `spawn_heal_effect("cast")`
  - アンデッド特効（`target.is_undead && 敵対陣営`）: `power × ATTACK_TYPE_MULT[magic] × damage_mult` で魔法ダメージ適用 + `MessageLog.add_combat` で特効ログ
  - 通常回復: `power × heal_mult` で回復量算出 + `target.heal()` + `target.log_heal()`
  - 戻り値 `HealResult` enum（FAILED / HEALED / UNDEAD_DAMAGED）で呼び出し元が分岐可能
- **player_controller.gd**: `_execute_heal` を 6 行に縮小。`SkillExecutor.execute_heal` を呼び、`HEALED` 結果かつ対象が未加入 NPC の場合のみ `healed_npc_member` シグナルを発火する責務に限定。
- **unit_ai.gd**: `"heal":` 分岐を縮小。CharacterData から slot 辞書（`cost` / `heal_mult` / `damage_mult`）を合成して `SkillExecutor.execute_heal` に渡す。WAITING 状態への遷移は呼び出し元責務として維持。
- **CLAUDE.md**: 「実処理の共通化」セクションを「推奨・未実装」→「段階移行中」に更新。進捗表（heal ✅ / 残り 9 種類 ⏳）を追加。要調査項目の「Player 側と AI 側の計算ロジック統一」エントリも進捗表付きで更新。

### 決定事項
- **slot 辞書の扱い**: AI 側はクラス JSON の `slots.Z` を保持しないため、CharacterData のフラット化フィールド（`z_heal_mult` / `z_damage_mult` / `heal_cost`）から合成する。Player 側は既存の `_slot_z` をそのまま渡す。
- **シグナル責務**: `healed_npc_member` は UI 固有（game_map の `_on_npc_healed` が購読）なので SkillExecutor には移さず、PlayerController に残す。`HealResult.HEALED` のときだけ発火（アンデッド特効時は除外）。
- **use_energy 挙動**: SkillExecutor では「失敗したら何もせず false を返す」防御的な挙動を採用。Player 側は事前に `_enter_pre_delay` でエネルギーチェック済みのため安全。AI 側も従来どおりの防御的な挙動と整合。

### 動作確認
- `godot --headless --check-only` でスクリプトのパース成功を確認（エラー 0 件）。
- 実機動作確認（Player ヒーラーの Z 回復 / AI ヒーラーの Z 回復 / アンデッドへのダメージ）は次回セッションで実施予定。

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

## 攻撃クールダウン全面見直し（2026-04-17）

### 背景
pre_delay / post_delay 周りの調査で以下の問題が判明：
- 通常攻撃の pre_delay が長く、攻撃ボタンを押してから射程表示までワンテンポ遅れる
- pre_delay 中に敵が動いて照準が定まりにくい体感
- プレイヤーはスロット単位（`slots.Z` / `slots.V`）、AI はクラス JSON のトップレベル `pre_delay` / `post_delay` を見ており、一部クラス（archer / magician-fire / magician-water / healer / scout）で値がズレていた
- V スロット特殊攻撃の AI 側はハードコード固定値（`_timer = 0.3` / `0.5` 等）で、JSON のスロット V 値を無視していた
- pre_delay / post_delay だけ `game_speed` の影響を受けず、2倍速にしても攻撃テンポが変わらなかった

### 変更方針
仕様を「味方はスロット単位・敵はトップレベル」に一元化し、プレイヤーと AI が同じ値を参照する設計に統一。射程オーバーレイは PRE_DELAY 中から表示し、押下直後のレスポンス感を確保。game_speed を pre/post_delay にも適用して移動系と整合。

### 数値変更
全7クラスの通常攻撃（スロット Z）と特殊攻撃（スロット V）の pre_delay / post_delay を短縮方向に再設定。通常攻撃は 0.05〜0.20 / 0.20〜0.45、特殊攻撃は 0.15〜0.60 / 0.40〜0.70 のレンジで「通常はテンポ良く、特殊は少し『ため』」を実現。詳細値は docs/spec.md 参照。

### 実装変更
- 全7クラス JSON のトップレベル `pre_delay` / `post_delay` を削除。slots.Z / slots.V に値を設定
- `CharacterData` に `z_pre_delay` / `z_post_delay` / `v_pre_delay` / `v_post_delay` フィールドと対応する getter を追加
- `CharacterGenerator._build_data()` が slots.Z / slots.V から pre_delay / post_delay を読み込んで CharacterData に設定
- `UnitAI._start_action` の `"attack"` で `_member.character_data.pre_delay` 参照を `get_z_pre_delay()` に変更
- `UnitAI._start_action` の `"v_attack"` を即時実行から ATTACKING_PRE 経由に変更（`_timer = get_v_pre_delay()` → `_execute_v_attack()` → ATTACKING_POST）
- `ATTACKING_PRE` ハンドラ内で `_current_action.action` をチェックして通常攻撃／特殊攻撃を分岐。POST 遷移時に対応する post_delay を適用
- 各 `_v_*` メソッド（`_v_rush_slash` / `_v_whirlwind` / `_v_headshot` / `_v_flame_circle` / `_v_water_stun` / `_v_sliding`）末尾のハードコード `_state = WAITING / _timer = 0.3〜0.5` 行を削除
- ヒーラー `heal` / `buff` のタイマーを `get_z_post_delay()` / `get_v_post_delay()` 参照に変更（buff は V スロット相当）
- `game_map._draw` の射程オーバーレイ判定を `is_targeting()` → `is_in_attack_windup()`（新設）に変更。PRE_DELAY 中から射程が見える
- `PlayerController._process_pre_delay` / `_process_post_delay` および `UnitAI` の `_timer -= delta` を `delta * game_speed` に変更（MOVING / WAITING / ATTACKING_PRE / ATTACKING_POST すべて）
- pre-scaled だった `_timer = WAIT_DURATION / game_speed` と MOVING 継続時の `_timer = _get_move_interval()` を raw 値（`WAIT_DURATION` / `MOVE_INTERVAL`）に変更。カウントダウン側で game_speed を掛ける統一仕様に

## HP状態ラベルの色・点滅統一（2026-04-17）

### 背景
調査の結果、以下の問題が判明：
- スプライト・アイコン系と HP ゲージ・状態ラベル文字系で色体系がズレていた（前者は3色モデル：白／橙／赤+点滅。後者は4色モデル：緑／黄／橙／赤。wounded/injured の境界が1段ずれていた）
- 点滅は critical のスプライト・アイコンにしか適用されておらず、操作キャラの HP 減少に気付きにくかった
- 色定数が `GlobalConstants` に集約されておらず、複数ファイル（`character.gd` / `left_panel.gd` / `right_panel.gd` / `dialogue_window.gd` / `debug_window.gd`）に同種の色マッチ文が手書きコピペされていた

### 変更方針
- 全要素で同じ 4 段階状態ラベル（healthy / wounded / injured / critical）に統一
- 色定数を `GlobalConstants` に集約（SPRITE / GAUGE / TEXT の3パレット・計12定数 + 点滅Hz）
- ヘルパー関数 `condition_sprite_modulate` / `condition_sprite_color` / `condition_gauge_color` / `condition_text_color` / `ratio_to_condition` を追加し、各 UI ファイルはこれらを呼ぶだけに統一
- 点滅は wounded / injured / critical の 3 段階に拡張（旧：critical のみ）。3Hz 一律
- 点滅対象はスプライト・顔アイコンのみ。HP ゲージ・状態ラベル文字・DebugWindow は静的色

### 色の微調整
- スプライト wounded/injured の色境界を1段ずらした：旧「wounded=橙 / injured=赤」→ 新「wounded=黄 / injured=橙 / critical=赤」
- ゲージ critical の赤を `(0.90, 0.20, 0.20)` に統一（旧 spritepath の `(1.0, 0.15, 0.15)` 暗赤は点滅用 ×0.7 計算に置き換え）
- DebugWindow の healthy を `(0.85, 0.85, 0.85)` 灰白 → `Color.WHITE` に
- DebugWindow の wounded を `(1.0, 1.0, 0.3)` 明黄 → `(1.00, 0.85, 0.20)` に統一（SPRITE パレット流用）

### 実装変更
- `scripts/global_constants.gd` に色定数12個 + `CONDITION_PULSE_HZ = 3.0` + ヘルパー6関数を追加
- `character.gd._update_modulate` の HP 状態色分岐（7行）を削除し `GlobalConstants.condition_sprite_modulate(get_condition())` の1行に
- `left_panel.gd._draw_bar` の HPゲージ色分岐を `condition_gauge_color(ratio_to_condition(ratio))` で置換
- `left_panel.gd._hp_modulate` を簡略化（`condition_sprite_modulate` を返すだけ）
- `left_panel.gd._condition_text_color` を `condition_text_color` のラッパーに短縮（既存呼び出し元の互換保持）
- `right_panel.gd._hp_modulate` も同様にリファクタ
- `right_panel.gd` と `dialogue_window.gd` のインラインコピペ（状態テキスト色 match）を `GlobalConstants.condition_text_color(cond)` 1行で置換
- `debug_window.gd` の HP 色分岐2箇所を共通関数 `_hp_color_for(ch)` に統合（内部で `condition_sprite_color` を呼ぶ）

## Config Editor 実装（2026-04-17）

### 背景
ゲームバランス調整のためにゲーム内から定数を編集できるツールを導入。
最終的に 100 個規模になる見込みだが、まずは 5 定数でワークフロー全体が成立するか検証（Phase A）してから本実装に進む方針。

### Phase A：プロトタイプ（5定数・commit b267342）
- 対象定数（`const` → `var` へ変換）：
  - `CONDITION_WOUNDED_THRESHOLD` / `CONDITION_PULSE_HZ` / `CONDITION_COLOR_SPRITE_WOUNDED` / `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` / `PARTY_FLEE_ALIVE_RATIO`
- 追加ファイル：
  - `assets/master/config/constants.json`（ユーザー値）・`constants_default.json`（デフォルト＋メタ情報）
  - `scenes/config_editor.tscn`・`scripts/config_editor.gd`
- `GlobalConstants._ready()` で `_load_constants()` を呼び、起動時に外部 JSON から値を代入
- F4 キーで開閉、タイトル画面・ゲーム中の両方で動作
- `save_constants()` / `reset_to_defaults()` / `commit_as_defaults()` の3操作を提供
- 読み込み失敗時は `last_config_error` にメッセージ記録・UI に赤字表示

### タブ機能拡張（commit 62347b0）
- プロトタイプはフラットな行リストだったが、将来の 100 定数規模を見据えて `TabContainer` 化
- 7 タブ（Character / UnitAI / PartyLeader / NpcLeaderAI / Healer / PlayerController / EnemyLeaderAI）+ Unknown タブを表示
- `constants_default.json` の `category` フィールドでタブに振り分け
- 既存5定数のカテゴリを再設定（HP状態 / 戦闘 / AI → Character / UnitAI / PartyLeader）
- 未登録カテゴリの定数は Unknown タブに自動振り分け（`push_warning`）
- 空タブには「このカテゴリには定数がまだ登録されていません。」のプレースホルダー
- タブ名末尾の ` ●` インジケータでそのタブ内に非デフォルト値があることを表示
- Ctrl+Tab / Ctrl+Shift+Tab / Ctrl+PageUp / Ctrl+PageDown でタブ循環
- ゲーム中 F4 の他 UI ガード（OrderWindow / PauseMenu / DebugWindow / NpcDialogueWindow 表示中は無視）

### バグ修正
- **デフォルト列に `%.4g` が literal 表示される**：GDScript の `%` フォーマットは `%g` 未対応。`%.4f` で丸めて末尾ゼロを削る `_format_number()` を新設し、整数扱いなら `"3"` 形式、小数なら `"0.35"` 形式で返すように修正
- **ゲーム中 F4 が即座に自己 close される**：`game_map._input` の KEY_F4 処理後に `set_input_as_handled()` を呼ばなかったため、同じ F4 イベントが `config_editor._unhandled_input` に伝搬して `visible=true` 直後に `close()` が呼ばれていた。`get_viewport().set_input_as_handled()` を追加して伝搬を遮断

### Phase B - ステータスタブ（class_stats.json / attribute_stats.json 編集）
- トップタブ「ステータス」のサブタブ 2 つを本実装
- クラスステータス：行 = ステータス / 列 = クラス、各セルに base + rank の LineEdit 2 つ横並び。ヘッダー 2 段（クラス名 + base/rank 小ヘッダー）
- 属性補正：上段に 8 列（sex/age/build）の横断表、下段に 1 列 random_max 表
- 型変換・書き戻しは味方クラスタブと同じ仕組み（`_coerce_class_value` 流用、`sort_keys=false` でキー順保持）
- 「新ステータス追加」は Config Editor 外の作業（CharacterData 等コード変更を伴うため別タスク）
- デフォルト復帰機能は無効化（デフォルト値を保持しない方針）

### Phase B：味方クラス横断編集
- トップレベル TabContainer を「定数 / 味方クラス / 敵 / ステータス / アイテム」の 5 タブ構造に拡張
- 「味方クラス」タブで 7 クラス JSON（`assets/master/classes/*.json`）を横断表で編集できる実装を追加
  - `_load_class_files()`：ConfigEditor 初期化時に 7 ファイルをパースして `_class_data[class_id]` に保持
  - `_flatten_class()`：`slots.Z.*` / `slots.V.*` を `Z_*` / `V_*` に平坦化して表示用 Dict を生成
  - `_save_class_files()`：変更されたクラスのみ `JSON.stringify(data, "  ", false)` で書き戻し
  - `_coerce_class_value()`：元 JSON の値の型（bool / int / float / string）に合わせて変換。変換失敗時は保存中止・警告
- `CLASS_PARAM_GROUPS` 配列でパラメータのグループ分け（基本/リソース/特性/Zスロット/Vスロット）。未分類は「その他」グループに自動集約＋警告
- 下部ボタンを上段タブに応じて有効/無効切替：定数タブは全ボタン有効・味方クラスタブは保存のみ・その他はすべて無効
- **重要**：Godot 4 の `JSON.stringify` デフォルトは `sort_keys=true`（キーをアルファベット順にソート）。クラス JSON のキー順を保持するため `sort_keys=false` を明示指定。同じ理由で `GlobalConstants.save_constants()` / `commit_as_defaults()` にも `false` を追加
- 「すべてデフォルトに戻す」「現在値をすべてデフォルト化」は味方クラスタブでは無効化（デフォルト値を保持しない方針・復帰は git 履歴で管理）

## 敵データの構造整理（2026-04-17）

### 背景
将来の Config Editor「敵クラス」タブ実装に向けた下準備。
- 旧実装では個別敵 JSON（`goblin.json` 等）に `attack_type` / `pre_delay` / `post_delay` / `attack_range` などの「クラスで決まる項目」が書かれており、同じ fighter-axe クラスを使うゴブリンとホブゴブリンで異なる値を持てる状態だった
- 人間クラス JSON（`classes/fighter-sword.json` 等）はこれらをクラス単位で定義しており、敵側と対称性がない
- 敵固有 5 クラス（zombie / wolf / salamander / harpy / dark-lord）のクラス JSON が存在しない

### 変更方針
人間クラスと敵クラスの構造を対称に揃える：
- 敵固有 5 クラスのクラス JSON を `assets/master/classes/` に新規作成
- 個別敵 JSON からクラス項目を除去
- `CharacterGenerator.apply_enemy_stats()` でクラス JSON を読んで `CharacterData` に注入

### 新規作成（5 クラス JSON）
- `classes/zombie.json` / `wolf.json` / `salamander.json` / `harpy.json` / `dark-lord.json`
- 構造は人間クラスと同じ（`id` / `name` / `weapon_type` / `base_defense` / `attack_type` / `attack_range` / `is_flying` / `behavior_description` / `slots.Z` / `slots.V`）
- slots.V は全て null（敵固有クラスは特殊攻撃スロットを持たない。dark-lord のワープ・炎陣は `dark_lord_unit_ai.gd` 側の AI 実装）

### 個別敵 JSON から除去（16 ファイル）
- 全敵：`attack_type` / `attack_range` / `pre_delay` / `post_delay`
- dark-priest のみ：`heal_mp_cost` / `buff_mp_cost`（healer クラス経由で自動適用）
- `projectile_type`（demon のみ）は個別 JSON に残す（共用の magician-fire クラスでは指定できない個体値）

### `healer.json` の正規化
- top-level の `heal_mp_cost` / `buff_mp_cost` を削除
- `slots.Z.mp_cost`（action="heal"）と `slots.V.mp_cost`（action="buff_defense"）を唯一の真実源に
- `CharacterGenerator._build_data` と `apply_enemy_stats` で slot action を見て `heal_mp_cost` / `buff_mp_cost` を設定

### `CharacterGenerator` の変更
- `_build_data`（味方）：top-level `heal_mp_cost` / `buff_mp_cost` の読み込みを削除し、slots.Z.mp_cost / slots.V.mp_cost から action 条件付きで取得する方式に
- `apply_enemy_stats`（敵）：既存の stats 計算後に `_load_class_json(stat_type)` を呼び、`attack_type` / `attack_range` / `slots.Z/V` 由来値（pre_delay / post_delay / mp_cost）を `CharacterData` に注入

### 副次的な挙動変更
- **dark-priest の攻撃**：旧 `attack_type="magic"` → クラス healer 経由で `attack_type="heal"` に。純粋ヒーラー化し、非アンデッド対象には攻撃しなくなる（`_execute_attack` の `atype=="heal"` 分岐でアンデッド以外は早期 return）
- **敵の攻撃クールダウン**：同一クラスを流用する敵は同一の Z スロット pre/post_delay 値を使うようになる。goblin と hobgoblin は両者ともに fighter-axe の 0.20 / 0.45 に統一

### 確認済み
- Godot `--check-only` / `--quit` とも EXIT: 0
- すべての敵 JSON から対象 4 フィールド（attack_type / attack_range / pre_delay / post_delay）の削除完了（grep で 0 件）
- healer.json / dark-priest.json から heal_mp_cost / buff_mp_cost の削除完了（grep で 0 件）

## Config Editor の不具合 3 件修正（2026-04-18）

### バグ修正: 「敵一覧」タブでチェックボックス変更時に行ハイライトが付かない
- 症状: is_flying / is_undead / instant_death_immune のチェックボックスを ON/OFF しても、その行が薄黄色ハイライトされない（LineEdit の変更では正しくハイライトされる）
- 原因: `_add_enemy_checkbox()` は CheckBox を単純な Control でラップするだけで `_enemy_cell_styles` に StyleBoxFlat を登録していなかった。また `_on_enemy_indiv_field_changed()` ハンドラも dirty フラグ更新のみで視覚フィードバック処理がなかった
- 修正:
  - `_add_enemy_checkbox()` を PanelContainer + CenterContainer 構成に変更し、`_make_cell_style()` で生成した StyleBoxFlat を wrapper に `add_theme_stylebox_override("panel", sb)` でアタッチ。`_enemy_cell_styles[wk] = sb` に登録
  - `_on_enemy_indiv_field_changed()` を更新。元値（`_enemy_indiv_data[eid].get(field, false)`）と比較して `sb.bg_color` を `HIGHLIGHT_BG_COLOR` / `Color(0.12, 0.12, 0.16)` に切り替え
  - 保存時の `_clear_enemy_cell_highlights()` は既に全 `_enemy_cell_styles` を走査するため、チェックボックスの style も自動でクリアされる
- 元 JSON に is_flying フィールドがなかった場合: `_apply_enemy_indiv_edits()` の既存ロジック（line 1295-1296）が「cur_val == false and not orig_had」の場合にフィールド追加をスキップするため、CLAUDE.md 545行目のルールは引き続き守られる

### 機能追加: 「敵一覧」トップタブ名末尾の ● インジケータ
- 追加: `_update_enemy_list_tab_indicator()` / `_find_top_tab_index()` を新設
- `_enemy_list_dirty` または `_enemy_indiv_dirty` に true があれば「敵一覧」トップタブ名の末尾に " ●" を付加
- 敵一覧タブの全変更ハンドラ（5 つ）と `_save_enemy_list_tab()` から呼び出し
- 副次的な修正: `_current_top_tab_name()` が末尾の " ●" を除去してから純粋なタブ識別名を返すよう変更（下部ボタンの有効判定で TOP_TAB_ENEMY_LIST と比較失敗を防ぐ）

### バグ修正: 「すべてデフォルトに戻す」「現在値をすべてデフォルト化」ボタンが効かない
- 症状 A: 「敵一覧」タブなど定数タブ以外では、両ボタンが常に disabled で押せない状態
- 症状 B: 定数タブで押した場合でも、ConfirmationDialog が表示されず動作しない（CanvasLayer の子として Window サブウィンドウを add_child すると表示が不安定になる環境依存の挙動）
- 原因 A: `_on_top_tab_changed()` で `_btn_reset.disabled = not is_constants` / `_btn_commit.disabled = not is_constants` と定数タブ以外で常時無効化していた
- 原因 B: `add_child(dlg)` が CanvasLayer 直下に Window を追加しており、`popup_centered()` のサイズ指定もなかったため初期サイズ不定で非表示状態になるケースがあった
- 修正:
  - ボタンを常時有効（`_btn_reset.disabled = false` / `_btn_commit.disabled = false`）に変更。作用対象は定数タブの SpinBox / ColorPicker のみだが、どのタブからでも操作できるように
  - ConfirmationDialog の親を `get_tree().root.add_child(dlg)`（メイン Viewport）に変更し、`popup_centered(Vector2i(480, 180))` / `popup_centered(Vector2i(480, 200))` で明示的なサイズを指定
  - `dlg.close_requested.connect(dlg.queue_free)` を追加（X ボタンでも確実に解放されるように）
- 動作: 定数タブで値変更 → 「すべてデフォルトに戻す」→ 確認ダイアログ OK → `GlobalConstants.reset_to_defaults()` が constants_default.json を読み直して全定数をリセット → `_refresh_all()` で全 SpinBox / ColorPicker が更新されハイライトも解除される

### バグ修正追補: 「敵一覧」タブでリセットを押してもデフォルト値に戻らない
- 症状: 敵一覧タブで値を変更してから「すべてデフォルトに戻す」ボタンを押しても、確認ダイアログは出るが値が元に戻らない
- 原因: 前回修正ではボタンを有効化したものの、リセット処理自体は `GlobalConstants.reset_to_defaults()`（定数タブ専用）を呼ぶだけで、敵一覧タブの値は何も変わらなかった
- 修正方針: リセットボタンをタブ別動作に変更（「すべて」の意味をタブ内の全フィールドに限定）
  - 定数タブ: 従来通り `GlobalConstants.reset_to_defaults()` + `_refresh_all()`
  - 敵一覧タブ: 新設 `_reset_enemy_list_tab()` が `_load_enemy_list_files()` で JSON を再読込し、16 敵×9 種類のウィジェットをすべて元値に戻す
  - 味方クラス / 敵クラス / ステータスタブ: 未実装の警告ステータスを表示（将来実装予定）
  - それ以外（アイテムタブ等）: 「このタブではリセット操作はありません」ステータス表示
- 「現在値をすべてデフォルト化」も定数タブ専用と明確化（他タブでは警告のみ）
- 実装:
  - `_reset_enemy_list_tab()`: JSON 再読込 → rank/stat_type（OptionButton）、bool 3 フィールド（CheckBox、`set_pressed_no_signal` で toggled 非発火）、LineEdit 3 フィールド、stat_bonus 6 スロットを全敵について元値に設定 → `_clear_enemy_cell_highlights()` → `_update_enemy_list_tab_indicator()`
  - `_select_option_by_text()` ヘルパを新設（`OptionButton.select()` は item_selected を発火しないことを利用）
  - `_on_reset_pressed()` / `_on_reset_confirmed()` を `match top` でタブ別分岐に変更。ダイアログ文言もタブ別に切替
  - `_on_commit_pressed()` 冒頭に定数タブ以外の早期 return を追加
- 注意点: CheckBox の `button_pressed` プロパティ代入は `toggled` シグナルを発火するため、代入ではなく `set_pressed_no_signal()` を使う。LineEdit の `.text` 代入・OptionButton の `.select()` は Godot 4 ではシグナル非発火のためそのまま代入でよい

### 仕様変更: 「現在値をすべてデフォルト化」を全タブで使えるようにする
- 背景: 前回修正で「現在値をすべてデフォルト化」ボタンを定数タブ専用にしていたが、他のタブでも押せるようにしたいという要望
- 実装方針: タブごとに意味合いを分けて動作させる
  - 定数タブ: 従来通り `GlobalConstants.commit_as_defaults()` で constants_default.json の value フィールドに書き戻し（constants.json とは別ファイル）
  - 味方クラス / 敵クラス / 敵一覧 / ステータスタブ: 対応する `_save_*` 関数を呼び出してディスクに書き戻し（他タブには専用の「デフォルトファイル」が存在せず、ソース JSON 自体が真実なので、動作としては通常の保存と同じ）
  - アイテムタブなど対象外: 警告ステータスのみ
- UI: ダイアログ文言をタブごとに切替。非定数タブでは「専用のデフォルトファイルはないため、通常の保存と同じ動作です」と明示
- 新設ヘルパー: `_report_commit_save_result()` が `{"saved": Array, "errors": Array}` 形式の保存結果をステータスラベル表示に変換（既存 `_on_save_pressed` 内で重複していたロジックを切り出し）

## Config Editor 定数タブの再編（2026-04-18）

### 背景・設計意図
定数タブのカテゴリが「実装ファイル別」に分かれていたが、実際には同じ概念が複数ファイルで参照されるケースが多く、粒度がバラついていた。また「Healer」カテゴリは定数 1 個のためタブとしてほぼ空の存在になっていた。

方針：
- **タブは陣営・階層（リーダー層 → 個体層）で再編**し、実装ファイル名ではなく概念の住所で分類する
- **AI 判断基準は戦況判断に一元化**する方向へ向かう。別系統の判定ロジック（NPC_HP/ENERGY_THRESHOLD のような独立閾値）は削除し、戦況判断が返す指標を参照する形に揃える

### 新規定数追加
- `SPECIAL_ATTACK_FIRE_ZONE_RANGE = 2`（UnitAI・int・min 0 max 5）：炎陣の発動判定範囲（自分中心の半径マス数）
- `SPECIAL_ATTACK_FIRE_ZONE_MIN_ENEMIES = 2`（UnitAI・int・min 1 max 10）：炎陣の発動に必要な範囲内の敵数

### magician-fire の発動判定ロジック変更
- 旧：`SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES`（隣接8マスの敵数）で判定
- 新：`SPECIAL_ATTACK_FIRE_ZONE_RANGE` 半径内の敵数が `SPECIAL_ATTACK_FIRE_ZONE_MIN_ENEMIES` 以上
- 理由：炎陣は自分中心の範囲攻撃であり、「隣接 8 マス」より「範囲内の敵密度」で判定したほうが AI 仕様として自然
- `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` は近接3クラス（fighter-sword / fighter-axe / scout）専用に用途を限定
- 新ヘルパー `_count_enemies_in_range(range_tiles)` を追加（チェビシェフ距離ベースで同フロア敵を数える）

### カテゴリ変更（4 定数）
| 定数 | 旧 | 新 |
|---|---|---|
| `NEAR_DEATH_THRESHOLD` | PartyLeader | UnitAI |
| `HEALER_HEAL_THRESHOLD` | Healer | UnitAI |
| `POTION_SP_MP_AUTOUSE_THRESHOLD` | PlayerController | UnitAI |
| `PARTY_FLEE_ALIVE_RATIO` | PartyLeader | EnemyLeaderAI |

参照元はすべて UnitAI または EnemyLeaderAI に属するため、実態と合わせた形に修正。

### 定数廃止（2 個）
- `NPC_HP_THRESHOLD`（0.5）
- `NPC_ENERGY_THRESHOLD`（0.3）

これに伴い `NpcLeaderAI._get_target_floor()` のフロア遷移補正ロジックを変更：
- 旧：最低 HP 率 < NPC_HP_THRESHOLD または 平均エネルギー率 < NPC_ENERGY_THRESHOLD → 適正フロア -1
- 新：パーティー平均 HP 率（`_calc_hp_status_for` と同じ式・ポーション込み）< `HP_STATUS_STABLE` (0.5) → 適正フロア -1
- エネルギー判定は削除（戦況判断拡張で後日検討）
- 新ヘルパー `_calc_party_hp_ratio()` を追加（HpStatus の raw ratio を返す）
- 未使用となった `_calc_recoverable_energy()` を削除

### description 修正
`COMBAT_RATIO_*` 4 定数の説明文を「自軍/敵軍戦力比」→「戦況（ランク和×HP充足率の比）」に修正。`PartyLeader._evaluate_combat_situation()` の実装と一致させる。

### Config Editor タブ構成変更
旧：Character / UnitAI / PartyLeader / NpcLeaderAI / Healer / PlayerController / EnemyLeaderAI / Unknown（7+Unknown）
新：Character / PartyLeader / NpcLeaderAI / EnemyLeaderAI / UnitAI / Unknown（5+Unknown）

- **削除**：Healer タブ（定数 1 個だったため UnitAI に吸収）、PlayerController タブ（定数 1 個だったため UnitAI に吸収）
- **順序変更**：実装ファイル順 → 陣営・階層順（Character → リーダー層 → 個体層）
- **NpcLeaderAI タブは空のまま残す**：将来の NPC 固有定数追加用プレースホルダー（仕様通り `_build_tab` のプレースホルダー Label で「このカテゴリには定数がまだ登録されていません。」と表示される）

### 定数配分（再編後）
- Character: 16 個（変更なし）
- PartyLeader: 11 個（COMBAT_RATIO ×4 / POWER_BALANCE ×4 / HP_STATUS ×3）
- NpcLeaderAI: 0 個（プレースホルダー）
- EnemyLeaderAI: 1 個（PARTY_FLEE_ALIVE_RATIO）
- UnitAI: 7 個（SELF_FLEE_HP_THRESHOLD / SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES / SPECIAL_ATTACK_FIRE_ZONE_RANGE / SPECIAL_ATTACK_FIRE_ZONE_MIN_ENEMIES / NEAR_DEATH_THRESHOLD / HEALER_HEAL_THRESHOLD / POTION_SP_MP_AUTOUSE_THRESHOLD）
- 合計 35 個

### CONFIG_KEYS 配列
`GlobalConstants.CONFIG_KEYS` の並び順を新カテゴリ順に並べ直し。これにより `constants.json` 書き出し時のキー順も変わる（sort_keys=false なので保証される順序）。

## base_defense / defense フィールドを廃止（2026-04-18）

### 背景
`docs/investigation_base_defense.md` の調査で、`base_defense`（味方クラス JSON）と `defense`（個別敵 JSON）が CLAUDE.md のダメージ計算フロー仕様に載っていない平ダメージカット処理として動作していることが判明。CLAUDE.md の仕様（防御強度 → 耐性の 2 段階）を正とし、実装側を整合させる方針。味方全員 `base_defense=0` でテスト済み・影響が小さいことを確認。バランス微調整は後日まとめて行う。

### JSON 変更
- `assets/master/classes/*.json` 全 12 ファイル（味方 7 ＋ 敵固有 5）から `base_defense` フィールドを削除
- `assets/master/enemies/*.json` 全 16 ファイルから `defense` フィールドを削除
- キー順・インデント・末尾改行は保持。副作用として一部の小数（例：`0.10` → `0.1`）が Python の JSON 正規化で表記変更（値は同一）

### コード変更
- `CharacterData.defense` フィールドを削除（[character_data.gd:38](scripts/character_data.gd#L38)）
- `CharacterData.load_from_json` の `data.defense = ...` 行を削除（[character_data.gd:161](scripts/character_data.gd#L161)）
- `CharacterGenerator.generate()` の `data.defense = int(class_json.get("base_defense", 3))` 行を削除（[character_generator.gd:113](scripts/character_generator.gd#L113)）
- `Character.defense` フィールド削除（[character.gd:46](scripts/character.gd#L46)）
- `Character._read_character_data()` の `defense = character_data.defense` 行を削除（[character.gd:271](scripts/character.gd#L271)）
- `Character.get_effective_defense()` 関数を削除
- `Character.DEFENSE_BUFF_BONUS` 定数（=3）を削除
- `Character.take_damage()` のダメージ計算を `raw_after_mult - get_effective_defense() - blocked` → `raw_after_mult - blocked` に変更
- `is_fully_blocked` の判定式も同様に簡素化
- `Character._log_damage()` のデバッグ文字列から `get_effective_defense()` 減算を撤去
- `Config Editor` の `CLASS_PARAM_GROUPS`「リソース」グループから `base_defense` を削除

### 副次的影響：防御バフ（healer V スロット）
- `apply_defense_buff()` / `defense_buff_timer` / `DEFENSE_BUFF_DURATION` は保持（バリアエフェクトの視覚表現は継続）
- しかし `get_effective_defense()` 撤去により **numeric な効果は一旦失われる**（バリアエフェクト表示のみ）
- バランス微調整時に物理耐性／防御強度への再割り当てを検討すること（`character.gd:84-86` に TODO コメント記載）

### CLAUDE.md 整理
- 「要調査・要整理項目」セクションから「legacy フィールドの棚卸し」の `base_defense` 言及を削除（廃止完了のため）
- ダメージ計算フロー仕様セクションは元々 `defense` を記載していなかったので変更不要（実装が仕様に追いついた形）

### 確認
- Godot `--check-only` exit 0、パースエラーなし
- `grep -n "\.defense\b" scripts/` で残存ヒットなし（battle_policy 文字列の `"defense"` のみ）

## クラス JSON / 敵 JSON から mp / max_sp フィールドを廃止（2026-04-18）

### 背景
`docs/investigation_mp_max_sp_divergence.md` の調査で、味方クラス JSON の `mp` / `max_sp` フィールドはコードから一切参照されない完全な legacy と判明（パターン A）。CLAUDE.md 450-452 行は既に「廃止（energy で代替）」と記述しており、JSON 側の物理削除が漏れていただけ。Phase 12-15 で移行宣言済みだが削除忘れ。

### ランタイムの実際の経路
- **味方・NPC**: `CharacterGenerator.generate()` が `class_stats.json` の `energy` から `data.max_mp`（魔法クラス）または `data.max_sp`（非魔法クラス）を設定
- **敵**: `CharacterData.load_from_json` で JSON の `"mp"` を読んでいたが、直後の `apply_enemy_stats()` が `max_mp = 0` / `max_sp = stats.energy` で上書きするため未使用

### JSON 変更
- `assets/master/classes/` 味方 7 ファイル:
  - `magician-fire.json` / `healer.json`: `mp` フィールド削除
  - `magician-water.json`: `mp` ＋ `max_sp` フィールド削除（max_sp=0 の削除忘れも同時整理）
  - `fighter-sword.json` / `fighter-axe.json` / `archer.json` / `scout.json`: `max_sp` フィールド削除
- `assets/master/enemies/` 6 ファイル: `mp` フィールド削除
  - dark_priest / dark_mage / dark_lord / goblin_mage / lich / demon
- 計 14 フィールド削除

### コード変更
- `scripts/character_data.gd:148-149` の `d.get("mp")` / `d.get("max_sp")` 読み込みを撤去
  - `max_mp` / `max_sp` はフィールドの既定値 0 のまま残し、`apply_enemy_stats` / `generate()` 側で energy 由来値を設定する経路に一本化
- `scripts/config_editor.gd:84` の `CLASS_PARAM_GROUPS`「リソース」グループから `mp` / `max_sp` を削除（残るのは `heal_mp_cost` / `buff_mp_cost` のみ）

### CLAUDE.md 更新
- 450-452 行の「廃止（energy で代替）」記述はそのまま（今回の変更で実装と記述が完全一致）
- 「要調査・要整理」セクションの legacy フィールド棚卸しから `mp` を削除（廃止完了）
- 「要調査・要整理」セクションに新項目を追加：「敵ヒーラー（dark_priest）の回復が機能していない可能性」（`apply_enemy_stats` が全敵 `max_mp=0` に設定する結果、`_generate_heal_queue` が `mp < cost` で無限スキップされる疑い。本調査の副次発見・別タスクで追跡）

### 確認
- Godot `--check-only` exit 0
- `grep '"mp"\|"max_sp"' assets/master/classes/*.json` と `grep '"mp"' assets/master/enemies/*.json` いずれも 0 件

## MP / SP を energy に統合（2026-04-18）

### 背景・設計意図
- 1 キャラは MP または SP のどちらか一方しか持たない排他構造で、「魔法クラスは max_mp / sp=0」「非魔法クラスは max_sp / mp=0」と冗長なフィールド対を維持していた
- ポーションも MP / SP の 2 種類があり、プレイヤー間のアイテム受け渡し負担が大きかった
- クラス JSON の `mp` / `max_sp` は 2026-04-18 に廃止済み（energy ベースに移行）で、内部データのみ置き換えれば完全統合できる状態だった
- UI 上の「MP」「SP」という区別はプレイヤーの直感に馴染んでいるため、**見た目は維持し、内部データのみ統合**する方針

### 変更方針
- 内部データ：`mp` / `max_mp` / `sp` / `max_sp` → **`energy` / `max_energy`** の 2 フィールドに統合
- UI 表示：`CharacterData.is_magic_class()` で判定し、魔法クラスは「MP」、非魔法クラスは「SP」として表示
- スロット定義：`slots.*.mp_cost` / `slots.*.sp_cost` → `slots.*.cost`
- CharacterData フィールド：`heal_mp_cost` → `heal_cost`、`buff_mp_cost` → `buff_cost`、`v_slot_mp_cost` + `v_slot_sp_cost` → `v_slot_cost`
- ポーション：`potion_mp.json` + `potion_sp.json` → **`potion_energy.json`**（1種類・エネルギーポーション）
- effect キー：`restore_mp` / `restore_sp` → `restore_energy`（旧キーもフォールバックで読めるようにする）

### JSON 変更
- `assets/master/classes/*.json` 12 ファイル: `slots.Z.mp_cost` / `slots.Z.sp_cost` → `slots.Z.cost`（V スロットも同様）
- `assets/master/items/potion_mp.json` / `potion_sp.json` を削除、`potion_energy.json` を新設（アイコンは `potion_mp.png` を流用）
- `assets/master/maps/dungeon_handcrafted.json`: `"item_type": "potion_mp"/"potion_sp"` → `"potion_energy"`、`"restore_mp"/"restore_sp"` → `"restore_energy"`（178 箇所）

### コード変更（主要箇所）
- `character_data.gd`:
  - `max_mp` / `max_sp` → `max_energy`
  - `heal_mp_cost` / `buff_mp_cost` → `heal_cost` / `buff_cost`
  - `v_slot_mp_cost` / `v_slot_sp_cost` → `v_slot_cost`（単一フィールドに統合）
  - **新ヘルパー `is_magic_class()`** を追加（UI 表示切替用・`class_id in ["magician-fire", "magician-water", "healer"]`）
- `character.gd`:
  - `mp` / `max_mp` / `sp` / `max_sp` → `energy` / `max_energy`
  - `use_mp()` / `use_sp()` → `use_energy()`（単一メソッドに統合）
  - `_mp_recovery_accum` / `_sp_recovery_accum` → `_energy_recovery_accum`、`MP_SP_RECOVERY_RATE` → `ENERGY_RECOVERY_RATE`
  - `_recover_mp_sp()` → `_recover_energy()`
  - `use_consumable()` を `restore_energy` に対応（`restore_mp` / `restore_sp` は legacy 互換で読める）
- `character_generator.gd`:
  - `generate()`: 全クラス共通で `data.max_energy = stats.energy`（分岐廃止）
  - `apply_enemy_stats()`: 敵も同じく `max_energy = stats.energy`（旧 `max_mp=0` 固定の副作用で dark_priest が回復不能だった問題も自動解消）
  - 新ヘルパー `_slot_cost()`: 新形式 `"cost"` 優先、旧形式 `"mp_cost"` / `"sp_cost"` にフォールバック
- `unit_ai.gd`:
  - `_member.mp` / `_member.sp` 参照を全て `_member.energy` に
  - `_has_v_slot_cost()` / `_execute_v_attack()` / `_generate_heal_queue()` / `_generate_buff_queue()` などを energy ベースに書き換え
  - `_find_potion_in_inventory()` に legacy キー（`restore_mp` / `restore_sp`）のフォールバックを追加
- `player_controller.gd`:
  - 各 `_execute_*()` の MP/SP コスト計算を `_slot_cost()` ベースに統一
  - `_build_effect_lines()` / `_is_consumable_usable_by_char()` を energy に対応
  - `character.use_mp()` / `character.use_sp()` → `character.use_energy()` に全置換
- `left_panel.gd`:
  - 二本立ての MP / SP バー描画を `max_energy > 0` の単一判定に統合
  - バー色は `is_magic_class()` で決定（魔法=濃い青 / 非魔法=水色、コスト不足時は紫系）
- `order_window.gd`:
  - ステータス表示の MP/SP 行を「energy を MP/SP どちらのラベルで表示するか」のみの分岐に変更
  - `_EFFECT_LABELS` に `restore_energy` を追加
- `consumable_bar.gd`:
  - `ITEM_COLORS` に `potion_energy` を追加（legacy の `potion_mp` / `potion_sp` も残存）
  - `_is_consumable_usable()` を `max_energy` 判定に
  - 詳細表示のラベル（MP回復/SP回復）をキャラクターの `is_magic_class()` で切替
- `npc_leader_ai.gd`:
  - SP/MP ポーション受け渡しロジックを energy 単一判定に統合
  - `_find_potion_in_cd()` に legacy キーのフォールバック追加
- `game_map.gd`:
  - 初期ポーション付与を `potion_energy` 1 種に統合（魔法クラス=MP / 非魔法=SP の分岐を撤去）
- `debug_window.gd`:
  - ゴッドモードの MP/SP 無限化を `energy` の 10 倍化に統合
- 敵魔法AI 3 ファイル（`dark_mage_unit_ai.gd` / `goblin_mage_unit_ai.gd` / `lich_unit_ai.gd`）:
  - `_member.mp` → `_member.energy`、`use_mp()` → `use_energy()`
- `config_editor.gd`:
  - `CLASS_PARAM_GROUPS` の Z スロット / V スロットグループから `_mp_cost` / `_sp_cost` を削除、`Z_cost` / `V_cost` を追加
  - リソースグループから `heal_mp_cost` / `buff_mp_cost` を削除（プレーンな `cost` キー経由でスロット側から読み取られるため）

### ポーションアイコンの扱い
- 新しい `potion_energy.json` のアイコンは既存の `potion_mp.png` を流用（`"image": "assets/images/items/potion_mp.png"`）
- 旧 `potion_sp.png` は残置（将来独立アイコンを作る際の素材として・現状未参照）
- 色の付け方：魔法クラスが持っていれば UI 上「MP」として、非魔法クラスが持っていれば「SP」として表示されるが、ポーションアイコン自体はクラス中立（同じ色・同じ絵）

### 副次的に解消したはずの問題
- `apply_enemy_stats` が `max_mp = 0` を設定していたため dark_priest が回復できなかった問題は、本変更で `max_energy = stats.energy` になることで自動解消される見込み（実機確認は別途）

### 注意点・後方互換
- effect キーの legacy（`restore_mp` / `restore_sp`）は `use_consumable` / `_find_potion_in_inventory` / `_find_potion_in_cd` が `restore_energy` にフォールバックする互換ロジックを持つ。セーブデータに旧キーが残っていても動作する
- スロット cost の legacy（`mp_cost` / `sp_cost`）は `_slot_cost()` ヘルパーが `cost` を優先しつつ旧キーにフォールバック。古い class JSON でも動作する
- 旧 `potion_mp` / `potion_sp` item_type も `ITEM_COLORS` に残しているため、旧データを拾った場合もアイコン色が決まる

### 確認
- Godot `--check-only` exit 0・パースエラーなし
- `grep '\.mp\b\|\.sp\b\|\.max_mp\b\|\.max_sp\b' scripts/` で残存ヒットなし（magic_power 用のローカル変数 `var mp: int` とコメント内の legacy 言及のみ）
- `grep 'mp_cost\|sp_cost' assets/master/classes/*.json` 0 件

## ポーション命名の整理（2026-04-18）

### 背景
前回の energy 統合で MP/SP ポーションを `potion_energy` に統合。ついでに HP ポーションも命名を揃える：`potion_hp` → `potion_heal`（アイテム名として「回復」の意味で統一）。
ついでに、以前から「要調査」に残っていた effect キー名の不整合（マスター側 `heal_hp` vs インスタンス側 `restore_hp`）も同時に解消。

### 画像
- `assets/images/items/potion_hp.png` → `potion_heal.png` にリネーム（ユーザー側で事前配置済み）
- `assets/images/items/potion_energy.png` を新規追加（`potion_mp.png` のコピー・ユーザー側で事前配置済み）
- 旧 `potion_mp.png` / `potion_sp.png` は legacy 互換用に残置

### JSON
- `assets/master/items/potion_hp.json` → `potion_heal.json` にリネーム
  - `item_type`: `potion_hp` → `potion_heal`
  - `effect.heal_hp` → `effect.restore_hp`（legacy キー `heal_hp` を撤去・インスタンス側の `restore_hp` に統一）
  - `image` パスも `potion_heal.png` に更新
- `assets/master/items/potion_energy.json` の `image` を `potion_mp.png` → `potion_energy.png` に更新
- `assets/master/maps/dungeon_handcrafted.json`: `"item_type": "potion_hp"` → `"potion_heal"`（78 箇所）

### コード
- `game_map.gd`: 初期ポーション付与の `"item_type": "potion_hp"` → `"potion_heal"`
- `consumable_bar.gd`: `ITEM_COLORS` に `potion_heal` を追加（旧 `potion_hp` / `potion_mp` / `potion_sp` は legacy として残置）

### CLAUDE.md
- 「assets/images/items/ ：アイテム画像」の例を `potion_heal.png / potion_energy.png` に更新
- 「要調査・要整理」から `heal_hp` vs `restore_hp` の不整合項目を削除（今回解消）

### 確認
- `grep '"potion_hp"' assets/master/maps/dungeon_handcrafted.json` 0 件
- `grep 'heal_hp' assets/master/` 0 件（マスター側も統一）

## ポーション表示名を刷新（2026-04-18）

### 方針
- 「HPポーション」→「**ヒールポーション**」
- 「エネルギーポーション」→「**エナジーポーション**」（ファイル名 `potion_energy.json` は維持）
- 内部データ名（`energy` / `max_energy` / `restore_energy` 等）は英語のまま維持

### 命名方針メモ
ポーション名は「ヒール」「エナジー」というカタカナ英語を採用する：
- MP/SP 統合でポーションが 1 種類になった際、既存 RPG 用語の「HPポーション」に対する自然な対として「ヒールポーション」を採用
- 統合ポーションは「エナジーポーション」（energy のカタカナ表記は「エネルギー」より「エナジー」のほうが英語発音に近く短いため）

内部データと UI 表示の用語は意図的に分離している：
- **内部**：開発者向けの統一性（`energy` / `max_energy`）
- **UI**：プレイヤー向けの慣例用語（MP/SP バー表示）とアイテム名（ヒール / エナジー）

### JSON
- `assets/master/items/potion_heal.json`: `"name": "ヒールポーション"` を追加
- `assets/master/items/potion_energy.json`: `"name": "エナジーポーション"` を追加
- `dungeon_handcrafted.json`: インスタンス側の `item_name` を置換（`HPポーション` → `ヒールポーション`、`エネルギーポーション` → `エナジーポーション`）

### コード
- `game_map.gd`: 初期ポーション付与時の `item_name` を新名称に
- `character.gd`: ポーション使用時のバトルメッセージを新名称に
- コード内コメント（`scripts/*.gd`）で参照されていた旧名称も新名称に置換

### ドキュメント
- `CLAUDE.md`: メッセージ表記方針（228-231行）を新名称に、その他の現行仕様の記述も置換
- `docs/spec.md`: 現行仕様の箇所を置換
- `constants_default.json`: description 文字列内のポーション名を置換（Config Editor 表示）

### 対象外（歴史的記録として原文維持）
- `docs/history.md`: 過去の変更履歴セクション内の旧名称は記録として保持

## ポーション効果表示をMP/SP表記に統一（プレイヤーUIから「エネルギー」用語を排除）（2026-04-18）

### 方針
プレイヤー向け UI で「エネルギー」という内部用語を露出させない。エナジーポーション名との一貫性と、プレイヤーから見た自然さを優先。

### 変更内容
- `scripts/order_window.gd`:
  - `_EFFECT_LABELS` 定数（`Dictionary`）を廃止し、動的関数 `_effect_label(key, ch)` に変更
  - `restore_energy` キーを `ch.character_data.is_magic_class()` で「MP回復 / SP回復」に切替
  - 呼び出し元 2 箇所（`_draw_status_section` の所持アイテム欄・`_item_char` の未装備アイテム欄）で `ch` / `_item_char` を渡すよう修正
- `scripts/consumable_bar.gd`: 既に `_energy_label` 動的切替が実装済み（変更なし）
- `scripts/player_controller.gd`: 既に `_build_effect_lines` で動的切替が実装済み（変更なし）
- `scripts/character.gd`: ポーション使用時の MessageLog も既に動的切替済み（変更なし）

### CLAUDE.md 更新
- 「メッセージ表記方針」セクション直下に **「UI 用語の分離方針」** を新設。プレイヤー向け UI / 内部データ / デバッグ表示の用語分担を明文化：
  - プレイヤー UI：MP / SP（クラス別）・ヒール / エナジー（アイテム名）
  - 内部データ：`energy` / `max_energy` 等の英語
  - デバッグ表示：`energy` 英語のまま
  - 「エネルギー」カタカナ表記はプレイヤー UI では使わない

### 確認
- `grep '"[^"]*エネルギー[^"]*"' scripts/` で 0 件（文字列リテラル内の「エネルギー」がプレイヤー UI に露出していないことを確認）
- コメント内の「エネルギー」は開発者向け説明として残置

## アイテム効果表記を「MP/SP回復」固定に変更（2026-04-18）

### 背景
直前のコミットで `restore_energy` の UI ラベルを「閲覧中キャラのクラスで MP/SP 切替」としていたが、ポーションは他メンバーに渡すこともあるため、閲覧中キャラのクラスで決め打ちすると混乱する（魔法クラスで「MP回復」と表示されていたポーションを物理クラスに渡すと実際は SP 回復になる）。

### 変更内容
アイテム効果の表記は**固定で「MP/SP回復」と両併記**に変更：
- `scripts/order_window.gd`: `_effect_label(key, ch)` から `ch` 引数を削除。`restore_energy` は固定で `"MP/SP回復"`
- `scripts/consumable_bar.gd`: `EFFECT_LABELS` の `restore_energy` を `"MP/SP回復"` に固定
- `scripts/player_controller.gd`: `_build_effect_lines` で `"MP/SP回復 %d"` 固定表記に

### 維持する動的切替（キャラクター特定済みの箇所）
- `scripts/character.gd:use_consumable()` のバトルメッセージ：「自身の%sを回復した」% energy_label はキャラクター使用時なので MP / SP 切替を維持
- 左パネルのエネルギーバー・OrderWindow の MP/SP 行：そのキャラクターのリソースを表示するので `is_magic_class()` 切替を維持

### CLAUDE.md 更新
「UI 用語の分離方針」セクションを詳細化：
- ステータス表示・バトルメッセージ（キャラ特定時）：MP / SP 切替
- アイテム効果表示（複数キャラ間で受け渡し可能）：固定「MP/SP回復」

## AIヒーラーバグ修正 + アンデッド特効倍率の明示化 + ATTACK_TYPE_MULT外出し（2026-04-18）

### 背景
`docs/investigation_healer_undead_damage.md` の調査で以下が判明：
1. **AI ヒーラーの heal 実行時に `heal_mult` が未適用**（Player 側の 3.4 倍のダメージ・回復量になるバグ）
2. ヒーラー Z は現状 `ATTACK_TYPE_MULT` を経由せず独自計算
3. アンデッド特効はアンデッド敵の `magic_resistance` 低設定で自然発生しており、ヒーラー固有の特効倍率は存在しなかった

### 変更方針
ヒーラーのアンデッド特効を設計で明確に表現するため：
- ヒーラー Z のダメージ計算を他魔法クラスと同じフロー（`power × ATTACK_TYPE_MULT[magic] × damage_mult`）に統一
- ヒーラー `slots.Z` に `damage_mult: 2.0` を追加（`slots.X` も同様）
- `Z_heal_mult` は回復量専用・`Z_damage_mult` はダメージ専用として役割を分離
- AI / Player 両方で同じ計算フローになるよう統一

### ATTACK_TYPE_MULT の Config Editor 外出し
旧：`const ATTACK_TYPE_MULT: Dictionary = { "melee": 0.3, ... }`（編集不可）
新：個別 var 4 個として定義し、`_ready()` で `ATTACK_TYPE_MULT` 辞書に集約
- `ATTACK_TYPE_MULT_MELEE` / `_RANGED` / `_DIVE` / `_MAGIC`（全て `var float`）
- `_rebuild_attack_type_mult()` が 4 vars から辞書を組み立て
- 既存の `GlobalConstants.ATTACK_TYPE_MULT.get("melee", 1.0)` アクセスは互換のまま動作
- Config Editor「Character」タブに 4 定数を追加（min 0.0, max 2.0, step 0.05）

### healer.json 更新
```jsonc
"Z": { ..., "heal_mult": 0.3, "damage_mult": 2.0, ... }
"X": { ..., "heal_mult": 0.6, "damage_mult": 2.0, ... }
```

### CharacterData 追加フィールド
- `z_heal_mult: float = 0.0`（回復量倍率）
- `z_damage_mult: float = 1.0`（ダメージ倍率。ヒーラーは 2.0）

### CharacterGenerator のロードロジック
`generate()` / `apply_enemy_stats()` の slots.Z 読み込み部分に以下を追加：
```gdscript
data.z_heal_mult    = float(z_dict.get("heal_mult",   0.0))
data.z_damage_mult  = float(z_dict.get("damage_mult", 1.0))
```

### Player 側（player_controller.gd _execute_heal）の計算式
旧：`heal_amount = power × heal_mult`（回復・ダメージ兼用）
新：
- 回復時：`heal_amount = power × heal_mult`（従来通り）
- アンデッドダメージ時：`base_damage = power × ATTACK_TYPE_MULT[magic] × damage_mult`

### AI 側（unit_ai.gd heal 分岐）の統一
旧：`target.heal(power)` / `target.take_damage(power, ...)` （heal_mult / damage_mult 未適用）
新：Player 側と同じ計算式。`CharacterData.z_heal_mult` / `z_damage_mult` を参照

### バランス変動（参考値・power 50 / skeleton に対して）
| 攻撃者 | 旧 Base Damage | 新 Base Damage | 最終ダメージ（magic res 0.167） |
|---|---:|---:|---:|
| Player ヒーラー Z | 15 | 20（= 50 × 0.2 × 2.0） | 16 |
| AI ヒーラー Z | 50（バグ） | 20 | 16 |
| AI ヒーラー回復 | 50（バグ） | 15（= 50 × 0.3） | — |

AI ヒーラーの過剰回復（3.4 倍）が解消され、Player と完全一致。Player ヒーラーのアンデッドへのダメージは 1.33 倍に増加。

### 副次的な確認
- `dark_priest` の回復が機能するかは、energy 統合（max_energy>0）と heal_cost 参照の両方で確認される状態に
- バランス微調整は Phase 14 で実施予定。本コミットは設計整合性を優先

### 確認
- Godot `--check-only` exit 0
- `grep 'ATTACK_TYPE_MULT\.get' scripts/` で呼び出し 15 件、すべて `.get("キー", 1.0)` 形式で互換動作

## 味方クラスタブの整理（V_duration統合・V_tick_interval明文化・要調査項目の掃除）（2026-04-18）

### 調査で判明した事実
1. `V_stun_duration`（magician-water）・`V_buff_duration`（healer）・`V_duration`（magician-fire）は意味は同じ「効果持続秒数」だが、キー名が統一されていなかった
2. **`V_buff_duration` は完全に未使用**（`apply_defense_buff()` が `DEFENSE_BUFF_DURATION = 10.0` ハードコードを使用し JSON 値を読まない）
3. `V_stun_duration` は Player 側のみ JSON を読み、**AI 側は `apply_stun(2.5, ...)` ハードコード**でバグ
4. `V_duration`（炎陣）は Player 側のみ JSON を読み、**AI 側は `flame.setup(..., 2.5, 0.5, ...)` ハードコード**でバグ
5. `V_tick_interval` は炎陣の「ダメージ判定間隔」で、ゲームロジック定数（UI 側の点滅周期ではない）

### 変更方針（ケース1採用）
- `V_*_duration` 3 キー（stun/buff/duration）は意味が同じなので **`V_duration` に統合**
- `V_tick_interval` は炎陣固有のゲームロジック定数なので slots.V 直下に維持
- Player / AI で同じ計算フロー（JSON 値を尊重）に統一

### JSON 変更
- `healer.json` slots.V: `buff_duration: 10.0` → `duration: 10.0`
- `magician-water.json` slots.V: `stun_duration: 4.0` → `duration: 4.0`
- `magician-fire.json` slots.V: `duration: 2.5` / `tick_interval: 0.5`（変更なし）

### コード変更
- `CharacterData` に `v_duration: float` と `v_tick_interval: float` を追加
- `CharacterGenerator._build_data` / `apply_enemy_stats` で `slots.V.duration` / `tick_interval` をロード
- `Character.apply_defense_buff(duration: float = 0.0)` に引数追加。0.0 は `DEFENSE_BUFF_DURATION` 定数フォールバック
- `player_controller.gd`:
  - `_execute_water_stun`: `slot_data.get("stun_duration", ...)` → `slot_data.get("duration", 3.0)`
  - `_execute_buff`: `apply_defense_buff()` に `slot_data.get("duration", 0.0)` を渡すよう変更
  - `_execute_flame_circle`: 既に `duration` / `tick_interval` を読んでいたため変更なし
- `unit_ai.gd`:
  - `_v_water_stun`: ハードコード `apply_stun(2.5, ...)` → `apply_stun(cd.v_duration or 2.5, ...)`
  - `_v_flame_circle`: ハードコード `setup(..., 2.5, 0.5, ...)` → `setup(..., cd.v_duration or 2.5, cd.v_tick_interval or 0.5, ...)`
  - `"buff"` アクション: `apply_defense_buff()` → `apply_defense_buff(cd.v_duration)`
- `config_editor.gd`: `CLASS_PARAM_GROUPS` の V スロットから `V_stun_duration` / `V_buff_duration` を削除（`V_duration` / `V_tick_interval` は残置）

### CLAUDE.md 更新
- **demon の is_flying 要調査項目を削除**（Config Editor で既に修正済み）
- 炎陣仕様：「2〜3秒間」→「`slots.V.duration` 秒間、`slots.V.tick_interval` 秒ごとにダメージ判定」
- 無力化水魔法仕様：「2〜3秒間」→「`slots.V.duration` 秒間」
- 防御バフ仕様：「`slots.V.duration` 秒間バフ状態」明記
- Vスロット仕様セクションに **「Vスロット JSON パラメータ」サブセクション**を新設：`duration` と `tick_interval` の用途を明文化

### バグ修正副次効果
- AI の水魔法使い：スタン秒数が 2.5 固定 → 4.0（JSON 値）
- AI の魔法使い(火)：炎陣の燃焼秒数・tick 間隔が JSON 値を反映
- AI のヒーラー（味方 NPC / 敵 dark_priest）：バフ秒数が JSON 値を反映

### 確認
- Godot `--check-only` exit 0
- `grep '"stun_duration"\|"buff_duration"' assets/master/classes/` 0 件

## クラス側 behavior_description を削除し個別敵側に一本化（2026-04-18）

### 背景
`behavior_description` は UnitAI 継承クラス（GoblinUnitAI 等）の実装時に Claude Code が読む自然言語仕様として機能する。UnitAI 継承単位は「種族」なので、`behavior_description` は種族単位の個別敵 JSON（`assets/master/enemies/`）にあるべき。クラス JSON（`assets/master/classes/`）の `behavior_description` は冗長で混乱の元だったため削除。

### 位置付けの明文化
- **`behavior_description` は個別敵 JSON にのみ記述**
- UnitAI 継承クラス実装時に Claude Code が参照する「種族単位の行動仕様」
- クラス側 JSON（味方クラス・敵固有クラス）には持たせない

### 削除したファイル（12 件）
- `assets/master/classes/` 味方 7 ファイル（fighter-sword / fighter-axe / archer / magician-fire / magician-water / healer / scout）
- `assets/master/classes/` 敵固有 5 ファイル（zombie / wolf / salamander / harpy / dark-lord）

### 残したもの（16 件）
- `assets/master/enemies/` 個別敵 JSON 全 16 ファイル（goblin / hobgoblin / goblin-archer / goblin-mage / wolf / zombie / salamander / harpy / dark-knight / dark-mage / dark-priest / demon / lich / skeleton / skeleton-archer / dark-lord）

### コード影響
- **class-side 参照あり（発見）**：`character_generator.gd:119` の `data.behavior_description = str(class_json.get("behavior_description", ""))` — 味方・NPC 生成時にクラス JSON から読み込んでいた。今回の削除で `""`（空文字）になる。CharacterData.behavior_description フィールドは残存するが現状どこからも読まれていない legacy 状態（旧 LLM 実装の `enemy_ai.gd` のみで参照、それも未使用）
- **Config Editor**：`CLASS_PARAM_GROUPS` の「基本」グループから `behavior_description` を削除。味方クラスタブ・敵固有クラスタブで表示されなくなる
- 敵一覧タブは個別敵 JSON を参照するので表示維持

### CLAUDE.md 更新
- 1058 行の記述を「個体側の属性」から「個別敵 JSON にのみ記述する」に変更し、UnitAI 継承クラス実装時の参照用途を明記

### 確認
- `grep -l "behavior_description" assets/master/classes/*.json` → 0 件
- `grep -c "behavior_description" assets/master/enemies/*.json` → 16 件（全て残存）
- Godot `--check-only` exit 0

## FLEE 立ち往生バグ修正：出口タイル定義を内側 → 外側に変更（2026-04-25）

### 現象
味方パーティーの FLEE 挙動で「部屋の出口に到達した時点で立ち往生する」現象が発生。
リーダーは避難先エリア（フロア 0 の安全部屋 `r0_10`）と推奨出口タイルを正しく選定し、
全メンバーに配布するところまでは機能していたが、メンバーが配布された goal タイルに
到達した時点で逃走が完了扱いになり、次のエリアへ向かう新しい goal が配布されずに
キュー消化で停止していた。

スナップショット例（フロア 0・操作キャラはベルナール）：
```
[プレイヤー]  生存:2/2  area:r0_5  戦況:優勢(11.0/6.0=1.83) ...
              避難先:r0_10(d:3)@(13,22)
  ★ベルナール ... @r0_5 ... 状態:flee→(13,22)
  ヴィクター  ... @r0_5 ... 状態:flee→(13,22)
```

期待挙動：(13,22) 到達 → エリア変化検知 → 隣エリアから r0_10 への次の出口を再計算
→ 新 goal を配布 → r0_10 まで連鎖。
実挙動：(13,22) 到達後に逃走停止し再配布なし。

### 原因調査の流れ

#### 第 1 次調査（クールダウン仮説）
PartyLeader の `on_member_area_changed()` が `FLEE_REEVAL_MIN_INTERVAL = 0.3s` の
クールダウンに引っかかってスキップされている可能性を疑った。確かにクールダウンが効く
経路はあるが、それは付随的な問題。

#### 第 2 次調査（出口タイル定義の不整合）
真の原因を特定。`MapData.get_exit_tiles_from()` の出口タイルが「**そのエリアの内側**で
隣接エリアに接しているタイル」と定義されていた。このため：
- メンバーが goal（出口タイル）に到達してもエリア ID が変わらない
- `UnitAI._notify_area_change_if_needed()` が発火しない（エリア ID 不変なので）
- リーダーの再計算 → 新 goal 配布の連鎖が走らない
- `_is_in_refuge_area()` も false のまま（現エリア = 元エリアのまま）
- キュー消化後の IDLE 分岐で古い `_order` が使われ立ち往生

つまり「エリア境界のタイル」をどこに置くかという設計選択が、エリア変化通知機構と
噛み合っていなかった。

### 採用した修正方針

**出口タイル定義を「外側」（隣接エリアに踏み込んだ最初のタイル）に変更**。

代替案（FLEE 専用 API 新設・goal 補正・エリア ID 変化での到達判定）も検討したが、
- `get_exit_tiles_from()` の呼び出し元が **FLEE 系の 2 箇所のみ**（事前調査で確認）
- 他用途（explore / 階段ナビ / NPC 合流判定 / デバッグ表示）では未使用
- A* 側に既に「ゴール例外」ロジックが実装済み（`unit_ai.gd:1726-1727` の
  `neighbor != goal` 分岐）で、外側 goal でも経路探索が成立する
という条件が揃っていたため、**既存 API を直接書き換える**方式が最もクリーンと判断。

### 修正内容

#### 1. `MapData.get_exit_tiles_from(area_id)` の定義変更
- **旧**：そのエリア内のタイルのうち、4 近傍に異なるエリア ID を持つタイルがあるもの
- **新**：area_id とは異なるエリアに属するタイルのうち、4 近傍に area_id のタイルが
  あるもの（= area_id から見て一歩踏み出した先のタイル）
- 走査方向を反転（旧：内側タイル列挙 → 隣接が外なら採用 / 新：外側タイル列挙 → 隣接が
  area_id なら採用）

#### 2. `MapData.get_adjacent_area_ids_of_exit(exit_tile)` の意味調整
- **旧**：内側タイルから見た「向こう側エリア」を 4 近傍走査で探す（複数エリアに接する
  通路タイルでは複数返す）
- **新**：外側タイル前提なので、そのタイルが属するエリア ID をそのまま返す（最大 1 要素）
- 戻り値型 `Array[String]` は呼び出し側互換のため維持

#### 3. A* 関連
- 修正不要。既に `unit_ai.gd:1725-1727` で `neighbor != goal` のとき `area_limit_id`
  チェックをスキップする実装になっており、外側 goal でも経路探索が成立する。
- `unit_ai.gd:1696-1697` の start ガード（start も goal も area_limit_id 外なら諦める）
  も、start = current_area・goal = 外側エリア の組み合わせでは発火しないため問題なし。

#### 4. 推奨バイアス
- リーダー（`_determine_flee_recommended_goal`）とメンバー（`_find_flee_goal`）の
  双方が同じ `get_exit_tiles_from()` を起点にするため、両者とも外側タイル基準で計算。
- 座標一致判定（`unit_ai.gd:1482` の `exit_tile != recommended`）は外側タイル同士で
  比較されるので破綻しない。

#### 5. fall_back への波及
- `_find_fall_back_goal()` は `_find_flee_goal()` の軽量ラッパーなので、自動的に外側
  goal を返すようになる。
- 停止条件 `_is_far_enough_from_threats()` は座標距離（マンハッタン）ベースで、
  エリア ID 依存なし。外側 goal でも機能維持。

### 影響を与えなかったもの（変更なし）
- 敵パーティーの FLEE（`_find_flee_goal_legacy` 直線ロジック・既知の派生課題）
- explore モード・階段ナビ・NPC 合流判定（`get_exit_tiles_from()` を呼ばない）
- `_is_in_refuge_area()` の判定ロジック
- `_notify_area_change_if_needed()` の発火条件（毎フレーム実行）
- PartyStatusWindow の表示文言（座標値が外側になるだけで表示形式は不変）

### 想定される副次効果・観察ポイント
- **通路エリア（c0_*）の扱い**：通路は複数の部屋に接続するハブなので、通路から見た
  外側出口は「通路の端 → 隣接部屋に踏み込んだタイル」になる。1 つの通路に対して
  複数の隣接部屋方向の外側タイルが返される（FLEE 評価では各方向を個別に評価する）
- **階段タイル境界**：稀なケースだが、外側出口がたまたま階段タイルに位置する場合、
  到達と同時にフロア遷移が発火する可能性がある。階段タイル中継禁止ルール
  （`unit_ai.gd:1730-1731`）は中間地点のみに適用されるため、ゴール = 階段は許可される
- **クールダウン抑制**：`FLEE_REEVAL_MIN_INTERVAL = 0.3s` のクールダウンは引き続き
  効くが、外側 goal 化で「出口手前の連続エリア変化」が起きなくなったため、実害は
  顕在化しない見込み（要観察）

### 動作確認手順
1. フロア 0 でプレイヤーパーティーの `battle_policy = "retreat"` または HP critical で
   `on_low_hp = "flee"` に設定して FLEE 発動
2. F7 でスナップショット取得
3. 確認項目：
   - `避難先:r0_10(d:N)@(x,y)` の `(x,y)` がリーダー現在エリアの**外側**タイルになっている
   - メンバー行の `状態:flee→(x,y)` が同様に外側タイル
   - メンバーが (x,y) に到達したらエリア ID が変わり、新しい goal が配布される
   - 連鎖して r0_10 まで到達する
   - r0_10 到達後は `_is_in_refuge_area() == true` で待機状態になる

### 確認
- Godot `--check-only` exit 0
- `get_exit_tiles_from` / `get_adjacent_area_ids_of_exit` の呼び出し元 grep で 3 箇所
  すべてレビュー済み（party_leader.gd:599 / unit_ai.gd:1467 / party_leader.gd:639）
- CLAUDE.md「FLEE 時の逃走先決定ロジック」内 MapData 側 API 表を更新・経緯セクション追加
- 「実装状況」AI システム配下に 1 行追加

## FLEE/fall_back 出口選択ロジック統一・リーダー推奨機構の廃止（2026-04-25）

### 現象
出口タイル外側化（同日朝）で連鎖走行が動くようになったが、実プレイ検証で
**「逃走中のキャラが部屋の境界を往復する」**現象が発覚。避難先や各キャラの状態
（逃走）は変わらないまま、メンバーが出口タイルと前のエリアの間を行き来する。

### 原因（リーダー推奨機構と先行メンバーの座標不一致）

旧設計はリーダーが推奨出口タイル座標を全メンバーに配布する二段階構造だった：

1. リーダー（r0_5 にいる）の推奨出口 = c0_4 内の境界タイル（外側出口）
2. メンバーが境界を跨ぎ c0_4 に入る
3. リーダーは依然 r0_5 にいるので推奨は不変
4. メンバーの `_find_flee_goal()` で `get_exit_tiles_from(c0_4)` を呼ぶ → 戻り値は **c0_4 の外側タイル**（= r0_5 内 / r0_10 内 / 他部屋）
5. リーダーの推奨 c0_4 内タイルはメンバーの `exit_tiles` 配列に**含まれない**
6. `if exit_tile != recommended:` がすべての候補で真 → **全候補に同じ
   FLEE_NON_RECOMMENDED_PENALTY** が乗り、バイアスが事実上中立化
7. メンバーは純粋に reach_cost（= ステップ数 + 脅威コスト）だけで選択 → r0_5 への
   1 歩戻りが最も近い → r0_5 に戻る → 振動

問題の本質：旧設計はリーダーとメンバーが**同じエリアにいる前提**で書かれていた。
メンバーがリーダーより先行した瞬間、推奨タイルが概念的に「メンバーから見て手前」に
位置するため、座標一致判定が破綻する。

### 採用した修正方針

**リーダー推奨機構を廃止し、メンバー自律判断に統一**。

設計選択の理由：
1. メンバー先行時の破綻を根本解決
2. 「敵がいないなら全員同じ出口に収束（パーティー分散防止）」「敵がいれば各自が
   別出口を選べる（脅威回避）」の両立を `FLEE_AREA_DISTANCE_WEIGHT` のウェイト
   バランス 1 つで実現できる
3. リーダーの A* 評価（出口数 × walker コンテキスト）を削除でき、計算量が単純化
4. fall_back / 将来の `keep_distance` も同じコア関数で動く統一感

検討した代替案：
- **案 B（出口チェーン全体配布）**：実装複雑・データ構造変更大
- **案 C（座標一致 → 方向一致）**：単独では不十分・案 A の追加バイアスが必要
- **案 D（来た方向ペナルティ）**：往復には効くが「狭間で詰まる」副作用懸念

→ **案 A（メンバー自律 + refuge_dist バイアス）**を採用。実装最小・意味論明快。

### 修正内容

#### 1. UnitAI に共通コア関数を新設

```
_evaluate_exit_costs() -> Array[Dictionary]
  各外側出口について:
    reach_cost       = メンバー位置 → exit_tile の脅威コスト付き A* 距離
    refuge_dist_cost = get_area_distance(area_of(exit_tile), _flee_refuge_area_id)
                       × FLEE_AREA_DISTANCE_WEIGHT
                       避難先未設定なら 0・到達不能なら 999.0
    total_cost       = reach_cost + refuge_dist_cost
  到達可能な候補配列を返す。空なら呼出側 legacy フォールバック
```

`_find_flee_goal()` / `_find_fall_back_goal()` の双方が同じ関数を共用。
fall_back は停止条件 `_is_far_enough_from_threats()` だけが追加で違う。

#### 2. PartyLeader 側の役割を「避難先エリア ID 決定のみ」に削減

`_update_flee_refuge_area_id()`（新設）がリーダー現エリアから **BFS ホップ距離**で
最も近い避難先エリアを選び、`_flee_refuge_area_id` に格納。`receive_order` 経由で
全メンバーに配布。出口タイル選定は完全にメンバー側で完結する。

#### 3. 大規模削除

**PartyLeader**：
- `_flee_recommended_goal` / `_flee_refuge_distance` / `_flee_is_fallback` /
  `_flee_last_reeval_time` フィールド
- `_determine_flee_recommended_goal()` / `_update_flee_recommended_goal()` /
  `_build_threat_map()`（UnitAI に移管）/ `_perf_leader_pos_safe()`
- `get_flee_recommended_goal()` / `get_flee_refuge_distance()` / `is_flee_fallback()`
- `on_member_area_changed()`（推奨再計算機構ごと不要に）

**UnitAI**：
- `_flee_recommended_goal` / `_last_area_id` フィールド
- `_notify_area_change_if_needed()`（リーダーへの通知不要に）
- `_process()` 冒頭の `_notify_area_change_if_needed()` 呼び出し

**GlobalConstants / constants.json / constants_default.json**：
- `FLEE_NON_RECOMMENDED_PENALTY`（推奨外ペナルティ・推奨機構ごと廃止）
- `FLEE_REEVAL_MIN_INTERVAL`（推奨再計算クールダウン・廃止）

**receive_order ペイロード**：
- `flee_recommended_goal: Vector2i` → `flee_refuge_area_id: String` に置換

#### 4. UnitAI 側の追加フィールド
- `_flee_refuge_area_id: String`（receive_order 経由で配布）
- `_last_flee_goal: Vector2i`（PartyStatusWindow `flee→(x,y)` 表示用に
  メンバー本人が選定した直近 goal を保持）

#### 5. PartyStatusWindow 表示の単純化
- ヘッダー：`避難先:r0_10(d:3)@(13,22)` → **`避難先:r0_10`** のみ（座標・距離・
  フォールバック表示を削除）
- メンバー行：`flee→(x,y)` / `fb→(x,y)` は維持。ただし参照先を
  `_flee_recommended_goal`（リーダー配布値）から `_last_flee_goal`（メンバー本人の
  選定値）に変更。各メンバーごとに異なる出口が表示されるようになる
- F7 スナップショットも同様

### パーティー分散防止と脅威回避の両立

`FLEE_AREA_DISTANCE_WEIGHT`（既定 10.0）の値で挙動が連続的に変わる：
- **大きい**（例 20.0）：避難先方向に強く収束。脅威があっても突っ込みやすい
- **小さい**（例 5.0）：脅威回避を優先。パーティーが分散しやすい
- 既定 10.0 はバランス値。`reach_cost` のスケール（1 ステップ ≒ 1.0 + 脅威コスト
  最大 ~15）と概ね釣り合う

### 影響範囲外
- **敵パーティーの FLEE**：従来通り `_find_flee_goal_legacy`（直線実装）。派生課題で対応
- **`keep_distance`**：現状の `_find_flee_goal()` 流用のままに保持。将来の派生課題で
  `_evaluate_exit_costs()` 経由に切り替える際、距離確保の意味（射程維持・後退ではなく
  脇に退避）に合わせたロジック差別化を併せて入れる

### 確認
- Godot `--check-only` exit 0
- 旧 API シンボル（`_flee_recommended_goal` / `FLEE_NON_RECOMMENDED_PENALTY` /
  `FLEE_REEVAL_MIN_INTERVAL` / `_notify_area_change_if_needed` /
  `on_member_area_changed` / `_determine_flee_recommended_goal` /
  `_update_flee_recommended_goal` / `get_flee_recommended_goal` /
  `get_flee_refuge_distance` / `is_flee_fallback` / `_flee_is_fallback` /
  `_flee_refuge_distance` / `_flee_last_reeval_time` / `_last_area_id`）の grep で
  scripts/ 配下に残存なし（map_data.gd / game_map.gd の comment 文言は更新済み）
- CLAUDE.md 「FLEE 時の逃走先決定ロジック」セクションを大幅改訂（二段階構造の節を
  廃止し「メンバー自律出口選択」「リーダー側の役割」「fall_back との関係」「keep_distance
  との関係」を新設）
- 「実装状況」AI システム配下に 1 行追加
- 「残タスク」の `fall_back 実機動作確認` を「FLEE / fall_back 動作確認」に統合・
  リーダー推奨機構廃止後の検証項目に書き換え
- 「FLEE 派生課題」を新仕様に合わせて再整理（`keep_distance` を `_evaluate_exit_costs()`
  経由に切り替える項を派生課題 4 として明記）

### 後追い修正（同日・避難先到達後の境界往復）

リーダー推奨機構廃止の実機検証で「避難先に到達した後、避難先と隣接通路の間で振動する」
現象が発覚。状態は「逃走」のまま。

#### 原因

`_generate_queue(FLEE)` は `_is_in_refuge_area()` が true なら `[{wait}]` を返すが、
これはキュー**生成時**にしか働かない。FLEE 戦略中はキューが `[flee × 5]` で生成され、
各アクションが `_step_toward_goal()` 内で `_find_flee_goal()` を呼んで goal を都度
再計算する。

メンバーが避難先 r0_10 に入った時点で `_find_flee_goal()` が呼ばれると：
- `_evaluate_exit_costs()` が r0_10 の外側出口（隣接通路 c0_X 内のタイル）を返す
- 避難先 = 現エリアなので refuge_dist_cost = 0 ではなく、出口エリア c0_X から見た
  refuge までの距離 = 1 ホップ → `1 × FLEE_AREA_DISTANCE_WEIGHT(10) = 10.0`
- それでもメンバーは外へ出てしまう（最小コストに従うため）
- 通路に出た瞬間、再評価で r0_10 が refuge_dist_cost = 0 → 戻る → 振動

#### 修正

`_find_flee_goal()` の冒頭に「避難先到達済みなら現在位置を返す」早期停止を追加。
旧キューに残った flee アクションは grid_pos == goal で即完了し、次のキュー生成で
wait 分岐に入る。状態表示も即座に「逃走」→「待機」に切り替わる。

#### 確認

- Godot `--check-only` exit 0
- `_find_fall_back_goal()` には影響なし（fall_back は `_is_far_enough_from_threats()`
  による独自停止条件があり、避難先に居れば脅威との距離が大きく自然停止する）
- `keep_distance`（敵専用）には影響なし（is_friendly == false で legacy 経路に分岐）

### 後追い修正 2（同日・撤退途中の WAIT 切替→巻き戻り）

リーダー推奨機構廃止後、避難先から離れた地点で battle_policy="retreat" を指示した
場合の検証で発覚：「避難先到達前にメンバーが WAIT に切り替わり、戻ってくる」現象。

#### 原因

撤退中、メンバーが敵から十分離れると `nearby_enemy_rank_sum` が 0 になり：

1. `PartyLeader._update_flee_refuge_area_id()` が `_flee_refuge_area_id = ""` にリセット
   （旧仕様：「敵検知中のみ refuge を計算」）
2. `_combat_situation.situation` が SAFE になる
3. `UnitAI._determine_effective_action()` の line 2632 `if _is_combat_safe(): return WAIT`
   が `_combat == "flee"` より優先され、戦略が **FLEE → WAIT** に切替
4. メンバー停止。Avoid 表示も消える
5. しばらく経つと敵が再接近 / 視界に入って SAFE 解除 → 再び FLEE
6. ループ

つまり「敵が見えなくなった瞬間に retreat が中断される」設計バグ。プレイヤーが明示的に
撤退を指示している以上、敵の有無に関係なく避難先まで退却すべき。

#### 修正

**1. `UnitAI._determine_effective_action()`**：`_combat == "flee"` を SAFE 判定より
**前**にチェックする項目として独立させた。

```
if _combat == "flee":
    if _should_ignore_flee():
        return ATTACK  # 逃げない種族
    if _is_in_refuge_area():
        return WAIT    # 避難先到達済み → 自然停止
    return FLEE        # 避難先未到達 → SAFE でも継続
```

避難先到達後は自然に WAIT に切り替わる（`_is_in_refuge_area()` 経由）ので、無限に
逃げ続けることはない。

**2. `PartyLeader._update_flee_refuge_area_id()`**：`battle_policy == "retreat"` の
ときは敵不在でも refuge_area_id を維持する。

```
var is_retreating := _global_orders.get("battle_policy", "") == "retreat"
if enemy_rank_sum <= 0 and not is_retreating:
    _flee_refuge_area_id = ""
    return
```

これでメンバーは敵が見えなくなっても refuge を見失わず、`_evaluate_exit_costs()` が
正しく避難先方向の出口を選び続ける。

#### 設計思想の変化

旧：「敵が見えてれば FLEE、見えなければ WAIT」（自動応答型）
新：「`combat == flee` 指示中は敵の有無に関係なく避難先まで退却」（明示指示尊重型）

NpcLeaderAI の自動 battle_policy 切替（CRITICAL → retreat / SAFE → attack）は維持。
SAFE 検知でクールダウン後に "attack" に戻れば `_combat` が "attack" に更新され、
通常モードに復帰する。撤退途中（クールダウン中）は新仕様で確実に refuge へ向かう。

#### 確認
- Godot `--check-only` exit 0
- 敵パーティーは `_is_enemy_party()` 早期リターンで影響なし
- battle_policy != "retreat" の通常戦闘では従来どおり SAFE → WAIT が動作

### 後追い修正 3（同日・避難先到達後の隊形戻り）

撤退指示の修正後（後追い修正 2）の検証で発覚：「メンバーが避難先（r0_10）に到達した
あと、`→隊形` アクションでリーダー方向に戻ってしまう」現象。

#### 原因

メンバーが避難先に到達すると、修正 2 のロジックで `_determine_effective_action()` が
WAIT を返す。WAIT の queue 生成は `_generate_move_queue()` を呼ぶ：

```
_:  # cluster / follow / same_room
    if not _formation_satisfied():
        # move_to_formation × 3 → wait
```

リーダー（操作キャラ）がまだ通路 c0_4 にいる間、メンバーから見ると `_formation_satisfied()`
は false（リーダーが避難先内ではないため）→ `move_to_formation` がキューに積まれる
→ メンバーがリーダーのいる通路方向に戻る。

#### 修正

`_generate_queue()` の WAIT 分岐に「撤退中で避難先到達済みなら隊形を組まずに待機」を
明示的に追加：

```
# WAIT: 移動方針に従って行動
if _member.is_friendly and _combat == "flee" and _is_in_refuge_area():
    return [{"action": "wait"}]
return _generate_move_queue()
```

これにより避難先内のメンバーは move_policy=cluster/follow/same_room であってもその場に
留まる。リーダーが追いつくのを待つ設計に統一。

#### 設計意図

撤退中の `_combat == "flee"` は「避難先まで退却する」だけでなく「避難先到達後は
リーダーを待つ」という意味も含む。隊形維持より避難先確保を優先する。

リーダーも同じく flee で動いているので、最終的にはリーダーも避難先に到達し、
全員が refuge 内で待機する形に収束する。

#### 確認
- Godot `--check-only` exit 0
- 平常時（_combat != "flee"）の WAIT は従来どおり formation 維持が動作
- 避難先未到達のメンバーは FLEE 戦略のままなので影響なし
- 敵パーティーは `_combat` を持たないので影響なし

### 後追い修正 4（同日・flee 中の前進不要判定追加 + `combat == flee` 意味論の明文化）

ここまでの修正で「border 往復」「WAIT 切替戻り」「隊形戻り」を順に解消したが、実プレイで
「敵から十分離れた後も避難先まで前進し続ける」状態が依然として残ることが分かった。
これは追加の改修とドキュメント整備で対応した。

#### `combat == flee` 意味論の変遷

旧仕様：「敵が見えれば flee・見えなければ wait」（自動応答型）
- → 敵検知が部屋単位で動作するため、境界往復や前進中断の温床
- → 後追い修正 2 で「明示指示尊重型」に変更（`_combat == "flee"` 中は敵の有無に
  関わらず避難先まで退却）

ただし新仕様では「敵から離れた後も避難先まで進み続ける」状態が発生したため、追加で
**flee 中の移動先決定**として前進不要判定を導入した。

#### 設計判断のポイント：「flee 解除」と「flee 中の移動先 = 現在地」の区別

検討段階で「FLEE_RELEASE_RANGE を新設して flee 状態を解除する」案も挙がったが、
**flee 解除トリガーは外部要因（HP critical 解除 / battle_policy 切替）に委ね、メンバー側
では能動的に解除しない設計**とした。

理由：
- メンバーが flee 状態を能動的に解除すると、敵が再接近したときの再 flee 発動条件が
  複雑化する（解除した瞬間に攻撃モードになり、また敵接近で flee に戻ると振動）
- 「flee 状態は維持したまま、移動先 = 現在地」のほうがシンプル：
  - 敵が再接近 → 次回 `_find_flee_goal()` で前進不要判定が外れ、再び避難先方向へ前進
  - 敵が離れたまま → 移動先 = 現在地のまま静止
  - HP critical 解除や battle_policy 切替で flee 状態自体が終了 → 通常モード復帰
- 解除条件と移動先決定を**異なるレイヤー**として分離することで、ロジックの直交性を
  確保

これは「停止条件」ではなく「移動先決定の自然な帰結」。flee 状態は維持される点が
「flee 解除」とは決定的に違う。

#### 修正内容

**1. `GlobalConstants` に `FLEE_SAFE_DISTANCE: int = 8` を追加**
- 意味：flee 中、最近接脅威との距離がこの値以上なら移動先 = 現在地
- placeholder 値：8 タイル（実プレイ調整対象）。`FLEE_THREAT_RANGE`（5）より大きく
  しないと脅威コスト計算範囲との整合が取れない
- Config Editor の UnitAI カテゴリに追加（既存 FLEE 系定数と同列）

**2. `UnitAI._calc_nearest_threat_distance()` を新設**
```
func _calc_nearest_threat_distance() -> int:
    # 同フロア・対立陣営・生存中のキャラクターの中で、
    # 自分の grid_pos から最近接のマンハッタン距離を返す
    # 該当なしは 999999（INT_MAX 相当）
```
- 既存の `_calc_threat_cost()`（per-tile コスト計算用）/ `_build_threat_map()`
  （事前計算用）/ `_is_far_enough_from_threats()`（fall_back 停止判定）とは用途が
  異なるため独立に保つ
- 敵ステータス直接参照禁止ルール準拠（位置と is_friendly / current_floor / hp のみ参照）

**3. `_find_flee_goal()` の冒頭に前進不要判定を追加**
```
func _find_flee_goal(threat) -> Vector2i:
    # ...既存ガード（味方限定・敵 legacy フォールバック）...
    if _is_in_refuge_area():
        return _member.grid_pos  # 既存：避難先到達済み
    # 新規：脅威から十分離れていれば前進不要
    if _calc_nearest_threat_distance() >= FLEE_SAFE_DISTANCE:
        return _member.grid_pos
    # 既存：_evaluate_exit_costs() で出口総合コスト評価
    ...
```

`_member.grid_pos` を返すと `_step_toward_goal()` が `goal == grid_pos` で false を
返してアクション完了 → 次のアクションも同じ → キュー消化が瞬時に進む。次の
queue 生成で `_generate_queue(FLEE)` が走るが、`_is_in_refuge_area()` が false で
かつ `_combat == "flee"` なので、未到達時は引き続き flee アクションが積まれる
（ただし実行時に再び前進不要判定で stop）。

#### fall_back への影響

なし。fall_back は別関数（`_find_fall_back_goal`）で独自の停止条件
（`_is_far_enough_from_threats() = attack_range + FALL_BACK_MARGIN`）を持つ。
両者は別関数・別定数で独立しているため、新たな前進不要判定は fall_back に波及しない。

意味論的にも：
- fall_back：「戦闘継続しつつ射程外まで下がる」（射程確保が目的）
- FLEE：「戦闘から離脱して安全な距離まで下がる」（安全距離確保が目的）

設計が独立しているため別 API として維持する。

#### CLAUDE.md 更新

「FLEE / fall_back の逃走先決定ロジック」セクションに以下を追加：
- `combat == "flee"` 指示の意味論小節（明示指示尊重型・解除条件は外部要因のみ）
- 「flee 中の移動先決定（前進不要判定）」小節（`FLEE_SAFE_DISTANCE` 経由の停止）
- fall_back との関係小節を更新（両者の停止条件の独立性を明記）
- 関連定数表に `FLEE_SAFE_DISTANCE` を追加

「実装状況」AI システム配下に 1 行追加。

#### 動作確認

- Godot `--check-only` exit 0
- `_calc_nearest_threat_distance()` の閾値判定は既存 `_calc_threat_cost()` などと
  独立しているため互いに干渉しない
- 平常時（`_combat != "flee"`）の挙動は変更なし

#### スコープ外

- 敵パーティーの flee（既存 `_find_flee_goal_legacy` のまま・別タスク）
- `keep_distance` の共通コア関数経由化（既存派生課題のまま）
- PartyStatusWindow に「前進不要中」フラグの追加表示（現状 `状態:flee→(grid_pos)` で
  「目標 = 現在地」が読み取れるため十分・必要なら別タスク）

## ヒーラーの回復対象選定に射程内フィルタを追加（2026-04-25）

### 報告された現象
1. ヒーラーを仲間にしてもリーダーについてこない（追従動作が機能しない）
2. 撤退指示（`battle_policy = "retreat"` / `combat = "flee"`）を出しても
   ヒーラーの状態が「逃走」にならない

### 原因（調査結果）

`UnitAI._find_heal_target()` に**射程チェックがなく**、ヒーラーは全フロア・全味方の
中から HP 率最低の対象を返していた（射程外でも対象とみなす）。結果：

- `_generate_queue` 行 752-754 で **strategy 判定（FLEE/ATTACK/WAIT）より前に**
  `[move_to_heal, heal]` キューが返される
- `move_to_heal` アクションが「射程外なら隣接タイルへ移動」を発動
- → move_policy（follow / cluster）も `combat == "flee"` も実質的に無視される

技術的には `_determine_effective_action()` が `combat == "flee"` で正しく FLEE strategy を
返すが、回復キューが先に消化されるため strategy 判定まで処理が到達しない（マスクされる）。

### 設計意図の整理（修正前）

ヒーラーは以下の規約で動くべき（要再確認）：
- 射程内の対象だけを回復する（射程外の対象を追って移動しない）
- 戦闘行動のために移動しない（移動は move 指示・combat 指示に従う）
- 回復は `combat` 値に関わらず、射程内に対象がいれば実行（撤退中も）
- 射程内にアンデッド + 回復対象がいたら回復優先

通常はリーダー追従（`move == "follow"`）により自軍メンバーが自然と射程内に入る前提。
射程外の味方を救えないケースは現状の仕様の自然な帰結として受容する（プレイヤーが
追従指示を維持する責務）。

### 検討した修正方針

| 案 | 概要 | 推奨度 | 採否 |
|---|---|---|---|
| A | `_find_heal_target()` に射程内フィルタ追加 | ★★★★★ | **採用** |
| B | `combat == "flee"` 時に回復をスキップ | ★★★ | 不採用（撤退中も回復継続の設計に矛盾） |
| C | `move_policy` で `heal_mode` を動的切替（follow なら conservative） | ★★ | 不採用（UI 指示が無視される感覚） |
| D | `move_to_heal` の到達不能ガード強化 | ★★ | 不採用（既に実装相当・効果薄） |

「射程外の critical を救う例外条件」も検討したが、設計の単純性を優先し採用しない。
通常運用で問題が出れば後追いで例外条件を入れる。

### 修正内容

`UnitAI._find_heal_target()` の各 `heal_mode` 分岐（`aggressive` / `lowest_hp_first` /
`own_party_first` / `conservative`）の対象選定ロジックに `_is_in_heal_range()` フィルタを
追加。

```gdscript
func _is_in_heal_range(target: Character) -> bool:
    if _member == null or not is_instance_valid(_member):
        return false
    if target == null or not is_instance_valid(target):
        return false
    if target.current_floor != _member.current_floor:
        return false
    return _manhattan(_member.grid_pos, target.grid_pos) <= _member.attack_range
```

- 射程の判定には `Character.attack_range`（装備補正込み・最終値）を使う
- 同フロア + マンハッタン距離 ≤ attack_range のみ対象
- 自分自身は距離 0 で常に射程内（既存仕様維持）
- 射程内に対象なし → `null` 返却 → `_generate_queue` の通常フローに合流（move 指示・
  FLEE 戦略・WAIT 戦略が機能する）

### 期待挙動

| シナリオ | 修正前 | 修正後 |
|---|---|---|
| 射程内に被ダメージ味方あり | 回復実行 | 回復実行（変化なし） |
| 射程外に被ダメージ味方あり | **追って移動 → 回復** | **無視（move 指示に従う）** |
| 自分自身が被ダメージ | 自己回復 | 自己回復（変化なし・距離 0） |
| 射程内に対象なし・move=follow | 遠方の対象を追う | リーダー追従 |
| `combat == "flee"` 中 | 回復が先に消化されて FLEE 状態にならない | 射程内対象あれば回復・なければ FLEE 戦略へ |
| アンデッド + 回復対象が射程内 | 回復優先（変化なし） | 回復優先（変化なし） |

### 副次的影響と確認項目（次タスク候補）

修正後の実機検証で以下を観察：

1. **`rear` 隊形でヒーラーが ATTACK strategy に入った場合**：射程内に回復対象なし、
   非アンデッド敵のみ存在のとき、`_can_attack_target` がヒーラーのスキル不在を考慮
   しないため無駄な `move_to_attack` キューが積まれる可能性。スコープ外。
2. **合流直後の `_follow_hero_floors` 更新タイミング**：`receive_order` の
   `QUEUE_MIN_LEN` チェック（行 312）でキュー再生成が抑制される可能性。スコープ外。
3. **OrderWindow の heal_mode UI 設定の有無**：未指定時はソースコード固定の
   `lowest_hp_first` がデフォルト。プレイヤーが UI から変更できるか別途確認。

### CLAUDE.md 更新

「クラスシステム」セクション内（魔法使い（水）の仕様の直後・AI と実処理の責務分離方針の
直前）に「ヒーラーの行動規約」小節を新設。設計意図を簡潔に明記し、実装場所を
[`unit_ai.gd:_find_heal_target()`](scripts/unit_ai.gd) に紐付ける。

「実装状況」AI システム配下に 1 行追加。

### 確認

- Godot `--check-only` exit 0
- 4 つの heal_mode 分岐すべてに `_is_in_heal_range()` フィルタを通すことを目視確認
- 自パ用候補（own_party_first / conservative）と全体候補（aggressive / lowest_hp_first）の
  両系統で動作

### スコープ外（今回触らない）

- `rear` 隊形の動作確認・「後衛前進問題」（既存派生課題）
- `_can_attack_target` がヒーラーのスキル不在を考慮しない問題
- 合流直後の `_follow_hero_floors` 更新タイミング（QUEUE_MIN_LEN 抑制）
- 敵ヒーラー（dark_priest）の動作確認
- 回復モード 4 種の内部実装の改善

## rear 隊形を keep_distance ベースに変更・keep_distance 実装をターゲット中心ロジックに刷新（2026-04-25）

### 報告された現象

「後衛前進問題」：弓使い・魔法使い・ヒーラーといった rear 指定（後衛）のメンバーが、
戦闘開始時に敵に向かって近づき、近接戦闘の射程まで踏み込んでしまう。敵が後衛に
踏み込んできても下がるロジックがないため、後衛が前線に取り残される。

### 原因（2 段階の調査結果）

#### 第 1 次調査：攻撃キュー生成条件

[unit_ai.gd:824-828](scripts/unit_ai.gd) の `match _battle_formation` の `"rear"` ケース：
```gdscript
"rear":
    if _can_attack_target(target, atype):
        return [{"action": "attack"}, {"action": "attack"}]
    return [{"action": "move_to_attack"}, {"action": "attack"}]  # ← 射程外なら近づく
```

→ rear でも射程外なら `move_to_attack` で接近する。「rear = 背後を取る位置取り」
（`_get_path_method()` で `ASTAR_FLANK`）の方針は持つが、「下がる」ロジックは存在しない。

#### 第 2 次調査：探索→戦闘の遷移

戦闘モード遷移は単純で `_combat_situation.situation != SAFE` で個体の strategy が
ATTACK になる。rear 隊形のメンバーは ATTACK 戦略確定後すぐ `move_to_attack` を生成
（射程外なら接近・射程内なら攻撃）。退避ロジックの介入余地がない。

「戦闘モード」を表現する明確な状態フラグはなく、`_is_combat_safe() == false` が
事実上の戦闘判定。

### 設計方針の確定

#### `keep_distance` の本質

- **ターゲット中心の距離維持**（避難先方向ではなく、自分の攻撃ターゲットを基準）
- 理想範囲：ターゲットからのマンハッタン距離が `[KEEP_DISTANCE_MIN, KEEP_DISTANCE_MAX]`
- 理想範囲は遠距離射程基準の絶対値（クラス非依存）

#### 3 個体アクションの位置づけ整理

| アクション | 移動の本質 | 参照位置 | 実装 |
|---|---|---|---|
| `flee` | 戦闘離脱・避難先方向 | パーティーの避難先エリア | `_evaluate_exit_costs()` |
| `fall_back` | 戦線後退・避難先方向 | パーティーの避難先エリア | `_evaluate_exit_costs()` |
| `keep_distance` | 戦闘継続・**ターゲット中心**の距離維持 | **攻撃ターゲット** | **`_find_keep_distance_goal()`（新設）** |

flee / fall_back は「パーティーレベルの方向性（避難先）」に従う。keep_distance は
「個別の戦闘位置（自分のターゲット）」に従う。**思想が異なるので別ロジックで実装**。

#### rear 隊形の動作フロー

```
ATTACK 戦略 + battle_formation == "rear":
  dist = manhattan(self, target)
  if dist in [KEEP_DISTANCE_MIN, KEEP_DISTANCE_MAX]:
    if 射程内:
      attack
    else:
      keep_distance（近接が rear 指定された場合・理想範囲だが攻撃不可）
  else:
    keep_distance（理想範囲外・近づく or 下がる）
```

近接キャラが rear を選ぶと、理想範囲内にいても攻撃できない状態が続く（仕様として
許容・プレイヤーの選択責任）。

### 修正内容

#### 1. 新定数（GlobalConstants）
- `KEEP_DISTANCE_MIN: int = 3` — 理想距離下限
- `KEEP_DISTANCE_MAX: int = 4` — 理想距離上限
- `KEEP_DISTANCE_REACH_WEIGHT: float = 0.5` — goal 選定の到達コスト重み
- すべて Config Editor の UnitAI カテゴリに露出（placeholder 値・実プレイ調整対象）

#### 2. `UnitAI._find_keep_distance_goal(target)` を新設

ターゲット中心の同心円帯（マンハッタン距離 `[MIN, MAX]`）から候補タイルを列挙し、
`threat_cost + reach_cost × KEEP_DISTANCE_REACH_WEIGHT` 最小のタイルを返す。

- threat_cost：候補タイルでの脅威累積（`_build_threat_map()` から引く）
- reach_cost：自分の現在位置 → 候補タイルの A* 距離
- 候補タイルは `_is_walkable_for_self()` でフィルタ（壁・障害物・占有・敵の安全エリア進入禁止）
- 候補なし / target 不在 → 現在位置を返す（IDLE = 動かない）
- 現在位置が理想範囲内なら自然に候補に含まれる（無駄な移動を避ける）

#### 3. `_generate_queue()` ATTACK 分岐の rear ケース変更

旧：射程内なら attack、射程外なら `move_to_attack` で接近
新：理想範囲内 + 射程内なら attack、それ以外は `keep_distance`

#### 4. `keep_distance` アクションハンドラの差し替え

`_start_action` / `_step_toward_goal` で `keep_distance` 実行時に `_find_flee_goal()` を
呼んでいた箇所を `_find_keep_distance_goal(_target)` に切り替え。

#### 5. PartyStatusWindow 表示

メンバー行の goal 表示に `kd→(x,y)` ラベル追加（`flee→` / `fb→` と並列）。
`_current_action.action == "keep_distance"` のときに kd ラベルが選ばれる。

### GoblinArcher / Salamander への影響

旧：`_find_flee_goal()` 流用 → 避難先方向に動く（敵にとって不自然）
新：`_find_keep_distance_goal()` → プレイヤーから距離 3〜4 を維持しつつ攻撃

「敵が避難先方向に下がる」という旧挙動は元々設計として変だったため、これは挙動改善。
派生課題「`keep_distance` を `_evaluate_exit_costs()` 経由に切り替え」は別ロジックで
実装する形で実質的に解消。

### 動作確認項目

1. プレイヤーパーティーで弓使い・魔法使い・ヒーラーを連れて敵に遭遇
2. battle_formation = "rear" のメンバーがターゲットからの距離 3〜4 を維持して攻撃
3. 敵が踏み込んできた時、後衛が下がる
4. 後衛が遠すぎる時、適切に近づいて理想範囲に入る
5. 近接キャラ（剣士・斧戦士）に rear 指定 → 理想範囲内でも攻撃しない（仕様）
6. 敵側 GoblinArcher / Salamander：プレイヤーから距離 3〜4 を維持して攻撃
7. 戦況 SAFE になったら（敵未検知・撃破後）後衛は move 指示に従う

### CLAUDE.md 更新

- 「個体アクションの分類」表で `keep_distance` の生成元・発生キャラを更新
- 「実行ロジック」一覧で `keep_distance → _find_keep_distance_goal()` に書き換え
- 「rear 隊形の動作」項目を新設
- 「FLEE / fall_back の逃走先決定ロジック」内に「keep_distance との関係」小節を更新（思想の違いを明記）
- 「関連定数」表に `KEEP_DISTANCE_MIN/MAX/REACH_WEIGHT` を追加
- 「FLEE 派生課題」から完了 2 項目（味方クラスへの keep_distance 適用 / `_evaluate_exit_costs()` 経由化）を削除
- 「実装状況」AI システム配下に 1 行追加
- 「残タスク」に「NPC スタック問題（ランダム要素検討）」を追加（観察項目として）

### 確認

- Godot `--check-only` exit 0
- `keep_distance` アクションは `_start_action` と `_step_toward_goal` の両方で
  `_find_keep_distance_goal()` を呼ぶように差し替え済み
- 既存の flee / fall_back ロジックには影響なし（_find_flee_goal / _find_fall_back_goal は変更なし）

### スコープ外

- 個別メンバーの戦闘モード判定を個体視点に切り替える（後日検討）
- 1.5 秒遷移遅延問題（`notify_situation_changed` のエリア進入連携）
- 壁越し攻撃が可能な問題（既知・別タスク）
- NPC スタック問題（残タスク追加・別タスクで対応）
- 敵パーティーの flee（既存 `_find_flee_goal_legacy` のまま）

### 後追い修正（同日・実機検証で 3 つの問題発覚）

スナップショットで観察された問題：
1. **`kd→` ラベルが表示されない**：オフィア（魔法使い）が「距離確保[q1]」状態なのに `状態:flee→(10,19)` と表示
2. **ヒーラーが距離確保にならない**：ロシェル F:rear なのに `[follow]キュー空(WAIT)`
3. **魔法使いが距離確保なのに敵から動かない**：オフィア @r0_5（target は @c0_16・距離 10+）が「距離確保」表示のまま動かず

#### 原因と修正

**1. 表示ラベルの問題**

`PartyStatusWindow._build_ai_flag_parts()` のラベル分岐は `_current_action.action` を参照。
IDLE 状態の瞬間（アクション完了 → 次アクション pop の合間）には `_current_action` が空辞書
になり、ラベルが default の "flee" に落ちる。`_last_flee_goal` 値も古いまま表示される。

**修正**：`_current_action.action` が空なら `_queue[0].action` をフォールバック参照する。

**2. ヒーラーが distance 確保にならない問題**

`_generate_queue` の ATTACK 分岐で、ヒーラー（`atype == "heal"`）+ 非アンデッド target の
場合、line 820-822 で `_generate_move_queue()` で抜けていた。これは rear 分岐より**前**
のため、rear 指定ヒーラーも move_policy（follow 等）に従ってしまう。

**修正**：rear 指定ヒーラーは早期 return せず、後続の rear 分岐に進ませる。
非 rear のヒーラーは従来どおり `_generate_move_queue()` に進む。

```gdscript
if atype == "heal":
    if target.character_data == null or not target.character_data.is_undead:
        if _battle_formation != "rear":
            return _generate_move_queue()
        # rear ヒーラー：下の rear 分岐に進ませる
```

rear 分岐内では `_can_attack_target` が false（ヒーラーは非アンデッド攻撃不可）なので、
理想範囲内でも `keep_distance` を返す。これにより rear ヒーラーは「敵から距離 3〜4 を
維持する」挙動になる。

**3. 魔法使いが動かない問題**

`_find_keep_distance_goal()` の各候補タイル評価で `_astar(member, tile)` を呼ぶが、
member が target から遠い（10+ タイル）場合、A* の `max_iter=400` を超えてパスが
empty で返る。全候補が rejected → `found_any = false` → 現在位置返却 → 動かない。

**修正**：A* 失敗時は `_manhattan(member, tile)` をフォールバック reach_cost として使い、
候補から外さない。これで遠方の rear メンバーも近づく方向の候補が選ばれ、移動開始。
近づくにつれ A* が成功するようになり、正確な評価へ自然移行する。

```gdscript
var reach_cost: float
if tile == _member.grid_pos:
    reach_cost = 0.0
else:
    var path = _astar(_member.grid_pos, tile)
    if not path.is_empty():
        reach_cost = float(path.size())
    else:
        # A* 失敗 → マンハッタン距離で代替評価
        reach_cost = float(_manhattan(_member.grid_pos, tile))
```

#### 確認

- Godot `--check-only` exit 0
- 3 修正は独立しており互いに干渉しない
- 仕様変更：ヒーラーで非アンデッド target の場合の挙動が「rear なら距離確保 / 非 rear なら move 指示」に変わる（旧：常に move 指示）
- パフォーマンス：A* フォールバックは候補数を減らさないため評価コスト変化なし。実際の移動は変わる

## PartyStatusWindow 表記整理 + HpStatus 廃止 + 戦況表示構造化（2026-04-25）

### 背景

PartyStatusWindow / F7 スナップショットの表示が日本語と英語（コード内部値）で混在していた。
3 段の事前調査（表示要素のリストアップ → HP 表現の使い分け確認 → HpStatus 用途特定）の結果、
以下の整理方針が確定：

- **UI（ゲーム上）で日本語表示されるもの → 日本語**（OrderWindow の選択肢など）
- **それ以外 → コード上の名前**（既存のコード識別子をそのまま使用・新規命名禁止）

加えて以下の問題を同時に解消：
1. `HpStatus` enum（FULL/STABLE/LOW/CRITICAL）の用途が `_should_use_special_skill()` の
   "disadvantage" モード判定 1 箇所のみで、4 段階の意味が薄れていた
2. 個体 HP 段階（healthy/wounded/injured/critical・閾値 50/35/25%）と HpStatus
   （FULL/STABLE/LOW/CRITICAL・閾値 75/50/25%）の閾値が異なり混乱の種だった
3. 戦況計算の構造（戦力 × HP 率 = 戦況比）が表示で見えず、計算過程のデバッグが困難
4. デッドコード `_calc_hp_status()` / `_calc_hp_status_for()` が残存

### 設計方針

#### HP 関連表現の整理

「行動判断ごとに専用閾値」方式を採用：
- **個体 HP 段階**（`Character.get_condition()`）：複数判断で共有する閾値として段階ラベル経由方式を維持
- **パーティー HP 率**：段階表現は廃止し、用途ごとの専用閾値を float 定数として持つ

#### 戦況表示の構造化

旧：`戦況:互角(9.0/9.0=1.00) ... HP:満(...)`
新：`戦況:EVEN(9.0×1.00 / 9.0×0.85 = 1.18)`

- 戦況比の計算に使われる「自軍戦力 × 自軍 HP 率 / 敵戦力 × 敵 HP 率」を括弧内で完全に表示
- 独立した HP 表示は廃止
- 戦況・戦力の値は CombatSituation / PowerBalance enum 名そのまま（日本語化を廃止）

### 修正内容

#### 1. `HpStatus` enum の廃止

`global_constants.gd` から削除：
- `enum HpStatus { FULL, STABLE, LOW, CRITICAL }`
- `HP_STATUS_FULL` (0.75) — どこからも参照なし
- `HP_STATUS_LOW` (0.25) — どこからも参照なし

`HP_STATUS_STABLE` (0.5) は npc_leader_ai.gd で使用されていたため、
`NPC_FLOOR_DOWNGRADE_HP_RATIO` に改名し、意味を明示。

#### 2. 新定数 `SPECIAL_SKILL_DISADVANTAGE_HP_RATIO`

```
SPECIAL_SKILL_DISADVANTAGE_HP_RATIO: float = 0.5
```
- 旧 `HpStatus.LOW` (HpStatus 廃止前の閾値 0.5 = STABLE/LOW 境界) を踏襲
- Config Editor の UnitAI カテゴリに登録

#### 3. `_should_use_special_skill()` の修正

`unit_ai.gd:2369-2374` の "disadvantage" 判定を float 比較に変更：

```gdscript
"disadvantage":
    var hp_ratio: float = float(_combat_situation.get(
        "nearby_allied_hp_ratio", 1.0))
    return hp_ratio <= GlobalConstants.SPECIAL_SKILL_DISADVANTAGE_HP_RATIO
```

#### 4. `_combat_situation` 辞書の整理

- 削除：`hp_status` キー（`_combat_situation` および `hint`）
- 追加：`nearby_enemy_hp_ratio` キー（戦況構造化表示に必要）
- 既存維持：`nearby_allied_hp_ratio` / `full_party_hp_ratio`

#### 5. デッドコード削除

`party_leader.gd` から削除：
- `_calc_hp_status()` 関数
- `_calc_hp_status_for()` 関数
- `_calc_hp_breakdown_for()` の `status` キー導出ロジック（戻り値も簡略化）

#### 6. PartyStatusWindow 表示刷新

**戦況構造化**：
- `_combat_situation_label_with_ratio()` を `戦況:<ENUM>(自軍×自軍HP率 / 敵×敵HP率 = 比)` 形式に
- `_hp_status_label*()` 関数群を削除
- `_combat_situation_label()` / `_power_balance_label()` を enum 名そのまま返すように変更
- `HP:` 独立表示を廃止（味方 / 敵パーティーヘッダー両方）

**短縮形廃止**：
- `_build_orders_field_list()` の `_shorten()` 呼び出しを `_label()` に置き換え
- OrderWindow の正規表記（日本語）を直接表示
- 例：`T:same_as_` → `T:リーダーと同じ` / `S:積極` → `S:積極的に使う`
- 文字数増は F3 詳細度トグルで対応する方針

**NPC フラグの識別子化**：
- 旧：`合流:Y 拒絶:N 共闘:Y 回復:N 床固定`
- 新：`joined_to_player:Y was_refused:N has_fought_together:Y has_been_healed:N suppress_floor_navigation:N`
- コード上のフィールド名そのまま（`suppress_floor_navigation` も Y/N 表示に統一）

**アクション名のコード識別子化**：
- `get_debug_goal_str()` の戻り値を「コード上のアクション名そのまま」に変更
- 例：`→攻撃Goblin` → `move_to_attack:Goblin` / `攻撃準備` → `attack[ATKp]`
- `逃走` → `flee` / `距離確保` → `keep_distance` / `後退` → `fall_back` / `回復実行` → `heal` / `バフ実行` → `buff` / `ポーション` → `use_potion` / `待機` → `wait`
- `→隊形` → `move_to_formation` / `→帰還` → `move_to_home`
- `move_to_explore` の階段タイル特殊表示は `move_to_explore:stairs_down(x,y)` 形式に
- キュー空表示：`[follow]キュー空(MOV)` → `[follow]queue_empty(MOV)` / `L追従` → `follow_leader`

**維持項目**：
- `mv=↓階段(F2)` の特殊表記は現状維持（NPC 専用・移動方針の方向を視覚的に示す表現）
- パーティー種別ヘッダー（`[プレイヤー] / [NPC] / [敵]`）
- 陣営ラベル（`fac:味方 / fac:敵`）
- ランクラベル（`[S] / [A] / [B] / [C]`）
- クラス名（`(剣士) / (ヒーラー)` 等）
- ラベル名（`戦況: / 戦力: / 避難先: / 指示: / 状態: / 種:` 等）
- ステータス略称（`pow / skl / rng` 等）
- HP 個体段階（`healthy / wounded / injured / critical`・既に英語）

#### 7. F7 スナップショットへの反映

PartyStatusWindow と同じ `_format_*` / `_build_*` 関数を共有するため、上記すべての変更が
自動的に反映される。スナップショット用の独立した formatter は持たない。

### CLAUDE.md 更新

- 「HP 充足率（HpStatus）」セクションを大幅縮小・命名は「HP 充足率（パーティー単位）」に変更し、
  3 つの HP 表現の使い分けを明示
- 「特殊攻撃の指示と発動条件」表で「劣勢なら使う」の発動条件を `nearby_allied_hp_ratio ≤ SPECIAL_SKILL_DISADVANTAGE_HP_RATIO` に書き換え
- 「ゲーム内閾値一覧」表から `HP_STATUS_*` を削除し、専用閾値（`SPECIAL_SKILL_DISADVANTAGE_HP_RATIO` /
  `NPC_FLOOR_DOWNGRADE_HP_RATIO`）の存在を明記
- 「PartyStatusWindow」ヘッダー行例を新表記に更新（戦況構造化・enum 名・正規表記・NPC フラグ識別子）
- 「実装状況」AI システム配下に 1 行追加
- 「残タスク」優先度低に「HP 表現の命名整理」「state 表示の実装」を追加

### 動作確認

- Godot `--check-only` exit 0
- HpStatus / HP_STATUS_* / hp_status の grep でコード上の参照ゼロ確認（残るのは説明コメントのみ）
- `_should_use_special_skill()` の "disadvantage" 判定動作確認（次セッションで実機検証）

### スコープ外

- CombatLogWindow / MessageWindow / バトルメッセージの表記（後日対応）
- HP 表現の命名整理（`get_estimated_condition()` への改名等・残タスクに追加）
- state 表示の実装（残タスクに追加）
- mv=↓階段(F2) の特殊表記（現状維持）
- 個体 HP 段階（healthy/wounded/injured/critical）の閾値・命名（設計原則として維持）


## 2026-04-25 NPC 階段ナビの per-member 配布化（`_global_orders.move` 規約違反の解消）

### 背景・問題

PartyStatusWindow / F7 スナップショットで NPC パーティーのヘッダー行に `mv=↓階段(F1)`
が表示されていた。CLAUDE.md 規約上、ヘッダー行の `mv=` は `_global_orders.move`
（パーティー全体指示）を表示する場所であり、想定値域は OrderWindow の 5 値
（follow / cluster / same_room / standby / explore）のみ。`stairs_down` / `stairs_up`
が出るのは設計違反。

```
[NPC]  生存:2/2  area:r0_10  ... mv=↓階段(F1)  battle=攻撃 ...
  ジョルダン[A](斥候) ... | move:↓階段 |
  エドワード[C](ヒーラー) ... | move:密集 |
```

### 調査結果（2 段階）

#### 第 1 段階：階段ナビ実装の調査

- `_global_orders.move` への書き込み箇所は `npc_leader_ai.gd:_build_orders_part()`
  のみ（探索モード時に `hint["move"] = "stairs_down/stairs_up/explore"`、`hint["target_floor"]`
  も同時に書き込み）
- `party_leader.gd:_assign_orders()` には**既に正しい per-member 上書きロジックが
  存在**（line 374-388）：`_is_in_explore_mode()` 時にリーダー → `_get_explore_move_policy()`
  の戻り値（stairs_*/explore）/ 非リーダー → `cluster` で per-member 配布
- 問題は「内部処理は正しいが、`_build_orders_part()` の戻り値が `get_global_orders_hint()`
  経由で PartyStatusWindow ヘッダーに直接表示される」という二重役割の汚染
- CLAUDE.md 規約「リーダー→stairs_down / 非リーダー→cluster に差し替え」は実装済み（実際は
  per-member 配布が機能していた）

#### 第 2 段階：合流済みパーティーの実態確認

修正前に「合流済みパーティー（`joined_to_player == true`）が独立実体として存在するか」
を確認。結論：

- 2026-04-24 改修（commit 0bf8c9c）で `_merge_npc_into_player_party` がメンバーを
  `_hero_manager` に**完全移管**する方式に変更
- 元の NPC PartyManager は `queue_free()` で削除される（`game_map.gd:1108`）
- ただし `_merge_npc_into_player_party` で `_hero_manager.set_joined_to_player(true)`
  が呼ばれていない → 独立した「合流済み NPC パーティー」は実態として存在しない
- CLAUDE.md の「合流済みパーティーは別途 `_generate_floor_follow_queue()` が...」
  記述は旧実装ベース（commit 6d4e2d5 以前）で乖離
- 階段ナビ修正は合流済みパーティー対応を考慮する必要なし

非対称な発見：`_merge_player_into_npc_party`（プレイヤーが NPC パーティーに加入する
逆パターン）では NPC 側に `set_joined_to_player(true)` がセットされる。逆パターンの
発火経路の有無は要確認（残タスクに追加）。

### 修正内容

#### 1. `npc_leader_ai.gd:_build_orders_part()` — `stairs_*` / `target_floor` の hint 書き込み廃止

旧：
```gdscript
if not joined_to_player and _is_in_explore_mode():
    var pol := _get_explore_move_policy()
    hint["move"] = pol  # stairs_down/stairs_up/explore
    if pol == "stairs_down" or pol == "stairs_up":
        hint["target_floor"] = str(_get_target_floor())
```

新：
```gdscript
if not joined_to_player and _is_in_explore_mode():
    var pol := _get_explore_move_policy()
    if pol == "explore":
        hint["move"] = pol
    # stairs_down / stairs_up / target_floor は hint に書き込まない
    # （_assign_orders 側の per-member 配布ロジックがリーダー個人にのみ伝達する）
```

#### 2. CLAUDE.md 更新

- 「実装状況」AI システムに新項目を追加（NPC 階段ナビの per-member 配布化）
- 「フロア間メンバー追従」セクションを更新：`_global_orders.move` への書き込みを
  禁ずる旨と、合流済みパーティー実態の修正を反映
- PartyStatusWindow セクションの「移動方針プレフィックス」記述を更新：per-member の
  実体が `_move_policy` であること、`_global_orders.move` の値域は OrderWindow 5 値
  限定であることを明記
- 「残タスク」優先度：中 に「合流済みパーティー周辺の実装整理」を追加

### 設計上の決定

#### `explore` の扱い（スコープ外）

`explore` は OrderWindow 定義値の範囲内（5 値の 1 つ）なので、`_build_orders_part()`
が `hint["move"] = "explore"` と書き込むのは規約準拠。ただし「全体指示として `explore`
を配布する」という意味で、OrderWindow の他値（`follow` 等）と意味的にやや異質
（NPC ベースラインからの上書き）。これは別議論・スコープ外として今回は触らない。

#### `battle_policy` の自動切替（OrderWindow 定義値の範囲内なので問題なし）

`npc_leader_ai.gd:_evaluate_and_update_battle_policy()` が CRITICAL 時に
`_global_orders["battle_policy"] = "retreat"` と書き換える挙動は、OrderWindow 定義値
の範囲内（attack / defense / retreat）なので規約違反ではない。今回の修正対象外。

### 動作確認・スコープ外

- 動作確認：実機での挙動確認は次セッション
- 期待挙動：
  - NPC ヘッダー行 `mv=` が OrderWindow 定義値（追従/密集/同じ部屋/待機/探索）になる
    （`↓階段(F1)` は出ない）
  - メンバー行：リーダーは `move:↓階段` / 非リーダーは `move:密集`（`_move_policy`
    直読みなので per-member の値が出る）
  - 階段ナビ動作自体は変化なし（リーダーが階段に向かい、他は追従系で続く）

### スコープ外（残タスク化）

- `explore` の `_global_orders.move` への書き込み（同種の問題だが OrderWindow 定義値内なので
  実害なし）
- 合流済みパーティー周辺の整理（`_merge_npc_into_player_party` で
  `set_follow_hero_floors()` が呼ばれない・`_generate_floor_follow_queue()` のデッド
  コード判定・`joined_to_player` フラグの存在意義整理）
- `_generate_floor_follow_queue()` 自体の現状の発動経路の確認
- 階段ナビの ヘッダー目標フロア表示（`(F1)` 部分）が消えるが、これはパーティー全体
  ではなくリーダー個人の動的目標として扱う方針なので意図通り。リーダー側のメンバー行に
  `(F1)` を出すかは別議論

## 2026-04-25 セッション総括（派生課題と次セッションへの引継ぎ）

### このセッションで実施した修正（時系列）

1. **FLEE / fall_back 出口選択ロジック統一・リーダー推奨機構廃止**
   - 境界往復バグ（メンバー先行時に推奨タイル座標が exit_tiles に含まれず、座標一致判定が常に偽になる現象）の根本対策
   - 共通コア `UnitAI._evaluate_exit_costs()`（reach_cost + refuge_dist × WEIGHT）でメンバー自律判断に統一
   - リーダーは避難先エリア ID のみ配布（推奨出口タイル機構を物理削除）
   - 関連定数 `FLEE_NON_RECOMMENDED_PENALTY` / `FLEE_REEVAL_MIN_INTERVAL` / `_notify_area_change_if_needed` / `on_member_area_changed` を物理削除
   - 出口タイル定義を内側 → 外側に変更（`MapData.get_exit_tiles_from()` が「area_id 内のタイル」から「隣接エリアに踏み込んだ最初のタイル」を返す形へ）。goal 到達 = エリア境界跨ぎになり連鎖走行が自律的に成立

2. **`combat == "flee"` 意味論変更 + flee 中の前進不要判定追加**
   - 旧「敵検知 → flee / 未検知 → wait」の自動応答型ロジックが境界往復・WAIT 切替で前進中断する温床だったため、明示指示尊重型に変更
   - 敵の有無に関わらず指示中は避難先まで退却する仕様に
   - `_calc_nearest_threat_distance() >= FLEE_SAFE_DISTANCE` なら移動先 = 現在地（前進不要判定）を `_find_flee_goal()` 冒頭に追加
   - これは flee 解除ではなく移動先決定ロジックの拡張で、flee 状態自体は維持される

3. **ヒーラーの回復対象選定に射程内フィルタ追加**
   - 旧実装では `_find_heal_target()` に射程チェックがなく、ヒーラーは常に最遠の対象を追って移動 → move 指示・`combat == "flee"` 指示が無視されていた（追従しない・撤退しない）
   - 射程内フィルタ追加で「射程内対象あれば回復・なければ move 指示に従う」のシンプルな対称性を確立
   - 通常メンバーと同じ move/combat フローに合流

4. **rear 隊形を keep_distance ベースに変更・keep_distance 実装をターゲット中心ロジックに刷新**
   - 旧 rear は「背後を取る位置取り」のみで敵接近時の退避ロジックなし（後衛前進問題）
   - 新仕様：rear メンバーは「理想範囲（`KEEP_DISTANCE_MIN`〜`MAX`）内に入ってから攻撃」の階層構造
   - `keep_distance` アクションを `_find_flee_goal()` 流用から `_find_keep_distance_goal()`（ターゲット中心・脅威コスト最小タイル選定）に刷新
   - GoblinArcher / Salamander も新ロジックで動作

5. **PartyStatusWindow 表記整理 + HpStatus 廃止 + 戦況表示構造化**
   - 日本語/英語混在の表示を方針に従って整理（OrderWindow 由来は日本語・コード内部値はコード上の名前）
   - 短縮形（`T:same_as_` / `S:積極` 等）を廃止し OrderWindow 正規表記に統一
   - NPC フラグ（合流/拒絶/共闘/回復/床固定）をコード識別子表記に変更
   - `HpStatus` enum は用途が `_should_use_special_skill()` の "disadvantage" モード 1 箇所のみで段階表現の意味が薄れていたため廃止し、`SPECIAL_SKILL_DISADVANTAGE_HP_RATIO` 定数（ConfigEditor 調整可能）に置換
   - `HP_STATUS_STABLE`（NPC フロア降下判定で使用）は `NPC_FLOOR_DOWNGRADE_HP_RATIO` に改名
   - 戦況表示を構造化（`戦況:EVEN(9.0×1.00 / 9.0×0.85 = 1.18)`）し計算過程を可視化
   - `HP:` 独立表示は廃止
   - アクション表示（→攻撃/距離確保/逃走 等）をコード識別子（move_to_attack/keep_distance/flee 等）に統一

6. **NPC 階段ナビの per-member 配布化**
   - 旧実装は NpcLeaderAI が `_global_orders.move = "stairs_down"` を書き込み全メンバーに配布
   - PartyStatusWindow ヘッダーに OrderWindow 定義外の `mv=↓階段(F1)` が表示される規約違反だった
   - 調査で `_assign_orders()` 側に既に正しい per-member 配布ロジックが存在することが判明（リーダー → stairs_* / 非リーダー → cluster）
   - 修正は `_build_orders_part()` で `stairs_*` と `target_floor` の hint 書き込みを廃止するだけで完結（最小修正）
   - 詳細は同日付別エントリ参照

### このセッションで発見した派生課題（次セッションへ）

1. **`mv=` と `move:` の不整合**：ヘッダー `mv=追従` に対し非リーダー個別行が `move:密集` のケース観察。NPC ベースラインの実値 / 探索モード分岐の影響 / ヘッダー表示のいずれかに原因。要調査。
2. **`tgt=リーダーと同じ` の挙動確認**：観察対象として記録（具体的な違和感シナリオは次セッションで確定）
3. **`_global_orders.move` への `explore` 書き込み**：4/25 の階段ナビ修正でスコープ外とした残課題。同種の設計問題
4. **後衛キャラがリーダーで先陣を切る問題**：keep_distance/rear 隊形修正の議論で「後回し」と判断
5. **ヒーラーの ATTACK strategy 時の挙動確認**：射程フィルタ追加で `_can_attack_target` がヒーラーで「攻撃可能」と判定される場面の検証
6. **壁越し攻撃の禁止**：本来の正しい仕様への修正
7. **`battle_policy` 自動切替の設計再考**：NPC リーダー判断結果を `_global_orders` に書き込む構造の整理（将来の方針整理タスク）

これらは [CLAUDE.md](CLAUDE.md) の「残タスク」セクションに優先度別に追加済み。

### 採用しなかった案・経緯メモ

- **FLEE 出口選定をリーダー推奨機構で続けるべきだったか？**：境界往復バグの再発リスクと
  メンバー先行時の推奨座標不一致問題があり、リーダー推奨機構の維持は不可能と判断。
  per-member 自律判断 + 避難先エリア ID 配布の現方式を採用
- **NPC 階段ナビ修正で per-member 専用フィールド `_dynamic_move_state` を新設すべきだったか？**：
  調査で `_assign_orders()` 側に既に per-member 配布ロジックがあることが判明したため不要。
  最小修正で完結（`_build_orders_part()` の hint 書き込みを廃止するだけ）
- **HpStatus enum を残して `disadvantage` モードのみ閾値定数化すべきだったか？**：
  enum の用途が 1 箇所のみで段階表現の意味が希薄化していたため、enum ごと廃止し
  用途別 float 定数に分解する方針を採用

### 想定外の発見

1. **CLAUDE.md 規約「リーダー → stairs_down / 非リーダー → cluster に差し替え」が実装は済んでいた**
   - 調査時に `_assign_orders()` 内（party_leader.gd:374-388）に該当ロジックが存在
   - 「規約と実装が乖離している」のではなく「規約は実装済みだが、別経路で違反が起きている」
     という構造の問題だった
2. **`_merge_npc_into_player_party` で `_hero_manager.set_joined_to_player(true)` が呼ばれていない**
   - 2026-04-24 改修でメンバー移管方式に変わった際、フラグの扱いが整理されていない
   - 「合流済みパーティー」という独立実体は存在しないことが判明
3. **`_merge_player_into_npc_party`（逆パターン）の存在**
   - プレイヤーが NPC パーティーに加入するパターンのコードが残っている
   - 実プレイで発火する経路があるか不明（要確認）
4. **`_generate_floor_follow_queue()` がデッドコードの可能性**
   - 形式的には実装されているが、実際の発動経路が `_follow_hero_floors=true` のセット
     依存で、その経路自体が不透明
