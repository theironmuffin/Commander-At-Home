extends Node

const DECK_CACHE_PATH = "user://deck_cache.json"
const BUNDLED_DECK_CACHE_PATH = "res://deck_cache.json"
const ART_CACHE_DIR = "user://card_art_cache"

var _texture_cache: Dictionary = {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ART_CACHE_DIR)

func load_cache_from_disk() -> Dictionary:
	var cache := {}
	if FileAccess.file_exists(BUNDLED_DECK_CACHE_PATH):
		var bf := FileAccess.open(BUNDLED_DECK_CACHE_PATH, FileAccess.READ)
		if bf:
			var bjson := JSON.new()
			if bjson.parse(bf.get_as_text()) == OK and bjson.get_data() is Dictionary:
				cache = bjson.get_data()
	if FileAccess.file_exists(DECK_CACHE_PATH):
		var uf := FileAccess.open(DECK_CACHE_PATH, FileAccess.READ)
		if uf:
			var ujson := JSON.new()
			if ujson.parse(uf.get_as_text()) == OK and ujson.get_data() is Dictionary:
				var u_data: Dictionary = ujson.get_data()
				for k in u_data.keys():
					cache[k] = u_data[k]
	return cache

func save_cache_to_disk(cache: Dictionary) -> void:
	var uf := FileAccess.open(DECK_CACHE_PATH, FileAccess.WRITE)
	if uf:
		uf.store_string(JSON.stringify(cache))

func _get_art_cache_path(url: String) -> String:
	return "%s/%s.img" % [ART_CACHE_DIR, url.md5_text()]

func _decode_image_from_buffer(body: PackedByteArray) -> Image:
	if body.is_empty():
		return null
	var img := Image.new()
	var err := ERR_INVALID_DATA
	if body.size() >= 8 and body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47:
		err = img.load_png_from_buffer(body)
	elif body.size() >= 12 and body.slice(0, 4) == PackedByteArray([0x52, 0x49, 0x46, 0x46]) and body.slice(8, 12) == PackedByteArray([0x57, 0x45, 0x42, 0x50]):
		err = img.load_webp_from_buffer(body)
	else:
		err = img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_png_from_buffer(body)
		if err != OK:
			err = img.load_webp_from_buffer(body)
	if err != OK or img.is_empty():
		return null
	if OS.get_name() in ["Android", "iOS"] and (img.get_width() > 512 or img.get_height() > 512):
		var scale_f := 512.0 / float(maxi(img.get_width(), img.get_height()))
		img.resize(maxi(1, int(img.get_width() * scale_f)), maxi(1, int(img.get_height() * scale_f)), Image.INTERPOLATE_BILINEAR)
	return img

func get_cached_image_texture(url: String) -> Texture2D:
	if url.is_empty():
		return null
	if _texture_cache.has(url):
		return _texture_cache[url]
	var path := _get_art_cache_path(url)
	if FileAccess.file_exists(path):
		var body := FileAccess.get_file_as_bytes(path)
		var img := _decode_image_from_buffer(body)
		if img:
			var tex := ImageTexture.create_from_image(img)
			_texture_cache[url] = tex
			return tex
	return null

func store_image_to_cache(url: String, body: PackedByteArray) -> Texture2D:
	if url.is_empty() or body.is_empty():
		return null
	var img := _decode_image_from_buffer(body)
	if not img:
		return null
	DirAccess.make_dir_recursive_absolute(ART_CACHE_DIR)
	var path := _get_art_cache_path(url)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(body)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[url] = tex
	return tex
