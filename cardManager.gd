extends Node

const CACHE_FILE = "user://saved_decks_full_cache.json"
const DECKS_JSON_FILE = "res://decks_data.json"

const ART_CACHE_DIR = "user://card_art_cache/"
const ART_METADATA_FILE = "user://card_art_cache/art_metadata.json"
const CACHE_EXPIRY_DAYS = 30.0
const SECONDS_PER_DAY = 86400.0

signal texture_loaded(url: String, texture: Texture2D)

var _art_metadata_cache: Dictionary = {}
var _art_metadata_loaded: bool = false
var _texture_cache: Dictionary = {}

func _ready() -> void:
	_ensure_cache_dir_exists()
	clean_expired_art_cache()

func load_decks_data_json() -> Array:
	if FileAccess.file_exists(DECKS_JSON_FILE):
		var file := FileAccess.open(DECKS_JSON_FILE, FileAccess.READ)
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data = json.get_data()
			if data is Array:
				return data
	return [{"id": 27463170, "name": "The Great Goblin", "commander": "The Great Goblin"}]

func load_cache_from_disk() -> Dictionary:
	if FileAccess.file_exists(CACHE_FILE):
		var file := FileAccess.open(CACHE_FILE, FileAccess.READ)
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data = json.get_data()
			if data is Dictionary:
				return data
	return {}

func save_cache_to_disk(cache_dict: Dictionary) -> void:
	var file := FileAccess.open(CACHE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(cache_dict, "\t"))

func _ensure_cache_dir_exists() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("card_art_cache"):
		dir.make_dir("card_art_cache")

func load_art_metadata() -> Dictionary:
	if _art_metadata_loaded:
		return _art_metadata_cache

	if FileAccess.file_exists(ART_METADATA_FILE):
		var file := FileAccess.open(ART_METADATA_FILE, FileAccess.READ)
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data = json.get_data()
			if data is Dictionary:
				_art_metadata_cache = data
				_art_metadata_loaded = true
				return _art_metadata_cache

	_art_metadata_cache = {}
	_art_metadata_loaded = true
	return _art_metadata_cache

func save_art_metadata(metadata: Dictionary) -> void:
	_art_metadata_cache = metadata
	_art_metadata_loaded = true
	var file := FileAccess.open(ART_METADATA_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(metadata, "\t"))

func get_cache_filename(url: String) -> String:
	return ART_CACHE_DIR + url.sha256_text() + ".cache"

func get_cached_image_texture(url: String) -> Texture2D:
	if url.is_empty():
		return null

	if _texture_cache.has(url):
		return _texture_cache[url]

	var file_path := get_cache_filename(url)
	if FileAccess.file_exists(file_path):
		var metadata := load_art_metadata()
		if metadata.has(url):
			var entry: Dictionary = metadata[url]
			var timestamp: float = entry.get("timestamp", 0.0)
			var age_days := (Time.get_unix_time_from_system() - timestamp) / SECONDS_PER_DAY

			if age_days <= CACHE_EXPIRY_DAYS:
				var buffer := FileAccess.get_file_as_bytes(file_path)
				if not buffer.is_empty():
					var image := Image.new()
					if _load_image_smart_buffer(image, buffer) == OK:
						var tex := ImageTexture.create_from_image(image)
						_texture_cache[url] = tex
						return tex
	return null

func store_image_to_cache(url: String, buffer: PackedByteArray) -> Texture2D:
	if url.is_empty() or buffer.is_empty():
		return null
	var file_path := get_cache_filename(url)

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_buffer(buffer)
		file.close()

		var metadata := load_art_metadata()
		metadata[url] = {
			"timestamp": Time.get_unix_time_from_system(),
			"path": file_path
		}
		save_art_metadata(metadata)

		var image := Image.new()
		if _load_image_smart_buffer(image, buffer) == OK:
			var tex := ImageTexture.create_from_image(image)
			_texture_cache[url] = tex
			return tex
	return null

func clean_expired_art_cache() -> void:
	var metadata := load_art_metadata()
	if metadata.is_empty():
		return

	var current_time := Time.get_unix_time_from_system()
	var updated_metadata := {}
	var dir := DirAccess.open(ART_CACHE_DIR)

	if not dir:
		return

	for url in metadata.keys():
		var entry: Dictionary = metadata[url]
		var timestamp: float = entry.get("timestamp", 0.0)
		var file_path: String = entry.get("path", "")
		var age_days := (current_time - timestamp) / SECONDS_PER_DAY

		if age_days > CACHE_EXPIRY_DAYS:
			if FileAccess.file_exists(file_path):
				dir.remove(file_path.get_file())
		elif FileAccess.file_exists(file_path):
			updated_metadata[url] = entry

	save_art_metadata(updated_metadata)

func _load_image_smart_buffer(image: Image, body: PackedByteArray) -> Error:
	if body.size() > 4 and body[0] == 137 and body[1] == 80:
		return image.load_png_from_buffer(body)

	var err := image.load_jpg_from_buffer(body)
	return image.load_png_from_buffer(body) if err != OK else OK
