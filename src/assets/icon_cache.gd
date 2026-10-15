class_name IconCache
extends RefCounted
## Icon textures by name (e.g. "Ability_Warrior_Cleave"), decoded from the game's MPQ on first use.

const ICON_PATH := "Interface\\Icons\\%s.blp"

var _archive: MpqArchive
var _textures: Dictionary = {}  # name -> Texture2D or null when missing


func _init(archive: MpqArchive = null) -> void:
	_archive = archive


## The icon's texture, or null if there is no archive or the icon can't be read.
func get_icon(icon_name: String) -> Texture2D:
	if _archive == null or icon_name.is_empty():
		return null
	if not _textures.has(icon_name):
		_textures[icon_name] = _load(icon_name)
	return _textures[icon_name]


func _load(icon_name: String) -> Texture2D:
	var file := _archive.read_file(ICON_PATH % icon_name)
	if not file.ok:
		return null
	var image := BlpImage.decode(file.value)
	return ImageTexture.create_from_image(image.value) if image.ok else null
