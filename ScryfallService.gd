class_name ScryfallService
extends Node

const CHUNK_SIZE = 75
const API_URL = "https://api.scryfall.com/cards/collection"

func fetch_batch_metadata(card_requests: Array, callback: Callable) -> void:
	var unique_keys: Array[String] = []
	var id_by_key := {}
	var fallback_name_by_key := {}
	var alias_map := {} # query_name -> [original_requested_names]

	for raw_item in card_requests:
		var orig := ""
		var s_id := ""
		var s_set := ""
		var s_cn := ""
		if raw_item is Dictionary:
			orig = str(raw_item.get("name", "")).strip_edges()
			s_id = str(raw_item.get("scryfall_id", "")).strip_edges()
			s_set = str(raw_item.get("set", "")).strip_edges().to_lower()
			s_cn = str(raw_item.get("collector_number", "")).strip_edges()
		else:
			orig = str(raw_item).strip_edges()
		if orig.is_empty() and s_id.is_empty(): continue
		# Scryfall's /cards/collection matches front-face names reliably for "A // B" cards
		var query_name := orig.split(" // ")[0].strip_edges() if " // " in orig else orig
		if not query_name.is_empty():
			if not alias_map.has(query_name): alias_map[query_name] = []
			if not orig in alias_map[query_name]: alias_map[query_name].append(orig)

		var req_key := ""
		var ident := {}
		if not s_id.is_empty():
			req_key = "id:" + s_id
			ident = {"id": s_id}
		elif not s_set.is_empty() and not s_cn.is_empty():
			req_key = "set:" + s_set + "|" + s_cn
			ident = {"set": s_set, "collector_number": s_cn}
		else:
			req_key = "name:" + query_name
			ident = {"name": query_name}

		if not req_key in unique_keys:
			unique_keys.append(req_key)
			id_by_key[req_key] = ident
			if not query_name.is_empty():
				fallback_name_by_key[req_key] = query_name

	var metadata_map := {}
	var chunks: Array[Array] = []
	for i in range(0, unique_keys.size(), CHUNK_SIZE):
		var slice_keys := unique_keys.slice(i, i + CHUNK_SIZE)
		var chunk_idents: Array[Dictionary] = []
		for k in slice_keys:
			chunk_idents.append(id_by_key[k])
		chunks.append(chunk_idents)

	_fetch_chunks_recursive(chunks, 0, metadata_map, alias_map, fallback_name_by_key, callback)

func _fetch_chunks_recursive(chunks: Array[Array], chunk_idx: int, metadata_map: Dictionary, alias_map: Dictionary, fallback_name_by_key: Dictionary, callback: Callable) -> void:
	if chunk_idx >= chunks.size():
		callback.call(metadata_map)
		return

	var identifiers: Array = chunks[chunk_idx]

	var http := HTTPRequest.new()
	add_child(http)
	var http_id := http.get_instance_id()

	http.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		var req := instance_from_id(http_id)
		if req and is_instance_valid(req): req.queue_free()
		if response_code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var resp_dict: Dictionary = json.get_data()
				_parse_scryfall_response(resp_dict, metadata_map, alias_map)
				# Queue name-based fallback for any printing ID / set+cn not found on Scryfall
				var fb_idents: Array[Dictionary] = []
				for nf in resp_dict.get("not_found", []):
					if not (nf is Dictionary): continue
					var nf_key := ""
					if nf.has("id"): nf_key = "id:" + str(nf["id"])
					elif nf.has("set") and nf.has("collector_number"): nf_key = "set:" + str(nf["set"]).to_lower() + "|" + str(nf["collector_number"])
					if not nf_key.is_empty() and fallback_name_by_key.has(nf_key):
						var fb_name: String = str(fallback_name_by_key[nf_key])
						if not metadata_map.has(fb_name):
							fb_idents.append({"name": fb_name})
				if not fb_idents.is_empty():
					for fi in range(0, fb_idents.size(), CHUNK_SIZE):
						chunks.append(fb_idents.slice(fi, fi + CHUNK_SIZE))

		_fetch_chunks_recursive(chunks, chunk_idx + 1, metadata_map, alias_map, fallback_name_by_key, callback)
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

		var finishes: Array = j.get("finishes", [])
		var foil_only: bool = (finishes.size() == 1 and str(finishes[0]) == "foil")
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
			"card_faces": parsed_faces,
			"is_foil": foil_only
		}
		var j_id: String = str(j.get("id", "")).strip_edges()
		var j_set: String = str(j.get("set", "")).strip_edges().to_lower()
		var j_cn: String = str(j.get("collector_number", "")).strip_edges()
		if not j_id.is_empty():
			metadata_map["id:" + j_id] = entry
		if not j_set.is_empty() and not j_cn.is_empty():
			metadata_map["set:" + j_set + "|" + j_cn] = entry
		metadata_map[card_name] = entry
		if not parsed_faces.is_empty():
			var front_name: String = parsed_faces[0]["name"]
			if not front_name.is_empty():
				metadata_map[front_name] = entry
				for orig_alias in alias_map.get(front_name, []):
					metadata_map[orig_alias] = entry
		for orig_alias in alias_map.get(card_name, []):
			metadata_map[orig_alias] = entry
