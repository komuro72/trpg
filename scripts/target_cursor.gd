class_name TargetCursor
extends Node2D

## ターゲット選択中に対象キャラクターの位置を追跡するノード。
## 視覚表現は Character.is_targeted の modulate（白輝き）で行うため、ここでは描画なし。
## PlayerController が生成・位置更新・破棄を管理する。
