class_name EnemyManager
extends PartyManager

## 後方互換ラッパー
## EnemyManager の機能はすべて PartyManager に移行しました。
## 新しいコードでは PartyManager を直接使用してください。
##
## このクラスが残っている理由:
##   - vision_system.gd が add_enemy_manager(em: EnemyManager) で型アノテーションを使用
##   - right_panel.gd が em_var as EnemyManager でキャストを使用
##   - game_map.gd が Array[EnemyManager] で管理
## これらを変更せずに新アーキテクチャへ移行するため、
## EnemyManager は PartyManager のサブクラスとして存続させる。
