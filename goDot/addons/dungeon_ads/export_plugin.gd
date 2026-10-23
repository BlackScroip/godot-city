@tool
extends EditorPlugin

var exporter: EditorExportPlugin

func _enter_tree() -> void:
	exporter = AndroidAdsExport.new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	remove_export_plugin(exporter)
	exporter = null

class AndroidAdsExport extends EditorExportPlugin:
	func _supports_platform(platform) -> bool:
		return platform is EditorExportPlatformAndroid
	func _get_name() -> String:
		return "DungeonAds"
	func _get_android_libraries(_platform, debug) -> PackedStringArray:
		return PackedStringArray(["res://addons/dungeon_ads/bin/DungeonAds-%s.aar" % ("debug" if debug else "release")])
	func _get_android_dependencies(_platform, _debug) -> PackedStringArray:
		return PackedStringArray(["com.anythink.sdk:core-tpn:6.6.41", "com.anythink.sdk:adapter-tpn-admob:25.4.0.1.1", "com.google.android.gms:play-services-ads:25.4.0", "com.google.android.ump:user-messaging-platform:4.0.0", "androidx.appcompat:appcompat:1.6.1", "androidx.browser:browser:1.4.0"])
	func _get_android_dependencies_maven_repos(_platform, _debug) -> PackedStringArray:
		return PackedStringArray(["https://jfrog.anythinktech.com/artifactory/overseas_sdk"])
