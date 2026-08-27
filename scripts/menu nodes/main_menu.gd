extends Node2D

func _on_play_pressed():
	SceneManager.change_scene("res://scenes/main/tutorial.tscn")


func _on_options_pressed():
	SceneManager.change_scene("res://scenes/gui/options_menu.tscn")
