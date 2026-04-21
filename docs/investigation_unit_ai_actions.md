# UnitAI キューアクション棚卸し調査

調査日: 2026-04-21

## 1. 概要

UnitAI._generate_queue() 及び派生クラスが生成する「キューアクション」辞書の全種類を棚卸し、用途重複・表示曖昧性を特定。

背景：PartyStatusWindow で flee アクション（HP低下逃走・パーティー全員撤退・GoblinArcher/Salamander カイティング）が全て「逃走」と表示される。

## 2. キューアクション全種類一覧

13 種のアクション名が識別：

attack, move_to_attack, flee, wait, move_to_explore, move_to_formation, move_to_home, move_to_heal, heal, move_to_buff, buff, v_attack, use_potion

重複アクション：flee（3コンテキスト）

## 3. flee の 3 コンテキスト

### ①敵の FLEE 戦略逃走
- 発生：unit_ai.gd:736
- 条件：strategy==1（敵全体のパーティーレベル FLEE 指示）
- キュー：5個連続 flee

### ②GoblinArcher カイティング
- 発生：goblin_archer_unit_ai.gd:35
- 条件：strategy==0 かつ敵距離<=2
- キュー：3個連続 flee

### ③Salamander カイティング
- 発生：salamander_unit_ai.gd:31
- 条件：strategy==0 かつ敵距離<=2
- キュー：3個連続 flee

## 4. PartyStatusWindow 表示問題

get_debug_goal_str(unit_ai.gd:176) が全てを「逃走」と表示。
_format_action_goal(party_status_window.gd:803) で先頭アクション表示のため文脈区別なし。

## 5. 派生クラス拡張（13種族）

オーバーライド統計：
- _get_path_method: 13/13（全）
- _should_ignore_flee: 7/13（敵）
- _should_self_flee: 2/13（ゴブリン系）
- _can_attack: 3/13（魔法系）
- _generate_queue: 2/13（カイティング実装のみ：GoblinArcher, Salamander）

## 6. 表示改善案

### 案 A：reason フィールド追加（推奨）

```
# unit_ai.gd:736
q.append({"action": "flee", "reason": "party_flee"})

# goblin_archer_unit_ai.gd:35
q.append({"action": "flee", "reason": "kite"})

# get_debug_goal_str() 拡張
"flee":
    match head.get("reason", ""):
        "party_flee": return "撤退"
        "kite": return "距離確保"
        _: return "逃走"
```

メリット：最小変更、低リスク、意図明確化
影響範囲：修正 3 ファイル (unit_ai.gd, goblin_archer_unit_ai.gd, salamander_unit_ai.gd) + game_map.gd 確認

### 案 B：新規 "kite" アクション

メリット：セマンティック正確
デメリット：game_map.gd 実行エンジン修正が大きい

### 案 C：動的判定

メリット：既存データ変更なし
デメリット：ロジック複雑化・パフォーマンス

## 7. 結論

- アクション総数：13 種
- 重複用途：1 種（flee が敵撤退・GoblinArcher カイティング・Salamander カイティングの 3 コンテキスト）
- 派生クラス：13 種族
- _generate_queue override：2 クラス（カイティング実装）
- 表示問題：全 3 コンテキストで「逃走」

推奨：案 A (reason フィールド追加) → 最小変更で実装リスク低い、PartyStatusWindow 改善が即座、デバッグ効率向上
