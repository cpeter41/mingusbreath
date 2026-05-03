class_name EnemyActionState
extends BaseState

var enemy: Enemy
var actionSM: StateMachine  # concrete type causes circular ref
