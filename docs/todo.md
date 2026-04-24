# TODO リスト（作業再開時の引き継ぎ）— 2026-04-24 深夜時点

## 作業の区切りについて

2026-04-24 深夜、以下の一連の大規模改修を完了：

1. fall_back 個体アクションの実装（FLEE 再利用方式・脅威マップ事前計算で高速化）
2. パーティー加入処理の完全化（動的 adopt/release API・`_member_to_npc_manager` 除去）
3. 合流 NPC 追従バグ修正（ポーション修正の副作用解消）

**fall_back の実機動作確認は次回以降**とする（NPC を仲間にして HP 低下させるまでのお膳立てが大変なため、他の実装を進めながら実プレイで観察する方針）。

CLAUDE.md には実装内容が記録済み。作業再開時はこの TODO を起点に優先順位を判断する。

## 🔧 小タスク（片手間で処理可能）

### T1. `[EXIT_PERF]` 計測コードの削除

- **場所**：`scripts/party_leader.gd` の `_update_flee_recommended_goal()` 付近・`PartyLeader._process()` 付近
- **タグ**：`PERF_MEASUREMENT_START` / `PERF_MEASUREMENT_END` のコメントでマークされているブロック
- **削除対象**：
  - `[EXIT_PERF] ...` を出力する `DebugLog.log(...)` 呼び出し
  - `Time.get_ticks_usec()` による計測変数
  - 計測用の if 判定（`if total_us > N`）
- **判断根拠**：脅威マップ事前計算で単発コストが 5〜10ms に収束し、効果確認完了。本番に残す意義なし
- **grep パターン**：`grep -rn "PERF_MEASUREMENT\|EXIT_PERF\|EXIT_FRAME" scripts/`
- **コミット**：`clean: remove EXIT_PERF measurement after fall_back refactor verified`

### T2. fall_back 実装完了に伴う CLAUDE.md の整理

- 「次セッションで検討するタスク」セクションから **FLEE 派生課題 4（fall_back 差別化）** のエントリを「完了」として外す（または ✅ マークで完了マーク）
- 「最近の大きな変更」の 2026-04-24 エントリが既に複数個の追加修正（夕・深夜・深夜・深夜）で膨らんでいる。読みやすさのために、コンパクトにまとめるかは Komuro 判断

上記は T1 と同じコミットに含めてよい。

## 📋 残タスク（優先順位順）

### 高優先度

#### P1. fall_back 実機動作確認（機会があれば）

**目的**：実装した fall_back の挙動が設計意図通りか確認。

**確認観点**：

- 発火条件：`on_low_hp = fall_back` のメンバーが critical 状態で fall_back アクション開始
- 目標方向：推奨出口方向（`_flee_recommended_goal`）へ向かう
- 停止条件：最寄り脅威との距離が `attack_range + FALL_BACK_MARGIN(=2)` 以上で `wait` 遷移
- 出口通過：必要なら出口を通過して隣エリアへ入る（射程外まで下がる）
- UI 表示：`fb→(x,y)` がアクション実行中に表示される

**エッジケース**：

- fall_back 中に HP 回復（critical → injured）で挙動がどうなるか
- fall_back 中に敵全滅した時の挙動
- 複数メンバーが同時に fall_back 発火した時のパーティー連携

**進め方**：

- 実プレイでメンバーが低 HP 状態になる機会を待つ（NPC 加入 + 戦闘でポーション使用後に発火する場合がある）
- 観察のため PartyStatusWindow で状態を確認
- ポーションの自動使用が fall_back 観察の妨げになる場合、`hp_potion = "never"` に変更して検証する選択肢あり
- 調整が必要なパラメータがあれば `FALL_BACK_MARGIN` の値を見直す（既定 2）

#### P2. 実プレイ再検証（2026-04-22 調整）

**目的**：ダメージ倍率・絶対値ダメージの調整が適切か確認（長らく保留）。

**確認観点**（既存 TODO から）：

- 戦闘テンポが妥当か
- Floor 0 のアーチャーの挙動
- FLEE 動作
- 最低保証 1 の張り付き
- 火力バランス

**進め方**：
- 腰を据えた実プレイセッションを設ける
- 問題があればパラメータ調整

### 中優先度

#### P3. FLEE 派生課題 3：味方クラスへの `keep_distance` 適用（後衛前進問題）

**背景**：現在、後衛クラス（魔法使い・弓使い・ヒーラー）が敵に近づきすぎる問題が顕在化している（既知）。

**設計済みの方針**：

- 味方の後衛クラスにも `keep_distance` を適用
- FLEE 計算結果（`_flee_recommended_goal`）が既に常時計算されているので、流用できる土台は整っている

**論点（実装時に詰める）**：

- どの条件で `keep_distance` を発火させるか（現状ゴブリンアーチャーは距離 ≤ 2 で発火）
- 味方クラス固有の挙動が必要か（例：弓使い・魔法使い・ヒーラーで閾値が違うか）
- 種族固有クラス（`GoblinArcherUnitAI`）と同じパターンで各クラス AI に実装するか、基底 UnitAI でまとめて扱うか
- ゴブリンアーチャーの既存挙動（`MIN_CLOSE_RANGE = 2` ハードコード）を一般化するタイミング

**進め方**：着手時に新セッションで設計議論 → instruction → 実装

#### P4. FLEE 派生課題 1：敵パーティーの FLEE 二段階化

**背景**：現状の敵 FLEE は `_find_flee_goal_legacy`（脅威から 5 タイル離れる）のまま。味方と同じ二段階協調ロジックに統一したい。

**進め方**：
- 敵版の推奨出口計算（`nearby_enemy_party` 相当の味方視点情報を使う）を設計
- 敵の fall_back 対応も同時に検討（派生課題 1 と 4 敵側の合流）
- 作業を本格的に始める前に設計方針を新セッションで議論

### 低優先度（将来タスク）

#### P5. NpcLeaderAI 撤退ロジックと CombatSituation の連携

**背景**：現状、NpcLeaderAI の撤退ロジックで CombatSituation（戦況評価）の結果が連携されていない（DISADVANTAGE_THRESHOLD 定数はあるが未使用）。

**進め方**：撤退判断に戦況（ADVANTAGE / EVEN / DISADVANTAGE 等）を加味する設計議論から。

#### P6. 特殊指示（strong_enemy / disadvantage）の AI 挙動連携

**背景**：UI 上は選択できるが AI 挙動に反映されていない。

**進め方**：まず各選択肢の意味論を定義してから実装。

#### P7. ゲーム開始時のクラス・ランク選択 UI

**背景**：現状は固定配置。将来的にプレイヤーが選択できるようにしたい。

**進め方**：UI 設計から。

#### P8. NpcLeaderAI のアイテム収集動的切り替え

**背景**：現状は固定挙動。状況に応じた動的切り替えがほしい。

## 🗺️ 残課題の関係図

```
fall_back 実装完了
    ↓
P1 実機確認（機会があれば・いつでもよい）
    ↓
P3 keep_distance 味方適用 ← fall_back の資産（FLEE 計算結果常時）を活用
    ↓
P4 敵 FLEE 二段階化 ← 味方側のロジックを敵にも展開
    ↓
AI 系の基本が整う
    ↓
P5-P8 各種調整・UI 拡張
```

## ⚠️ 作業再開時の注意点

- **実装は相当進んでいる**：fall_back・加入処理・脅威マップ事前計算など 1 日で大規模改修が入っている。作業再開時は CLAUDE.md の 2026-04-24 エントリを最初に全読み
- **FLEE と fall_back が `flee_recommended_goal` を共用**：FLEE 側の変更は fall_back にも影響する。FLEE 側を触るときは fall_back への波及を意識
- **`_member_to_npc_manager` は完全廃止済み**：パーティー加入関連のコードを触るときに古い設計を参照しないよう注意
- **未加入 NPC と合流済み NPC は管理主体が異なる**：未加入は `NpcLeaderAI` 管理・合流済みは `PartyLeaderPlayer` 管理に一本化済み
- **`[EXIT_PERF]` 計測コード**：T1 で削除予定だが、削除前に次回引き継ぐ場合は残存箇所を grep で確認
- **fall_back 実機確認が未実施**：バグが潜んでいる可能性あり。実プレイで違和感があれば即座にログを取って調査

## 作業開始時の手順

1. CLAUDE.md を開いて 2026-04-24 エントリを確認（「最近の大きな変更」セクション）
2. 本 TODO の「作業再開時の注意点」を確認
3. 優先順位を見て進めるタスクを選択：
   - **小さく始めるなら T1**（計測コード削除）
   - **本格的に進めるなら P3**（keep_distance 味方適用）
   - **機会があれば P1**（fall_back 実機確認）
4. タスク着手前に新セッションで Komuro と設計議論 → instruction 化 → Claude Code 実装 のフローに乗せる

## 付録：廃止された実装の痕跡

以下は 2026-04-24 で廃止されたが、古いドキュメント・コメント等に名前が残っている可能性あり。見かけたら整理：

- `FALL_BACK_SEARCH_RADIUS` / `FALL_BACK_LEADER_DISTANCE_WEIGHT` / `FALL_BACK_ALLY_CENTROID_WEIGHT`（削除済み）
- `_determine_fallback_recommended_goal()`（削除済み）
- `_calc_ally_centroid()`（削除済み）
- `_is_walkable_for_fallback()`（削除済み）
- `_formation_fallback_goal`（削除済み・配布キー名含む）
- `_member_to_npc_manager`（削除済み・Dictionary 定義・参照・配布ループ）
- `_is_far_enough_from_threats()` のみ残存（fall_back 停止判定で使用中）
