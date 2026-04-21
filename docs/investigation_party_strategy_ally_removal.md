# 味方側 `_party_strategy` 廃止の影響範囲調査

**調査日:** 2026-04-21

**対象:** `scripts/**/*.gd` 全体（136ファイル）

---

## 1. 概要（背景・目的）

`_party_strategy` は本来「敵パーティー（EnemyLeaderAI 系）の戦略決定」として設計されたが、現在は以下の4つのクラスで使用されている：

- **敵専用:** `EnemyLeaderAI`, `GoblinLeaderAI`, `WolfLeaderAI`
- **味方専用:** `PartyLeaderPlayer`, `NpcLeaderAI`
- **基底（両者）:** `PartyLeader`, `PartyLeaderAI`

味方側（Player / NPC）で `_party_strategy` を廃止し、代わりに `global_orders.battle_policy` による指示ベース戦略に統一する場合、システム全体への影響を事前に把握する。

---

## 2. `_party_strategy` 参照箇所マトリクス

| ファイル:行 | R/W | 分類 | 概要 |
|---|---|---|---|
| `party_leader.gd:29` | W | 基底 | 変数宣言・初期化 |
| `party_leader.gd:209` | W | 共通 | 戦略評価・設定 |
| `party_leader.gd:212` | R | 共通 | 変更検出判定 |
| `party_leader.gd:214` | W | 共通 | 前回値更新 |
| `party_leader.gd:219` | R | 共通 | FLEE フラグ決定 |
| `party_leader.gd:266` | R | 共通 | EXPLORE 時移動方針上書き |
| `party_leader.gd:278` | R | 共通 | GUARD_ROOM 時移動方針上書き |
| `party_leader.gd:344` | R | 共通 | デバッグ情報出力 |
| `party_leader.gd:378` | R | 共通 | ログ用名前変換 |
| `party_leader.gd:417` | R | 共通 | 現在戦略名取得 |
| `party_leader.gd:455` | R | 共通 | ログ用理由取得（match） |
| `party_leader.gd:477` | R | 敵専用 | 範囲チェック GUARD_ROOM |
| `party_leader.gd:485` | R | 敵専用 | 範囲チェック ATTACK 判定 |
| `party_leader_player.gd:29` | オーバーライド | 味方 | battle_policy → Strategy 変換 |
| `npc_leader_ai.gd:85` | オーバーライド | 味方 | 敵検知 / EXPLORE / FLEE |
| `enemy_leader_ai.gd:38` | オーバーライド | 敵 | friendly 生存判定 |
| `goblin_leader_ai.gd:17` | オーバーライド | 敵 | HP < 50% で FLEE |
| `goblin_leader_ai.gd:31` | R | 敵 | 戦略変更理由（ログ） |
| `npc_leader_ai.gd:219` | R | 味方 | ヒント合成（match） |
| `npc_leader_ai.gd:253-259` | R | 味方 | 戦略変更理由（複数） |
| `npc_leader_ai.gd:467` | R | 味方 | 共闘状態判定 |
| `wolf_leader_ai.gd:30` | R | 敵 | 戦略変更理由（ログ） |
| `party_status_window.gd:1066` | R | UI | 敵ヘッダー enum 取得 |
| `party_manager.gd:547` | R | シーン管理 | 部屋制圧判定（FLEE 離脱） |

**集計:** 参照総数 40行、読み取り 23行、書き込み 3行、オーバーライド定義 5行

---

## 3. `party_fleeing` 参照箇所マトリクス

| ファイル:行 | R/W | 概要 |
|---|---|---|
| `party_leader.gd:219` | W | ローカル変数設定 (= _party_strategy == FLEE) |
| `party_leader.gd:317` | W | receive_order に渡す |
| `unit_ai.gd:49` | W | 変数宣言 |
| `unit_ai.gd:238` | W | receive_order で受け取る |
| `unit_ai.gd:2163` | R | 行動決定（FLEE 判定） |
| `party_status_window.gd:868` | R | フラグ表示判定 |
| `party_status_window.gd:869` | R | フラグ値取得 |

**集計:** 参照総数 11行、読み取り 4行、書き込み 4行

---

## 4. `_evaluate_party_strategy()` override 一覧

| クラス | ファイル:行 | 戻り値 |
|---|---|---|
| `PartyLeaderPlayer` | `party_leader_player.gd:29` | ATTACK / WAIT / FLEE |
| `NpcLeaderAI` | `npc_leader_ai.gd:85` | ATTACK / EXPLORE / FLEE |
| `EnemyLeaderAI` | `enemy_leader_ai.gd:38` | ATTACK / WAIT |
| `GoblinLeaderAI` | `goblin_leader_ai.gd:17` | (super) + FLEE条件 |
| `WolfLeaderAI` | `wolf_leader_ai.gd:17` | (super) + FLEE条件 |

---

## 5. 部屋制圧判定での strategy 参照

**ファイル:** `party_manager.gd:545-549`

```
部屋の外にいる場合：FLEE 戦略なら離脱扱い、それ以外は追跡中
var is_fleeing := _leader_ai != null and _leader_ai._party_strategy == PartyLeader.Strategy.FLEE
```

**影響:** 敵パーティーのみ → 味方廃止は本ロジックに影響なし

---

## 6. `battle_policy` 依存箇所

| ファイル:行 | 用途 |
|---|---|
| `party.gd:22` | デフォルト値 |
| `party_leader_player.gd:30` | 戦略決定（battle_policy → Strategy） |
| `order_window.gd:24,572,580,596` | UI操作・プリセット適用 |
| `npc_leader_ai.gd:219-231` | ヒント合成時に _party_strategy から battle_policy 上書き |
| `party_status_window.gd:471,550` | UI表示 |

**重要:** NPC では battle_policy は内部的に _party_strategy から合成されている（219-231行）

---

## 7. NpcLeaderAI の FLEE ロジック現行実装

### 戦略評価（npc_leader_ai.gd:85-120）
- 敵検知 → ATTACK
- 敵なし → EXPLORE
- 戦況CRITICAL → FLEE

### ヒント合成（npc_leader_ai.gd:219-231）
```
match _party_strategy:
  FLEE: hint["battle_policy"] = "retreat"
  WAIT/DEFEND: hint["battle_policy"] = "defense"
  EXPLORE: hint["move"] = _get_explore_move_policy()
  GUARD_ROOM: hint["move"] = "guard_room"
```

### 共闘判定（npc_leader_ai.gd:467）
```
func is_in_combat() -> bool: return _party_strategy == Strategy.ATTACK
```

### 結論
NPC では戦略評価 → ヒント合成 → UnitAI指示という 3段階で FLEE が実装。廃止時には戦況判定に基づく自動 FLEE ロジック全体を新規実装が必須。

---

## 8. PartyStatusWindow の strategy 表示依存

### 敵ヘッダー表示（party_status_window.gd:1066）
- enum値を英字名に変換（ATTACK / FLEE / WAIT / DEFEND / EXPLORE / GUARD_ROOM）

### メンバーフラグ（party_status_window.gd:868-870）
- `_party_fleeing` フラグから P↓ インジケータ表示

### 味方廃止時の影響
- 敵表示: 継続（敵は Strategy を保持）
- UI: 変更なし（_party_fleeing は UnitAI が持つため）

---

## 9. 影響範囲サマリー

### 変更が必要なファイル・関数

| ファイル | 対象 | 工数 |
|---|---|---|
| `npc_leader_ai.gd:85-120` | _evaluate_party_strategy() | 中規模 |
| `npc_leader_ai.gd:219-231` | get_global_orders_hint() | 中規模 |
| `npc_leader_ai.gd:252-261` | _get_strategy_change_reason() | 軽微 |
| `npc_leader_ai.gd:467` | is_in_combat() | 軽微 |
| `party_leader.gd:266-279` | _assign_orders() 敵分岐 | 軽微 |

敵側（EnemyLeaderAI/GoblinLeaderAI/WolfLeaderAI）は変更不要

### 新規実装が必要な機構

1. **敵検知フラグ:** NPC が敵検知状態を保持するメカニズム
2. **戦況CRITICAL自動FLEE:** 敵検知状態＋戦況判定で FLEE を自動判定
3. **共闘判定更新:** 敵検知フラグで is_in_combat() を判定

---

## 10. 実装工数見積もり

### 総合判定: **中規模**

- NPC 敵検判定フラグ追加: 軽微
- 戦況CRITICAL自動FLEE: 小
- ログ・デバッグ削除: 軽微
- 敵/UI分岐フラグ: 軽微
- テスト・検証: 中

### リスク

- NPC FLEE 自動判定が機能しない（中確率、高影響）
- 敵 strategy 参照漏れ（低確率、高影響）

---

## 11. 相互参照

- 敵指示システム: [`investigation_enemy_order_system.md`](investigation_enemy_order_system.md)
- 敵指示実動: [`investigation_enemy_order_effective.md`](investigation_enemy_order_effective.md)
- receive_order一覧: [`investigation_receive_order_keys.md`](investigation_receive_order_keys.md)

---

## 12. 結論

**味方側 `_party_strategy` 廃止は技術的に実現可能だが、NPC の自動 FLEE / 敵検知フラグの新規実装が必須。**

敵側は変更不要。廃止により敵分岐チェック含めて 50-100行の修正が必要だが、戦況判定ロジック再実装で工数は中規模。

