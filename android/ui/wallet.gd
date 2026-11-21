extends Control

# Atom Wallet. A persistent shell (header, navigation, sheet layer and toast)
# hosts one screen at a time. Screens change with a short transition; data
# refreshes rebuild only the screen's content at its scroll position. Folded
# phones get bottom tabs and bottom sheets; unfolded screens get a side rail,
# two-column screens and centred dialogs.

const D = preload("res://design.gd")
const M = preload("res://model.gd")
const ATOM = preload("res://atom.gdshader")
const VERSION := "0.3.0"
var prefs_path := "user://prefs.cfg"
const WIDE := 600.0

var bridge: Object
var live_state := {}
var overview := {}
var history := []
var history_loaded := false
var history_total := 0
var history_limit := 30
var detail := {}
var pending := {}
var seq := 0
var refreshing := false
var refresh_again := false
var token_contract := {}
var contract_kind := "token"
var known_types := {}
var mint_amount := "1"
var label_asset := {}
var busy := false
var demo := false
var page := "welcome"
var words := PackedStringArray()
var receive_kind := "unshielded"
var preview := {}
var recipient := ""
var amount := ""
var send_kind := "unshielded"
var token_type := M.NIGHT_TYPE
var token_labels := {}
var last_tx := ""
var receipt := {}
var boot_error := ""
var proof_status := ""
var android_edges := []
var trace := {}
var trace_origin := "home"
var trace_now := 0
var trace_ticks := 0
var clocks: Array = []
var clock_timer: Timer
var explorer_url := ""
var browser_bounds: Control
var browser_location: Label
var browser_return := "explore"
var browser_requested := ""
var browser_error := ""
var chain_hash := ""
var chain_receipt := {}
var chain_origin := "explore"
var watching_hash := ""
var lookup_generation := 0
var config := {}
var config_draft := {}
var recent := []
var history_origin := "activity"
var drawer_owner := "home"
var settings_return := "home"
var activity_filter := "all"
var prefs := {"developer": false, "hide_balances": false, "haptics": true, "auto_lock": 0}
var balances_hidden := false
var phrase_revealed := false
var verify_slots := []
var restore_text := ""
var biometric := {"available": false, "enabled": false}
var biometric_opt := true
var bio_prompted := false
var preparing_error := ""
var finalized_seen := ""
var bridge_network := ""

# Shell
var frame: MarginContainer
var column: VBoxContainer
var header: MarginContainer
var stage: Control
var tabbar: PanelContainer
var tab_thumb: Panel
var tab_buttons := []
var tab_index := -1
var overlay: Control
var scrim: ColorRect
var sheet: PanelContainer
var sheet_tween: Tween
var sheet_open := false
var sheet_rest := 0.0
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var shell_key := []
var main_scroll: ScrollContainer
var main_built := ""
var scroll: ScrollContainer
var body: VBoxContainer
var feedback: Label
var status_line: Label
var phrase_grid: GridContainer
var dust_balance_label: Label
var touch := preload("res://touch_scroll.gd").new()
var animate_sheet := false

const EXPLORERS := {
	"preview": "https://explorer.preview.midnight.network/",
	"preprod": "https://explorer.preprod.midnight.network/",
	"mainnet": "https://midnightexplorer.com/",
}
const FAUCETS := {
	"preview": "https://faucet.preview.midnight.network/",
	"preprod": "https://midnight-tmnight-preprod.nethermind.dev/",
}
const CHAINS := [
	["preview", "Preview", "Test network for early development"],
	["preprod", "Preprod", "Test network that mirrors Mainnet"],
	["mainnet", "Mainnet", "Real NIGHT and DUST"],
]
const LOCAL_APP := "https://mdwa.local/"
const DRAWERS := ["send", "receive", "choose_token", "review", "preparing"]
const TABS := ["home", "activity", "explore"]
const SETTINGS_PAGES := ["settings", "network", "connections", "proving", "rescan", "remove"]
const DEPTH := {
	"welcome": 0, "unlock": 0, "restore": 1, "phrase": 1, "verify": 2, "create": 3,
	"home": 0, "activity": 0, "explore": 0, "settings": 0,
	"detail": 1, "dust": 1, "token_label": 1, "browser": 1, "chain": 2, "contracts": 2,
	"dust_review": 2, "contract_review": 3, "working": 2, "sent": 3,
	"network": 1, "connections": 2, "proving": 1, "rescan": 1, "remove": 1,
}

# ------------------------------------------------------------------ setup ---

func _ready() -> void:
	get_tree().auto_accept_quit = false
	add_child(touch)
	touch.sheet_drag = drag_sheet
	clock_timer = Timer.new()
	clock_timer.wait_time = .1
	clock_timer.timeout.connect(update_clocks)
	add_child(clock_timer)
	load_prefs()
	balances_hidden = prefs.hide_balances
	D.haptic = func(kind: String):
		if prefs.haptics: native("haptic", [kind])
	if Engine.has_singleton("WalletEngine"):
		bridge = Engine.get_singleton("WalletEngine")
		bridge.connect("message", _message)
		bridge.startEngine()
		native("setAutoLock", [int(prefs.auto_lock)])
	var backdrop := ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material_ := ShaderMaterial.new()
	material_.shader = preload("res://atmosphere.gdshader")
	backdrop.material = material_
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draw_page()

func load_prefs() -> void:
	var file := ConfigFile.new()
	if file.load(prefs_path) != OK: return
	for key in prefs: prefs[key] = file.get_value("ui", key, prefs[key])

func save_pref(key: String, value) -> void:
	prefs[key] = value
	var file := ConfigFile.new()
	file.load(prefs_path)
	file.set_value("ui", key, value)
	file.save(prefs_path)

# Calls the Android plugin, or a test double that implements the same method.
func native(method: String, args := []):
	if not bridge or demo and method in ["unlockWithBiometric"]: return null
	if Engine.has_singleton("WalletEngine") and bridge == Engine.get_singleton("WalletEngine"): return bridge.callv(method, args)
	if bridge.has_method(method): return bridge.callv(method, args)
	return null

func network() -> String:
	return str(live_state.get("network", "preview"))

func chain_name(id := "") -> String:
	if id.is_empty(): id = network()
	for c in CHAINS: if c[0] == id: return c[1]
	return id.capitalize()

func is_wide() -> bool:
	return size.x - margin("left") - margin("right") >= WIDE

func margin(side: String) -> int:
	return frame.get_theme_constant("margin_" + side) if is_instance_valid(frame) else 0

func authed() -> bool:
	return demo or (live_state.get("hasWallet", false) and not live_state.get("locked", true))

# ---------------------------------------------------------------- bridge ---

func ask(method: String, params: Dictionary, done: Callable) -> void:
	if not bridge or demo: return
	seq += 1
	pending[str(seq)] = done
	bridge.request(JSON.stringify({"id": str(seq), "method": method, "params": params}))

func command(method: String, params: Dictionary, done: Callable, progress := "Working…") -> void:
	if busy: return
	busy = true
	notice("")
	show_toast(progress, "busy")
	ask(method, params, func(reply):
		busy = false
		hide_toast_if("busy")
		if reply.has("error"):
			D.buzz("error")
			notice(reply.error.message)
		else: done.call(reply.result)
	)

func refresh_biometric() -> void:
	var raw = native("biometricStatus", [network()])
	var parsed = JSON.parse_string(str(raw)) if raw != null else null
	biometric = parsed if parsed is Dictionary else {"available": false, "enabled": false}

func _message(raw: String) -> void:
	var msg = JSON.parse_string(raw)
	if not msg is Dictionary: return
	match msg.get("type", ""):
		"transaction":
			trace = msg.trace
			trace_now = int(msg.get("at", Time.get_unix_time_from_system() * 1000))
			trace_ticks = Time.get_ticks_msec()
			if trace.get("status") == "finalized" and finalized_seen != str(trace.get("key")):
				finalized_seen = str(trace.get("key"))
				D.buzz("success")
			if page in ["working", "sent"]: redraw_at_scroll()
		"browser":
			if page == "browser":
				explorer_url = str(msg.get("url", explorer_url))
				browser_error = str(msg.get("error", ""))
				if is_instance_valid(browser_location): browser_location.text = url_label(explorer_url)
				notice(browser_error)
		"exploreAction":
			if page == "browser" and msg.get("kind") in ["token", "counter"]: open_contract(msg.kind)
		"scan":
			if msg.get("value"): use_scanned(str(msg.value))
			elif msg.get("error"): show_toast(str(msg.error))
		"biometric":
			match msg.get("event", ""):
				"password":
					if page == "unlock" and not busy:
						command("unlock", {"password": str(msg.password)}, func(_r): pass, "Unlocking…")
				"enabled":
					refresh_biometric(); D.buzz("success"); show_toast("Biometric unlock is on")
					if page == "settings": redraw_at_scroll()
				"error":
					refresh_biometric()
					if msg.get("message"): show_toast(str(msg.message))
					if page in ["settings", "unlock"]: redraw_at_scroll()
		"insets":
			android_edges = msg.edges
			D.motion = float(msg.get("motion", 1.0))
			var dp := Vector2i(msg.widthDp, msg.heightDp)
			if dp.x > 0 and dp.y > 0 and get_window().content_scale_size != dp:
				get_window().content_scale_size = dp
			_on_size_changed()
			var focus := get_viewport().gui_get_focus_owner()
			if focus is LineEdit and is_instance_valid(scroll) and scroll.is_ancestor_of(focus):
				scroll.ensure_control_visible.call_deferred(focus)
		"slow":
			if live_state.is_empty() and not demo:
				boot_error = msg.message
				draw_page()
		"closed", "fatal":
			pending.clear()
			refreshing = false
			busy = false
			live_state.clear()
			boot_error = msg.get("message", "")
			bio_prompted = false
			if demo and msg.type == "fatal": return
			wipe()
			demo = false
			go("welcome")
		"state":
			var first := live_state.is_empty()
			var had: bool = live_state.get("hasWallet", false)
			var locked: bool = live_state.get("locked", false)
			var previous_network = live_state.get("network")
			var revision = live_state.get("viewRevision", -1)
			var previous_addresses = live_state.get("addresses")
			var previous_head = live_state.get("sync", {}).get("tip")
			var previous_sync = live_state.get("sync", {}).get("status")
			live_state = msg.state
			boot_error = ""
			if demo: return
			if first or previous_network != network(): refresh_biometric()
			if first or had != live_state.hasWallet or locked != live_state.locked or previous_network != network():
				var keep_settings: bool = previous_network != network() and page in SETTINGS_PAGES and not first
				wipe()
				if live_state.hasWallet and live_state.locked: bio_prompted = false
				if keep_settings and live_state.hasWallet and not live_state.locked: go(page)
				elif live_state.hasWallet: go("unlock" if live_state.locked else "home")
				elif page == "network": draw_page()
				else: go("welcome")
				if live_state.hasWallet and not live_state.locked:
					ask("tokenLabels", {}, func(reply):
						if reply.has("result"):
							for item in reply.result:
								token_labels[item.kind + ":" + item.type] = item
							if not token_labels.is_empty() and page in ["home", "send", "choose_token", "activity"]: redraw_at_scroll()
					)
					if network() == "preview":
						ask("previewTokenContract", {"kind": "token"}, func(reply):
							var types = reply.get("result", {}).get("types") if reply.get("result") is Dictionary else null
							if types is Dictionary:
								known_types = types
								if page in ["home", "send", "choose_token"]: redraw_at_scroll()
						)
			elif page == "receive" and previous_addresses != live_state.get("addresses"):
				draw_page()
			else:
				update_header_status()
				if is_instance_valid(status_line): status_line.text = sync_text()
				if previous_sync != live_state.get("sync", {}).get("status") and page == "home": redraw_at_scroll()
			if revision != live_state.get("viewRevision", 0): refresh()
			if page == "chain" and watching_hash and previous_head != live_state.get("sync", {}).get("tip"):
				lookup_receipt(watching_hash)
			if busy and page == "review" and live_state.get("busy") is Dictionary:
				match live_state.busy.stage:
					"proving": show_toast("Proving on this device…", "busy")
					"submitting": show_toast("Submitting to Midnight…", "busy")
		_:
			var key := str(msg.get("id", ""))
			if not pending.has(key): return
			var callback: Callable = pending[key]
			pending.erase(key)
			callback.call(msg)

func wipe() -> void:
	proof_status = ""
	token_contract.clear()
	known_types.clear()
	contract_kind = "token"
	mint_amount = "1"
	label_asset.clear()
	words.clear()
	phrase_revealed = false
	verify_slots = []
	restore_text = ""
	overview = {}
	history = []
	history_loaded = false
	history_total = 0
	history_limit = 30
	preview = {}
	detail = {}
	token_labels.clear()
	recipient = ""
	amount = ""
	send_kind = "unshielded"
	receive_kind = "unshielded"
	token_type = M.NIGHT_TYPE
	last_tx = ""
	receipt.clear()
	trace = {}
	recent = []
	chain_hash = ""; chain_receipt = {}; watching_hash = ""; lookup_generation += 1
	config = {}
	config_draft = {}
	explorer_url = ""; browser_requested = ""; browser_error = ""
	drawer_owner = "home"
	balances_hidden = prefs.hide_balances
	if native_explorer(): bridge.closeExplorer()

# ------------------------------------------------------------ navigation ---

func go(target: String, transition := "auto") -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	if page in ["review", "dust_review", "contract_review"] and target != "sent" and preview.has("id") and not demo:
		ask("cancel", {"id": preview.id}, func(_reply): pass)
	if target not in ["sent", "browser", "chain"]: receipt = {}
	if target not in ["review", "dust_review", "contract_review"]: preview = {}
	if target in ["welcome", "unlock"]:
		recipient = ""; amount = ""
		send_kind = "unshielded"; token_type = M.NIGHT_TYPE
	if target in ["welcome", "unlock", "home"] and page in ["phrase", "verify", "create", "restore"]:
		words.clear()
	if target in DRAWERS and page not in DRAWERS:
		drawer_owner = page if page in TABS or page in ["dust", "detail", "settings"] else "home"
		animate_sheet = true
	if target == "settings" and page not in SETTINGS_PAGES:
		settings_return = page if page in TABS else "home"
	if page == "chain" and target != "chain":
		watching_hash = ""; lookup_generation += 1
	if page == "browser" and target != "browser" and native_explorer():
		bridge.hideExplorer()
	if target in ["connections", "proving", "network"] and not config.is_empty():
		config_draft = config.get("endpoints", {}).get(network(), {}).duplicate(true)
	if transition == "auto":
		var top := TABS + ["settings"]
		if target in DRAWERS or page in DRAWERS: transition = "none"
		elif target in top and page in top: transition = "fade"
		elif DEPTH.get(target, 1) > DEPTH.get(page, 0): transition = "push"
		elif DEPTH.get(target, 1) < DEPTH.get(page, 0): transition = "pop"
		else: transition = "fade"
	var leaving_drawer := page in DRAWERS and target not in DRAWERS
	page = target
	if leaving_drawer and target == drawer_owner and main_built == target:
		dismiss_sheet()
		draw_page("none")
	else:
		draw_page(transition)
	refresh()

func navigate(target: String) -> void:
	if not busy: go(target)

func back() -> void:
	if busy: return
	match page:
		"send", "receive", "preparing": close_drawer()
		"review": go("send")
		"choose_token": go("send")
		"network", "proving", "rescan", "remove":
			go("settings" if authed() else ("unlock" if live_state.get("hasWallet") else "welcome"))
		"connections": go("network")
		"settings": go(settings_return)
		"contracts": go("browser" if explorer_url.begins_with(LOCAL_APP) else "explore")
		"browser":
			if native_explorer() and bridge.explorerBack(): return
			go(browser_return)
		"working": go(trace_origin)
		"sent": go("home")
		"dust_review": go("dust")
		"contract_review": go("contracts")
		"detail": go(history_origin)
		"chain": go(chain_origin)
		"verify": go("phrase")
		"create": go("verify")
		"restore", "phrase": go("welcome")
		"welcome", "unlock": get_tree().quit()
		"home":
			if demo: exit_demo()
			else: get_tree().quit()
		_: go("home")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST: back()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()

# Errors stay next to the content; confirmations go to the toast.
func notice(value: String) -> void:
	if is_instance_valid(feedback):
		feedback.text = value
		feedback.get_parent().get_parent().visible = not value.is_empty()
		if not value.is_empty() and is_instance_valid(scroll) and scroll.is_ancestor_of(feedback):
			scroll.ensure_control_visible.call_deferred(feedback)

func show_toast(text: String, kind := "info") -> void:
	if not is_instance_valid(toast_panel): return
	if text.is_empty(): return
	toast_label.text = text
	toast_panel.set_meta("kind", kind)
	toast_panel.show()
	if toast_tween and toast_tween.is_valid(): toast_tween.kill()
	toast_tween = toast_panel.create_tween()
	toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.16 * D.motion)
	if kind != "busy":
		toast_tween.tween_interval(1.8)
		toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.25 * D.motion)
		toast_tween.tween_callback(toast_panel.hide)

func hide_toast_if(kind: String) -> void:
	if is_instance_valid(toast_panel) and toast_panel.get_meta("kind", "") == kind:
		if toast_tween and toast_tween.is_valid(): toast_tween.kill()
		toast_panel.hide()

func sync_text() -> String:
	if demo: return "Sample balances"
	var sync: Dictionary = live_state.get("sync", {})
	if overview.get("cachedAt") and sync.get("status") != "synced": return "Saved balance · syncing"
	match sync.get("status", "idle"):
		"synced":
			if sync.get("headsConnected", false): return "Live · block %s" % group_digits(str(int(sync.get("tip", 0))))
			return "Synced with Midnight"
		"syncing": return "Syncing · %d%%" % int(sync.get("percent", 0))
		"error": return str(sync.get("error", "Connection interrupted"))
	return str(sync.get("error") if sync.get("error") else "Connecting to " + chain_name() + "…")

func sync_tone() -> Color:
	if demo: return D.ACCENT
	match live_state.get("sync", {}).get("status", "idle"):
		"synced": return D.MINT
		"error": return D.DANGER
	return D.AMBER

func group_digits(digits: String) -> String:
	return M.units(digits, 0)

# --------------------------------------------------------------- refresh ---

func refresh() -> void:
	if demo or not bridge: return
	if page in SETTINGS_PAGES:
		if config.is_empty() and not refreshing:
			refreshing = true
			ask("settings", {}, func(reply):
				refreshing = false
				if reply.get("result") is Dictionary:
					config = reply.result
					if page in SETTINGS_PAGES:
						config_draft = config.get("endpoints", {}).get(network(), {}).duplicate(true)
						redraw_at_scroll()
				elif page == "settings": notice(reply.error.message)
				if refresh_again:
					refresh_again = false; refresh.call_deferred()
			)
		return
	if not live_state.get("hasWallet") or live_state.get("locked"): return
	if refreshing:
		refresh_again = true
		return
	if busy or page not in ["home", "dust", "activity", "send", "contracts", "detail", "choose_token", "sent", "receive"]: return
	var target := page
	var limit := history_limit
	refreshing = true
	var method: String = {"home": "walletHome", "activity": "history", "contracts": "previewTokenContract", "detail": "activityItem", "sent": "activityItem"}.get(target, "overview")
	var params := {"offset": 0, "limit": limit} if method == "history" else ({"hash": last_tx if target == "sent" else detail.get("hash", "")} if method == "activityItem" else {})
	var selected_kind := contract_kind
	if target == "sent" and last_tx.is_empty(): refreshing = false; return
	if target == "contracts": params = {"kind": selected_kind}
	ask(method, params, func(reply):
		refreshing = false
		if refresh_again:
			refresh_again = false
			refresh.call_deferred()
		if page != target or demo or busy or history_limit != limit or (target == "contracts" and selected_kind != contract_kind): return
		if reply.has("error"):
			if target in ["activity", "contracts"] or overview.is_empty(): notice(reply.error.message)
			return
		if target == "contracts":
			if token_contract != reply.result:
				token_contract = reply.result
				if token_contract.get("types") is Dictionary: known_types = token_contract.types
				redraw_at_scroll()
		elif target == "sent":
			if reply.result is Dictionary and receipt != reply.result:
				receipt = reply.result; redraw_at_scroll()
		elif target == "detail":
			if reply.result is Dictionary and reply.result.get("hash") and detail != reply.result:
				detail = reply.result; redraw_at_scroll()
		elif target == "activity":
			if not history_loaded or history != reply.result.items or history_total != int(reply.result.total):
				history_loaded = true
				history = reply.result.items; history_total = int(reply.result.total); redraw_at_scroll()
		else:
			var latest: Dictionary = reply.result.get("overview", {}) if target == "home" else reply.result
			var recent_changed := false
			if target == "home":
				recent_changed = recent != reply.result.get("recent", [])
				recent = reply.result.get("recent", [])
			if overview == latest and not recent_changed: return
			var old_tokens: Array = overview.get(send_kind, [])
			var previous := overview
			overview = latest
			if not recent_changed and target in ["home", "dust"] and only_dust_balance_changed(previous, overview) and is_instance_valid(dust_balance_label):
				dust_balance_label.text = money(short_dust() + " DUST") if target == "home" else money(M.units(overview.dust.balance, 15))
			elif target not in ["send", "receive"] or old_tokens != overview.get(send_kind, []):
				redraw_at_scroll()
	)

func only_dust_balance_changed(previous: Dictionary, current: Dictionary) -> bool:
	if previous.is_empty(): return false
	var expected := previous.duplicate()
	var dust: Dictionary = previous.dust.duplicate()
	dust.balance = current.dust.balance
	dust.updating = current.dust.get("updating", false)
	expected.dust = dust
	return expected == current

func short_dust() -> String:
	var amount_text := M.units(overview.dust.balance, 15)
	var point := amount_text.find(".")
	if point < 0 or amount_text.length() <= point + 5: return amount_text
	if amount_text.begins_with("0.0000"): return "<0.0001"
	return amount_text.left(point + 5).rstrip("0").trim_suffix(".")

func money(text: String) -> String:
	return "••••••" if balances_hidden else text

func redraw_at_scroll() -> void:
	var offset := scroll.scroll_vertical if is_instance_valid(scroll) else 0
	draw_page("none")
	if is_instance_valid(scroll): scroll.set_deferred("scroll_vertical", offset)

func enter_demo() -> void:
	if busy: return
	demo = true
	wipe()
	overview = M.SAMPLE.duplicate(true)
	history = M.HISTORY.duplicate(true)
	recent = history.slice(0, 3)
	history_total = history.size()
	history_loaded = true
	go("home", "push")

func exit_demo() -> void:
	demo = false
	wipe()
	go("unlock" if live_state.get("hasWallet") else "welcome", "pop")

# ----------------------------------------------------------------- shell ---

func show_nav() -> bool:
	var drawer := page in DRAWERS
	var main_page := drawer_owner if drawer else page
	if not authed(): return false
	if is_wide(): return main_page not in ["working", "sent"]
	return main_page in TABS or main_page == "settings"

func ensure_shell() -> void:
	var key := [is_wide(), authed(), show_nav()]
	if key == shell_key and is_instance_valid(frame): return
	shell_key = key
	if is_instance_valid(frame):
		remove_child(frame); frame.queue_free()
	main_scroll = null; main_built = ""; sheet = null; sheet_open = false
	frame = MarginContainer.new()
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	update_insets()
	tabbar = null; tab_index = -1; tab_buttons = []
	var layout := D.row(frame, 0)
	if key[0] and key[2]: build_rail(layout)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	layout.add_child(center)
	column = D.vbox(center, 0)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	header = D.inset(column, 18, 8, 4)
	stage = Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(stage)
	if not key[0] and key[2]: build_tabbar(D.inset(column, 14, 6, 10))
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(overlay)
	scrim = ColorRect.new()
	scrim.color = Color(0.02, 0.02, 0.05, 0.66)
	scrim.hide()
	overlay.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e): if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed: close_drawer())
	toast_panel = PanelContainer.new()
	var tb := D.style(Color("#f2f0fa"), 16)
	tb.content_margin_left = 16; tb.content_margin_right = 16; tb.content_margin_top = 10; tb.content_margin_bottom = 10
	toast_panel.add_theme_stylebox_override("panel", tb)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.modulate.a = 0
	toast_panel.hide()
	overlay.add_child(toast_panel)
	toast_label = D.label(toast_panel, "", 13, D.ON_ACCENT, 650)
	toast_panel.anchor_left = 0.5; toast_panel.anchor_right = 0.5; toast_panel.anchor_top = 1; toast_panel.anchor_bottom = 1
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast_panel.offset_bottom = -88 if (key[2] and not key[0]) else -24
	resize_column()

func resize_column() -> void:
	if not is_instance_valid(column): return
	var rail := 92 if shell_key.size() and shell_key[0] and shell_key[2] else 0
	var available := size.x - margin("left") - margin("right") - rail
	column.custom_minimum_size.x = minf(maxf(100, available), 1080.0 if is_wide() else 560.0)
	if is_instance_valid(header):
		header.visible = size.y - margin("top") - margin("bottom") >= 240

func build_rail(parent: Control) -> void:
	var rail := D.panel(parent, Color(0.08, 0.075, 0.13, 0.85), 0, Color.TRANSPARENT)
	rail.custom_minimum_size.x = 92
	var v := D.vbox(D.inset(rail, 10, 16), 6)
	var logo := CenterContainer.new()
	logo.custom_minimum_size.y = 52
	v.add_child(logo)
	D.icon(logo, "atom", D.ACCENT, 30)
	for item in [["home", "Wallet", "wallet"], ["activity", "Activity", "activity"], ["explore", "Explore", "explore"]]:
		rail_item(v, item)
	D.space(v, 0, true)
	rail_item(v, ["settings", "Settings", "gear"])

func rail_item(parent: Control, item: Array) -> void:
	var b := Button.new()
	b.accessibility_name = item[1]
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(72, 64)
	b.set_meta("tab", item[0])
	for s in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	parent.add_child(b)
	var v := D.vbox(b, 3)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pillbox := PanelContainer.new()
	pillbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pillbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pillbox.custom_minimum_size = Vector2(56, 32)
	v.add_child(pillbox)
	var c := CenterContainer.new(); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; pillbox.add_child(c)
	D.icon(c, item[2], D.MUTED, 21)
	var l := D.label(v, item[1], 11, D.MUTED, 620)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func(): D.buzz("tick"); navigate(item[0]))
	b.set_meta("parts", [pillbox, c.get_child(0), l])
	tab_buttons.append(b)

func build_tabbar(parent: Control) -> void:
	tabbar = D.panel(parent, Color(0.09, 0.085, 0.15, 0.94), 26, D.LINE)
	var holder := Control.new()
	holder.custom_minimum_size.y = 58
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	tabbar.add_child(holder)
	tab_thumb = Panel.new()
	tab_thumb.add_theme_stylebox_override("panel", D.style(D.ACCENT, 21))
	tab_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tab_thumb)
	var h := D.row(holder, 0)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for item in [["home", "Wallet", "wallet"], ["activity", "Activity", "activity"], ["explore", "Explore", "explore"]]:
		var b := Button.new()
		b.accessibility_name = item[1]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("tab", item[0])
		for s in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
		h.add_child(b)
		var v := D.vbox(b, 2)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var c := CenterContainer.new(); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(c)
		var glyph = D.icon(c, item[2], D.MUTED, 21)
		var l := D.label(v, item[1], 11, D.MUTED, 640)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(func(): D.buzz("tick"); navigate(item[0]))
		b.set_meta("parts", [null, glyph, l])
		tab_buttons.append(b)
	h.resized.connect(func(): place_tab_thumb(false))

func selected_tab() -> String:
	var main_page: String = drawer_owner if page in DRAWERS else page
	if main_page in SETTINGS_PAGES: return "settings"
	return {"contracts": "explore", "browser": "explore", "chain": "explore", "dust": "home", "dust_review": "home", "token_label": "home", "detail": history_origin, "working": trace_origin, "sent": "home"}.get(main_page, main_page)

func place_tab_thumb(animated: bool) -> void:
	if not is_instance_valid(tabbar) or tab_buttons.is_empty(): return
	var index := tab_buttons.find_custom(func(b): return b.get_meta("tab") == selected_tab())
	tab_thumb.visible = index >= 0
	if index < 0: tab_index = -1; return
	var r: Rect2 = tab_buttons[index].get_rect().grow(-5)
	if animated and tab_index >= 0 and tab_index != index and D.motion > 0:
		var tw := tab_thumb.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(tab_thumb, "position", r.position, 0.3 * D.motion)
		tw.tween_property(tab_thumb, "size", r.size, 0.3 * D.motion)
	else:
		tab_thumb.position = r.position; tab_thumb.size = r.size
	tab_index = index

func update_nav() -> void:
	var selected := selected_tab()
	for b in tab_buttons:
		var on: bool = b.get_meta("tab") == selected
		var parts: Array = b.get_meta("parts")
		var ink: Color
		if is_instance_valid(tabbar): ink = D.ON_ACCENT if on else D.MUTED
		else: ink = D.ACCENT if on else D.MUTED
		if parts[0]: parts[0].add_theme_stylebox_override("panel", D.style(D.ACCENT_SOFT, 16) if on else StyleBoxEmpty.new())
		parts[1].ink = ink; parts[1].queue_redraw()
		parts[2].add_theme_color_override("font_color", D.INK if on and not is_instance_valid(tabbar) else ink)
		b.disabled = busy
	if is_instance_valid(tabbar):
		if tabbar.get_parent().is_inside_tree(): place_tab_thumb.call_deferred(true)

func build_header() -> void:
	for child in header.get_children(): header.remove_child(child); child.queue_free()
	var top := D.row(header, 8)
	top.custom_minimum_size.y = 48
	var rail: bool = shell_key.size() > 0 and shell_key[0] and shell_key[2]
	if not rail:
		D.icon(top, "atom", D.ACCENT, 26)
		if column.custom_minimum_size.x >= 352 or not authed():
			var name_ := D.label(top, "Atom", 20, D.INK, 720)
			name_.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip := network_chip(top)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	D.space(top, 0, true)
	if authed() and page not in ["working", "sent"]:
		var eye := D.button(top, "Show balances" if balances_hidden else "Hide balances", func():
			balances_hidden = not balances_hidden; redraw_at_scroll(), "ghost", "eyeoff" if balances_hidden else "eye", true)
		eye.size_flags_horizontal = Control.SIZE_SHRINK_END
		if not rail:
			var gear := D.button(top, "Settings", func(): navigate("settings"), "ghost", "gear", true)
			gear.size_flags_horizontal = Control.SIZE_SHRINK_END
			gear.disabled = busy

func network_chip(parent: Control) -> Button:
	var b := Button.new()
	b.accessibility_name = "Chain"
	b.focus_mode = Control.FOCUS_NONE
	var box := D.style(Color(1, 1, 1, 0.05), 99, D.LINE)
	box.content_margin_left = 10; box.content_margin_right = 10
	box.expand_margin_top = -8; box.expand_margin_bottom = -8
	for s in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(s, box)
	b.custom_minimum_size.y = 48
	parent.add_child(b)
	var h := D.row(b, 6)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", D.style(sync_tone(), 4))
	dot.name = "Dot"
	h.add_child(dot)
	D.label(h, "Demo" if demo else chain_name(), 12, D.MUTED, 620)
	b.custom_minimum_size.x = h.get_combined_minimum_size().x + 22
	b.disabled = demo or busy or page in ["working", "sent"]
	b.pressed.connect(func(): D.buzz("tick"); navigate("network"))
	return b

func update_header_status() -> void:
	if not is_instance_valid(header): return
	for dot in header.find_children("Dot", "Panel", true, false):
		dot.add_theme_stylebox_override("panel", D.style(sync_tone(), 4))

# ------------------------------------------------------------ page build ---

func draw_page(transition := "none") -> void:
	clocks.clear()
	clock_timer.stop()
	status_line = null; phrase_grid = null; dust_balance_label = null
	browser_bounds = null; browser_location = null
	ensure_shell()
	build_header()
	update_nav()
	var drawer := page in DRAWERS
	var main_page: String = drawer_owner if drawer else page
	if not (drawer and main_built == main_page and is_instance_valid(main_scroll)):
		build_main(main_page, transition)
	elif drawer:
		body = main_scroll.get_child(0).get_child(0)
	if drawer: build_sheet()
	elif is_instance_valid(sheet) and sheet_open: dismiss_sheet()
	feedback_slot()
	touch.area = scroll
	if page == "browser" and browser_error: notice(browser_error)
	if not clocks.is_empty(): update_clocks(); clock_timer.start()

func feedback_slot() -> void:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", D.style(D.DANGER_SOFT, 14))
	holder.hide()
	body.add_child(holder)
	var row := D.row(D.inset(holder, 14, 11), 10)
	D.icon(row, "info", D.DANGER, 18)
	feedback = D.label(row, "", 14, D.DANGER, 560, true)
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback.get_parent().get_parent().visible = false

func make_scroll(parent: Control) -> ScrollContainer:
	var view := ScrollContainer.new()
	view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	view.follow_focus = true
	parent.add_child(view)
	return view

func page_body(view: ScrollContainer, x := -1) -> VBoxContainer:
	var narrow := is_instance_valid(column) and column.custom_minimum_size.x < 352
	if x < 0: x = 28 if is_wide() else (14 if narrow else 18)
	elif narrow: x = mini(x, 16)
	var margin_ := D.inset(view, x, 8, 28)
	margin_.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return D.vbox(margin_, 12)

func build_main(main_page: String, transition: String) -> void:
	var old := main_scroll
	main_scroll = make_scroll(stage)
	main_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body = page_body(main_scroll)
	main_built = main_page
	scroll = main_scroll
	match main_page:
		"welcome", "unlock": welcome()
		"phrase": phrase_page()
		"verify": verify_page()
		"create", "restore": password_page()
		"home": home()
		"dust", "dust_review": dust_page()
		"activity": activity_page()
		"detail": detail_page()
		"chain": chain_page()
		"working", "sent": progress_page()
		"explore": explore_page()
		"browser": browser_page(stage)
		"contracts", "contract_review": contracts_page()
		"token_label": label_page()
		"settings": settings_page()
		"network": network_page()
		"connections": connections_page()
		"proving": proving_page()
		"rescan": rescan_page()
		"remove": remove_page()
	if is_instance_valid(old):
		old.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if transition == "none" or D.motion <= 0:
			old.queue_free()
		else:
			var dx: float = {"push": -24.0, "pop": 24.0}.get(transition, 0.0)
			var tw := old.create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(old, "modulate:a", 0.0, 0.12 * D.motion)
			tw.tween_method(shift.bind(old, 0.0), 0.0, dx, 0.12 * D.motion)
			tw.chain().tween_callback(old.queue_free)
	if transition != "none" and D.motion > 0:
		var from: float = {"push": 28.0, "pop": -28.0}.get(transition, 0.0)
		var rise := 8.0 if transition == "fade" else 0.0
		main_scroll.modulate.a = 0.0
		shift(from, main_scroll, rise)
		var tw := main_scroll.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_interval(0.06 * D.motion)
		tw.chain()
		tw.set_parallel(true)
		tw.tween_property(main_scroll, "modulate:a", 1.0, 0.22 * D.motion)
		var entering := main_scroll
		tw.tween_method(func(t: float): shift(from * (1.0 - t), entering, rise * (1.0 - t)), 0.0, 1.0, 0.26 * D.motion)

# Moves a full-rect page by shifting its anchor offsets, so it keeps tracking
# the stage's size while it animates.
func shift(x: float, page_: Control, y := 0.0) -> void:
	if not is_instance_valid(page_): return
	page_.offset_left = x; page_.offset_right = x
	page_.offset_top = y; page_.offset_bottom = y

# ----------------------------------------------------------------- sheet ---

func build_sheet() -> void:
	var wide := is_wide()
	var first := not sheet_open or not is_instance_valid(sheet)
	if first:
		if is_instance_valid(sheet): sheet.queue_free()
		sheet = PanelContainer.new()
		var radius := 28
		var box := D.style(D.SHEET, radius, Color(1, 1, 1, 0.08))
		if not wide:
			box.corner_radius_bottom_left = 0; box.corner_radius_bottom_right = 0
			box.border_width_bottom = 0
		box.shadow_color = Color(0, 0, 0, 0.45); box.shadow_size = 24
		sheet.add_theme_stylebox_override("panel", box)
		sheet.mouse_filter = Control.MOUSE_FILTER_STOP
		overlay.add_child(sheet)
		overlay.move_child(toast_panel, -1)
		scrim.show()
	for child in sheet.get_children(): sheet.remove_child(child); child.queue_free()
	var v := D.vbox(sheet, 0)
	var handle := CenterContainer.new()
	handle.custom_minimum_size.y = 22 if not wide else 10
	handle.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(handle)
	if not wide:
		var grab := Panel.new()
		grab.custom_minimum_size = Vector2(38, 5)
		grab.add_theme_stylebox_override("panel", D.style(Color(1, 1, 1, 0.22), 3))
		grab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		handle.add_child(grab)
	touch.sheet_handle = handle
	var sheet_scroll := make_scroll(v)
	sheet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body = page_body(sheet_scroll, 22)
	scroll = sheet_scroll
	touch.sheet_area = sheet_scroll
	match page:
		"receive": receive_page()
		"preparing": preparing_page()
		_: send_page()
	sheet_open = true
	var contents: Control = body.get_parent()
	contents.minimum_size_changed.connect(fit_sheet.call_deferred)
	if not overlay.resized.is_connected(fit_sheet): overlay.resized.connect(fit_sheet)
	if first:
		animate_sheet = true
	else:
		contents.modulate.a = 0.0
		contents.create_tween().tween_property(contents, "modulate:a", 1.0, 0.16 * maxf(D.motion, 0.01))
	fit_sheet.call_deferred()

func fit_sheet() -> void:
	if not is_instance_valid(sheet) or not sheet.is_inside_tree() or not sheet_open: return
	var area := overlay.size
	if area.y < 10: return
	var contents: Control = scroll.get_child(0) if is_instance_valid(scroll) and scroll.get_child_count() else null
	var want := (contents.get_combined_minimum_size().y if contents else 300.0) + (22 if not is_wide() else 10) + 4
	if is_wide():
		var w := minf(480.0, area.x - 48)
		var h := minf(want, area.y - 48)
		sheet.size = Vector2(w, h)
		sheet_rest = (area.y - h) * 0.5
		sheet.position = Vector2((area.x - w) * 0.5, sheet.position.y if not animate_sheet else sheet_rest)
		if not animate_sheet and not (sheet_tween and sheet_tween.is_running()): sheet.position.y = sheet_rest
		sheet.pivot_offset = sheet.size * 0.5
	else:
		var h := minf(want, area.y * 0.92)
		sheet.size = Vector2(area.x, h)
		sheet_rest = area.y - h
		sheet.position.x = 0
		if not animate_sheet and not (sheet_tween and sheet_tween.is_running()): sheet.position.y = sheet_rest
	if animate_sheet:
		animate_sheet = false
		if sheet_tween and sheet_tween.is_valid(): sheet_tween.kill()
		scrim.modulate.a = 0
		sheet_tween = create_tween().set_parallel(true)
		if is_wide():
			sheet.position.y = sheet_rest
			sheet.scale = Vector2.ONE * 0.94
			sheet.modulate.a = 0
			sheet_tween.tween_property(sheet, "scale", Vector2.ONE, 0.24 * D.motion).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			sheet_tween.tween_property(sheet, "modulate:a", 1.0, 0.18 * D.motion)
		else:
			sheet.position.y = area.y
			sheet_tween.tween_property(sheet, "position:y", sheet_rest, 0.34 * D.motion).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		sheet_tween.tween_property(scrim, "modulate:a", 1.0, 0.22 * D.motion)
		sheet_tween.chain().tween_callback(fit_sheet)
		if D.motion <= 0: sheet_tween.kill(); sheet.position.y = sheet_rest; scrim.modulate.a = 1; sheet.modulate.a = 1; sheet.scale = Vector2.ONE

func drag_sheet(dy: float, phase: String, velocity: float) -> void:
	if not is_instance_valid(sheet) or not sheet_open or is_wide() or busy: return
	if phase == "move":
		if sheet_tween and sheet_tween.is_valid(): sheet_tween.kill()
		sheet.position.y = sheet_rest + maxf(0.0, dy)
		scrim.modulate.a = clampf(1.0 - maxf(0.0, dy) / maxf(1.0, sheet.size.y), 0.0, 1.0)
	elif dy > sheet.size.y * 0.3 or velocity > 900:
		close_drawer()
	else:
		sheet_tween = create_tween().set_parallel(true)
		sheet_tween.tween_property(sheet, "position:y", sheet_rest, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		sheet_tween.tween_property(scrim, "modulate:a", 1.0, 0.18)

func close_drawer() -> void:
	if busy: return
	if page not in DRAWERS: return
	go(drawer_owner)

func dismiss_sheet() -> void:
	sheet_open = false
	touch.sheet_area = null
	touch.sheet_handle = null
	if not is_instance_valid(sheet): scrim.hide(); return
	var old := sheet
	sheet = null
	if sheet_tween and sheet_tween.is_valid(): sheet_tween.kill()
	sheet_tween = create_tween().set_parallel(true)
	if is_wide():
		sheet_tween.tween_property(old, "modulate:a", 0.0, 0.14 * D.motion)
		sheet_tween.tween_property(old, "scale", Vector2.ONE * 0.96, 0.14 * D.motion)
	else:
		sheet_tween.tween_property(old, "position:y", overlay.size.y, 0.2 * D.motion).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	sheet_tween.tween_property(scrim, "modulate:a", 0.0, 0.2 * D.motion)
	sheet_tween.chain().tween_callback(func():
		old.queue_free()
		if not sheet_open: scrim.hide()
	)
	if D.motion <= 0: sheet_tween.kill(); old.queue_free(); scrim.hide()

func _on_size_changed() -> void:
	if not is_instance_valid(frame): return
	update_insets()
	if shell_key.size() and shell_key[0] != is_wide():
		var offset := scroll.scroll_vertical if is_instance_valid(scroll) else 0
		draw_page("none")
		if is_instance_valid(scroll): scroll.set_deferred("scroll_vertical", offset)
		return
	resize_column()
	if is_instance_valid(phrase_grid):
		phrase_grid.columns = phrase_columns()
	fit_sheet.call_deferred()
	place_tab_thumb.call_deferred(false)

func update_insets() -> void:
	var margins := [0, 0, 0, 0]
	var scale_factor := get_viewport().get_screen_transform().get_scale()
	if android_edges.size() == 4:
		margins = [ceili(android_edges[0] / scale_factor.x), ceili(android_edges[1] / scale_factor.y), ceili(android_edges[2] / scale_factor.x), ceili(android_edges[3] / scale_factor.y)]
	elif OS.get_name() == "Android":
		var safe := DisplayServer.get_display_safe_area()
		var win := DisplayServer.window_get_size()
		var origin := DisplayServer.window_get_position()
		if win.x > 0 and safe.size.x > 0:
			margins = [maxi(0, roundi((safe.position.x - origin.x) / scale_factor.x)), maxi(0, roundi((safe.position.y - origin.y) / scale_factor.y)), maxi(0, roundi((win.x + origin.x - safe.end.x) / scale_factor.x)), maxi(0, roundi((win.y + origin.y - safe.end.y) / scale_factor.y))]
	for i in 4: frame.add_theme_constant_override("margin_" + ["left", "top", "right", "bottom"][i], margins[i])

# --------------------------------------------------------------- helpers ---

func heading(title: String, subtitle := "", back_button := false) -> void:
	var h := D.row(body, 6)
	if back_button and page not in DRAWERS:
		D.button(h, "Back", back, "ghost", "back", true).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var t := D.label(h, title, 26 if not back_button else 22, D.INK, 720, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if page in DRAWERS:
		var closing := page in ["send", "receive", "preparing"]
		D.button(h, "Close" if closing else "Back", back, "ghost", "close" if closing else "back", true).size_flags_horizontal = Control.SIZE_SHRINK_END
	if subtitle: D.label(body, subtitle, 14, D.MUTED, 480, true)

func columns(parent: Control, count := 2) -> Array:
	var h := D.row(parent, 20)
	var out := []
	for i in count:
		var v := D.vbox(h, 12)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out.append(v)
	return out

func artwork(parent: Control, height: int, centered := false, card := true) -> ColorRect:
	var art := ColorRect.new()
	art.custom_minimum_size.y = height
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = ATOM
	mat.set_shader_parameter("centered", float(centered))
	mat.set_shader_parameter("card", float(card))
	mat.set_shader_parameter("motion", D.motion)
	art.material = mat
	parent.add_child(art)
	art.resized.connect(func(): mat.set_shader_parameter("canvas_size", art.size))
	return art

func kv(parent: Control, key: String, value: String, mono := false) -> Label:
	var h := D.row(parent, 12)
	h.custom_minimum_size.y = 40
	var k := D.label(h, key, 14, D.MUTED, 500)
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := D.label(h, value, 13 if mono else 14, D.INK, 600, true)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return v

func has_any(text: String, chars: String) -> bool:
	for c in chars: if text.contains(c): return true
	return false

func middle(text: String, keep := 10) -> String:
	return text if text.length() <= keep * 2 + 1 else text.left(keep) + "…" + text.right(keep)

func copy(text: String, what := "Copied") -> void:
	DisplayServer.clipboard_set(text)
	D.buzz("confirm")
	show_toast(what)

func share(text: String) -> void:
	if bridge and (Engine.has_singleton("WalletEngine") or bridge.has_method("share")): native("share", [text])
	else: copy(text, "Copied to share")

# --------------------------------------------------------- onboarding ---

func welcome() -> void:
	var locked := page == "unlock"
	var wide := is_wide()
	var parent: Control = body
	if wide:
		var cols := columns(body)
		artwork(cols[0], int(maxf(360, size.y * 0.62)), true, false)
		parent = cols[1]
		cols[1].alignment = BoxContainer.ALIGNMENT_CENTER
	else:
		artwork(body, int(clampf(size.y * 0.36, 220, 340)), true, false)
	var title := D.label(parent, "Welcome back" if locked else "Atom Wallet", 32, D.INK, 740, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	D.label(parent, ("Unlock your %s wallet." % chain_name()) if locked else "A private wallet for Midnight. Your keys and proofs stay on this phone.", 15, D.MUTED, 480, true)
	D.space(parent, 4)
	if locked:
		if biometric.get("enabled"):
			D.button(parent, "Unlock with biometrics", biometric_unlock, "primary", "finger")
			if not bio_prompted:
				bio_prompted = true
				biometric_unlock.call_deferred()
		var pw := D.field(parent, "Wallet password", true)
		var submit := func():
			if pw.text.is_empty(): notice("Enter your password."); return
			command("unlock", {"password": pw.text}, func(_result): pass, "Unlocking…")
		D.button(parent, "Unlock", submit, "secondary" if biometric.get("enabled") else "primary", "lock")
		pw.text_submitted.connect(func(_s): submit.call())
		var other := D.row(parent, 8)
		D.chip(other, chain_name() + " · switch chain", func(): navigate("network"), false, "chain")
		return
	var ready := not live_state.is_empty()
	if not bridge:
		D.label(parent, "Run Atom Wallet on Android to create or restore a wallet.", 14, D.MUTED, 480, true)
	elif not ready:
		var r := D.row(parent, 12)
		if boot_error:
			D.icon(r, "info", D.AMBER, 20)
			D.label(r, boot_error, 14, D.MUTED, 500, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			D.button(parent, "Retry", func(): boot_error = ""; draw_page(); bridge.retryEngine(), "secondary", "refresh")
		else:
			var ring := D.Ring.new(26)
			ring.spinning = true
			ring.width = 3
			r.add_child(ring)
			D.label(r, "Starting the secure engine…", 14, D.MUTED, 520)
	else:
		D.button(parent, "Create a new wallet", func():
			command("generateMnemonic", {}, func(result):
				words = PackedStringArray(result.words)
				phrase_revealed = false
				verify_slots = []
				go("phrase")
			, "Generating your phrase…")
		, "primary", "plus")
		D.button(parent, "I already have a wallet", func(): restore_text = ""; go("restore"), "secondary", "key")
		var other := D.row(parent, 8)
		D.chip(other, chain_name(), func(): navigate("network"), false, "chain")
	D.button(parent, "Try the demo", enter_demo, "ghost", "next")

func biometric_unlock() -> void:
	if busy or page != "unlock": return
	native("unlockWithBiometric", [network()])

func step_label(n: int) -> void:
	D.label(body, "Step %d of 3" % n, 12, D.ACCENT, 640)

func phrase_columns() -> int:
	var w := column.custom_minimum_size.x if is_instance_valid(column) else 360.0
	return 4 if w >= 640 else (3 if w >= 360 else 2)

func phrase_page() -> void:
	step_label(1)
	heading("Your recovery phrase", "These %d words are the only way to restore this wallet. Write them down in order and keep them offline." % words.size(), true)
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.add_child(holder)
	var g := GridContainer.new()
	phrase_grid = g
	g.columns = phrase_columns()
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	holder.add_child(g)
	for i in words.size():
		var cell := D.panel(g, D.SURFACE, 14)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := D.row(D.inset(cell, 12, 10), 8)
		D.label(h, "%d" % (i + 1), 12, D.DIM, 600).custom_minimum_size.x = 18
		D.label(h, words[i] if phrase_revealed else "••••••", 15, D.INK, 600)
	if not phrase_revealed:
		var cover := Button.new()
		cover.accessibility_name = "Reveal phrase"
		cover.focus_mode = Control.FOCUS_NONE
		cover.add_theme_stylebox_override("normal", D.style(Color(0.08, 0.075, 0.13, 0.9), 18, Color(D.ACCENT, 0.4)))
		cover.add_theme_stylebox_override("hover", D.style(Color(0.08, 0.075, 0.13, 0.9), 18, Color(D.ACCENT, 0.4)))
		cover.add_theme_stylebox_override("pressed", D.style(Color(0.1, 0.09, 0.16, 0.92), 18, D.ACCENT))
		cover.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		holder.add_child(cover)
		var v := D.vbox(cover, 6)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var c := CenterContainer.new(); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(c)
		D.icon(c, "eye", D.ACCENT, 28)
		D.label(v, "Tap to reveal", 16, D.INK, 660).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		D.label(v, "Make sure no one can see your screen", 13, D.MUTED, 500).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cover.pressed.connect(func(): D.buzz("confirm"); phrase_revealed = true; redraw_at_scroll())
	var warn := D.panel(body, Color(D.AMBER, 0.08), 16, Color.TRANSPARENT)
	var wr := D.row(D.inset(warn, 14, 12), 10)
	D.icon(wr, "shield", D.AMBER, 20)
	D.label(wr, "Atom Wallet never sees or stores this phrase. Anyone who has it controls your funds.", 13, D.MUTED, 500, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var next := D.button(body, "I've written it down", func():
		verify_slots = []
		go("verify"), "primary", "check")
	next.disabled = not phrase_revealed

func verify_page() -> void:
	step_label(2)
	heading("Confirm your phrase", "Choose the right word for each position.", true)
	if verify_slots.is_empty():
		var picks := range(words.size())
		picks.shuffle()
		picks = picks.slice(0, 3)
		picks.sort()
		for index in picks:
			var options := [words[index]]
			var pool := Array(words)
			pool.shuffle()
			for w in pool:
				if options.size() >= 4: break
				if w not in options: options.append(w)
			if options.size() < 4:
				var extra := M.wordlist()
				extra.shuffle()
				for w in extra:
					if options.size() >= 4: break
					if w not in options: options.append(w)
			options.shuffle()
			verify_slots.append({"index": index, "options": options, "picked": ""})
	var all := true
	for slot in verify_slots:
		var card := D.card(body, D.SURFACE, 16, 14, 10)
		D.label(card, "Word %d" % (slot.index + 1), 14, D.MUTED, 600)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 4)
		card.add_child(flow)
		var right: String = words[slot.index]
		if slot.picked != right: all = false
		for option in slot.options:
			D.chip(flow, option, func():
				if option == right:
					slot.picked = option
					D.buzz("confirm")
				else:
					slot.picked = ""
					D.buzz("error")
					show_toast("That's not word %d" % (slot.index + 1))
				redraw_at_scroll()
			, slot.picked == option, "check" if slot.picked == option else "")
	var next := D.button(body, "Continue", func(): go("create"), "primary", "next")
	next.disabled = not all

func password_page() -> void:
	var restore := page == "restore"
	if not restore: step_label(3)
	heading("Restore a wallet" if restore else "Set a password", ("Enter your 12 or 24 words for %s." % chain_name()) if restore else "Your password unlocks this wallet on this phone.", true)
	var phrase: LineEdit
	if restore:
		D.caption(body, "Recovery phrase")
		phrase = D.field(body, "Words in order, separated by spaces")
		phrase.text = restore_text
		phrase.context_menu_enabled = true
		var info := D.row(body, 8)
		var count := D.label(info, "", 12, D.MUTED, 560)
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var paste := D.chip(info, "Paste", func():
			var text := DisplayServer.clipboard_get().strip_edges().to_lower()
			if text: phrase.text = text; phrase.text_changed.emit(text); phrase.caret_column = text.length()
		, false, "copy")
		paste.size_flags_horizontal = Control.SIZE_SHRINK_END
		var suggestions := HFlowContainer.new()
		suggestions.add_theme_constant_override("h_separation", 8)
		body.add_child(suggestions)
		var update := func(text: String):
			restore_text = text
			var parts := Array(text.strip_edges().to_lower().split(" ", false))
			var bad: Array = parts.filter(func(w): return not M.is_word(w))
			var partial: String = "" if text.ends_with(" ") or parts.is_empty() else parts[-1]
			if not partial.is_empty() and M.is_word(partial): bad.erase(partial)
			if not partial.is_empty(): bad.erase(partial)
			count.text = "%d words" % parts.size() + ("" if bad.is_empty() else " · check “%s”" % bad[0])
			count.add_theme_color_override("font_color", D.DANGER if not bad.is_empty() else D.MUTED)
			for c in suggestions.get_children(): c.queue_free()
			if partial.length() >= 2:
				for w in M.complete(partial, 4):
					D.chip(suggestions, w, func():
						var head := phrase.text.strip_edges()
						head = head.left(head.length() - partial.length())
						phrase.text = head + w + " "
						phrase.caret_column = phrase.text.length()
						phrase.text_changed.emit(phrase.text)
						phrase.grab_focus()
					)
		phrase.text_changed.connect(update)
		update.call(phrase.text)
	D.caption(body, "Password")
	var pw := D.field(body, "At least 8 characters", true)
	var confirm := D.field(body, "Confirm password", true)
	var strength := D.label(body, "", 12, D.MUTED, 560)
	pw.text_changed.connect(func(v: String):
		var score := int(v.length() >= 8) + int(v.length() >= 12) + int(v.to_lower() != v and v.to_upper() != v) + int(has_any(v, "0123456789")) + int(has_any(v, "!@#$%^&*()-_=+[]{};:,.<>/?~ "))
		strength.text = "" if v.is_empty() else ["Too short", "Weak", "Fair", "Good", "Strong", "Very strong"][score if v.length() >= 8 else 0]
		strength.add_theme_color_override("font_color", D.DANGER if score < 2 or v.length() < 8 else (D.AMBER if score < 4 else D.MINT))
	)
	if biometric.get("available"):
		var bio := D.list(body)
		var r := D.list_row(bio, "Use biometrics to unlock", func(): pass, false)
		D.badge(r, "finger", D.ACCENT, 36)
		D.text_column(r, "Unlock with biometrics", "Fingerprint or face, after setup")
		var t := D.Toggle.new(biometric_opt)
		r.add_child(t)
		var target: Button = r.get_parent().get_parent().get_child(0)
		target.pressed.connect(func(): biometric_opt = not biometric_opt; t.set_on(biometric_opt))
	D.button(body, "Restore wallet" if restore else "Create wallet", func():
		var mnemonic := " ".join(phrase.text.strip_edges().to_lower().split(" ", false)) if restore else " ".join(words)
		if restore and mnemonic.split(" ").size() not in [12, 15, 18, 21, 24]:
			notice("Enter all 12 or 24 words of your recovery phrase."); return
		if pw.text.length() < 8 or pw.text != confirm.text:
			notice("Enter matching passwords of at least 8 characters."); return
		var password := pw.text
		command("createWallet", {"mnemonic": mnemonic, "password": password, "restore": restore}, func(_v):
			words.clear()
			if biometric.get("available") and biometric_opt: native("enableBiometric", [network(), password])
		, "Restoring your wallet…" if restore else "Creating your wallet…")
	, "primary", "check")

# ------------------------------------------------------------------ home ---

func home() -> void:
	if is_wide():
		var cols := columns(body)
		home_summary(cols[0])
		home_lists(cols[1])
	else:
		home_summary(body)
		home_lists(body)

func home_summary(parent: Control) -> void:
	var hero := Control.new()
	hero.custom_minimum_size.y = 188
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hero)
	var art := artwork(hero, 188)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var info := D.vbox(D.inset(hero, 20, 18), 2)
	info.get_parent().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	D.label(info, "NIGHT balance", 13, D.MUTED, 560)
	var balance_text := M.units(overview.night.available, 6) if overview.has("night") else "—"
	var big := D.label(info, money(balance_text), 42 if balance_text.length() < 12 else 28, D.INK, 720)
	big.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	big.clip_text = true
	D.label(info, "NIGHT", 13, D.ACCENT, 680)
	D.space(info, 0, true)
	var line := D.row(info, 6)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", D.style(sync_tone(), 3))
	line.add_child(dot)
	status_line = D.label(line, sync_text(), 12, D.MUTED, 520)
	status_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_line.clip_text = true
	if not demo and str(live_state.get("sync", {}).get("error", "")).contains("Blockfrost"):
		D.button(parent, "Add a Blockfrost project ID", func(): navigate("network"), "soft", "key")
	var actions := GridContainer.new()
	actions.columns = 3
	actions.add_theme_constant_override("h_separation", 10)
	parent.add_child(actions)
	action_tile(actions, "Send", "send", func(): navigate("send"), true)
	action_tile(actions, "Receive", "receive", func(): navigate("receive"))
	action_tile(actions, "Scan", "scan", scan_qr)
	if overview.is_empty():
		D.skeleton(parent, 2)
		return
	fuel_card(parent)

func action_tile(parent: Control, title: String, symbol: String, action: Callable, primary := false) -> void:
	var b := Button.new()
	b.accessibility_name = title
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 72
	var fill := D.ACCENT if primary else D.RAISED
	b.add_theme_stylebox_override("normal", D.style(fill, 20, Color.TRANSPARENT if primary else D.LINE))
	b.add_theme_stylebox_override("hover", D.style(fill, 20, Color.TRANSPARENT if primary else D.LINE))
	b.add_theme_stylebox_override("pressed", D.style(fill.lightened(0.08), 20, Color.TRANSPARENT if primary else D.LINE))
	b.add_theme_stylebox_override("disabled", D.style(Color(fill, 0.5), 20))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	parent.add_child(b)
	var v := D.vbox(b, 4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := CenterContainer.new(); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(c)
	var ink := D.ON_ACCENT if primary else D.INK
	D.icon(c, symbol, ink, 22)
	D.label(v, title, 13, ink, 660).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.disabled = busy
	b.pressed.connect(func(): D.buzz("tap"); action.call())
	D._press_feedback(b)

func fuel_card(parent: Control) -> void:
	D.section(parent, "Network fuel", "DUST")
	var dust: Dictionary = overview.dust
	var group := D.list(parent)
	var r := D.list_row(group, "DUST generation", navigate.bind("dust"), false)
	var ring := D.Ring.new(48)
	var cap := float(M.units(dust.cap, 15).replace(",", ""))
	var have := float(M.units(dust.balance, 15).replace(",", ""))
	ring.value = 0.0 if cap <= 0 else have / cap
	ring.tint = D.MINT
	ring.width = 4.5
	r.add_child(ring)
	var generating: bool = dust.registeredNight != "0"
	var share_ := "%d%% of cap" % roundi(100.0 * ring.value) if cap > 0 else "No cap yet"
	var names := D.text_column(r, "", share_ + (" · generating" if generating else " · not generating"))
	dust_balance_label = names.get_child(0)
	dust_balance_label.text = money(short_dust() + " DUST")
	D.icon(r, "next", D.DIM, 14)

func home_lists(parent: Control) -> void:
	D.section(parent, "Assets", "" if overview.is_empty() else str(asset_list().size()))
	if overview.is_empty():
		D.skeleton(parent, 3)
		return
	var assets := D.list(parent)
	for item in asset_list():
		asset_row(assets, item)
	if not recent.is_empty():
		var top := D.section(parent, "Recent")
		D.chip(top, "See all", func(): navigate("activity"))
		var group := D.list(parent)
		for tx in recent: history_row(group, tx, "home")

func asset_list() -> Array:
	var out := []
	if overview.has("night"): out.append({"kind": "unshielded", "type": M.NIGHT_TYPE, "amount": overview.night.available})
	for kind in ["shielded", "unshielded"]:
		for coin in overview.get(kind, []):
			if kind == "unshielded" and coin.type == M.NIGHT_TYPE: continue
			out.append({"kind": kind, "type": coin.type, "amount": coin.amount})
	return out

func asset_row(parent: Control, item: Dictionary, action := Callable(), selected := false) -> void:
	var kind: String = item.kind
	var asset := describe_asset(kind, item.type)
	var night: bool = kind == "unshielded" and item.type == M.NIGHT_TYPE
	if not action.is_valid() and not night and not demo:
		action = func(): label_asset = {"kind": kind, "type": item.type}; go("token_label")
	var r := D.list_row(parent, "Select " + asset.name if selected or action.is_valid() and page in DRAWERS else ("Edit token label" if not night else asset.name), action)
	D.badge(r, "night" if night else ("shield" if kind == "shielded" else "contracts"), D.ACCENT)
	var names := D.vbox(r, 2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := D.label(names, asset.name, 15, D.INK, 620)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	var line := D.row(names, 6)
	D.label(line, asset.unit if asset.unit != "base units" else "Unlabelled", 12, D.MUTED, 500)
	D.pill(line, "Private" if kind == "shielded" else "Public", D.ACCENT if kind == "shielded" else D.MUTED)
	var value := D.label(r, money(M.units(item.amount, asset.decimals)), 15, D.INK, 640)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if selected: D.icon(r, "check", D.ACCENT, 18)

func tx_symbol(tx: Dictionary) -> String:
	match tx.get("kind"):
		"receive": return "receive"
		"dust": return "dust"
		"dapp": return "code"
	return "send"

func tx_private(tx: Dictionary) -> bool:
	return tx.get("deltas", []).any(func(d): return d.kind == "shielded")

func history_row(parent: Control, tx: Dictionary, origin: String) -> void:
	var r := D.list_row(parent, "Details", func(): history_origin = origin; detail = tx; go("detail") if not (is_wide() and page == "activity") else redraw_at_scroll())
	var incoming: bool = tx.get("kind") == "receive"
	D.badge(r, tx_symbol(tx), D.MINT if incoming or tx.get("kind") == "dust" else D.ACCENT)
	var names := D.vbox(r, 2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := D.label(names, tx_title(tx), 15, D.INK, 620)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	var line := D.row(names, 6)
	D.label(line, receipt_status(tx), 12, D.MUTED, 500)
	if not tx.get("deltas", []).is_empty(): D.pill(line, "Private" if tx_private(tx) else "Public", D.ACCENT if tx_private(tx) else D.MUTED)
	for change in tx.get("deltas", []):
		if change.kind != "dust":
			var asset := describe_asset(change.kind, change.type)
			var positive := not str(change.amount).begins_with("-")
			var delta := D.label(r, money(("+" if positive else "") + asset_amount(change.amount, asset)), 14, D.MINT if positive else D.INK, 640)
			delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			break

# ------------------------------------------------------------------ dust ---

func dust_page() -> void:
	if page == "dust_review":
		var registering: bool = preview.action == "register"
		heading("Start generating" if registering else "Stop generating", "Review the NIGHT and the fee before confirming.", true)
		var summary := D.card(body, D.SURFACE, 18, 14, 2)
		kv(summary, "Network fee", M.units(str(preview.fee), 15) + " DUST")
		for output in preview.utxos:
			kv(summary, middle(str(output.ref), 8), M.units(output.amount, 6) + " NIGHT")
		if not preview.canPay:
			D.label(body, "More DUST is needed to pay this fee. Go back and check again once it has accumulated.", 14, D.MUTED, 480, true)
			return
		D.hold_button(body, "Hold to confirm", func():
			if demo: go("dust"); show_toast("Demo review complete"); return
			submit_review("dustApply"), "dust")
		return
	heading("DUST", "Registered NIGHT generates the DUST that pays network fees.", true)
	if overview.is_empty(): D.skeleton(body, 2); return
	var parent: Control = body
	var side: Control = body
	if is_wide():
		var cols := columns(body)
		parent = cols[0]; side = cols[1]
	var top := D.card(parent, D.SURFACE, 20, 20, 10)
	var h := D.row(top, 18)
	var ring := D.Ring.new(96)
	ring.width = 8
	ring.tint = D.MINT
	var cap := float(M.units(overview.dust.cap, 15).replace(",", ""))
	ring.value = 0.0 if cap <= 0 else float(M.units(overview.dust.balance, 15).replace(",", "")) / cap
	h.add_child(ring)
	var v := D.vbox(h, 2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	D.label(v, "Available", 13, D.MUTED, 520)
	dust_balance_label = D.label(v, money(M.units(overview.dust.balance, 15)), 26, D.INK, 720, true)
	D.label(v, "of %s DUST cap" % M.units(overview.dust.cap, 15), 13, D.MUTED, 520)
	var rows := D.card(side, D.SURFACE, 18, 8, 0)
	kv(rows, "Registered NIGHT", money(M.units(overview.dust.registeredNight, 6)))
	kv(rows, "Unregistered NIGHT", money(M.units(overview.dust.unregisteredNight, 6)))
	for action in ["register", "deregister"]:
		var key := "unregisteredNight" if action == "register" else "registeredNight"
		if overview.dust[key] == "0": continue
		D.button(side, "Register NIGHT" if action == "register" else "Stop generation", func():
			if demo:
				preview = {"action": action, "canPay": true, "fee": "250000000000000", "utxos": [{"ref": "Sample output", "amount": overview.dust[key]}]}
				go("dust_review")
				return
			prepare_review("dustPreview", {"action": action}, "dust_review")
		, "primary" if action == "register" else "secondary", "bolt" if action == "register" else "close")
	var address := wallet_address("dust")
	if not address.is_empty():
		D.section(side, "DUST address")
		var card := D.card(side, D.SURFACE, 16, 12, 8)
		D.label(card, "Share this address to let another wallet's NIGHT generate DUST for you.", 13, D.MUTED, 480, true)
		D.label(card, middle(address, 14), 13, D.INK, 560)
		var acts := D.row(card, 8)
		D.chip(acts, "Copy", func(): copy(address, "DUST address copied"), false, "copy")
		D.chip(acts, "Share", func(): share(address), false, "share")

# -------------------------------------------------------------- activity ---

func activity_page() -> void:
	if is_wide():
		var cols := columns(body)
		cols[1].size_flags_stretch_ratio = 1.1
		activity_list(cols[0])
		if detail.is_empty():
			var empty := D.card(cols[1], D.SURFACE, 20, 40, 8)
			var c := CenterContainer.new(); empty.add_child(c)
			D.icon(c, "activity", D.DIM, 34)
			D.label(empty, "Select a transaction to see its receipt", 14, D.MUTED, 520).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			detail_content(cols[1])
		return
	activity_list(body)

func activity_list(parent: Control) -> void:
	var saved := body
	body = parent
	heading("Activity")
	body = saved
	var chips := D.row(parent, 8)
	for f in [["all", "All"], ["private", "Private"], ["public", "Public"]]:
		D.chip(chips, f[1], func(): activity_filter = f[0]; redraw_at_scroll(), activity_filter == f[0])
	if history.is_empty():
		if not history_loaded: D.skeleton(parent, 4); return
		var empty := D.card(parent, D.SURFACE, 20, 28, 6)
		var c := CenterContainer.new(); empty.add_child(c)
		D.icon(c, "activity", D.DIM, 30)
		D.label(empty, "No transactions yet", 16, D.INK, 640).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_line = D.label(empty, sync_text(), 13, D.MUTED, 500, true)
		status_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	var shown := history.filter(func(tx): return activity_filter == "all" or tx_private(tx) == (activity_filter == "private"))
	if shown.is_empty():
		D.label(parent, "No %s transactions in the loaded history." % activity_filter, 14, D.MUTED, 500, true)
	var day := "~"
	var group: VBoxContainer
	for tx in shown:
		var label := day_label(tx)
		if label != day:
			day = label
			D.label(parent, label, 13, D.MUTED, 600)
			group = D.list(parent)
		history_row(group, tx, "activity")
	if history_total > history.size():
		D.button(parent, "Show more", func(): history_limit += 30; refresh(), "secondary", "down")

func day_label(tx: Dictionary) -> String:
	if tx.get("time") == null:
		return "Pending" if str(tx.get("status", "")) in ["pending", "offered"] else "Earlier"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var seconds := int(float(tx.time) / 1000.0) + bias
	var today := int(Time.get_unix_time_from_system()) + bias
	var days := int(floor(today / 86400.0)) - int(floor(seconds / 86400.0))
	if days <= 0: return "Today"
	if days == 1: return "Yesterday"
	var d := Time.get_date_dict_from_unix_time(seconds)
	return "%s %d" % [["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.month - 1], d.day]

func tx_title(tx: Dictionary) -> String:
	if tx.get("kind") == "dapp": return contract_title(tx.get("action", "Contract transaction"))
	return {"receive": "Received", "send": "Sent", "dust": "DUST generation started" if tx.get("action") != "deregister" else "DUST generation stopped"}.get(tx.get("kind", ""), "Transaction")

func detail_page() -> void:
	heading(tx_title(detail), "", true)
	detail_content(body)

func detail_content(parent: Control) -> void:
	if is_wide() and page == "activity": D.label(parent, tx_title(detail), 22, D.INK, 700)
	var top := D.card(parent, D.SURFACE, 20, 18, 4)
	var shown := false
	for change in detail.get("deltas", []):
		if change.kind == "dust": continue
		var asset := describe_asset(change.kind, change.type)
		var positive := not str(change.amount).begins_with("-")
		D.label(top, money(("+" if positive else "") + asset_amount(change.amount, asset)), 30, D.MINT if positive else D.INK, 720, true)
		shown = true
		break
	if not shown: D.label(top, tx_title(detail), 22, D.INK, 700, true)
	var line := D.row(top, 8)
	D.pill(line, receipt_status(detail) if receipt_status(detail) else "Recorded", D.MINT if str(detail.get("status")) in ["finalized", "confirmed"] else D.AMBER)
	if not detail.get("deltas", []).is_empty(): D.pill(line, "Private" if tx_private(detail) else "Public", D.ACCENT if tx_private(detail) else D.MUTED)
	var rows := D.card(parent, D.SURFACE, 18, 6, 0)
	if detail.get("block") != null: kv(rows, "Block", group_digits(str(int(detail.block))))
	if detail.get("time"):
		kv(rows, "Time", Time.get_datetime_string_from_unix_time(int(detail.time / 1000.0) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60, true))
	kv(rows, "Chain", "Demo" if demo else chain_name())
	for change in detail.get("deltas", []):
		if change.kind == "shielded" or (change.kind == "unshielded" and change.type != M.NIGHT_TYPE):
			kv(rows, "Token", middle(change.type, 8), true)
	var hash := str(detail.get("hash", ""))
	var hr := D.row(rows, 8)
	hr.custom_minimum_size.y = 48
	D.label(hr, "Transaction", 14, D.MUTED, 500).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hl := D.label(hr, middle(hash, 8), 13, D.INK, 600)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hl.clip_text = true
	hl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	D.chip(hr, "Copy", func(): copy(hash, "Transaction hash copied"), false, "copy").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if detail.get("timeline") is Dictionary:
		var saved := body
		body = parent
		timeline(detail.timeline)
		body = saved
	if not demo and hash.length() == 64 and hash.is_valid_hex_number(false):
		D.button(parent, "View on explorer", open_browser.bind(explorer_tx(hash), "detail" if page == "detail" else "activity"), "secondary", "globe")
		if prefs.developer: D.button(parent, "On-chain receipt", open_receipt.bind(hash, "detail"), "ghost", "check")

func explorer_tx(hash: String) -> String:
	return EXPLORERS.get(network(), EXPLORERS.preview) + "transactions/" + hash

func wallet_address(kind: String) -> String:
	var addresses = live_state.get("addresses")
	return str(addresses.get(kind, "")) if addresses is Dictionary else ""

# --------------------------------------------------------------- receive ---

func receive_page() -> void:
	heading("Receive")
	if receive_kind == "dust": receive_kind = "unshielded"
	D.segmented(body, [["shielded", "Private", "Shielded tokens"], ["unshielded", "Public", "NIGHT and public tokens"]], receive_kind, func(kind): receive_kind = kind; draw_page())
	if demo:
		D.label(body, "Demo addresses can't receive funds. Open a wallet to show its address and QR code.", 14, D.MUTED, 480, true)
		return
	var address := wallet_address(receive_kind)
	if address.is_empty():
		D.skeleton(body, 1)
		return
	var qr_box := CenterContainer.new()
	body.add_child(qr_box)
	var plate := D.panel(qr_box, Color.WHITE, 24, Color.TRANSPARENT)
	var qr := TextureRect.new()
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var side := clampf(minf(size.x, 480) - 140, 180, 240)
	qr.custom_minimum_size = Vector2(side, side)
	D.inset(plate, 14, 14).add_child(qr)
	ask("qr", {"address": address}, func(reply):
		if not is_instance_valid(qr) or not qr.is_inside_tree(): return
		if not reply.has("result"):
			qr_box.hide()
			notice("The QR code could not be drawn. You can still copy the address.")
			return
		var rows: Array = reply.result.rows
		var img := Image.create_empty(rows.size() + 2, rows.size() + 2, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		for y in rows.size():
			for x in rows.size():
				if rows[y][x] == "1": img.set_pixel(x + 1, y + 1, Color("#0b0b14"))
		qr.texture = ImageTexture.create_from_image(img)
	)
	# Keep the human-readable prefix whole and group the data part in fours.
	var split := address.rfind("1") + 1
	var grouped := address.left(split)
	for i in range(split, address.length()):
		if i > split and (i - split) % 4 == 0: grouped += " "
		grouped += address[i]
	var addr := D.label(body, grouped, 13, D.MUTED, 520, true)
	addr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var acts := D.row(body, 10)
	D.button(acts, "Copy address", func(): copy(address, "Address copied"), "secondary", "copy")
	D.button(acts, "Share", func(): share(address), "primary", "share")

# ------------------------------------------------------------------ send ---

func address_kind(text: String) -> String:
	var t := text.strip_edges().to_lower()
	if t.begins_with("mn_shield-addr"): return "shielded"
	if t.begins_with("mn_dust"): return "dust"
	if t.begins_with("mn_addr"): return "unshielded"
	return ""

func held_coins(kind: String) -> Array:
	return overview.get(kind, []).filter(func(c): return str(c.amount) != "0")

func preparing_page() -> void:
	if preparing_error:
		heading("Couldn't prepare")
		D.label(body, preparing_error, 14, D.MUTED, 500, true)
		D.button(body, "Back to send", func(): preparing_error = ""; go("send"), "primary", "back")
		return
	heading("Preparing")
	var c := CenterContainer.new()
	c.custom_minimum_size.y = 120
	body.add_child(c)
	var ring := D.Ring.new(64)
	ring.spinning = true
	c.add_child(ring)
	D.label(body, "Balancing your transfer and estimating the DUST fee…", 14, D.MUTED, 500, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func send_page() -> void:
	if page == "review":
		heading("Confirm send", "", true)
		var output: Dictionary = preview.outputs[0]
		var asset := describe_asset(output.kind, output.type)
		var hero := D.label(body, asset_amount(output.amount, asset), 34, D.INK, 740, true)
		hero.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var to := D.label(body, "to " + middle(str(output.recipient), 10), 14, D.MUTED, 520, true)
		to.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var rows := D.card(body, D.SURFACE, 18, 6, 0)
		kv(rows, "Network fee", M.units(str(preview.fee), 15) + " DUST")
		kv(rows, "Transfer", "Private" if output.kind == "shielded" else "Public")
		kv(rows, "Chain", "Demo" if demo else chain_name())
		if output.kind == "shielded" or output.type != M.NIGHT_TYPE: kv(rows, "Token", middle(output.type, 8), true)
		if network() == "mainnet" and not demo:
			var w := D.row(body, 8)
			D.icon(w, "info", D.AMBER, 16)
			D.label(w, "Mainnet transfers are final and use real NIGHT.", 13, D.AMBER, 560, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		D.hold_button(body, "Hold to send", func():
			if demo: go("sent"); return
			submit_review("send"))
		return
	if page == "choose_token":
		heading("Choose an asset", "", true)
		var group := D.list(body)
		for item in asset_list():
			if str(item.amount) == "0": continue
			asset_row(group, item, func(): send_kind = item.kind; token_type = item.type; amount = ""; go("send"), item.kind == send_kind and item.type == token_type)
		return
	heading("Send")
	var held := held_coins(send_kind)
	var index := held.find_custom(func(coin): return coin.type == token_type)
	if index < 0:
		var any := asset_list().filter(func(i): return str(i.amount) != "0")
		if held.is_empty() and not any.is_empty():
			send_kind = any[0].kind; held = held_coins(send_kind)
		token_type = "" if held.is_empty() else str(held[0].type)
		amount = ""
		index = 0
	if held.is_empty():
		if overview.is_empty():
			D.skeleton(body, 1)
		else:
			var empty := D.card(body, D.SURFACE, 20, 20, 6)
			D.label(empty, "Nothing to send yet", 18, D.INK, 680)
			D.label(empty, "Receive NIGHT or a token first, then send it from here.", 14, D.MUTED, 480, true)
			D.button(body, "Receive tokens", func(): go("receive"), "primary", "receive")
		return
	var coin: Dictionary = held[index]
	var selected := describe_asset(send_kind, token_type)
	D.caption(body, "Asset")
	var asset_group := D.list(body)
	asset_row(asset_group, {"kind": send_kind, "type": token_type, "amount": coin.amount}, func(): navigate("choose_token"))
	asset_group.find_children("*", "Button", true, false)[0].accessibility_name = "Choose asset"
	var chev_row: HBoxContainer = asset_group.get_child(0).get_child(1).get_child(0)
	D.icon(chev_row, "down", D.DIM, 14)
	D.caption(body, "To")
	var address_field := D.field(body, ("Private" if send_kind == "shielded" else "Public") + " address  mn_…")
	address_field.text = recipient
	var hint := D.label(body, "", 12, D.MUTED, 560, true)
	var check_kind := func(value: String):
		var k := address_kind(value)
		if k == "dust": hint.text = "This is a DUST address. Send to a private or public address."; hint.add_theme_color_override("font_color", D.DANGER)
		elif k != "" and k != send_kind: hint.text = "This is a %s address. Choose a %s asset to send to it." % ["private" if k == "shielded" else "public", "private" if k == "shielded" else "public"]; hint.add_theme_color_override("font_color", D.AMBER)
		elif k != "": hint.text = "%s address" % ("Private" if k == "shielded" else "Public"); hint.add_theme_color_override("font_color", D.MINT)
		else: hint.text = ""
		hint.visible = not hint.text.is_empty()
	address_field.text_changed.connect(func(value): recipient = value; check_kind.call(value))
	check_kind.call(recipient)
	var shortcuts := HFlowContainer.new()
	shortcuts.add_theme_constant_override("h_separation", 8)
	body.add_child(shortcuts)
	D.chip(shortcuts, "Paste", func():
		var text := DisplayServer.clipboard_get().strip_edges()
		if text.is_empty(): show_toast("Clipboard is empty"); return
		recipient = text; address_field.text = text; check_kind.call(text)
	, false, "copy")
	if not demo: D.chip(shortcuts, "Scan", scan_qr, false, "scan")
	var own_address := wallet_address(send_kind)
	if not own_address.is_empty() and not demo:
		D.chip(shortcuts, "My address", func(): recipient = own_address; address_field.text = recipient; check_kind.call(recipient))
	if demo:
		D.chip(shortcuts, "Use sample transfer", func():
			recipient = "Demo recipient"; amount = "1" if send_kind == "shielded" else "12.50"
			draw_page()
		)
	D.caption(body, "Amount")
	var amount_box := D.panel(body, D.SURFACE, 20)
	var ar := D.row(D.inset(amount_box, 18, 8), 8)
	var value_field := LineEdit.new()
	value_field.placeholder_text = "0" if selected.decimals == 0 else "0.00"
	value_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	value_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_field.custom_minimum_size.y = 60
	value_field.add_theme_font_override("font", D.font(700))
	value_field.add_theme_font_size_override("font_size", 30)
	value_field.add_theme_color_override("font_color", D.INK)
	value_field.add_theme_color_override("font_placeholder_color", D.DIM)
	value_field.add_theme_color_override("caret_color", D.ACCENT)
	for s in ["normal", "focus", "read_only"]: value_field.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	value_field.accessibility_name = "Amount"
	ar.add_child(value_field)
	var unit := D.label(ar, selected.unit, 15, D.ACCENT, 680)
	unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	D.chip(ar, "Max", func():
		amount = M.units(coin.amount, selected.decimals).replace(",", "")
		value_field.text = amount
	).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_field.text = amount
	value_field.text_changed.connect(func(value): amount = value)
	D.label(body, "Available " + money(asset_amount(coin.amount, selected)), 12, D.MUTED, 520)
	D.button(body, "Review", func():
		recipient = address_field.text.strip_edges()
		amount = value_field.text.strip_edges().replace(",", "")
		var atomic := M.atomic_amount(amount, selected.decimals)
		if recipient.is_empty(): notice("Enter a recipient address."); return
		var k := address_kind(recipient)
		if k == "dust" or (k != "" and k != send_kind): notice(hint.text); return
		if atomic.is_empty():
			notice("Enter a positive whole number." if selected.decimals == 0 else "Enter a positive amount with up to %d decimal places." % selected.decimals); return
		if M.exceeds(atomic, coin.amount):
			notice("This is more than your available balance."); return
		var outputs := [{"recipient": recipient, "kind": send_kind, "type": token_type, "amount": atomic}]
		if demo:
			if recipient != "Demo recipient": notice("Use the sample transfer in the demo."); return
			preview = {"outputs": outputs, "fee": "250000000000000"}
			go("review"); return
		prepare_review("previewSend", {"outputs": outputs}, "review")
	, "primary", "next")

func use_scanned(value: String) -> void:
	var text := value.strip_edges()
	if text.to_lower().begins_with("midnight:"): text = text.substr(9).split("?")[0]
	var k := address_kind(text)
	if k == "dust": show_toast("That's a DUST address"); return
	recipient = text
	if k != "" and k != send_kind:
		var match_ := asset_list().filter(func(i): return i.kind == k and str(i.amount) != "0")
		if not match_.is_empty():
			send_kind = k; token_type = match_[0].type; amount = ""
	D.buzz("confirm")
	if page == "send": draw_page()
	else: go("send")

func scan_qr() -> void:
	if demo: show_toast("Scanning works in a real wallet"); return
	if native("scanQr", []) == null and not Engine.has_singleton("WalletEngine"):
		show_toast("The QR scanner needs the Android app")

func asset_amount(raw: String, asset: Dictionary) -> String:
	var unit: String = asset.unit
	if unit == "base units" and raw.trim_prefix("-") == "1": unit = "base unit"
	return M.units(raw, asset.decimals) + " " + unit

func describe_asset(kind: String, type: String) -> Dictionary:
	if kind == "dust":
		return {"name": "DUST", "unit": "DUST", "decimals": 15}
	if kind == "unshielded" and type == M.NIGHT_TYPE:
		return {"name": "Midnight", "unit": "NIGHT", "decimals": 6}
	if demo and type == M.DEMO_TYPE:
		return {"name": "Demo token", "unit": "DEMO", "decimals": 0}
	var metadata: Dictionary = token_labels.get(kind + ":" + type, {})
	if metadata.is_empty() and known_types.get(kind) == type:
		return {"name": "Test token", "unit": "sTEST" if kind == "shielded" else "uTEST", "decimals": 0}
	var name_: String = metadata.get("name", "")
	if name_.is_empty(): name_ = "Token " + type.left(4) + "…" + type.right(4)
	var symbol: String = metadata.get("symbol", "")
	return {"name": name_, "unit": symbol if symbol else "base units", "decimals": int(metadata.get("decimals", 0))}

func label_page() -> void:
	heading("Token label", "Only this wallet sees the name.", true)
	var previous: Dictionary = token_labels.get(label_asset.kind + ":" + label_asset.type, {})
	var id := D.card(body, D.SURFACE, 16, 12, 4)
	D.label(id, "Token ID", 12, D.MUTED, 560)
	D.label(id, label_asset.type, 13, D.INK, 520, true)
	D.caption(body, "Name")
	var token_name := D.field(body, "Token name")
	token_name.text = previous.get("name", "")
	D.caption(body, "Symbol")
	var symbol := D.field(body, "Symbol")
	symbol.text = previous.get("symbol", "")
	D.caption(body, "Decimal places")
	var decimals := D.field(body, "0")
	decimals.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	# JSON numbers arrive as floats; show them as whole numbers.
	decimals.text = str(int(previous.get("decimals", 0)))
	D.button(body, "Save label", func():
		if not decimals.text.strip_edges().is_valid_int(): notice("Enter a whole number of decimal places."); return
		var values := label_asset.duplicate()
		values.merge({"name": token_name.text.strip_edges(), "symbol": symbol.text.strip_edges(), "decimals": int(decimals.text)})
		command("setTokenLabel", values, func(result):
			token_labels[result.kind + ":" + result.type] = result
			show_toast("Label saved")
			go("home")
		)
	, "primary", "check")

# ------------------------------------------------------------- contracts ---

func contracts_page() -> void:
	if page == "contract_review":
		heading("Confirm contract action", "", true)
		var summary := D.card(body, D.SURFACE, 18, 6, 0)
		kv(summary, "Action", contract_title(preview.action))
		kv(summary, "Chain", chain_name())
		kv(summary, "Contract", middle(str(preview.address), 8), true)
		kv(summary, "Network fee", M.units(preview.fee, 15) + " DUST")
		if preview.action in ["mintShielded", "mintUnshielded"]:
			kv(summary, "Mint", preview.amount + " to your " + ("private" if preview.action == "mintShielded" else "public") + " address")
		D.hold_button(body, "Hold to confirm", func(): submit_review("submitTokenAction"), "contracts")
		return
	heading("Token contract" if contract_kind == "token" else "Counter contract", "mdwa.local test dApp", true)
	D.segmented(body, [["token", "Token"], ["counter", "Counter"]], contract_kind, func(kind):
		if busy or contract_kind == kind: return
		contract_kind = kind; token_contract = {}; go("contracts", "fade"))
	var panel := D.card(body, D.SURFACE, 18, 16, 8)
	D.label(panel, "Test token" if contract_kind == "token" else "Public counter", 18, D.INK, 680, true)
	if demo:
		D.label(panel, "Open a Preview wallet to deploy and mint tokens.", 14, D.MUTED, 480, true)
		return
	if token_contract.is_empty():
		D.label(panel, "Loading contract…", 14, D.MUTED, 500)
		return
	if not token_contract.get("address"):
		D.label(panel, "Deploy once to mint private and public test tokens to this wallet." if contract_kind == "token" else "Deploy a counter that anyone can read or increment on Preview.", 14, D.MUTED, 480, true)
		D.button(body, "Deploy contract", prepare_contract.bind("deploy"), "primary", "contracts")
		return
	var ar := D.row(panel, 8)
	var addr := D.label(ar, middle(token_contract.address, 10), 13, D.MUTED, 520)
	addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr.clip_text = true
	addr.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	D.chip(ar, "Copy", func(): copy(token_contract.address, "Contract address copied"), false, "copy")
	if token_contract.get("pending"):
		D.label(panel, "Confirmation is pending after an interrupted submission.", 14, D.AMBER, 520, true)
		D.button(panel, "Check submission", func():
			command("recoverTokenAction", {"kind": contract_kind}, func(result):
				refresh(); show_toast(result.get("message", "Submission checked"))
			, "Checking the indexer…")
		, "primary", "refresh")
		return
	if token_contract.get("value") is Dictionary and token_contract.value.has("error"):
		D.label(panel, token_contract.value.error, 14, D.MUTED, 480, true)
	elif token_contract.get("value") is Dictionary:
		kv(panel, "Mints" if contract_kind == "token" else "Count", str(token_contract.value.count))
		kv(panel, "At block", group_digits(str(int(token_contract.value.block))))
	if contract_kind == "counter":
		D.button(body, "Increment counter", prepare_contract.bind("increment"), "primary", "plus")
		return
	D.caption(body, "Amount to mint")
	var quantity := D.field(body, "Whole tokens")
	quantity.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	quantity.text = mint_amount
	quantity.text_changed.connect(func(value): mint_amount = value)
	var acts := D.row(body, 10)
	D.button(acts, "Mint private", prepare_contract.bind("mintShielded"), "primary", "shield")
	D.button(acts, "Mint public", prepare_contract.bind("mintUnshielded"), "secondary", "receive")

func contract_title(action: String) -> String:
	return {"deploy": "Deploy contract", "increment": "Increment counter", "mintShielded": "Mint private tokens", "mintUnshielded": "Mint public tokens"}.get(action, action)

func prepare_contract(action: String) -> void:
	var quantity := M.atomic_amount(mint_amount, 0) if action in ["mintShielded", "mintUnshielded"] else "1"
	if quantity.is_empty():
		notice("Enter a positive whole number."); return
	prepare_review("prepareTokenAction", {"kind": contract_kind, "action": action, "amount": quantity}, "contract_review")

# ---------------------------------------------------------- transactions ---

func prepare_review(method: String, params: Dictionary, review_page: String) -> void:
	if busy: return
	trace_origin = drawer_owner if page in DRAWERS else page
	trace = {}
	last_tx = ""
	preparing_error = ""
	busy = true
	var in_sheet := page in DRAWERS
	go("preparing" if in_sheet else "working")
	ask(method, params, func(reply):
		busy = false
		if reply.has("error"):
			D.buzz("error")
			if page == "preparing":
				preparing_error = reply.error.message
				draw_page()
			else: fail_transaction(reply.error.message)
			return
		preview = reply.result
		go(review_page)
	)

func submit_review(method: String) -> void:
	if busy or not preview.has("id"): return
	var id = preview.id
	busy = true
	last_tx = ""
	receipt = {}
	go("sent")
	ask(method, {"id": id}, func(reply):
		busy = false
		preview = {}
		if reply.has("error"):
			D.buzz("error")
			fail_transaction(reply.error.message)
			return
		last_tx = reply.result.txId
		if method == "send": recipient = ""; amount = ""
		draw_page()
		refresh()
	)

func fail_transaction(reason: String) -> void:
	trace["status"] = "error"
	trace["error"] = reason
	draw_page()

func receipt_status(item: Dictionary) -> String:
	if item.get("partial", false): return "Partially successful"
	return str(item.get("status", "")).capitalize()

func duration_label(parent: Control, start, end_time, px: int, color: Color) -> void:
	var text := D.label(parent, "", px, color, 600)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	text.custom_minimum_size.x = 50
	if end_time != null: text.text = seconds_text(int(end_time) - int(start))
	else: clocks.append({"label": text, "start": int(start)})

func seconds_text(ms: int) -> String:
	var seconds := maxf(0., ms / 1000.)
	return "%.1fs" % seconds if seconds < 60 else "%dm %02ds" % [int(seconds / 60), int(seconds) % 60]

func update_clocks() -> void:
	var now := trace_now + Time.get_ticks_msec() - trace_ticks
	for clock in clocks:
		if is_instance_valid(clock.label): clock.label.text = seconds_text(now - clock.start)

# Steps with timings. Developer mode adds each local proof as a sub-row.
func timeline(record: Dictionary, awaiting := false) -> void:
	if not record.has("start"): return
	var group := D.card(body, D.SURFACE, 18, 10, 2)
	var header_row := D.row(group)
	D.label(header_row, "Elapsed", 13, D.MUTED, 560).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_label(header_row, record.start, null if awaiting else record.get("end"), 17, D.ACCENT)
	for step in record.get("steps", []):
		var row := D.row(group, 8)
		row.custom_minimum_size.y = 34
		var done: bool = step.has("end") and not (awaiting and step.name == "Awaiting approval")
		D.icon(row, "check" if done else "activity", D.MINT if done else D.ACCENT, 15)
		D.label(row, step.name, 14, D.INK if done else D.ACCENT, 560, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		duration_label(row, step.start, step.get("end") if done else null, 13, D.MUTED)
		if not prefs.developer: continue
		for proof in step.get("proofs", []):
			var sub := D.row(group)
			D.space(sub, 0).custom_minimum_size.x = 23
			var name_ := "GPU · " + str(proof.name)
			if proof.get("failed"): name_ += " · Failed"
			D.label(sub, name_, 12, D.MUTED, 500, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			duration_label(sub, proof.start, proof.get("end"), 12, D.MUTED)

func progress_page() -> void:
	if demo:
		var c := CenterContainer.new(); c.custom_minimum_size.y = 180; body.add_child(c)
		var done_ring := D.Ring.new(110); done_ring.value = 1.0; done_ring.tint = D.MINT; done_ring.width = 7; c.add_child(done_ring)
		var okc := CenterContainer.new(); done_ring.add_child(okc); okc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		D.icon(okc, "check", D.MINT, 44)
		D.label(body, "Demo complete", 26, D.INK, 720).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		D.label(body, "A real transfer proves privately on this phone, then finalizes on Midnight.", 14, D.MUTED, 480, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		D.button(body, "Back to wallet", navigate.bind("home"), "primary")
		return
	var failed: bool = trace.get("status") == "error"
	var status := str(trace.get("status", ""))
	var finished := status in ["finalized", "complete"] or str(receipt.get("status", "")) == "finalized"
	var steps: Array = trace.get("steps", [])
	var current := str(steps.back().name) if not steps.is_empty() else ""
	var title := "Preparing"
	var sub := "Building your transaction"
	if failed: title = "Interrupted"; sub = str(trace.get("error", ""))
	elif status == "finalized" or str(receipt.get("status", "")) == "finalized": title = "Finalized"; sub = "Confirmed on " + chain_name()
	elif status == "complete": title = "Submitted"; sub = "Waiting for the block to finalize"
	elif current.begins_with("Proving"): title = "Proving privately"; sub = "Your phone is generating the zero-knowledge proof"
	elif current in ["Submitting", "Submitted", "In block", "Returned to pool"]: title = "Submitting"; sub = "Sending the proof to " + chain_name()
	elif page == "sent": title = "Signing"; sub = "Authorising with your keys"
	var wide := is_wide()
	var parent: Control = body
	var side: Control = body
	if wide:
		var cols := columns(body)
		parent = cols[0]; side = cols[1]
	var c := CenterContainer.new(); c.custom_minimum_size.y = 190; parent.add_child(c)
	var ring := D.Ring.new(120)
	ring.width = 7
	if failed:
		ring.value = 1.0; ring.tint = D.DANGER
	elif finished:
		ring.value = 1.0; ring.tint = D.MINT
	else:
		ring.spinning = true
	c.add_child(ring)
	if failed or finished:
		var markc := CenterContainer.new(); ring.add_child(markc); markc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var mark = D.icon(markc, "close" if failed else "check", D.DANGER if failed else D.MINT, 48)
		if finished and D.motion > 0:
			mark.pivot_offset = Vector2(24, 24); mark.scale = Vector2.ONE * 0.3
			mark.create_tween().tween_property(mark, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var t := D.label(parent, title, 28, D.INK, 740, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := D.label(parent, sub, 14, DANGER_TEXT() if failed else D.MUTED, 500, true)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var saved := body
	body = side
	timeline(trace)
	body = saved
	var rows := D.card(side, D.SURFACE, 18, 6, 0)
	var block = receipt.get("block") if receipt.get("block") != null else trace.get("block")
	if block != null: kv(rows, "Block", group_digits(str(int(block))))
	var state_text := receipt_status(receipt)
	if state_text: kv(rows, "Result", state_text)
	var hash := str(receipt.get("hash", trace.get("hash", "")))
	if hash.is_valid_hex_number(false) and hash.length() == 64:
		var hr := D.row(rows, 8)
		hr.custom_minimum_size.y = 48
		D.label(hr, "Transaction", 14, D.MUTED, 500).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var hl := D.label(hr, middle(hash, 8), 13, D.INK, 600)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hl.clip_text = true
		hl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		D.chip(hr, "Copy", func(): copy(hash, "Transaction hash copied"), false, "copy")
		D.button(side, "View on explorer", open_browser.bind(explorer_tx(hash), "sent"), "secondary", "globe").disabled = busy
		if prefs.developer: D.button(side, "On-chain receipt", open_receipt.bind(hash, "sent"), "ghost", "check").disabled = busy
	if rows.get_child_count() == 0: rows.get_parent().get_parent().hide()
	if not busy:
		if failed and page == "working": D.button(side, "Back", back, "secondary", "back")
		D.button(side, "Done", navigate.bind("home"), "primary", "check")

func DANGER_TEXT() -> Color:
	return D.DANGER

# --------------------------------------------------------------- explore ---

func explore_page() -> void:
	heading("Explore")
	var group := D.list(body)
	explore_link(group, "globe", "Block explorer", ("Midnight " + chain_name()) if not demo else "Midnight explorer", open_browser.bind(EXPLORERS.get(network(), EXPLORERS.preview), "explore"))
	if FAUCETS.has(network()) and not demo:
		explore_link(group, "faucet", "Get test NIGHT", "Faucet for " + chain_name() + " · copies your address", func():
			var address := wallet_address("unshielded")
			if address: DisplayServer.clipboard_set(address); show_toast("Address copied. Paste it in the faucet.")
			open_browser(FAUCETS[network()], "explore"))
	D.section(body, "Developer tools", "On" if prefs.developer else "")
	if not prefs.developer:
		var hint := D.card(body, D.SURFACE, 16, 14, 8)
		D.label(hint, "Turn on Developer mode in Settings for the test dApp, contract playground and transaction lookup.", 14, D.MUTED, 480, true)
		D.chip(hint, "Open Settings", func(): navigate("settings"), false, "gear")
		return
	var dev := D.list(body)
	if network() == "preview":
		explore_link(dev, "contracts", "mdwa test dApp", "Deploy, mint and count on Preview", open_browser.bind(LOCAL_APP, "explore"))
	if not demo: explore_link(dev, "search_tx" if false else "activity", "Find transaction", "Look up a receipt by hash", open_receipt.bind("", "explore"))
	if network() != "preview":
		D.label(body, "The test dApp runs on Preview only.", 13, D.MUTED, 500, true)

func explore_link(group: Control, symbol: String, title: String, subtitle: String, action: Callable) -> void:
	var r := D.list_row(group, title, action)
	D.badge(r, symbol, D.ACCENT)
	D.text_column(r, title, subtitle)
	D.icon(r, "next", D.DIM, 14)

func open_receipt(hash: String, origin: String) -> void:
	chain_hash = hash; chain_origin = origin; chain_receipt = {}; watching_hash = ""
	go("chain")
	if hash: lookup_receipt(hash)

func lookup_receipt(hash: String) -> void:
	hash = hash.strip_edges().trim_prefix("0x")
	if hash.length() != 64 or not hash.is_valid_hex_number(false):
		notice("Enter a 64-character transaction hash."); return
	chain_hash = hash
	watching_hash = ""
	lookup_generation += 1
	var request_id := lookup_generation
	show_toast("Checking " + chain_name() + "…")
	ask("chainReceipt", {"hash": hash}, func(reply):
		if page != "chain" or request_id != lookup_generation: return
		if reply.get("result") is Dictionary:
			chain_receipt = reply.result; draw_page()
		else:
			watching_hash = hash
			if reply.has("error"): notice(reply.error.message)
			else: show_toast("Waiting for the indexer…")
	)

func chain_page() -> void:
	heading("On-chain receipt", chain_name() + " indexer", true)
	if chain_receipt.is_empty():
		var query := D.field(body, "Transaction hash")
		query.text = chain_hash
		query.text_changed.connect(func(_v): watching_hash = ""; lookup_generation += 1; notice(""))
		D.button(body, "Look up", func(): lookup_receipt(query.text), "primary", "activity")
		return
	var top := D.card(body, D.SURFACE, 18, 14, 4)
	D.label(top, str(chain_receipt.execution).replace("_", " ").capitalize(), 20, D.MINT, 700)
	var rows := D.card(body, D.SURFACE, 18, 6, 0)
	kv(rows, "Block", group_digits(str(int(chain_receipt.block))))
	if chain_receipt.get("fee") != null: kv(rows, "Fee", M.units(str(chain_receipt.fee), 15) + " DUST")
	kv(rows, "Hash", middle(str(chain_receipt.hash), 8), true)
	var acts := D.row(body, 10)
	D.button(acts, "Copy hash", func(): copy(chain_hash, "Hash copied"), "secondary", "copy")
	D.button(acts, "Explorer", open_browser.bind(explorer_tx(chain_hash), "chain"), "secondary", "globe")

func open_contract(kind: String) -> void:
	if busy: return
	contract_kind = kind; token_contract = {}; go("contracts")

func open_browser(url: String, origin: String) -> void:
	if busy: return
	browser_return = origin
	explorer_url = url; browser_requested = url; browser_error = ""
	go("browser")

func url_label(url: String) -> String:
	return url.trim_prefix("https://").get_slice("/", 0)

func native_explorer() -> bool:
	return bridge != null and Engine.has_singleton("WalletEngine")

func browser_page(host: Control) -> void:
	var native_ := native_explorer() and not demo
	var bar := D.row(body, 6)
	D.button(bar, "Back to wallet screen", func(): go(browser_return), "ghost", "back", true).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pillbox := D.panel(bar, Color(1, 1, 1, 0.05), 99, D.LINE)
	pillbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pr := D.row(D.inset(pillbox, 14, 9), 6)
	D.icon(pr, "lock", D.MINT, 14)
	browser_location = D.label(pr, url_label(explorer_url), 14, D.INK, 560)
	browser_location.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	browser_location.clip_text = true
	browser_location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if native_: D.button(bar, "Reload", func(): bridge.reloadExplorer(), "ghost", "refresh", true).size_flags_horizontal = Control.SIZE_SHRINK_END
	if native_:
		browser_bounds = Control.new()
		host.add_child(browser_bounds)
		browser_bounds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		browser_bounds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		browser_bounds.offset_top = 68
		browser_bounds.resized.connect(place_browser.call_deferred)
		main_scroll.tree_exiting.connect(func(): if is_instance_valid(browser_bounds): browser_bounds.queue_free())
		place_browser.call_deferred()
	elif explorer_url.begins_with(LOCAL_APP):
		heading("mdwa test dApp")
		var group := D.list(body)
		explore_link(group, "shield", "Token contract", "Deploy and mint test tokens", open_contract.bind("token"))
		explore_link(group, "contracts", "Counter contract", "Deploy and increment a counter", open_contract.bind("counter"))
	else:
		D.button(body, "Open in browser", func(): OS.shell_open(explorer_url), "secondary", "globe")

func place_browser() -> void:
	if page != "browser" or not is_instance_valid(browser_bounds) or not native_explorer(): return
	var rect := get_viewport().get_screen_transform() * browser_bounds.get_global_rect()
	if rect.size.x < 1 or rect.size.y < 1: return
	bridge.showExplorer(browser_requested, roundi(rect.position.x), roundi(rect.position.y), roundi(rect.size.x), roundi(rect.size.y))
	browser_requested = ""

# -------------------------------------------------------------- settings ---

func toggle_row(group: Control, symbol: String, title: String, subtitle: String, on: bool, changed: Callable, enabled := true) -> void:
	var t := D.Toggle.new(on)
	var r := D.list_row(group, title, func():
		if not enabled: return
		t.set_on(not t.on)
		changed.call(t.on))
	D.badge(r, symbol, D.ACCENT if enabled else D.DIM)
	D.text_column(r, title, subtitle)
	r.add_child(t)
	if not enabled: r.modulate.a = 0.55

func link_row(group: Control, symbol: String, title: String, subtitle: String, action: Callable) -> void:
	explore_link(group, symbol, title, subtitle, action)

func settings_page() -> void:
	heading("Settings")
	var cols := columns(body) if is_wide() else [body, body]
	var left: Control = cols[0]
	var right: Control = cols[1]
	var prover_kind: String = config.get("endpoints", {}).get(network(), {}).get("prover", {}).get("kind", "wasm")
	D.label(left, "Network", 13, D.MUTED, 620)
	var net := D.list(left)
	link_row(net, "chain", "Chain", "Demo" if demo else chain_name(), navigate.bind("network"))
	link_row(net, "cpu", "Proving", "Proof server" if prover_kind == "server" else "On this phone · Vulkan", navigate.bind("proving"))
	if not demo:
		D.label(left, "Security", 13, D.MUTED, 620)
		var sec := D.list(left)
		var available: bool = biometric.get("available", false)
		toggle_row(sec, "finger", "Biometric unlock", "Fingerprint or face" if available else "Set up a fingerprint or face in Android settings", biometric.get("enabled", false), func(on):
			if on: biometric_setup()
			else:
				native("disableBiometric", [network()])
				refresh_biometric()
				show_toast("Biometric unlock is off")
		, available)
		var lock_card := D.card(sec, Color.TRANSPARENT, 14, 12, 8)
		lock_card.get_parent().get_parent().add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		D.divider(sec, 0)
		sec.move_child(sec.get_child(-1), sec.get_child_count() - 2)
		var lh := D.row(lock_card, 12)
		D.badge(lh, "lock", D.ACCENT)
		D.text_column(lh, "Auto-lock", "When Atom Wallet leaves the screen")
		D.segmented(lock_card, [[0, "Immediately"], [60, "1 min"], [300, "5 min"]], int(prefs.auto_lock), func(v):
			save_pref("auto_lock", int(v))
			native("setAutoLock", [int(v)])
			redraw_at_scroll())
		D.divider(sec, 64)
		link_row(sec, "lock", "Lock now", "", func(): command("lock", {}, func(_v): pass, "Locking…"))
	D.label(right, "Display", 13, D.MUTED, 620)
	var disp := D.list(right)
	toggle_row(disp, "eyeoff", "Hide balances on open", "Tap the eye to show them", prefs.hide_balances, func(on): save_pref("hide_balances", on))
	toggle_row(disp, "bolt", "Haptic feedback", "Ticks and confirmations", prefs.haptics, func(on): save_pref("haptics", on))
	D.label(right, "Advanced", 13, D.MUTED, 620)
	var adv := D.list(right)
	toggle_row(adv, "code", "Developer mode", "Test dApp, receipts, proof timings", prefs.developer, func(on):
		save_pref("developer", on)
		show_toast("Developer mode " + ("on" if on else "off")))
	if not demo: link_row(adv, "refresh", "Rescan wallet", "Rebuild balances and history", navigate.bind("rescan"))
	D.label(right, "About", 13, D.MUTED, 620)
	var about := D.list(right)
	var ar := D.list_row(about, "About", Callable())
	D.badge(ar, "atom", D.ACCENT)
	D.text_column(ar, "Atom Wallet " + VERSION, "Midnight wallet SDK 2.0.1 · ledger 9")
	if demo:
		D.button(right, "Exit demo", exit_demo, "secondary", "back")
	else:
		D.button(right, "Remove wallet from this phone", navigate.bind("remove"), "danger", "trash")

func biometric_setup() -> void:
	# Turning biometrics on needs the password once, to seal it with a key
	# that only a fingerprint or face can open.
	for child in body.get_children():
		if child.has_meta("bio_setup"): return
	var card := D.card(body, D.SURFACE, 16, 14, 8)
	card.get_parent().get_parent().set_meta("bio_setup", true)
	D.label(card, "Enter your password to turn on biometric unlock.", 14, D.INK, 560, true)
	var pw := D.field(card, "Wallet password", true)
	D.button(card, "Continue", func():
		if pw.text.length() < 8: notice("Enter your wallet password."); return
		var password := pw.text
		command("unlock", {"password": password}, func(_r):
			native("enableBiometric", [network(), password])
		, "Checking password…")
	, "primary", "finger")
	body.move_child(card.get_parent().get_parent(), 1)
	scroll.ensure_control_visible.call_deferred(pw)
	pw.grab_focus.call_deferred()

func network_page() -> void:
	heading("Chain", "Each chain keeps its own wallet and password.", true)
	var known := {}
	for item in live_state.get("networks", []): known[item.id] = item
	var group := D.list(body)
	for c in CHAINS:
		var id: String = c[0]
		var selected := id == network()
		var has: bool = known.get(id, {}).get("hasWallet", false)
		var r := D.list_row(group, c[1], func():
			if busy or selected or demo: return
			command("selectNetwork", {"network": id}, func(_r):
				config = {}
				show_toast("Switched to " + c[1])
				refresh()
			, "Switching to " + c[1] + "…"))
		D.badge(r, "chain", D.ACCENT if selected else D.MUTED)
		D.text_column(r, c[1], c[2] + (" · wallet ready" if has else ""))
		if selected: D.icon(r, "check", D.ACCENT, 20)
	if network() in ["preprod", "mainnet"]:
		D.section(body, "Blockfrost project ID")
		D.label(body, "Midnight's %s nodes are served by Blockfrost. Create a free %s project at blockfrost.io and paste its ID." % [chain_name(), chain_name()], 13, D.MUTED, 480, true)
		var field := D.field(body, "Project ID", true)
		field.text = str(config_draft.get("projectId", ""))
		field.context_menu_enabled = true
		D.button(body, "Save project ID", func():
			if config_draft.is_empty(): notice("Settings are still loading."); return
			config_draft["projectId"] = field.text.strip_edges()
			save_config()
		, "primary", "check")
	if authed() and not demo:
		D.section(body, "Endpoints")
		var eg := D.list(body)
		link_row(eg, "globe", "Custom endpoints", "Node and indexer for " + chain_name(), navigate.bind("connections"))

func connections_page() -> void:
	heading("Endpoints", chain_name(), true)
	if config_draft.is_empty(): D.skeleton(body, 2); return
	for item in [["node", "Node RPC", "wss://"], ["indexerHttp", "Indexer HTTP", "https://"], ["indexerWs", "Indexer WebSocket", "wss://"]]:
		D.caption(body, item[1])
		var field := D.field(body, item[2])
		field.text = config_draft[item[0]]
		field.text_changed.connect(func(v): config_draft[item[0]] = v.strip_edges())
	D.button(body, "Save endpoints", save_config, "primary", "check")
	D.button(body, "Restore defaults", func():
		for key in ["node", "indexerHttp", "indexerWs"]: config_draft[key] = config.defaults[network()][key]
		save_config()
	, "ghost", "refresh")

func proving_page() -> void:
	heading("Proving", "Zero-knowledge proofs for private transfers.", true)
	if demo: D.label(body, "Open a wallet to change proving.", 14, D.MUTED, 480, true); return
	if config_draft.is_empty(): D.skeleton(body, 1); return
	var prover: Dictionary = config_draft.prover
	D.segmented(body, [["wasm", "On this phone", "Private, Vulkan GPU"], ["server", "Proof server", "Faster on slow phones"]], prover.kind, func(kind): prover.kind = kind; redraw_at_scroll())
	if prover.kind == "server":
		var w := D.row(body, 8)
		D.icon(w, "info", D.AMBER, 16)
		D.label(w, "Private proof inputs are sent to this server.", 13, D.AMBER, 560, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var server := D.field(body, "https://")
		server.text = prover.get("url", "")
		server.text_changed.connect(func(v): prover.url = v.strip_edges())
	D.button(body, "Save proving", save_config, "primary", "check")
	if prefs.developer:
		D.section(body, "Benchmark")
		D.button(body, "Run local proof", test_local_prover, "secondary", "cpu")
		if proof_status: D.label(body, proof_status, 14, D.MINT, 560, true)

func rescan_page() -> void:
	heading("Rescan", "Rebuild balances and activity from " + chain_name() + ".", true)
	if demo: return
	D.button(body, "Rescan wallet", rescan_wallet.bind(false), "secondary", "refresh")
	if config.get("birthday"):
		D.label(body, "A full rescan also looks for private funds from before this wallet's birthday. It takes longer.", 13, D.MUTED, 480, true)
		D.button(body, "Rescan from genesis", rescan_wallet.bind(true), "ghost")

func remove_page() -> void:
	heading("Remove wallet", "This removes the %s wallet from this phone. You need your recovery phrase to restore it." % chain_name(), true)
	var password := D.field(body, "Wallet password", true)
	D.button(body, "Remove from this phone", func():
		if password.text.is_empty(): notice("Enter your password."); return
		command("resetWallet", {"password": password.text}, func(_r): native("disableBiometric", [network()]))
	, "danger", "trash")

func save_config() -> void:
	if not config_draft.node.begins_with("wss://") or not config_draft.indexerWs.begins_with("wss://") or not config_draft.indexerHttp.begins_with("https://"):
		notice("Use wss:// for WebSockets and https:// for HTTP."); return
	if config_draft.prover.kind == "server" and not str(config_draft.prover.url).begins_with("https://"):
		notice("Enter an HTTPS proof server URL."); return
	var from := page
	command("saveSettings", {"network": network(), "endpoints": config_draft}, func(_result):
		config = {}
		show_toast("Saved")
		go("network" if from in ["network", "connections"] else "settings")
	)

func rescan_wallet(from_start: bool) -> void:
	command("rescan", {"fromStart": from_start}, func(_result): config = {}; show_toast("Rescanning"); go("home"))

func test_local_prover() -> void:
	command("checkAndroidProver", {}, func(result):
		proof_status = "Proof verified in %.1f seconds." % result.seconds
		D.buzz("success")
		draw_page()
	, "Generating and verifying a local proof…")
