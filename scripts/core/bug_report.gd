class_name BugReport
extends RefCounted
## "Report a bug": opens a pre-filled GitHub issue form in the browser and
## copies the system details to the clipboard (in case the page is too long
## for a URL). Nothing is sent automatically.

const ISSUES_URL := "https://github.com/sathirapramudith123/game-develop/issues/new"


## Version, OS, hardware, graphics settings and where the logs are.
static func system_info() -> String:
	var lines := PackedStringArray([
		"Game: FPS Game %s" % NetworkManager.version_string(),
		"OS: %s %s" % [OS.get_name(), OS.get_version()],
		"CPU: %s (%d threads)" % [OS.get_processor_name(), OS.get_processor_count()],
		"RAM: %.1f GB" % (float(OS.get_memory_info().get("physical", 0)) / 1073741824.0),
		"GPU: %s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()],
		"Renderer: %s%s" % [RenderingServer.get_current_rendering_method(),
			" (Vulkan fallback)" if SettingsManager.vulkan_fallback_happened() else ""],
		"Graphics: %s, render scale %.2f, dynamic resolution %s" % [SettingsManager.graphics.display_name,
			SettingsManager.graphics.render_scale, "on" if SettingsManager.dynamic_resolution else "off"],
		"Mode: %s · %s · %s" % [GameConfig.MODE_NAMES[Match.mode], GameConfig.map_name(NetworkManager.current_map),
			["offline", "host", "dedicated", "client"][NetworkManager.mode]],
		"Logs: %s" % ProjectSettings.globalize_path("user://logs"),
	])
	return "\n".join(lines)


static func build_url() -> String:
	var info := system_info()
	return "%s?template=bug_report.yml&labels=bug&version=%s&system=%s" % [
		ISSUES_URL, NetworkManager.version_string().uri_encode(), info.uri_encode()]


static func open() -> void:
	DisplayServer.clipboard_set(system_info())
	OS.shell_open(build_url())
