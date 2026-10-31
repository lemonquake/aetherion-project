extends RefCounted
## (r17) Keeping the game running on weak PCs. Testers' laptops (4 GB RAM, an Intel UHD sharing it, 2020 drivers)
## crashed inside Godot's Vulkan renderer: RenderingDevice::_uniform_set_update_shared was handed a null uniform set
## (a GPU resource that could not be created), an access violation reading address 0x78. The OpenGL "Compatibility"
## renderer never runs that code, so it is the game's Safe graphics:
##   - a PC whose last session ended without the game closing (the session lock is still there) switches to Safe
##     graphics and restarts at once;
##   - on its first start a PC with under 6 GB of memory starts on Safe graphics, and one with an integrated GPU or
##     under 8 GB starts on the Low preset;
##   - Settings > Graphics > Renderer switches either way (from the next start).
## The renderer is chosen by user://graphics_mode.cfg, which project.godot's application/config/
## project_settings_override reads at startup (deleting the file goes back to Vulkan). Desktop exported builds only,
## started without command-line options (tests and tools never trip it).

const MODE_FILE := "user://graphics_mode.cfg"
const LOCK_FILE := "user://session.lock"
const STATE_FILE := "user://gfx_state.json"

## Shown once on the main menu after the game switched itself.
static var notice := ""
static var _locked := false


static func safe_on() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


static func safe_saved() -> bool:
	return FileAccess.file_exists(MODE_FILE)


static func set_safe(on: bool) -> void:
	## Safe graphics (OpenGL) from the next start, or back to the standard renderer.
	if on:
		var f := FileAccess.open(MODE_FILE, FileAccess.WRITE)
		if f:
			f.store_string("; Written by Aetherion (Settings > Graphics > Renderer). Delete it to go back to Vulkan.\n[rendering]\n\nrenderer/rendering_method=\"gl_compatibility\"\nrenderer/rendering_method.mobile=\"gl_compatibility\"\n")
	elif FileAccess.file_exists(MODE_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MODE_FILE))


static func hardware() -> Dictionary:
	## {ram_gb, gpu, integrated, weak (Low preset), very_weak (Safe graphics)}.
	var ram := float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	var gpu := RenderingServer.get_video_adapter_name()
	var integrated := RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU \
		or (gpu.contains("Intel") and (gpu.contains("UHD") or gpu.contains("HD Graphics") or gpu.contains("Iris")))
	return {"ram_gb": ram, "gpu": gpu, "integrated": integrated,
		"weak": integrated or (ram > 0.0 and ram < 7.5), "very_weak": ram > 0.0 and ram < 6.0}


static func _watching(args: Dictionary) -> bool:
	return OS.has_feature("template") and OS.has_feature("pc") and args.is_empty() and DisplayServer.get_name() != "headless"


static func _state() -> Dictionary:
	if not FileAccess.file_exists(STATE_FILE):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(STATE_FILE))
	return d if d is Dictionary else {}


static func _save_state(d: Dictionary) -> void:
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, " "))


static func boot_check(args: Dictionary, first_run: bool) -> bool:
	## Called first thing at boot. True: the game is restarting itself on Safe graphics (stop booting).
	if not _watching(args):
		return false
	var st := _state()
	var hw := hardware()
	var crashed := FileAccess.file_exists(LOCK_FILE)
	var reason := ""
	if crashed:
		st.crashes = int(st.get("crashes", 0)) + 1
		st.last_crash = Time.get_datetime_string_from_system()
		st.last_renderer = RenderingServer.get_current_rendering_method()
		print("[gfx] the last session did not close normally (%d so far); renderer %s, %s, %.1f GB" % [int(st.crashes), st.last_renderer, hw.gpu, hw.ram_gb])
		# A strong PC is switched only after two in a row (a session can also end by being killed or the power going).
		if not safe_on() and (bool(hw.weak) or int(st.crashes) >= 2):
			reason = "crash"
	elif not st.has("first_run") and bool(hw.very_weak) and not safe_on():
		reason = "weak"   # the first start of this check on this PC (a new install, or an update from before 0.18.0)
	if not st.has("first_run") and not first_run and bool(hw.weak) and str(Settings.get_value("graphics", "preset")) in ["high", "ultra"]:
		# An install from before 0.18.0 on a weak PC, still on the default High: Low, as a new install gets.
		Settings.set_value("graphics", "preset", "low")
		Settings.save_settings()
		st.low_notice = true
		print("[gfx] weak PC (%s, %.1f GB): graphics preset set to Low" % [hw.gpu, hw.ram_gb])
	st.first_run = st.get("first_run", Time.get_datetime_string_from_system())
	if reason != "" and not bool(st.get("user_chose", false)):
		st.auto_safe = reason
		st.notice = reason
		_save_state(st)
		set_safe(true)
		if crashed:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_FILE))   # this crash is counted; the restart starts clean
		print("[gfx] switching to Safe graphics (%s) and restarting" % reason)
		OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
		return true
	if safe_on() and str(st.get("notice", "")) != "":
		notice = ("Aetherion closed unexpectedly last time, so it now uses Safe graphics (OpenGL), which runs steadier on older laptops."
			if str(st.notice) == "crash" else "This PC has %.0f GB of memory, so Aetherion uses Safe graphics (OpenGL), which runs steadier on it." % hw.ram_gb) \
			+ " You can switch back in Settings > Graphics > Renderer."
		st.erase("notice")
	if bool(st.get("low_notice", false)):
		notice += (" " if notice != "" else "") + "Its graphics chip shares the PC's memory, so the graphics quality is now Low (Settings > Graphics > Quality preset)."
		st.erase("low_notice")
	_save_state(st)
	var f := FileAccess.open(LOCK_FILE, FileAccess.WRITE)
	if f:
		f.store_string(Time.get_datetime_string_from_system())
		_locked = true
	return false


static func end_session() -> void:
	## A normal exit: the next start is not a crash, and the count of crashes in a row starts again.
	if not _locked:
		return
	if FileAccess.file_exists(LOCK_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_FILE))
	var st := _state()
	if int(st.get("crashes", 0)) > 0:
		st.crashes = 0
		_save_state(st)
	_locked = false


static func user_chose(safe: bool) -> void:
	## The player picked the renderer in Settings: no automatic switch overrides it after this.
	set_safe(safe)
	var st := _state()
	st.user_chose = true
	_save_state(st)
