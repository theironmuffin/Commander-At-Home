class_name ScryfallService
extends Node

const CHUNK_SIZE = 75
const API_URL = "https://api.scryfall.com/cards/collection"

func fetch_batch_metadata(card_names: Array, callback: Callable) -> void:
	var unique_names: Array[String] = []
	var alias_map := {} # query_name -> [original_requested_names]

	for raw_name in card_names:
		var orig := str(raw_name).strip_edges()
		if orig.is_empty(): continue
		# Scryfall's /cards/collection matches front-face names reliably for "A // B" cards
		var query_name := orig.split(" // ")[0].strip_edges() if " // " in orig else orig
		if not query_name in unique_names:
			unique_names.append(query_name)
		if not alias_map.has(query_name):
			alias_map[query_name] = []
		if not orig in alias_map[query_name]:
			alias_map[query_name].append(orig)

	var metadata_map := {}
	var chunks: Array[Array] = []

	for i in range(0, unique_names.size(), CHUNK_SIZE):
		chunks.append(unique_names.slice(i, i + CHUNK_SIZE))

	_fetch_chunks_recursive(chunks, 0, metadata_map, alias_map, callback)

func _fetch_chunks_recursive(chunks: Array[Array], chunk_idx: int, metadata_map: Dictionary, alias_map: Dictionary, callback: Callable) -> void:
	if chunk_idx >= chunks.size():
		callback.call(metadata_map)
		return

	var chunk: Array = chunks[chunk_idx]
	var identifiers: Array[Dictionary] = []
	for card_name in chunk:
		identifiers.append({"name": card_name})

	var http := HTTPRequest.new()
	add_child(http)
	var http_id := http.get_instance_id()

	http.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		var req := instance_from_id(http_id)
		if req and is_instance_valid(req): req.queue_free()
		if response_code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				_parse_scryfall_response(json.get_data(), metadata_map, alias_map)

		_fetch_chunks_recursive(chunks, chunk_idx + 1, metadata_map, alias_map, callback)
	)

	var headers: Array[String] = ["Content-Type: application/json", "User-Agent: MTGBrawlSim/1.0"]
	var payload := JSON.stringify({"identifiers": identifiers})
	http.request(API_URL, headers, HTTPClient.METHOD_POST, payload)

func _parse_scryfall_response(data: Dictionary, metadata_map: Dictionary, alias_map: Dictionary = {}) -> void:
	for j in data.get("data", []):
		var card_name: String = j.get("name", "")
		var layout: String = str(j.get("layout", "normal"))
		var type_line: String = str(j.get("type_line", ""))
		var is_land := "Land" in type_line
		var cmc := 0.0 if is_land else float(j.get("cmc", 1.0))
		var mana_cost: String = str(j.get("mana_cost", "")) if not is_land else ""

		var colors: Array[String] = []
		for c in j.get("colors", []): colors.append(str(c).to_upper())

		var color_identity: Array[String] = []
		for c in j.get("color_identity", []): color_identity.append(str(c).to_upper())

		var produced_mana: Array[String] = []
		for c in j.get("produced_mana", []): produced_mana.append(str(c).to_upper())

		var oracle_text: String = str(j.get("oracle_text", ""))
		var power := str(j.get("power", "1"))
		var toughness := str(j.get("toughness", "1"))

		var img_uris: Dictionary = j.get("image_uris", {})
		var image_url: String = str(img_uris.get("normal", img_uris.get("small", "")))

		var parsed_faces: Array[Dictionary] = []
		if j.get("card_faces") is Array and not j["card_faces"].is_empty():
			for f in j["card_faces"]:
				if not (f is Dictionary): continue
				var f_uris: Dictionary = f.get("image_uris", {})
				var f_img: String = str(f_uris.get("normal", f_uris.get("small", image_url)))
				var f_colors: Array[String] = []
				for fc in f.get("colors", []): f_colors.append(str(fc).to_upper())
				parsed_faces.append({
					"name": str(f.get("name", "")),
					"mana_cost": str(f.get("mana_cost", "")),
					"type_line": str(f.get("type_line", "")),
					"oracle_text": str(f.get("oracle_text", "")),
					"power": str(f.get("power", "0")),
					"toughness": str(f.get("toughness", "0")),
					"colors": f_colors,
					"image_url": f_img,
					"image_uris": f_uris
				})

			if image_url.is_empty() and not parsed_faces.is_empty():
				image_url = parsed_faces[0]["image_url"]
			if oracle_text.is_empty() and not parsed_faces.is_empty():
				oracle_text = parsed_faces[0]["oracle_text"]
			if mana_cost.is_empty() and not parsed_faces.is_empty() and not is_land:
				mana_cost = parsed_faces[0]["mana_cost"]

		if is_land:
			var pm: Array[String] = produced_mana.duplicate()
			var ot_upper := oracle_text.to_upper()
			if pm.is_empty():
				if "{W}" in ot_upper or "PLAINS" in type_line.to_upper(): pm.append("W")
				if "{U}" in ot_upper or "ISLAND" in type_line.to_upper(): pm.append("U")
				if "{B}" in ot_upper or "SWAMP" in type_line.to_upper(): pm.append("B")
				if "{R}" in ot_upper or "MOUNTAIN" in type_line.to_upper(): pm.append("R")
				if "{G}" in ot_upper or "FOREST" in type_line.to_upper(): pm.append("G")

			if "ANY COLOR" in ot_upper or "MANA OF ANY" in ot_upper:
				pm = ["W", "U", "B", "R", "G"] as Array[String]
			elif pm.is_empty():
				pm = ["C"] as Array[String]

			produced_mana = pm

		var entry := {
			"name": card_name,
			"layout": layout,
			"type_line": type_line,
			"cmc": cmc,
			"mana_cost": mana_cost,
			"colors": colors,
			"color_identity": color_identity,
			"produced_mana": produced_mana,
			"oracle_text": oracle_text,
			"power": power,
			"toughness": toughness,
			"image_url": image_url,
			"card_faces": parsed_faces
		}
		metadata_map[card_name] = entry
		if not parsed_faces.is_empty():
			var front_name: String = parsed_faces[0]["name"]
			if not front_name.is_empty():
				metadata_map[front_name] = entry
				for orig_alias in alias_map.get(front_name, []):
					metadata_map[orig_alias] = entry
		for orig_alias in alias_map.get(card_name, []):
			metadata_map[orig_alias] = entry
