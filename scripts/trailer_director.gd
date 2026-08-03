extends CanvasLayer
class_name TrailerDirector

@export_group("Trailer Nodes")
@export var music_player: AudioStreamPlayer
@export var animation_player: AnimationPlayer
@export var title_label: Label
@export var overlay_rect: ColorRect
@export var gameplay_container: Node2D

var current_gameplay_scene: Node = null
var _rotation_off: float = 0.0
var _rotation_speed: float = TAU / 5.0 # 5 saniyede 1 tam tur
var _poi_layer: Node2D = null

var _light_angle: float = 0.8
var _light_speed: float = -TAU / 12.0 # Eksi yaparak dönüş yönünü düzelttik

func _process(delta: float) -> void:
	if current_gameplay_scene and current_gameplay_scene.get("_star"):
		var star = current_gameplay_scene.get("_star")
		if star.material:
			_rotation_off = fposmod(_rotation_off + _rotation_speed * delta, TAU)
			star.material.set_shader_parameter("rotation_offset", _rotation_off)
			
			_light_angle = fposmod(_light_angle + _light_speed * delta, TAU)
			var nx = sin(_light_angle)
			var nz = cos(_light_angle)
			star.material.set_shader_parameter("light_direction", Vector3(nx, -0.55, nz))
			
			if has_meta("orb_layer"):
				var orb_obj = get_meta("orb_layer")
				if is_instance_valid(orb_obj) and not orb_obj.is_queued_for_deletion():
					var orb: Control = orb_obj
					orb._planet_rotation = _rotation_off
					orb.queue_redraw()
				else:
					remove_meta("orb_layer")
					
			# Ay ve gezegen yörüngelerinin (SolarView/LocalView) kamerayla birlikte dönmesi
			if "_view_angle" in current_gameplay_scene and "_orbits" in current_gameplay_scene:
				current_gameplay_scene._view_angle += 0.25 * delta
				for node in current_gameplay_scene.get("_orbits"):
					if node.has_method("set_view_angle"):
						node.set_view_angle(current_gameplay_scene._view_angle)
				if "_asteroid_belts" in current_gameplay_scene:
					for belt in current_gameplay_scene.get("_asteroid_belts"):
						if belt.has_method("set_view_angle"):
							belt.set_view_angle(current_gameplay_scene._view_angle)

func _ready():
	print("🎬 Trailer Motoru Başlatıldı!")
	
	# Başlangıç durumu: Ekran tamamen siyah, yazı yok
	if overlay_rect:
		overlay_rect.modulate.a = 1.0
	if title_label:
		title_label.modulate.a = 0.0
		title_label.text = ""
	
	# Müziği başlat (varsa)
	if music_player and music_player.stream:
		music_player.play()
	
	# Trailer akışını başlat (Kod üzerinden!)
	play_trailer_sequence()

## Ana Akış (Timeline) burada kodla çok daha kolay kontrol edilebilir
func play_trailer_sequence():
	# Fragman sırasında oyunun menü kilitlerini (auto-redirect) tamamen açalım
	GameState.solar_unlocked = true
	GameState.galaxy_unlocked = true
	
	# Yazılar her zaman TEPE'de (Top) çıkacak
	if title_label:
		title_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		title_label.offset_top = 100
	
	# ADIM 1: Arka planda SolarView sahnesini yükle (Ama ekran simsiyah olacak)
	load_background_scene("res://scenes/solar/SolarView.tscn")
	await get_tree().process_frame # Boyutlar otursun
	
	var star = null
	
	# Terran gezegeni zorla oluştur (Tüm shader parametreleri dolmalı)
	if current_gameplay_scene and current_gameplay_scene.has_method("load_local"):
		var pd = load("res://scripts/planetary/PlanetData.gd").from_seed_as_type(42069, 0)
		pd.planet_name = "Earth 2.0"
		pd.has_atmosphere = true
		pd.atmosphere_density = 0.8
		
		var sd = load("res://scripts/solar/SolarData.gd").new()
		sd.is_home = true
		current_gameplay_scene._current = sd
		current_gameplay_scene.load_local(pd)
		
		# Gezegeni büyüt ve ortala
		star = current_gameplay_scene.get("_star")
		if star:
			var target_size = 700.0
			star.size = Vector2(target_size, target_size)
			star.position = (get_viewport().get_visible_rect().size / 2.0) - (star.size / 2.0)
			# Gezegeni animasyonlar için merkezden ölçeklenebilir yap
			star.pivot_offset = star.size / 2.0
			if star.material:
				star.material.set_shader_parameter("pixel_count", target_size)
				
		_build_background_stars()
		
		# POILayer'ı ekle (Gerçek 3D yüzey yazıları için)
		if star:
			_poi_layer = Node2D.new()
			_poi_layer.set_script(load("res://scripts/planetary/POILayer.gd"))
			add_child(_poi_layer)
			_poi_layer.setup(star)
			_poi_layer.z_index = 80
	
	# UI'ı tamamen gizle
	set_ui_visible(false)
	
	# Her şeyin üzerinde kalacak siyah overlay
	if overlay_rect:
		overlay_rect.modulate.a = 1.0 # EKRAN SİMSİYAH BAŞLAR
		overlay_rect.z_index = 50 
	
	# ---------------------------------------------------------
	# KANCA (HOOK) BAŞLIYOR: "NUMBERS GO UP"
	# ---------------------------------------------------------
	
	# Font ayarı
	var orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf") as Font
	title_label.add_theme_font_override("font", orbitron)
	title_label.z_index = 300 # Her şeyin (Özellikle SkillTreeView'ın z_index=200) üstünde olması için 300
	title_label.modulate.a = 1.0
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = ""
	
	# Siyah ekran kısacık bekler
	await get_tree().create_timer(0.5).timeout
	
	# 1. Gezegen Yavaşça Aydınlanmaya (Fade-in) başlar
	var initial_fade = create_tween()
	initial_fade.tween_property(overlay_rect, "modulate:a", 0.1, 4.0) # 4 saniyede yavaşça aydınlan
	
	# Gezegen aydınlanırken ufak tıklamalar (Floating Text) çıkar
	await get_tree().create_timer(1.0).timeout
	
	if _poi_layer:
		# Oyunun gerçek POILayer koordinatları (Küresel Yüzey)
		_poi_layer.spawn_floating_text(-30.0, 10.0, "+ 1", Color(0.8, 1.0, 0.8), 24)
		await get_tree().create_timer(1.2).timeout
		_poi_layer.spawn_floating_text(45.0, -15.0, "+ 5", Color(0.8, 1.0, 0.8), 28)
	
	await get_tree().create_timer(1.0).timeout
	
	# START SMALL (Daktilo)
	title_label.text = "START SMALL"
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	title_label.add_theme_constant_override("outline_size", 8)
	title_label.visible_ratio = 0.0
	
	var tw1 = create_tween()
	tw1.tween_property(title_label, "visible_ratio", 1.0, 1.0)
	await tw1.finished
	await get_tree().create_timer(0.8).timeout
	
	# Transition için yavaşça silinme...
	var tw_out = create_tween()
	tw_out.tween_property(title_label, "modulate:a", 0.0, 0.3)
	await tw_out.finished
	title_label.text = ""
	title_label.visible_ratio = 1.0
	title_label.modulate.a = 1.0
	
	# ---------------------------------------------------------
	# IMPACT FRAME (FLASH ÖNCESİ GERİLME)
	# ---------------------------------------------------------
	if star:
		var pre_scale = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		# Flash'tan hemen önce gezegen 0.25sn içinde şişerek kameraya doğru gelir (Nefes Alma)
		pre_scale.tween_property(star, "scale", Vector2(1.15, 1.15), 0.25)
	
	await get_tree().create_timer(0.25).timeout
	
	# =========================================================
	# PATLAMA (DROP) ANI!
	# =========================================================
	
	# 1. Beyaz Parlama (Flash Effect)
	var flash = ColorRect.new()
	flash.color = Color.WHITE
	flash.modulate.a = 0.0
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.z_index = 200
	add_child(flash)
	
	var f_tw = create_tween()
	f_tw.tween_property(flash, "modulate:a", 1.0, 0.05)
	f_tw.tween_property(flash, "modulate:a", 0.0, 0.8)
	f_tw.tween_callback(flash.queue_free)
	
	# Flash tam beyazken (Körlük anında) gezegen aniden küçülerek geri seker! (Anime stili darbe)
	if star:
		star.scale = Vector2(0.95, 0.95)
		var post_scale = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		post_scale.tween_property(star, "scale", Vector2(1.0, 1.0), 0.8)
	
	# Ekran tamamen aydınlanır
	overlay_rect.modulate.a = 0.0
	
	# 2. Şehir Işıkları (Districts) Bir Anda Yanar! (Gezegen Gelişir)
	if star and star.material:
		# Shader'daki gizli Ecumenopolis (-1) modunu açıyoruz! Tüm gezegen devasa bir şehir gibi parlar.
		star.material.set_shader_parameter("poi_count", -1) 
		var light_tw = create_tween()
		# Şehir ışıkları şiddetini (city_lights) 0'dan 1.5'e hızla çıkarıyoruz
		light_tw.tween_method(func(val): star.material.set_shader_parameter("city_lights", val), 0.0, 1.5, 0.8)
			
	if _poi_layer:
		# Karanlıkta devasa ışık halesi yayacak sahte (fake) ışıklar
		for i in 20:
			var lon = randf_range(-180.0, 180.0)
			var lat = randf_range(-60.0, 60.0)
			_poi_layer.add_poi(lon, lat, "", {"night_size": randi_range(3, 5), "fake": true})
			
	# =========================================================
	# OYUNUN ORİJİNAL YÖRÜNGE VE GEMİ MEKANİĞİ (OrbitalLayer)
	# =========================================================
	var orb_layer = load("res://scripts/planetary/OrbitalLayer.gd").new()
	var p_seed = 42069
	orb_layer._planet_seed = p_seed
	orb_layer._planet_radius = 350.0
	orb_layer._planet_center = get_viewport().get_visible_rect().size / 2.0
	orb_layer._planet_rotation = 0.0
	orb_layer.z_index = 85
	add_child(orb_layer)
	
	# _process içinde rotasyon güncellemesi için referans tutalım
	set_meta("orb_layer", orb_layer)
	
	# Yörüngeye oyunun kendi ShipData'larını ekle
	for i in 40:
		var ship = ShipData.make("Sat-" + str(i), p_seed, randf_range(0, TAU))
		ship.orbit_radius = randf_range(1.15, 1.8)
		ship.orbit_speed = randf_range(0.2, 0.8) * (1 if randi()%2==0 else -1)
		ShipManager.add_ship(ship)
		
	# Landing ve Dispatch (Launch) animasyonları (oyunun kendi mekaniği)
	var traffic_timer = Timer.new()
	traffic_timer.wait_time = 0.15
	traffic_timer.timeout.connect(func():
		var all_ships = ShipManager.ships_for(p_seed)
		if randi() % 100 < 30 and all_ships.size() > 10:
			# Rastgele bir gemiyi uzaya yolla (Launch animasyonu / Dispatch)
			var s = all_ships.pick_random()
			if not s.is_travelling():
				ShipManager.dispatch(s, 999, 10.0)
				
		if randi() % 100 < 25:
			# Dışarıdan gezegene inen (Landing) gemi
			var ship = ShipData.make("Incoming", p_seed, randf_range(0, TAU))
			ship.orbit_radius = randf_range(1.5, 2.0)
			ship.orbit_speed = randf_range(0.5, 1.0)
			ShipManager.add_ship(ship)
			orb_layer.start_landing(ship)
	)
	add_child(traffic_timer)
	traffic_timer.start()
	
	# Yeni vurucu metin (Daktilo)
	title_label.text = "GROW BEYOND MEASURE"
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.visible_ratio = 0.0
	
	var tw2 = create_tween()
	tw2.tween_property(title_label, "visible_ratio", 1.0, 0.6)
	
	# ÇILGIN SAYILAR FIRLAMAYA BAŞLAR! 
	var explosion_timer = Timer.new()
	explosion_timer.wait_time = 0.01 # Saniyede 100 sayı tetiklemesi!
	explosion_timer.timeout.connect(func():
		if _poi_layer:
			# Her tick'te 3 farklı yerden sayı fışkırsın! (Saniyede 300 sayı)
			for i in range(3):
				var amount = [ "+1.5M", "+42B", "+900K", "+12T", "+3M", "+180B" ].pick_random()
				var color = [ Color(0.3, 1.0, 0.4), Color(1.0, 0.8, 0.2), Color(0.2, 0.8, 1.0) ].pick_random()
				var size = randi_range(28, 48) 
				
				var lon = randf_range(-180.0, 180.0)
				var lat = randf_range(-80.0, 10.0) 
				
				# Duration'ı 0.4 saniye yapıyoruz: Anında uçup çok hızlı kaybolacaklar!
				_poi_layer.spawn_floating_text(lon, lat, amount, color, size, null, 0.4)
	)
	add_child(explosion_timer)
	explosion_timer.start()

	print("Giriş bölümü (Hook) tamamlandı! Gezegen dönüyor ve sayılar fışkırıyor.")

	# Phase 1'in izlenmesi için 4 saniye bekle
	await get_tree().create_timer(4.0).timeout
	
	# =========================================================
	# PHASE 2: OYNANIŞ VE DERİNLİK (The Engine of Growth)
	# =========================================================
	print("🎬 Phase 2 Başlıyor: UI ve Oynanış (Skill Tree)")
	
	# 1. Aşırı sayı patlamasını durdur ve yazıyı sil
	explosion_timer.stop()
	var tw_p2_out = create_tween()
	tw_p2_out.tween_property(title_label, "modulate:a", 0.0, 0.5)
	await tw_p2_out.finished
	
	# 2. Gezegeni ve arkaplanı komple gizle (Sadece UI)
	if current_gameplay_scene:
		current_gameplay_scene.visible = false
	if _poi_layer:
		_poi_layer.visible = false
	if orb_layer:
		orb_layer.visible = false
		
	# Phase 2 Yazısı
	title_label.text = "RESEARCH & EVOLVE"
	title_label.modulate.a = 0.0
	var tw_p2_text = create_tween()
	tw_p2_text.tween_property(title_label, "modulate:a", 1.0, 1.0)
		
	# 3. Gerçek SKILL TREE'yi aç!
	var st_root = get_tree().root.get_node("SkillTree")
	var all_skill_keys = []
	if st_root:
		# Bütün kutuları baştan (kilitli gri şekilde) üretmesi için hileyi AÇ
		st_root.set_meta("debug_reveal_all", true)
		
		# Ama asıl yetenekleri sıfırla ki kilitli görünsünler
		st_root.unlocked_skills.clear()
		st_root.unlocked_skills.append_array(["root", "unlock_solar_panel", "unlock_residential", "unlock_lab"])
		st_root.skill_levels = {
			"unlock_solar_panel": 1,
			"unlock_residential": 1,
			"unlock_lab": 1
		}
		
		# Bütün node id'lerini topla (default olanlar hariç)
		for id in st_root.get("nodes").keys():
			if id not in st_root.unlocked_skills:
				all_skill_keys.append(id)
				
		# Merkeze olan uzaklığına göre sırala (Bütün branchler aynı anda dalga dalga açılsın)
		all_skill_keys.sort_custom(func(a, b):
			var pos_a = st_root.get("nodes")[a].pos
			var pos_b = st_root.get("nodes")[b].pos
			return pos_a.length_squared() < pos_b.length_squared()
		)
	
	var skill_tree = load("res://scripts/ui/SkillTreeView.gd").new()
	skill_tree.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # Ekranı tamamen kapla
	add_child(skill_tree)
	skill_tree.modulate.a = 0.0
	
	# Yazıyı en öne al (Ağacın arkasında kalmasın)
	title_label.move_to_front()
	
	# Başlangıçta biraz Zoom-In yapılmış olsun
	skill_tree._center_ctrl.scale = Vector2(1.5, 1.5)
	
	# Skill tree yavaşça ekrana gelir
	var tw_st = create_tween()
	tw_st.tween_property(skill_tree, "modulate:a", 1.0, 0.5)
	
	# Ağaç içinde PANNING yerine ZOOM-OUT yap
	await get_tree().create_timer(0.5).timeout
	var st_zoom = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# SkillTree'yi dışarı doğru uzaklaştır
	st_zoom.tween_property(skill_tree._center_ctrl, "scale", Vector2(0.55, 0.55), 5.0)
	
	# Zoom yaparken arka planda skilleri merkezden dışa hızlıca unlock et
	var unlock_timer = Timer.new()
	unlock_timer.wait_time = 0.06 # Çok hızlı ardışık açılışlar
	unlock_timer.timeout.connect(func():
		# Eğer timer tetiklendiğinde SkillTree silinmişse (Faz bitmişse) timeri öldür.
		if not is_instance_valid(skill_tree):
			unlock_timer.stop()
			return
			
		if all_skill_keys.size() > 0:
			var id = all_skill_keys.pop_front()
			if st_root:
				st_root.unlocked_skills.append(id)
				st_root.skill_levels[id] = 1
				
				if skill_tree.get("_ui_nodes") != null and skill_tree.get("_ui_nodes").has(id):
					var card = skill_tree.get("_ui_nodes")[id]
					if is_instance_valid(card):
						# Punch Scale Animasyonu
						card.pivot_offset = card.size / 2.0
						card.scale = Vector2(1.5, 1.5)
						var tw_punch = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
						tw_punch.tween_property(card, "scale", Vector2(1.0, 1.0), 0.4)
						
						# Sadece hafif bir parlama (flash) efekti
						card.modulate = Color(2.5, 2.5, 2.5, 1.0)
						var tw_flash = create_tween()
						tw_flash.tween_property(card, "modulate", Color.WHITE, 0.4)
						
						# Kendi orijinal rengini (Unlocked) çizmesi için force_refresh
						if skill_tree.has_method("force_refresh_node"):
							skill_tree.force_refresh_node(id)
				
				# Sadece bağlantı çizgilerini güncelle
				if is_instance_valid(skill_tree.get("_connections_draw")):
					skill_tree.get("_connections_draw").queue_redraw()
		else:
			unlock_timer.stop()
	)
	add_child(unlock_timer)
	unlock_timer.start()
	
	await st_zoom.finished
	unlock_timer.stop() # Faz bitince her türlü timer'ı kapat!
	
	# Skill Tree'yi ve Yazıyı kapat
	var tw_st_out = create_tween()
	tw_st_out.tween_property(title_label, "modulate:a", 0.0, 0.5)
	tw_st_out.parallel().tween_property(skill_tree, "modulate:a", 0.0, 0.5)
	await tw_st_out.finished
	skill_tree.queue_free()
	
	# =========================================================
	# PHASE 3: SOLAR VE GALAKTİK ÖLÇEK (Expand Your Empire)
	# =========================================================
	print("🎬 Phase 3 Başlıyor: Moon System -> Solar System -> Galaxy")
	
	# Ekranı yavaşça karart
	var tw_p3 = create_tween()
	tw_p3.tween_property(overlay_rect, "modulate:a", 1.0, 0.5)
	await tw_p3.finished
	
	# Yörünge ve POI kalıntılarını tamamen temizle
	if is_instance_valid(orb_layer):
		orb_layer.queue_free()
		remove_meta("orb_layer")
	if is_instance_valid(_poi_layer):
		_poi_layer.queue_free()
	traffic_timer.stop()
		
	# A) LOCAL SYSTEM (Terran ve Aylarının Sistemi)
	load_background_scene("res://scenes/solar/SolarView.tscn")
	set_ui_visible(false) # UI tamamen gizli, saf sinematik görünüm!
	var sd_local = load("res://scripts/solar/SolarData.gd").new()
	sd_local.is_home = true
	current_gameplay_scene._current = sd_local
	
	var pd_local = GameState.get_home_planet()
	# Oyunun oluşturduğu Local System (Genelde 1 adet uydusu garanti vardır, ama yinede kontrol edelim)
	if pd_local.moons.is_empty():
		pd_local.moons.append(load("res://scripts/planetary/PlanetData.gd").make_moon(pd_local.seed + 1))
		
	current_gameplay_scene.load_local(pd_local)
	
	title_label.text = "CONQUER YOUR SYSTEM"
	title_label.modulate.a = 0.0
	
	var tw_local = create_tween()
	tw_local.tween_property(overlay_rect, "modulate:a", 0.0, 1.0)
	tw_local.parallel().tween_property(title_label, "modulate:a", 1.0, 1.0)
	await get_tree().create_timer(3.0).timeout
	
	var tw_local_out = create_tween()
	tw_local_out.tween_property(overlay_rect, "modulate:a", 1.0, 0.5)
	tw_local_out.parallel().tween_property(title_label, "modulate:a", 0.0, 0.5)
	await tw_local_out.finished
	
	# B) SOLAR SYSTEM (Yıldız ve Gezegenler)
	load_background_scene("res://scenes/solar/SolarView.tscn")
	set_ui_visible(false)
	var sd_system = GameState.get_home_solar()
	current_gameplay_scene.load_system(sd_system)
	
	title_label.text = "EXPAND YOUR HORIZON"
	title_label.modulate.a = 0.0
	
	var tw_solar = create_tween()
	tw_solar.tween_property(overlay_rect, "modulate:a", 0.0, 1.0)
	tw_solar.parallel().tween_property(title_label, "modulate:a", 1.0, 1.0)
	await get_tree().create_timer(3.0).timeout
	
	var tw_solar_out = create_tween()
	tw_solar_out.tween_property(overlay_rect, "modulate:a", 1.0, 0.5)
	tw_solar_out.parallel().tween_property(title_label, "modulate:a", 0.0, 0.5)
	await tw_solar_out.finished
	
	# C) GALAXY MAP (Yıldız Haritası)
	load_background_scene("res://scenes/galaxy/GalaxyView.tscn")
	set_ui_visible(false)
	title_label.text = "DOMINATE THE GALAXY"
	title_label.modulate.a = 0.0
	
	var gd_orig = current_gameplay_scene.get("_galaxy")
	if gd_orig:
		# Godot 4 Resource duplicate() bug'ı (Typed Array'leri bozması) yüzünden klonlamıyoruz!
		# Fragmanda ekranın full dolması ve bitmemesi için 250 yıldızlı DEV BİR GALAKSİ yaratıyoruz.
		var gd = load("res://scripts/galaxy/GalaxyData.gd").from_seed(GameState.home_planet_seed ^ 0xABCDEF, 250)
		
		# _ready()'de offsetin ezilmesini engellemek için değerleri gd içine zorluyoruz
		var center_offset = get_viewport().get_visible_rect().size / 2.0
		gd.view_zoom = 4.5
		gd.view_offset = center_offset
		
		# from_seed() zaten sadece home_idx'i true, diğerlerini false yaptığı için başka bir şeye gerek yok.
		current_gameplay_scene.set("_galaxy", gd)
		current_gameplay_scene.set("_zoom", 4.5) # Çok daha içeriden başlasın! (Önceki: 2.0)
		current_gameplay_scene.set("_offset", center_offset)
		
		# Zoom out animasyonunu yavaşlatıp 6 saniyeye çıkarıyoruz
		var tw_gal_zoom = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw_gal_zoom.tween_property(current_gameplay_scene, "_zoom", 0.65, 6.0)
		
		var dists = gd.compute_hop_distances()
		var explore_queue = []
		for hop in range(1, 40): # 250 yıldız olduğu için çok daha uzağa (40 hop) bakıyoruz
			for i in gd.unlocked.size():
				if dists[i] == hop:
					explore_queue.append(i)
		
		var explore_timer = Timer.new()
		explore_timer.wait_time = 0.05 # Hızı tık tık akıcı
		explore_timer.timeout.connect(func():
			var popped_any = false
			# Ekranın devasa bir şekilde dolması için her tick'te 3 yıldız birden açıyoruz
			for _burst in range(3):
				if explore_queue.size() > 0:
					var idx = explore_queue.pop_front()
					gd.unlocked[idx] = true
					popped_any = true
			
			if popped_any and is_instance_valid(current_gameplay_scene):
				current_gameplay_scene.queue_redraw()
			elif explore_queue.size() == 0:
				explore_timer.stop()
				explore_timer.queue_free() # İş bitince temizle
		)
		add_child(explore_timer)
		
		# Keşfetme dalgasının başlamasından önce 1 saniyelik dramatik bir sessizlik (gerilim) ekle
		var start_delay = get_tree().create_timer(1.2)
		start_delay.timeout.connect(func():
			if is_instance_valid(explore_timer):
				explore_timer.start()
		)
	
	var tw_gal = create_tween()
	tw_gal.tween_property(overlay_rect, "modulate:a", 0.0, 1.0)
	tw_gal.parallel().tween_property(title_label, "modulate:a", 1.0, 1.0)
	
	# Sahne süresini 4.0'dan 6.5 saniyeye uzatıyoruz ki keşif hissiyatını tam izleyelim
	await get_tree().create_timer(6.5).timeout
	
	# Phase 4'e geçmeden önce temizce karart
	var tw_gal_out = create_tween()
	tw_gal_out.tween_property(overlay_rect, "modulate:a", 1.0, 0.5)
	tw_gal_out.parallel().tween_property(title_label, "modulate:a", 0.0, 0.5)
	await tw_gal_out.finished
	
	# =========================================================
	# PHASE 4: PROCEDURAL SHOWCASE (Rapid Biome Switching)
	# =========================================================
	print("🎬 Phase 4 Başlıyor: Procedural Showcase")
	
	# Önceki sahneleri temizle
	if current_gameplay_scene != null:
		current_gameplay_scene.queue_free()
		current_gameplay_scene = null
		
	# Yüzeyde devasa bir gezegen göstereceğimiz için sadece boş bir UI ve üstüne gezegen koyacağız
	var proc_container = Control.new()
	proc_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(proc_container)
	move_child(proc_container, 0) # En arkaya at
	
	# Merkezdeki devasa gezegen rect'i
	var proc_star = ColorRect.new()
	proc_star.size = Vector2(600.0, 600.0)
	proc_star.position = (get_viewport().get_visible_rect().size / 2.0) - (proc_star.size / 2.0)
	proc_star.pivot_offset = proc_star.size / 2.0
	proc_container.add_child(proc_star)
	
	title_label.text = "ALL PROCEDURALLY GENERATED"
	title_label.modulate.a = 0.0
	
	var tw_proc = create_tween()
	tw_proc.tween_property(overlay_rect, "modulate:a", 0.0, 0.5)
	tw_proc.parallel().tween_property(title_label, "modulate:a", 1.0, 0.5)
	
	# Hızlıca gezegenleri değiştiren Timer
	var proc_timer = Timer.new()
	proc_timer.wait_time = 0.15 # Çok hızlı geçiş!
	var biome_types = [1, 2, 3, 4, 5, 6, 7] # Diğer biomlar
	
	# Shader'ı güncelleme fonksiyonu
	var update_planet_func = func(p_type: int, p_seed: int):
		var pdata = load("res://scripts/planetary/PlanetData.gd").from_seed_as_type(p_seed, p_type)
		var s_path = load("res://scripts/planetary/PlanetData.gd").get_shader_path(p_type)
		var p_mat = ShaderMaterial.new()
		p_mat.shader = load(s_path)
		p_mat.set_shader_parameter("planet_radius", 0.40)
		p_mat.set_shader_parameter("pixel_count", 600.0)
		p_mat.set_shader_parameter("aspect_ratio", 1.0)
		p_mat.set_shader_parameter("seed", p_seed)
		p_mat.set_shader_parameter("terrain_roughness", pdata.terrain_roughness)
		p_mat.set_shader_parameter("rotation_offset", 0.0)
		
		# Tüm renkleri doldur
		for key in load("res://scripts/planetary/PlanetData.gd").get_colors(pdata.planet_type):
			p_mat.set_shader_parameter(key, load("res://scripts/planetary/PlanetData.gd").get_colors(pdata.planet_type)[key])
			
		proc_star.material = p_mat
	
	# İlk başta beyaz bir kare gözükmemesi (glitch) için timerdan önce hemen bir tane yükleyelim
	update_planet_func.call(biome_types.pick_random(), randi() % 99999)

	proc_timer.timeout.connect(func():
		var rand_type = biome_types.pick_random()
		var rand_seed = randi() % 99999
		update_planet_func.call(rand_type, rand_seed)
	)
	add_child(proc_timer)
	proc_timer.start()
	
	await get_tree().create_timer(3.0).timeout
	proc_timer.stop()
	proc_timer.queue_free()
	
	# En son Terran'a kilitlen
	update_planet_func.call(0, 42069)
	
	# =========================================================
	# PHASE 5: KAPANIŞ (The Apex - Cover Art)
	# =========================================================
	print("🎬 Phase 5 Başlıyor: Kapanış ve Logo")
	
	var tw_p5 = create_tween()
	tw_p5.tween_property(title_label, "modulate:a", 0.0, 0.5)
	
	await tw_p5.finished
	
	# Gezegeni aşağı kaydır ve devasa büyüt (ss1 referansına göre)
	var final_scale = Vector2(2.5, 2.5)
	# Pivot merkezde olduğu için, X'i hiç ellemeyip sadece Y ekseninde kaydırıyoruz ki düz aşağı insin!
	var final_pos = Vector2(
		proc_star.position.x,
		proc_star.position.y + 600
	)
	
	var tw_slide = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw_slide.tween_property(proc_star, "scale", final_scale, 1.5)
	tw_slide.parallel().tween_property(proc_star, "position", final_pos, 1.5)
	tw_slide.parallel().tween_property(overlay_rect, "modulate:a", 0.3, 1.5) # Hafif kararır
	
	await tw_slide.finished
	
	# VOIDLE Yazısı (Görsel olarak)
	title_label.text = ""
	
	var tw_logo = create_tween()
	var logo_img = Image.new()
	var err = logo_img.load("/Users/sasete/.gemini/antigravity/brain/25e34f6e-20a7-4f83-8373-38782b3de1da/.user_uploaded/media__1785325116750.png")
	if err == OK:
		var logo_tex = ImageTexture.create_from_image(logo_img)
		var logo_rect = TextureRect.new()
		logo_rect.texture = logo_tex
		logo_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo_rect.custom_minimum_size = Vector2(460, 120)
		logo_rect.modulate.a = 0.0
		add_child(logo_rect)
		logo_rect.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		logo_rect.position.y -= 200
		tw_logo.tween_property(logo_rect, "modulate:a", 1.0, 1.0)
	else:
		title_label.text = "VOIDLE"
		title_label.add_theme_font_size_override("font_size", 140)
		title_label.modulate.a = 0.0
		add_child(title_label)
		title_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		title_label.position.y -= 200
		tw_logo.tween_property(title_label, "modulate:a", 1.0, 1.0)
		
	# --- ROKET EFEKTİ (Yüzeyden Kalkış + Yörünge Curve2D) ---
	var planet_center = final_pos + Vector2(300, 300)
	
	# Roket Görseli
	var rocket = ColorRect.new()
	rocket.size = Vector2(6, 6)
	rocket.color = Color.WHITE
	
	var glow = ColorRect.new()
	glow.size = Vector2(16, 16)
	glow.position = Vector2(-5, -5)
	glow.color = Color(0.4, 0.8, 1.0, 0.45)
	rocket.add_child(glow)
	
	add_child(rocket)
	
	# 1. FIRLATMA EĞRİSİ (Yüzeyden yörüngeye çıkış)
	var launch_curve = Curve2D.new()
	# Başlangıç: Ön yüzeyde SAĞ ÜST karanın üzeri.
	# Ekranın altına düşmemesi için (Y = -480) seviyesine aldım.
	# out = (80, -100) -> Gezegen yüzeyine DİK olarak dışarı doğru (sağ-yukarı) fırlatılır.
	launch_curve.add_point(Vector2(320, -450), Vector2(0, 0), Vector2(60, -120))
	# Tepe: Steam yazısının üstü
	launch_curve.add_point(Vector2(90, -580), Vector2(150, -20), Vector2(-150, 20))
	# Bitiş: Yörüngeye oturma (Okun ucu - sol alt)
	launch_curve.add_point(Vector2(-350, -250), Vector2(150, -200), Vector2(-150, 200))
	
	# 2. YÖRÜNGE EĞRİSİ (Sonsuz dönüş)
	var orbit_curve = Curve2D.new()
	# 0. Başlangıç (Okun ucu)
	orbit_curve.add_point(Vector2(-350, -250), Vector2(150, -200), Vector2(-150, 200))
	# 1. Gezegenin Arkası
	orbit_curve.add_point(Vector2(50, 100), Vector2(-250, 0), Vector2(250, 0))
	# 2. Sağdan tekrar çıkış
	orbit_curve.add_point(Vector2(580, -250), Vector2(100, 200), Vector2(-100, -200))
	# 3. Tepe noktası (Steam üstü)
	orbit_curve.add_point(Vector2(90, -580), Vector2(150, 0), Vector2(-150, 0))
	# 4. Geri dönüş (Loop)
	orbit_curve.add_point(Vector2(-350, -250), Vector2(150, -200), Vector2(-150, 200))
	
	var tw_rocket = create_tween()
	var flight_duration = 5.0
	
	tw_rocket.tween_method(func(t: float):
		if not is_instance_valid(rocket): return
		
		var curve: float
		var CRUISE_FRAC: float = 0.10
		var D: float = (1.0 + CRUISE_FRAC) * 0.5
		if t <= 0.5:
			curve = 2.0 * t * t
		else:
			var u = (t - 0.5) / 0.5
			var integ = u - u * u * (1.0 - CRUISE_FRAC) * 0.5
			curve = 0.5 + (integ / D) * 0.5
			
		var raw_pos = launch_curve.sample_baked(curve * launch_curve.get_baked_length())
		rocket.position = planet_center + raw_pos - (rocket.size / 2.0)
		
		# Kalkışta her zaman öndedir (Görünür)
		rocket.visible = true
		
	, 0.0, 1.0, flight_duration)
	
	# Yörüngeye oturduktan sonra arkadan dolanıp tur atmaya devam etsin
	tw_rocket.finished.connect(func():
		if not is_instance_valid(rocket): return
		var tw_orbit = create_tween().set_loops()
		tw_orbit.tween_method(func(t_orb: float):
			if not is_instance_valid(rocket): return
			
			var raw_pos = orbit_curve.sample_baked(t_orb * orbit_curve.get_baked_length())
			rocket.position = planet_center + raw_pos - (rocket.size / 2.0)
			
			# Görünürlük Mantığı:
			# t_orb < 0.5 iken roket arka yarımdadır (Arka tarafa doğru gidiyor).
			# EĞER roket arkadaysa VE gezegenin sınırları (radius=600) içindeyse gizle!
			# Aksi takdirde (uzayda sağdan çıkarken veya ön yarımdaysa) göster.
			var is_behind = (t_orb < 0.5)
			var is_inside_planet_disk = (raw_pos.length() < 595.0)
			
			rocket.visible = not (is_behind and is_inside_planet_disk)
		, 0.0, 1.0, 15.0)
	)
	
	await tw_logo.finished
	
	# STEAM Wishlist CTA
	await get_tree().create_timer(0.5).timeout
	
	var steam_panel = PanelContainer.new()
	var steam_style = StyleBoxFlat.new()
	steam_style.bg_color = Color("#749D38") # Steam Green
	steam_style.corner_radius_top_left = 6
	steam_style.corner_radius_top_right = 6
	steam_style.corner_radius_bottom_right = 6
	steam_style.corner_radius_bottom_left = 6
	steam_style.content_margin_left = 50
	steam_style.content_margin_right = 50
	steam_style.content_margin_top = 15
	steam_style.content_margin_bottom = 15
	steam_panel.add_theme_stylebox_override("panel", steam_style)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var steam_icon = TextureRect.new()
	var svg_tex = load("res://assets/steam_icon_user.png")
	if svg_tex:
		steam_icon.texture = svg_tex
		steam_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		steam_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		steam_icon.custom_minimum_size = Vector2(32, 32)
		
		# Siyah arka planı yok etmek için özel bir shader
		var sh_mat = ShaderMaterial.new()
		var sh = Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat brightness = (c.r + c.g + c.b) / 3.0;\n\tif (brightness < 0.2) {\n\t\tc.a = 0.0;\n\t}\n\tCOLOR = c;\n}"
		sh_mat.shader = sh
		steam_icon.material = sh_mat
		
	hbox.add_child(steam_icon)
	
	var cta_label = Label.new()
	cta_label.text = "WISHLIST NOW"
	orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	if orbitron: cta_label.add_theme_font_override("font", orbitron)
	cta_label.add_theme_font_size_override("font_size", 28)
	cta_label.add_theme_color_override("font_color", Color.WHITE) # Match white icon
	hbox.add_child(cta_label)
	
	steam_panel.add_child(hbox)
	
	steam_panel.modulate.a = 0.0
	add_child(steam_panel)
	# Eklendikten sonra ortala ve alta kaydır
	steam_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	steam_panel.position.y += 120
	
	var tw_cta = create_tween()
	tw_cta.tween_property(steam_panel, "modulate:a", 1.0, 1.0)
	await tw_cta.finished
		
	await get_tree().create_timer(3.0).timeout
	print("🎬 Fragman Sonu!")

# =========================================================
# YARDIMCI FONKSİYONLAR
# =========================================================

func load_background_scene(scene_path: String):
	if current_gameplay_scene != null:
		current_gameplay_scene.queue_free()
		
	var packed_scene = load(scene_path) as PackedScene
	if packed_scene:
		current_gameplay_scene = packed_scene.instantiate()
		
		# Rastgele sistem üretilmesini engelle
		current_gameplay_scene.set_meta("is_trailer", true)
		if "random_on_start" in current_gameplay_scene:
			current_gameplay_scene.set("random_on_start", false)
		
		# Sahne bir Control ise tam ekran yap
		if current_gameplay_scene is Control:
			current_gameplay_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			# ÖNEMLİ: Anchors bazen anında çalışmaz, manuel olarak ekran boyutunu verelim ki 0x0 olmasın!
			current_gameplay_scene.size = get_viewport().get_visible_rect().size
			
		if gameplay_container:
			gameplay_container.add_child(current_gameplay_scene)
		else:
			add_child(current_gameplay_scene)
			move_child(current_gameplay_scene, 0)
			
		# Sahne eklendikten sonra içindeki SpaceContainer'ın boyutunu da zorla güncelleyelim
		var space = current_gameplay_scene.get_node_or_null("SpaceContainer")
		if space and space is Control:
			space.size = get_viewport().get_visible_rect().size
			
	else:
		push_error("Sahne bulunamadı: ", scene_path)

func set_ui_visible(is_visible: bool):
	# 1. Fare imlecini (cursor) gizle/göster
	if is_visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		
	# Fareyi geri getiren CursorManager'ı bu branch'te görünmez yapıp donduralım (queue_free yapamayız, diğer scriptler çöküyor)
	if has_node("/root/CursorManager"):
		var cm = get_node("/root/CursorManager")
		cm.process_mode = Node.PROCESS_MODE_DISABLED if not is_visible else Node.PROCESS_MODE_ALWAYS
		if cm.get("_sprite"):
			cm.get("_sprite").visible = is_visible
		
	# 2. Global HUD'ı tamamen yok et
	if has_node("/root/HUDManager"):
		var hud = get_node("/root/HUDManager")
		if hud.has_method("set_game_hud"):
			hud.set_game_hud(is_visible) # Top layer dahil her şeyi kapatan kendi fonksiyonu
		else:
			hud.visible = is_visible
		hud.process_mode = Node.PROCESS_MODE_DISABLED if not is_visible else Node.PROCESS_MODE_INHERIT

	# 3. Yüklenen oyun sahnesindeki tüm arayüzleri (UICanvas vb.) acımasızca gizle
	if current_gameplay_scene:
		_hide_all_canvas_layers(current_gameplay_scene, is_visible)
		
		# (Opsiyonel) Eğer kamera sol üstte kalıyorsa, SolarView içindeki kamerayı zorla ortalayalım
		if not is_visible:
			_center_camera(current_gameplay_scene)

func _center_camera(node: Node):
	# Sahnedeki Camera2D'yi bul ve ortaya (atıyorum 960, 540) kaydır.
	# Eğer senin ekran çözünürlüğün 1920x1080 ise ortası 960x540 olur.
	if node is Camera2D:
		var vp_size = get_viewport().get_visible_rect().size
		node.global_position = vp_size / 2.0
		# zoom da yapmak istersen: node.zoom = Vector2(1.5, 1.5)
	else:
		for child in node.get_children():
			_center_camera(child)

func _hide_all_canvas_layers(node: Node, is_visible: bool):
	if node is CanvasLayer:
		node.visible = is_visible
	elif node.name == "UICanvas" or node.name.begins_with("UI"):
		# Özel olarak UI isimli nodeları gizle
		if "visible" in node:
			node.visible = is_visible
			
	for child in node.get_children():
		_hide_all_canvas_layers(child, is_visible)

func _build_background_stars() -> void:
	var vp := get_viewport().get_visible_rect().size
	_make_star_layer(vp, 180, 8.0,  Color(0.7, 0.75, 1.0, 0.45), 1.0)
	_make_star_layer(vp, 80,  18.0, Color(0.85, 0.90, 1.0, 0.65), 1.6)
	_make_star_layer(vp, 30,  32.0, Color(1.0,  1.0,  1.0, 0.90), 2.0)

func _make_star_layer(vp: Vector2, count: int, speed: float, col: Color, size: float) -> void:
	var p := CPUParticles2D.new()
	p.emitting              = true
	p.amount                = count
	p.lifetime              = (vp.x + 60.0) / speed
	p.preprocess            = p.lifetime
	p.explosiveness         = 0.0
	p.randomness            = 1.0

	p.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(vp.x * 0.5 + 40.0, vp.y * 0.5)
	p.position              = Vector2(vp.x * 0.5, vp.y * 0.5)

	p.direction             = Vector2(-1.0, 0.0)
	p.spread                = 3.0
	p.gravity               = Vector2.ZERO
	p.initial_velocity_min  = speed * 0.8
	p.initial_velocity_max  = speed * 1.2
	p.scale_amount_min      = size * 0.6
	p.scale_amount_max      = size * 1.4

	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 0.0))
	grad.set_color(1, col)
	grad.add_point(0.05, col)
	grad.add_point(0.95, col)
	p.color_ramp = grad
	
	p.z_index = -10 # Gezegenin arkasında kalsın
	
	if current_gameplay_scene:
		var space = current_gameplay_scene.get_node_or_null("SpaceContainer")
		if space:
			space.add_child(p)
		else:
			current_gameplay_scene.add_child(p)
