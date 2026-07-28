extends Node

func _input(event):
	# F12 tuşuna basıldığında tetiklenir
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		take_screenshot()

func take_screenshot():
	# Mevcut ekran görüntüsünü (Viewport) al
	var image = get_viewport().get_texture().get_image()
	
	# Tarih ve saat ile benzersiz bir dosya adı oluştur
	var time_dict = Time.get_datetime_dict_from_system()
	var filename = "user://screenshot_%d-%02d-%02d_%02d%02d%02d.png" % [
		time_dict.year, time_dict.month, time_dict.day, 
		time_dict.hour, time_dict.minute, time_dict.second
	]
	
	# PNG olarak kaydet
	var err = image.save_png(filename)
	if err == OK:
		var global_path = ProjectSettings.globalize_path(filename)
		print("✅ Ekran görüntüsü kaydedildi: ", global_path)
	else:
		print("❌ Ekran görüntüsü kaydedilemedi, Hata kodu: ", err)
