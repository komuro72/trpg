# 敵パーティー `_party_strategy` 遷移調査

調査日: 2026-04-26
対象: 敵パーティーが常に `strategy=ATTACK` のまま遷移しない現象の原因特定

## 背景（再現シナリオ）

実プレイ観察:
- 戦闘中の敵パーティーは常に `strategy=ATTACK`、メンバーは `move:追従` のまま
- `GUARD_ROOM`（部屋を守る）/ `EXPLORE`（探索）への遷移が発生しない
- `戦況:CRITICAL` / `戦力:DESPERATE` 表示でも `strategy=ATTACK` のまま FLEE しない

## 1. `_party_strategy` 値域と発火経路

### enum 定義
[`scripts/party_leader.gd:18`](../scripts/party_leader.gd) `enum Strategy { ATTACK, FLEE, WAIT, DEFEND, EXPLORE, GUARD_ROOM }`

### 発火経路一覧

| enum 値 | 設定箇所 (file:line) | 発火条件 |
|---|---|---|
| `ATTACK` | `enemy_leader_ai.gd:40` (`_evaluate_party_strategy`) | `_has_alive_friendly()` が真（生存プレイヤー/NPC が存在） |
| `ATTACK` | `party_leader.gd:731` (`_apply_range_check`) | 現状態が `GUARD_ROOM` かつ `_any_member_can_engage()` が真 |
| `WAIT` | `enemy_leader_ai.gd:41` (`_evaluate_party_strategy`) | 生存友好キャラがいない（メンバー死亡など） |
| `WAIT` | `party_leader.gd:733` (`_apply_range_check`) | 現状態が `GUARD_ROOM` かつ `_all_members_at_home()` が真 |
| `WAIT` | `party_leader.gd:873` (`PartyLeader._evaluate_party_strategy` 基底) | デフォルト戻り値（実際にここを通る経路はない: 全敵が EnemyLeaderAI 系を継承するため） |
| `WAIT` | `party_leader_ai.gd:16` (`PartyLeaderAI._evaluate_party_strategy`) | 同上（デフォルト） |
| `FLEE` | `goblin_leader_ai.gd:24-25` (`GoblinLeaderAI._evaluate_party_strategy`) | `生存数 / _initial_count < PARTY_FLEE_ALIVE_RATIO`（既定 0.5） |
| `FLEE` | `wolf_leader_ai.gd:23-24` (`WolfLeaderAI._evaluate_party_strategy`) | 同上（生存比率 < 0.5） |
| `FLEE` | `party_leader.gd:729` (`_apply_range_check`) | パススルー（base_strat が FLEE なら GUARD_ROOM 中でも維持） |
| `DEFEND` | — | **コード上の発火源なし** |
| `EXPLORE` | — | **敵 AI からの発火源なし**（NpcLeaderAI は `_is_in_explore_mode()` を override する別経路） |
| `GUARD_ROOM` | `party_leader.gd:737` (`_apply_range_check`) | 現状態が `ATTACK` かつ base_strat が `ATTACK` かつ `_all_members_out_of_range()` が真 |
| `GUARD_ROOM` | `party_leader.gd:734` (`_apply_range_check`) | 現状態が `GUARD_ROOM` でメンバーが帰還条件を満たさない場合の維持 |

### 個別質問への回答

**Q: GUARD_ROOM は実装されている?**
- A: コード上は実装されている（`party_leader.gd:719-738` の `_apply_range_check`）。ただし発火条件は厳しい（後述、項 3 と項 4）。**種族 AI で override しているサブクラスは無い**。
- 共通の `_apply_range_check` のみが GUARD_ROOM への遷移源。

**Q: EXPLORE は敵向けに実装されている?**
- A: **敵向けには実装されていない**。`Strategy.EXPLORE` を返す `_evaluate_party_strategy()` の override は **どの敵 AI にも存在しない**（grep 結果、Goblin/Wolf/Hobgoblin/EnemyLeaderAI/PartyLeaderAI のすべてに無し）。
- 基底 `_is_in_explore_mode()` ([`party_leader.gd:879-880`](../scripts/party_leader.gd)) は `_party_strategy == EXPLORE` を返すが、敵側で EXPLORE が立つ経路がないため常に false。
- NpcLeaderAI は別経路（`_is_in_explore_mode()` を `_has_visible_enemy()` で override、[`npc_leader_ai.gd:119-120`](../scripts/npc_leader_ai.gd)）。

**Q: ゴブリンの「HP < 30% → FLEE」は実装されているか?**
- CLAUDE.md には「ゴブリン系自己逃走」の記述があるが、これは **個体レベル**（`UnitAI._should_self_flee()`、`SELF_FLEE_HP_THRESHOLD = 0.3`）。
- **パーティー戦略レベル**の FLEE は「**生存メンバー比率 < 0.5**」のみ（[`goblin_leader_ai.gd:24`](../scripts/goblin_leader_ai.gd)）。HP 率は見ていない。
- つまりゴブリンパーティーは「半数が死亡するまで FLEE しない」。

**Q: なぜ ATTACK が貼り付くか?**
- 主因 C: `_evaluate_party_strategy()` が単純に `_has_alive_friendly() ? ATTACK : WAIT` を返すだけで、戦況（CRITICAL / DESPERATE）を一切参照していない。
- 戦況評価結果（`_combat_situation`）は `_evaluate_strategic_status()` で正しく算出されているが、`_evaluate_party_strategy()` では使用していない。
- Goblin/Wolf の FLEE は「半数死亡」のみ参照。CRITICAL であっても 1 体も死んでいなければ FLEE にならない。
- 他敵種族（Hobgoblin / Zombie / Wolf 以外 / Skeleton / Lich / Demon / DarkKnight / DarkPriest / Salamander / Harpy / DarkLord）には `_evaluate_party_strategy` の override が **一切ない** → 全員が `EnemyLeaderAI` のデフォルト（ATTACK / WAIT のみ）を使用。

## 2. `_move_policy` 反映経路

### EXPLORE 反映
- 基底実装: [`party_leader.gd:879-880`](../scripts/party_leader.gd) `_is_in_explore_mode()` → `_party_strategy == Strategy.EXPLORE`
- 反映箇所: [`party_leader.gd:380-381`](../scripts/party_leader.gd) `_assign_orders` 内、リーダーのみ `move_policy = _get_explore_move_policy()` で上書き
- override:
  - `NpcLeaderAI._is_in_explore_mode()` ([`npc_leader_ai.gd:119-120`](../scripts/npc_leader_ai.gd)) — `not _has_visible_enemy()` （EXPLORE strategy を経由しない代替経路）
  - 敵 AI 系（EnemyLeaderAI / Goblin / Wolf / Hobgoblin）: **override なし** → 基底実装が動くが、敵では `_party_strategy` が EXPLORE になることがないため常に false
- 結論: 敵パーティーがこの経路で `move_policy = "explore"` に遷移することは構造上ありえない。

### GUARD_ROOM 反映
- 基底実装: [`party_leader.gd:885-886`](../scripts/party_leader.gd) `_is_in_guard_room_mode()` → `_party_strategy == Strategy.GUARD_ROOM`
- 反映箇所: [`party_leader.gd:382-383`](../scripts/party_leader.gd) `_assign_orders` 内、リーダーのみ `move_policy = "guard_room"` で上書き
- override: **なし**（NpcLeaderAI も override しない＝味方は GUARD_ROOM に入らない）
- 結論: GUARD_ROOM への遷移自体は `_apply_range_check` 経由で起こりうる（条件が満たされれば）。構造としてはワイヤード。

## 3. 縄張り・追跡ロジックの実態

### `chase_range` / `territory_range` の参照箇所
ロジック実体は [`party_leader.gd:719-797`](../scripts/party_leader.gd) `_apply_range_check` 系のみ:
- `_all_members_out_of_range()` (741): 全員が `dist_home > territory_range` かつ最寄り敵まで `dist_target > chase_range` のとき真 → ATTACK → GUARD_ROOM 遷移トリガ
- `_any_member_can_engage()` (763): 1 体でも `dist_home <= territory_range` かつ最寄り敵まで `dist_target <= chase_range` のとき真 → GUARD_ROOM → ATTACK 復帰トリガ
- `_all_members_at_home()` (785): 全員がスポーン地点から `dx + dy <= 2` のとき真 → GUARD_ROOM → WAIT 遷移トリガ
- `home` は `UnitAI.get_home_position()` で取得 ([`unit_ai.gd:99,102-103`](../scripts/unit_ai.gd))。`setup()` 時の `member.grid_pos`（=スポーン位置）で固定。

### 現行値での発火可能性

JSON 値（個別敵 JSON より）:
| 敵 | chase_range | territory_range |
|---|---|---|
| goblin | 10 | 50 |
| goblin_archer / goblin_mage | 10 | 50 |
| hobgoblin | 6 | 8 |
| wolf | 8 | 8 |
| zombie | 10 | 50 |
| salamander | 6 | 8 |
| harpy | 10 | 12 |
| dark_knight | 10 | 18 |
| dark_mage / dark_priest | 6 | 10 |
| skeleton / skeleton_archer | 10 | 50 |
| lich | 8 | 15 |
| demon | 10 | 20 |
| dark_lord | 10 | 50 |

ダンジョンサイズに対して `territory_range = 50` は実質「無限」。フロアサイズが 50 マス以下なら全敵（ゴブリン系・ゾンビ・スケルトン系・ダークロード）はスポーン地点から **絶対に縄張り外に出ない** → `_all_members_out_of_range` が真にならず ATTACK → GUARD_ROOM 遷移は発火しない。

`territory_range` が小さい敵（hobgoblin=8 / wolf=8 / salamander=8 等）でも、`_all_members_out_of_range` は **全員 OR 条件**:
- 全員が territory 外 **かつ** 最寄り敵が chase_range の外
- → プレイヤーを追って 1 人でも territory 内に残っていれば発火しない
- → プレイヤーを追って全員 territory 外まで来ても、プレイヤー自身が chase_range 内なら発火しない（敵が追い続ける限り発火しない）

つまり「縄張りに帰る」のは **プレイヤーが敵から逃げ切って chase_range 外に消えた** ときのみ。実プレイで戦闘継続中に発火することはまずない。

### 「縄張り内で敵不在 → GUARD_ROOM」の経路はあるか?
**ない**。`_apply_range_check` は `ATTACK -> GUARD_ROOM` 遷移のみ。`_evaluate_party_strategy()` は敵不在で WAIT を返すので、敵不在の縄張り内では GUARD_ROOM ではなく WAIT になる。

## 4. 現象の原因仮説

| enum | 仮説 | 根拠 |
|---|---|---|
| **ATTACK の貼り付き** | **C（base が ATTACK 即 return、戦況考慮なし）** | `enemy_leader_ai.gd:38-41` が `_combat_situation` を一切見ない。CRITICAL でも友好キャラが生存していれば ATTACK |
| **GUARD_ROOM 未発火** | **B（実装はあるが条件が極めて厳しい）** | `_apply_range_check` のロジック自体は正常。ただし territory_range の値（多くが 50）と AND 条件のため戦闘中に発火するシチュエーションがほぼない |
| **EXPLORE 未発火** | **A（敵 AI 向けに実装されていない）** | どの敵 AI も `Strategy.EXPLORE` を返す override を持たない |
| **FLEE 未発火（戦況 CRITICAL でも）** | **C（条件が「半数死亡」のみで戦況非依存）** | Goblin/Wolf は `生存比率 < 0.5` のみ。Hobgoblin 含むその他 14 種族は FLEE する経路が無い |
| **DEFEND 未発火** | **A（実装されていない）** | enum 値はあるが書き込み元なし |

### 主因
ATTACK 貼り付きの主因は **C**。`EnemyLeaderAI._evaluate_party_strategy()` ([`enemy_leader_ai.gd:38-41`](../scripts/enemy_leader_ai.gd)) が `_has_alive_friendly()` だけで判断し、`_combat_situation`（CRITICAL / DESPERATE 等）を一切参照しないため、戦況に関係なく ATTACK が返り続ける。

味方 NPC 側は同等の課題を「`battle_policy` 自動書き換え」（[`npc_leader_ai.gd:316-349`](../scripts/npc_leader_ai.gd) `_evaluate_and_update_battle_policy`）で別経路から解決済み。敵側には対応する仕組みがない。

## 5. 推奨方針

### 短期対応（最小修正で挙動変化）

1. **EnemyLeaderAI に戦況連動の FLEE/DEFEND を追加**
   - `_evaluate_party_strategy()` で `_combat_situation.situation == CRITICAL` のとき `Strategy.FLEE`
   - 設計議論ポイント:
     - 「敵は逃げない」前提のままにするか? CLAUDE.md では「敵側の `_party_strategy` enum 直接配布」が将来課題として残っており、敵 FLEE 含めて自律ロジックを敵向けに整備する方針はある
     - 「半数死亡」と「戦況 CRITICAL」のいずれかで FLEE するべきか、AND にするべきか
   - Hobgoblin（「狂暴で絶対に逃げない」）等の例外も維持できるように、override で「FLEE しない」フラグを返せる設計にする

2. **GUARD_ROOM への帰還条件を緩和**
   - 例: 「敵を見失った（chase_range 外）かつメンバーの誰かが territory 外」で GUARD_ROOM
   - territory_range の数値見直し（50 が実質無効化されている敵が多い）
   - 「縄張り内で敵不在 → GUARD_ROOM」の遷移を新設するか?（現状 WAIT になる）

3. **CRITICAL 時の `move:追従` 解消**
   - FLEE/GUARD_ROOM が立てば `_assign_orders` の既存ロジックで自然に move_policy が変わるため、ステップ 1 の対応で副次的に解消

### 中期対応（設計レベル）

- 残タスクの「敵パーティーへの FLEE 自律ロジック適用」（CLAUDE.md 該当節）を本格着手。NPC の `battle_policy` 自動書き換え相当を敵にも導入する案
- EXPLORE は敵側で必要か?（現状は「敵は縄張り内で WAIT」前提。プレイヤーが見えない時の能動探索はゲームデザイン議論）

### 設計議論の論点（実装前に決めるべき）
1. **敵は逃げるべきか?** Hobgoblin の「狂暴で絶対に逃げない」のような例外設計をどうするか
2. **戦況 CRITICAL の閾値は敵向けにそのままで良いか?** 現状 `COMBAT_RATIO_DISADVANTAGE = 0.5`（戦力比 < 0.5 で CRITICAL）
3. **GUARD_ROOM の意味付け**: 「縄張り守備」を敵の通常状態にするか、戦闘終了時の「帰る」アニメーション扱いにするか
4. **territory_range の調整方針**: 現行値（goblin=50 等）を「無効化」とみなして全敵縮小するか、敵種別の特性に応じて再調整するか
