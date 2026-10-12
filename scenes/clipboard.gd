## Draws things offscreen and puts images on the system clipboard.
##
## Godot's DisplayServer can only put *text* on the clipboard
## (`clipboard_set`), so for an image we save a PNG to a temporary file and
## ask the operating system's own clipboard tool to copy it:
## - Linux: `wl-copy` (Wayland) or `xclip` (X11); one must be installed;
## - Windows: PowerShell;
## - macOS: `osascript` (AppleScript).
##
## GODOT CONCEPTS INTRODUCED HERE
## - SubViewport: an offscreen canvas with its own render target. Anything
##   added under it is drawn there instead of on screen, and
##   `get_texture().get_image()` reads the result back as an Image.
## - `OS.get_name()`: which platform we're running on.
## - `OS.execute()` runs a program and waits for it to finish, returning its
##   exit code. `OS.create_process()` starts one without waiting.
## - `user://`: a per-user folder for the app's own files.
##   `ProjectSettings.globalize_path()` turns it into a real path that other
##   programs understand.
class_name FSMClipboard
extends RefCounted

const TEMP_FILE := "user://clipboard.png"


## Draws `control` in an offscreen SubViewport and returns the picture.
## `size` is the picture's size in pixels; leave it at zero to use the
## control's minimum size (what a container needs to fit its contents).
## `host` must be in the scene tree: the viewport is added under it while it
## draws, then freed. `control` is freed with it.
##
## This is a coroutine: it waits one frame for the GPU to draw, so callers
## must `await` it.
static func render_control(control: Control, host: Node, size := Vector2i.ZERO,
		transparent := false) -> Image:
	var viewport := SubViewport.new()
	viewport.transparent_bg = transparent
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.add_child(control)
	host.add_child(viewport)
	# Only now, in the tree with a theme (fonts), can it measure its contents.
	if size == Vector2i.ZERO:
		size = Vector2i(control.get_combined_minimum_size().ceil())
	viewport.size = size
	control.size = Vector2(size)
	# Wait until the frame (including our offscreen viewport) has been drawn.
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


## Copies `image` to the clipboard as a PNG. Returns "" on success, or a
## message explaining why it couldn't.
static func copy_image(image: Image) -> String:
	var path := ProjectSettings.globalize_path(TEMP_FILE)
	var err := image.save_png(path)
	if err != OK:
		return "Could not save the image to %s: %s." % [path, error_string(err)]
	match OS.get_name():
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return _copy_linux(path)
		"Windows":
			return _copy_windows(path)
		"macOS":
			return _copy_macos(path)
	return "Copying images isn't supported on %s.\nThe image was saved to %s." % [
		OS.get_name(), path]


static func _copy_linux(path: String) -> String:
	# These tools stay running in the background to serve the clipboard to
	# other apps, so start them without waiting.
	if not OS.get_environment("WAYLAND_DISPLAY").is_empty() and _has_command("wl-copy"):
		# wl-copy reads the data from its standard input; let the shell redirect it.
		OS.create_process("sh", ["-c", "exec wl-copy --type image/png < " + _sh_quote(path)])
		return ""
	if _has_command("xclip"):
		OS.create_process("xclip", ["-selection", "clipboard", "-t", "image/png", "-i", path])
		return ""
	return ("Copying an image needs a clipboard tool: install xclip (X11) or "
		+ "wl-clipboard (Wayland).\nThe image was saved to %s." % path)


static func _copy_windows(path: String) -> String:
	# No PowerShell $variables here: OS.execute() would replace them itself.
	var script := ("Add-Type -AssemblyName System.Windows.Forms, System.Drawing; "
		+ "[System.Windows.Forms.Clipboard]::SetImage("
		+ "[System.Drawing.Image]::FromFile('%s'))" % path.replace("'", "''"))
	var code := OS.execute("powershell.exe",
		["-NoProfile", "-NonInteractive", "-STA", "-Command", script])
	if code != 0:
		return "PowerShell couldn't copy the image.\nIt was saved to %s." % path
	return ""


static func _copy_macos(path: String) -> String:
	var script := 'set the clipboard to (read (POSIX file "%s") as «class PNGf»)' % path
	if OS.execute("osascript", ["-e", script]) != 0:
		return "osascript couldn't copy the image.\nIt was saved to %s." % path
	return ""


## True if `command` is a program on the PATH.
static func _has_command(command: String) -> bool:
	return OS.execute("sh", ["-c", "command -v " + _sh_quote(command)]) == 0


## `text` in single quotes, safe to paste into a shell command. (We can't pass
## it as "$1" instead: OS.execute() replaces `$NAME` in arguments itself.)
static func _sh_quote(text: String) -> String:
	return "'" + text.replace("'", "'\\''") + "'"
