extends Node
## Lightweight localisation (Portuguese / English). Missing keys fall back to
## English, then to a prettified version of the key.

const LANGS := {"pt": "Português", "en": "English"}

var _tables: Dictionary = {}

func _ready() -> void:
	_tables["en"] = LocaleData.EN
	_tables["pt"] = LocaleData.PT

func t(key: String) -> String:
	var lang: String = Settings.language if Settings else "en"
	var tbl: Dictionary = _tables.get(lang, {})
	if tbl.has(key):
		return tbl[key]
	var en: Dictionary = _tables.get("en", {})
	if en.has(key):
		return en[key]
	var last := key.get_slice(".", key.get_slice_count(".") - 1)
	return last.replace("_", " ").capitalize()

func tf(key: String, args: Array) -> String:
	return t(key) % args
