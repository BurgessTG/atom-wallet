extends Control

const D = preload("res://design.gd")
const M = preload("res://model.gd")
const ECLIPSE = preload("res://eclipse.gdshader")

var bridge: Object
var live_state := {}
var overview := {}
var history := []
var history_loaded := false
var history_total := 0
var history_offset := 0
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
const EXPLORER := "https://explorer.preview.midnight.network/transactions/"
var boot_error := ""
var proof_status := ""
var android_edges := []

var frame: MarginContainer
var body: VBoxContainer
var column: VBoxContainer
var header: MarginContainer
var scroll: ScrollContainer
var feedback: Label
var status_line: Label
var phrase_grid: GridContainer
var dust_balance_label: Label
var touch := preload("res://touch_scroll.gd").new()
var sheet: PanelContainer
var sheet_tween: Tween
var sheet_host: Control
var sheet_contents: MarginContainer
var scrim: ColorRect
var animate_sheet := false
var drawer_owner := "home"
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
const LOCAL_APP := "https://mdwa.local/"
const NIGHT_SCAN := "https://explorer.preview.midnight.network/"
const DRAWERS := ["send","receive","choose_token","review"]
const TABS := ["home","activity","explore","settings"]

func _ready() -> void:
	get_tree().auto_accept_quit = false
	add_child(touch)
	clock_timer = Timer.new()
	clock_timer.wait_time = .1
	clock_timer.timeout.connect(update_clocks)
	add_child(clock_timer)
	if Engine.has_singleton("WalletEngine"):
		bridge = Engine.get_singleton("WalletEngine")
		bridge.connect("message", _message)
		bridge.startEngine()
	var backdrop := ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material_ := ShaderMaterial.new()
	material_.shader = preload("res://atmosphere.gdshader")
	backdrop.material = material_
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draw_page()

func ask(method: String, params: Dictionary, done: Callable) -> void:
	if not bridge or demo: return
	seq += 1
	pending[str(seq)] = done
	bridge.request(JSON.stringify({"id":str(seq),"method":method,"params":params}))

func command(method: String, params: Dictionary, done: Callable, progress := "Working…") -> void:
	if busy: return
	busy = true
	notice(progress)
	ask(method, params, func(reply):
		busy = false
		if reply.has("error"): notice(reply.error.message)
		else: done.call(reply.result)
	)

func _message(raw: String) -> void:
	var msg = JSON.parse_string(raw)
	if not msg is Dictionary: return
	match msg.get("type", ""):
		"transaction":
			trace = msg.trace
			trace_now = int(msg.get("at",Time.get_unix_time_from_system()*1000))
			trace_ticks = Time.get_ticks_msec()
			if page in ["working","sent"]: redraw_at_scroll()
		"browser":
			if page == "browser":
				explorer_url = str(msg.get("url",explorer_url))
				browser_error = str(msg.get("error",""))
				if is_instance_valid(browser_location): browser_location.text = url_label(explorer_url)
				notice(browser_error)
		"exploreAction":
			if page == "browser" and msg.get("kind") in ["token","counter"]: open_contract(msg.kind)
		"insets":
			android_edges = msg.edges
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
			if demo and msg.type == "fatal":
				return
			wipe()
			demo = false
			go("welcome")
		"state":
			var first := live_state.is_empty()
			var had: bool = live_state.get("hasWallet", false)
			var locked: bool = live_state.get("locked", false)
			var revision = live_state.get("viewRevision", -1)
			var previous_addresses = live_state.get("addresses")
			var previous_head = live_state.get("sync",{}).get("tip")
			live_state = msg.state
			boot_error = ""
			if demo: return
			if first or had != live_state.hasWallet or locked != live_state.locked:
				wipe()
				if live_state.hasWallet: go("unlock" if live_state.locked else "home")
				else: go("welcome")
				if live_state.hasWallet and not live_state.locked:
					ask("previewTokenContract", {"kind":"token"},func(reply):
						var types = reply.get("result",{}).get("types")
						if types is Dictionary:
							known_types = types
							if page in ["home","send","choose_token"]: redraw_at_scroll()
					)
					ask("tokenLabels", {}, func(reply):
						if reply.has("result"):
							for item in reply.result:
								token_labels[item.kind + ":" + item.type] = item
							if not token_labels.is_empty() and page in ["home","send","choose_token"]: redraw_at_scroll()
					)
			elif page == "receive" and previous_addresses != live_state.get("addresses"):
				draw_page()
			elif is_instance_valid(status_line):
				status_line.text = sync_text()
			if revision != live_state.get("viewRevision",0): refresh()
			if page=="chain" and watching_hash and previous_head != live_state.get("sync",{}).get("tip"):
				lookup_receipt(watching_hash)
			if busy and page in ["review","contract_review"] and live_state.get("busy") is Dictionary:
				match live_state.busy.stage:
					"proving": notice("Generating the proof on this device…")
					"submitting": notice("Submitting to Midnight Preview…")
		_:
			var key := str(msg.get("id",""))
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
	overview = {}
	history = []
	history_loaded = false
	history_total = 0
	history_offset = 0
	preview = {}
	detail = {}
	token_labels.clear()
	recipient = ""
	amount = ""
	last_tx = ""
	receipt.clear()
	trace = {}
	recent = []
	chain_hash = ""; chain_receipt = {}; watching_hash = ""; lookup_generation += 1
	config = {}
	config_draft = {}
	explorer_url = ""; browser_requested = ""; browser_error = ""
	drawer_owner = "home"
	if native_explorer(): bridge.closeExplorer()

func go(target: String) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	if page in ["review","dust_review","contract_review"] and target != "sent" and preview.has("id") and not demo:
		ask("cancel", {"id":preview.id}, func(_reply): pass)
	if target not in ["sent","browser","chain"]: receipt = {}
	if target not in ["review","dust_review","contract_review"]: preview = {}
	if target in ["home","welcome","unlock"]:
		recipient = ""; amount = ""; words.clear()
		send_kind = "unshielded"; token_type = M.NIGHT_TYPE
	if target in DRAWERS and page not in DRAWERS:
		if page != "working": drawer_owner = page if page in TABS else "home"
		animate_sheet = true
	if page == "chain" and target != "chain":
		watching_hash = ""; lookup_generation += 1
	if page == "browser" and target != "browser" and native_explorer():
		bridge.hideExplorer()
	if target in ["connections","proving"] and page == "settings" and not config.is_empty():
		config_draft = config.get("endpoints",{}).get("preview",{}).duplicate(true)
	page = target
	draw_page()
	refresh()

func navigate(target: String) -> void:
	if not busy:
		go(target)

func back() -> void:
	if busy: return
	match page:
		"send","receive": close_drawer()
		"review": go("send")
		"connections","proving","rescan","remove": go("settings")
		"contracts": go("browser" if explorer_url.begins_with(LOCAL_APP) else "explore")
		"browser":
			if native_explorer() and bridge.explorerBack(): return
			go(browser_return)
		"working": go(trace_origin)
		"sent": go("home")
		"choose_token": go("send")
		"dust_review": go("dust")
		"contract_review": go("contracts")
		"detail": go(history_origin)
		"chain": go(chain_origin)
		"create": go("phrase")
		"restore","phrase","unlock","welcome":
			if page == "welcome" or page == "unlock": get_tree().quit()
			else: go("welcome")
		"home":
			if demo: exit_demo()
			else: get_tree().quit()
		_: go("home")

func close_drawer() -> void:
	if busy: return
	if not is_instance_valid(sheet): go(drawer_owner); return
	if sheet_tween and sheet_tween.is_valid(): sheet_tween.kill()
	sheet_tween = create_tween().set_parallel(true)
	sheet_tween.tween_property(sheet,"position:y",-sheet.size.y,.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	sheet_tween.tween_property(scrim,"modulate:a",0.0,.15)
	sheet_tween.chain().tween_callback(func(): if page in DRAWERS: go(drawer_owner))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST: back()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()

func notice(value: String) -> void:
	if is_instance_valid(feedback):
		feedback.text = value
		feedback.visible = not value.is_empty()
		if feedback.visible: scroll.ensure_control_visible.call_deferred(feedback)

func sync_text() -> String:
	if demo: return "Demo"
	var sync: Dictionary = live_state.get("sync",{})
	if overview.get("cachedAt") and sync.get("status") != "synced": return "Saved balance  ·  Syncing"
	match sync.get("status","idle"):
		"synced":
			if sync.get("headsConnected",false): return "Live  ·  Block %d" % int(sync.get("tip",0))
			return "Synced with Midnight"
		"syncing": return "Syncing  ·  %d%%" % int(sync.get("percent",0))
		"error": return str(sync.get("error","Connection interrupted"))
	return str(sync.get("error") if sync.get("error") else "Connecting to Preview…")

func refresh() -> void:
	if demo or not bridge or not live_state.get("hasWallet") or live_state.get("locked"): return
	if refreshing:
		refresh_again = true
		return
	if page in ["settings","connections","proving","rescan","remove"]:
		if config.is_empty() and not refreshing:
			refreshing = true
			ask("settings",{},func(reply):
				refreshing = false
				if reply.get("result") is Dictionary:
					config = reply.result
					if page in ["settings","connections","proving","rescan","remove"]:
						config_draft = config.get("endpoints",{}).get("preview",{}).duplicate(true)
						redraw_at_scroll()
				elif page == "settings": notice(reply.error.message)
				if refresh_again:
					refresh_again = false; refresh.call_deferred()
			)
		return
	if busy or page not in ["home","dust","activity","send","contracts","detail","choose_token","sent"]: return
	var target := page
	var offset := history_offset
	refreshing = true
	var method: String = {"home":"walletHome","activity":"history","contracts":"previewTokenContract","detail":"activityItem","sent":"activityItem"}.get(target,"overview")
	var params := {"offset":offset,"limit":12} if method == "history" else ({"hash":last_tx if target == "sent" else detail.get("hash","")} if method == "activityItem" else {})
	var selected_kind := contract_kind
	if target == "sent" and last_tx.is_empty(): refreshing = false; return
	if target == "contracts": params = {"kind":selected_kind}
	ask(method, params, func(reply):
		refreshing = false
		if refresh_again:
			refresh_again = false
			refresh.call_deferred()
		if page != target or demo or busy or history_offset != offset or (target == "contracts" and selected_kind != contract_kind): return
		if reply.has("error"):
			if target in ["activity","contracts"] or overview.is_empty(): notice(reply.error.message)
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
			var latest: Dictionary = reply.result.get("overview",{}) if target == "home" else reply.result
			var recent_changed := false
			if target == "home":
				recent_changed = recent != reply.result.get("recent",[])
				recent = reply.result.get("recent",[])
			if overview == latest and not recent_changed: return
			var old_tokens: Array = overview.get(send_kind, [])
			var previous := overview
			overview = latest
			if not recent_changed and target in ["home", "dust"] and only_dust_balance_changed(previous, overview) and is_instance_valid(dust_balance_label):
				dust_balance_label.text = short_dust() if target == "home" else M.units(overview.dust.balance,15)
			elif target != "send" or old_tokens != overview.get(send_kind, []):
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
	var amount_text := M.units(overview.dust.balance,15)
	var point := amount_text.find(".")
	if point < 0 or amount_text.length() <= point+5: return amount_text
	if amount_text.begins_with("0.0000"): return "<0.0001"
	return amount_text.left(point+5).rstrip("0").trim_suffix(".")

func redraw_at_scroll() -> void:
	var offset := scroll.scroll_vertical
	draw_page()
	scroll.set_deferred("scroll_vertical", offset)

func enter_demo() -> void:
	if busy: return
	demo = true
	wipe()
	overview = M.SAMPLE.duplicate(true)
	history = M.HISTORY.duplicate(true)
	recent = history.slice(0,3)
	history_total = history.size()
	history_loaded = true
	go("home")

func exit_demo() -> void:
	demo = false
	wipe()
	go("unlock" if live_state.get("hasWallet") else "welcome")

func draw_page() -> void:
	if sheet_tween and sheet_tween.is_valid(): sheet_tween.kill()
	if is_instance_valid(frame):
		remove_child(frame); frame.queue_free()
	status_line = null; phrase_grid = null; dust_balance_label = null
	sheet = null; browser_bounds = null; browser_location = null
	clocks.clear()
	clock_timer.stop()
	frame = MarginContainer.new()
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	update_insets()
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(center)
	column = D.vbox(center,0)
	column.custom_minimum_size.x = minf(maxf(100,size.x-frame.get_theme_constant("margin_left")-frame.get_theme_constant("margin_right")),560)
	header = D.inset(column,16,2)
	update_header()
	var top := D.row(header,5)
	D.icon(top,"mark",D.ACCENT,23)
	D.label(top,"mdwa",22,D.INK,730)
	D.label(top,"Demo" if demo else "Preview",12,D.MUTED,510)
	D.space(top,0,true)
	var authed: bool = demo or (live_state.get("hasWallet",false) and not live_state.get("locked",true))
	if authed:
		for item in [["receive","Receive","qr"],["send","Send","plane"]]:
			var action := D.button(top,item[1],navigate.bind(item[0]),"quiet",item[2],true)
			action.size_flags_horizontal = Control.SIZE_SHRINK_END
			action.disabled = busy
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	column.add_child(stage)
	var drawer := page in DRAWERS
	var main_page := drawer_owner if drawer else page
	scroll = make_scroll(stage)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body = page_body(scroll)
	match main_page:
		"welcome","unlock": welcome()
		"phrase","restore","create": onboarding()
		"home": home()
		"dust","dust_review": dust_page()
		"activity": activity_page()
		"detail": detail_page()
		"chain": chain_page()
		"working","sent": progress_page()
		"explore": explore_page()
		"browser": browser_page(stage)
		"contracts","contract_review": contracts_page()
		"token_label": label_page()
		"settings","connections","proving","rescan","remove": settings_page()
	if authed and (drawer or main_page in TABS or main_page in ["dust","contracts","browser","detail"]):
		var nav_panel := D.glass_panel(D.inset(column,14,4),D.SURFACE,24)
		var nav := D.row(D.inset(nav_panel,6,3),4)
		var selected: String = {"contracts":"explore","browser":"explore","dust":"home","detail":history_origin}.get(main_page,main_page)
		for item in [["home","Wallet","wallet"],["activity","Activity","activity"],["explore","Explore","explore"],["settings","Settings","shield"]]:
			var b := D.button(nav,item[1],navigate.bind(item[0]),"primary" if selected==item[0] else "quiet",item[2],true)
			b.disabled = busy
	if drawer:
		show_drawer(stage)
		if page == "receive": receive_page()
		else: send_page()
	feedback = D.label(body,"",13,Color("#ffbb9c"),510,true)
	feedback.hide()
	touch.area = scroll
	if drawer: fit_drawer.call_deferred()
	if page == "browser" and browser_error: notice(browser_error)
	if page in ["review","dust_review","contract_review"] and trace.get("status")=="review":
		timeline(trace,true)
	if not clocks.is_empty(): update_clocks(); clock_timer.start()

func make_scroll(parent: Control) -> ScrollContainer:
	var view := ScrollContainer.new()
	view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	view.follow_focus = true
	parent.add_child(view)
	return view

func page_body(view: ScrollContainer) -> VBoxContainer:
	var margin := D.inset(view,16,8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return D.vbox(margin,8)

func show_drawer(stage: Control) -> void:
	sheet_host = stage
	scrim = ColorRect.new()
	scrim.color = Color(0.015,0.035,0.04,.78)
	stage.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e): if e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_LEFT and not e.pressed: close_drawer())
	sheet = PanelContainer.new()
	sheet.add_theme_stylebox_override("panel",D.style(Color("#17262b"),20,D.LINE))
	stage.add_child(sheet)
	sheet.anchor_right = 1.0
	scroll = make_scroll(sheet)
	body = page_body(scroll)
	sheet_contents = body.get_parent()
	sheet_contents.minimum_size_changed.connect(fit_drawer.call_deferred)
	stage.resized.connect(fit_drawer.call_deferred)

func fit_drawer() -> void:
	if not is_instance_valid(sheet) or not sheet.is_inside_tree(): return
	sheet.offset_bottom = sheet.offset_top + minf(sheet_host.size.y, sheet_contents.get_combined_minimum_size().y+6)
	if animate_sheet and sheet.size.y > 20:
		animate_sheet = false
		sheet.position.y = -sheet.size.y
		scrim.modulate.a = 0
		sheet_tween = create_tween().set_parallel(true)
		sheet_tween.tween_property(sheet,"position:y",0.,.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		sheet_tween.tween_property(scrim,"modulate:a",1.,.18)

func _on_size_changed() -> void:
	if not is_instance_valid(frame) or not is_instance_valid(column): return
	update_insets()
	column.custom_minimum_size.x = minf(maxf(100,size.x - frame.get_theme_constant("margin_left") - frame.get_theme_constant("margin_right")),560)
	update_header()
	if is_instance_valid(phrase_grid):
		phrase_grid.columns = 2 if column.custom_minimum_size.x < 360 else 3

func update_header() -> void:
	if is_instance_valid(header):
		header.visible = size.y - frame.get_theme_constant("margin_top") - frame.get_theme_constant("margin_bottom") >= 240

func update_insets() -> void:
	var margins := [0,0,0,0]
	var scale_factor := get_viewport().get_screen_transform().get_scale()
	if android_edges.size() == 4:
		margins = [ceili(android_edges[0]/scale_factor.x), ceili(android_edges[1]/scale_factor.y), ceili(android_edges[2]/scale_factor.x), ceili(android_edges[3]/scale_factor.y)]
	elif OS.get_name() == "Android":
		var safe := DisplayServer.get_display_safe_area()
		var win := DisplayServer.window_get_size()
		var origin := DisplayServer.window_get_position()
		if win.x > 0 and safe.size.x > 0:
			margins = [maxi(0,roundi((safe.position.x-origin.x)/scale_factor.x)),maxi(0,roundi((safe.position.y-origin.y)/scale_factor.y)),maxi(0,roundi((win.x+origin.x-safe.end.x)/scale_factor.x)),maxi(0,roundi((win.y+origin.y-safe.end.y)/scale_factor.y))]
	for i in 4: frame.add_theme_constant_override("margin_"+["left","top","right","bottom"][i],margins[i])

func heading(title: String, subtitle := "", back_button := false) -> void:
	var h := D.row(body,6)
	if back_button and page not in DRAWERS:
		D.button(h,"Back",back,"quiet","back",true).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	D.label(h,title,23,D.INK,650,true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if page in DRAWERS:
		D.button(h,"Back",back,"quiet","close" if page in ["send","receive"] else "back",true).size_flags_horizontal = Control.SIZE_SHRINK_END
	if subtitle: D.label(body,subtitle,13,D.MUTED,450,true)

func artwork(height: int, centered := false) -> Control:
	var art := ColorRect.new()
	art.custom_minimum_size.y = height
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = ECLIPSE
	mat.set_shader_parameter("centered",float(centered))
	art.material = mat
	body.add_child(art)
	art.resized.connect(func(): mat.set_shader_parameter("canvas_size", art.size))
	return art

func welcome() -> void:
	var locked := page == "unlock"
	artwork(220,true)
	heading("Unlock your wallet" if locked else "Your Midnight wallet.", "Enter your wallet password to continue." if locked else "Send and receive NIGHT, manage DUST, and follow your activity on Midnight Preview.")
	if locked:
		var pw := D.field(body,"Wallet password",true)
		var submit := func():
			if pw.text.is_empty(): notice("Enter your password."); return
			command("unlock",{"password":pw.text},func(_result): pass,"Unlocking…")
		D.button(body,"Unlock wallet",submit,"primary","lock")
		pw.text_submitted.connect(func(_s): submit.call())
	else:
		var ready := not live_state.is_empty()
		var create := D.button(body,"Create wallet",func():
			command("generateMnemonic",{},func(result):
				words = PackedStringArray(result.words)
				go("phrase")
			)
		,"primary","wallet")
		var restore := D.button(body,"Restore wallet",func(): go("restore"))
		for b in [create,restore]:
			b.disabled = not ready
			if b.disabled: b.modulate.a = .48
		if not ready:
			var explanation := "Open the Android app to create or restore a wallet." if not bridge else "Starting the wallet engine…"
			D.label(body, boot_error if boot_error else explanation, 13, D.MUTED, 450, true)
			if boot_error and bridge: D.button(body,"Retry",func(): boot_error = ""; draw_page(); bridge.retryEngine())
		D.button(body,"Explore demo wallet",enter_demo,"quiet","next")
		if ready:
			D.button(body,"Test local prover",test_local_prover,"quiet","shield")
			if proof_status: D.label(body,proof_status,14,D.MUTED,450,true)

func onboarding() -> void:
	if page == "phrase":
		heading("Recovery phrase","Write down these words in order. Anyone with this phrase can access your wallet.",true)
		var g := GridContainer.new()
		phrase_grid = g
		g.columns = 2 if column.custom_minimum_size.x < 360 else 3
		body.add_child(g)
		for i in words.size():
			var cell := D.card(g,D.SURFACE,8,7)
			cell.get_parent().get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
			D.label(cell,"%02d  %s" % [i+1,words[i]],12,D.INK,550)
		D.button(body,"I saved my phrase",func(): go("create"),"primary")
		return
	var restore := page == "restore"
	heading("Restore wallet" if restore else "Secure your wallet","Your password unlocks this wallet on this device.",true)
	var phrase: LineEdit
	if restore:
		D.label(body,"Recovery phrase",14,D.MUTED)
		phrase = D.field(body,"Words in order, separated by spaces",true)
		phrase.context_menu_enabled = true
	else:
		D.label(body,"Confirm the last word of your recovery phrase",14,D.MUTED,450,true)
		phrase = D.field(body,"Last word",true)
	D.label(body,"Wallet password",14,D.MUTED)
	var pw := D.field(body,"At least 8 characters",true)
	var confirm := D.field(body,"Confirm password",true)
	D.button(body,"Restore wallet" if restore else "Create wallet",func():
		if not restore and (words.is_empty() or phrase.text.strip_edges() != words[-1]):
			notice("Check the last word of your recovery phrase."); return
		if pw.text.length() < 8 or pw.text != confirm.text:
			notice("Enter matching passwords of at least 8 characters."); return
		var mnemonic := phrase.text.strip_edges() if restore else " ".join(words)
		command("createWallet",{"mnemonic":mnemonic,"password":pw.text,"restore":restore},func(_v): pass,"Opening your wallet…")
	,"primary")

func home() -> void:
	var balance_text := M.units(overview.night.available,6) if overview.has("night") else "—"
	var hero := D.card(body,Color("#173432"),17,13)
	D.label(hero,"Available NIGHT",13,D.MUTED,510)
	D.label(hero,balance_text,40 if balance_text.length()<13 else 23,D.INK,650,true)
	if not demo: status_line = D.label(hero,sync_text(),12,D.MUTED,470,true)
	D.label(body,"Assets",17,D.INK,630)
	if overview.is_empty(): D.label(body,"Syncing balances…",14,D.MUTED); return
	var assets := D.card(body,D.SURFACE,10,0)
	asset_row(assets,"night","NIGHT","Unshielded",balance_text,Callable(),"")
	for kind in ["shielded","unshielded"]:
		for coin in overview.get(kind,[]):
			if kind == "unshielded" and coin.type == M.NIGHT_TYPE: continue
			var asset := describe_asset(kind,coin.type)
			var change_label := func(): label_asset = {"kind":kind,"type":coin.type}; go("token_label")
			D.divider(assets)
			asset_row(assets,"shield" if kind=="shielded" else "contracts",asset.unit if asset.unit!="base units" else asset.name,kind.capitalize(),M.units(coin.amount,asset.decimals),Callable() if demo else change_label,"Edit token label")
	D.divider(assets)
	dust_balance_label = asset_row(assets,"dust","DUST","Network fees",short_dust(),navigate.bind("dust"),"DUST generation")
	if not recent.is_empty():
		D.label(body,"Recent activity",17,D.INK,630)
		var group := D.card(body,D.SURFACE,10,0)
		for tx in recent: history_row(group,tx,"home")

func asset_row(parent: Control, symbol: String, title: String, subtitle: String, value: String, action: Callable, accessible: String) -> Label:
	var row := D.list_row(parent,accessible,action)
	D.icon(row,symbol,D.GREEN if symbol == "dust" else D.ACCENT,24)
	var names := D.vbox(row,0)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D.label(names,title,15,D.INK,610,true)
	D.label(names,subtitle,12,D.MUTED)
	var number := D.label(row,value,16,D.INK,600,true)
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if action.is_valid(): D.icon(row,"next",D.DIM,13)
	return number

func history_row(parent: Control, tx: Dictionary, origin: String) -> void:
	if parent.get_child_count(): D.divider(parent)
	var row := D.list_row(parent,"Details",func(): history_origin = origin; detail=tx; go("detail"))
	D.icon(row,"receive" if tx.kind=="receive" else ("dust" if tx.kind=="dust" else "plane"),D.ACCENT,21)
	var description := D.vbox(row,0)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D.label(description,tx_title(tx),14,D.INK,590,true)
	D.label(description,receipt_status(tx),12,D.MUTED)
	for change in tx.get("deltas",[]):
		if change.kind != "dust":
			var asset := describe_asset(change.kind,change.type)
			var sign_text := "+" if not str(change.amount).begins_with("-") else ""
			var delta := D.label(row,sign_text+asset_amount(change.amount,asset),13,D.ACCENT,540,true)
			delta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			break
	D.icon(row,"next",D.DIM,13)

func dust_page() -> void:
	if page == "dust_review":
		var registering: bool = preview.action == "register"
		heading("Register NIGHT" if registering else "Stop generation","Review the NIGHT outputs and fee before confirming.",true)
		var summary := D.card(body)
		D.label(summary,"Network fee",13,D.MUTED)
		D.label(summary,M.units(str(preview.fee),15)+" DUST",22,D.INK,630,true)
		for output in preview.utxos:
			D.label(summary,M.units(output.amount,6)+" NIGHT",16,D.INK,580,true)
			D.label(summary,str(output.ref),12,D.MUTED,420,true)
		if not preview.canPay:
			D.label(body,"More DUST is needed to pay this fee. Go back and check again once it has accumulated.",14,D.MUTED,450,true)
			return
		D.button(body,"Confirm registration" if registering else "Confirm deregistration",func():
			if demo: go("dust"); notice("Demo review complete."); return
			submit_review("dustApply")
		,"primary")
		return
	heading("DUST generation","Registered NIGHT generates the DUST used to pay network fees.",true)
	if overview.is_empty(): return
	var box := D.card(body)
	for line in [["Available DUST","balance",15],["Generation cap","cap",15],["Registered NIGHT","registeredNight",6],["Unregistered NIGHT","unregisteredNight",6]]:
		D.label(box,line[0],12,D.MUTED)
		var value := D.label(box,M.units(overview.dust[line[1]],line[2]),19,D.INK,640,true)
		if line[1] == "balance": dust_balance_label = value

	for action in ["register","deregister"]:
		var key := "unregisteredNight" if action == "register" else "registeredNight"
		if overview.dust[key] == "0": continue
		D.button(body,"Register NIGHT" if action == "register" else "Stop generation",func():
			if demo:
				preview = {"action":action,"canPay":true,"fee":"250000000000000","utxos":[{"ref":"Sample output","amount":overview.dust[key]}]}
				go("dust_review")
				return
			prepare_review("dustPreview",{"action":action},"dust_review")
		,"normal")

func activity_page() -> void:
	heading("Activity")
	if history.is_empty():
		var empty := D.card(body)
		D.label(empty,"No transactions to show" if history_loaded else "Loading transactions…",18,D.INK,600)
		status_line = D.label(empty,sync_text(),14,D.MUTED,450,true)
		return
	var group := D.card(body,D.SURFACE,10,0)
	for tx in history: history_row(group,tx,"activity")
	if history_total > 12:
		var pager := D.row(body)
		for step in [-12,12]:
			var offset: int = history_offset + step
			var b := D.button(pager,"Previous" if step < 0 else "Next",func(): history_offset=offset; refresh())
			b.disabled = offset < 0 or offset >= history_total

func tx_title(tx: Dictionary) -> String:
	if tx.get("kind") == "dapp": return contract_title(tx.get("action","Contract transaction"))
	return {"receive":"Received","send":"Sent","dust":"DUST registration" if tx.get("action") != "deregister" else "DUST deregistration"}.get(tx.kind,"Transaction")

func detail_page() -> void:
	heading(tx_title(detail),receipt_status(detail),true)
	if detail.get("timeline") is Dictionary: timeline(detail.timeline)
	var info := D.card(body)
	D.label(info,"Transaction ID",13,D.MUTED)
	D.label(info,str(detail.hash),15,D.INK,500,true)
	if not demo and str(detail.hash).length() == 64 and str(detail.hash).is_valid_hex_number(false):
		D.button(info,"On-chain receipt",open_receipt.bind(str(detail.hash),"detail"),"normal","check")
		D.button(info,"View on explorer",open_browser.bind(EXPLORER+str(detail.hash),"detail"),"quiet","explore")
	if detail.get("block") != null: D.label(info,"Block "+str(int(detail.block)),14,D.MUTED)
	if detail.get("time"):
		D.label(info,Time.get_datetime_string_from_unix_time(int(detail.time/1000.0),true)+" UTC",13,D.MUTED)
	for change in detail.get("deltas",[]):
		var asset := describe_asset(change.kind, change.type)
		D.label(info,asset_amount(change.amount, asset),16,D.INK,550,true)
		if change.kind == "shielded" or (change.kind == "unshielded" and change.type != M.NIGHT_TYPE):
			D.label(info,change.type,13,D.MUTED,450,true)

func wallet_address(kind: String) -> String:
	var addresses = live_state.get("addresses")
	return str(addresses.get(kind, "")) if addresses is Dictionary else ""

func receive_page() -> void:
	heading("Receive","",true)
	var kinds := D.row(body,4)
	for kind in ["unshielded","shielded","dust"]:
		D.button(kinds,"DUST" if kind=="dust" else kind.capitalize(),func(): receive_kind=kind; draw_page(),"primary" if kind==receive_kind else "normal")
	var about: String = {"shielded":"For private tokens.","unshielded":"For NIGHT and other public tokens.","dust":"For directing DUST generation to this wallet."}[receive_kind]
	var panel := D.card(body)
	D.label(panel,about,13,D.MUTED,500,true)
	if demo:
		D.label(panel,"Demo addresses cannot receive funds. Open a Preview wallet to show its address and QR code.",14,D.MUTED,450,true)
		return
	var address := wallet_address(receive_kind)
	if address.is_empty():
		D.label(panel,"Waiting for the wallet address…",14,D.MUTED,450,true)
		return
	var qr_box := CenterContainer.new()
	panel.add_child(qr_box)
	var qr := TextureRect.new()
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.custom_minimum_size = Vector2(192,192)
	qr_box.add_child(qr)
	ask("qr",{"address":address},func(reply):
		if not is_instance_valid(qr) or not qr.is_inside_tree(): return
		if not reply.has("result"):
			qr_box.hide()
			notice("The QR code could not be loaded. You can still copy the address.")
			return
		var rows: Array = reply.result.rows
		var img := Image.create_empty(rows.size()+8,rows.size()+8,false,Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		for y in rows.size():
			for x in rows.size():
				if rows[y][x]=="1": img.set_pixel(x+4,y+4,Color.BLACK)
		qr.texture = ImageTexture.create_from_image(img)
	)
	D.label(panel,address,12,D.MUTED,450,true)
	D.button(body,"Copy address",func(): DisplayServer.clipboard_set(address); notice("Address copied."),"primary","copy")

func send_page() -> void:
	if page == "review":
		heading("Review transfer","",true)
		var box := D.card(body)
		var output: Dictionary = preview.outputs[0]
		var asset := describe_asset(output.kind, output.type)
		var entries := [["You send",asset_amount(output.amount, asset)],["Transfer",str(output.kind).capitalize()],["Recipient",output.recipient]]
		if output.kind == "shielded" or output.type != M.NIGHT_TYPE:
			entries.append(["Token ID",output.type])
		entries.append_array([["Network","Demo" if demo else "Midnight Preview"],["Estimated fee",M.units(str(preview.fee),15)+" DUST"]])
		for entry in entries:
			D.label(box,entry[0],13,D.MUTED)
			D.label(box,entry[1],17,D.INK,580,true)
		D.button(body,"Finish demo" if demo else "Confirm and send",func():
			if demo: go("sent"); return
			submit_review("send")
		,"primary","send")
		return
	var held: Array = overview.get(send_kind, []).filter(func(c): return str(c.amount) != "0")
	if page == "choose_token":
		heading("Choose a token",send_kind.capitalize()+" assets in this wallet.",true)
		for coin in held:
			var asset := describe_asset(send_kind, coin.type)
			var panel := D.card(body)
			D.label(panel,asset.name,17,D.INK,620,true)
			D.label(panel,coin.type,13,D.MUTED,450,true)
			D.label(panel,asset_amount(coin.amount, asset),15,D.INK,500,true)
			D.button(panel,"Select",func(): token_type=coin.type; amount=""; go("send"))
		return
	heading("Send","",true)
	var modes := D.row(body,6)
	for kind in ["unshielded","shielded"]:
		D.button(modes,kind.capitalize(),select_send_kind.bind(kind),"primary" if send_kind == kind else "normal")
	var index := held.find_custom(func(coin): return coin.type == token_type)
	if index < 0:
		token_type = "" if held.is_empty() else str(held[0].type)
		amount = ""
		index = 0
	if held.is_empty():
		if overview.is_empty():
			D.label(body,"Loading available balances…",15,D.MUTED,500,true)
		else:
			var empty := D.card(body)
			D.label(empty,"No "+send_kind+" tokens available",19,D.INK,620,true)
			D.label(empty,"Receive a token at your "+send_kind+" address to send it from this wallet.",15,D.MUTED,450,true)
			D.button(body,"Receive "+send_kind+" tokens",func(): receive_kind=send_kind; go("receive"),"primary","receive")
		return
	var coin: Dictionary = held[index]
	var selected := describe_asset(send_kind,token_type)
	var asset_box := D.card(body)
	D.label(asset_box,"Available   "+asset_amount(coin.amount,selected),15,D.INK,570,true)
	if held.size() > 1: D.button(asset_box,"Choose token",func(): navigate("choose_token"),"quiet")
	D.label(body,"Recipient address",14,D.MUTED)
	var address_field := D.field(body,send_kind.capitalize()+" address")
	address_field.text = recipient
	address_field.text_changed.connect(func(value): recipient = value)
	if not demo:
		var shortcuts := D.row(body,4)
		D.button(shortcuts,"Paste",func():
			var text := DisplayServer.clipboard_get().strip_edges()
			if text.is_empty(): notice("Clipboard is empty."); return
			recipient = text; address_field.text = text
		,"quiet","copy")
		var own_address := wallet_address(send_kind)
		if not own_address.is_empty():
			D.button(shortcuts,"Use my address",func(): recipient = own_address; address_field.text = recipient,"quiet")
	D.label(body,"Amount in "+selected.unit,14,D.MUTED)
	var value_field := D.field(body,"0" if selected.decimals == 0 else "0.00")
	value_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	value_field.text = amount
	value_field.text_changed.connect(func(value): amount = value)
	if demo:
		D.button(body,"Use sample transfer",func():
			recipient="Demo recipient"; amount="1" if send_kind=="shielded" else "12.50"
			address_field.text=recipient; value_field.text=amount
		,"quiet")
	D.button(body,"Review transfer",func():
		recipient = address_field.text.strip_edges()
		amount = value_field.text.strip_edges()
		var atomic := M.atomic_amount(amount,selected.decimals)
		if recipient.is_empty() or atomic.is_empty():
			notice("Enter a recipient and a positive whole number." if selected.decimals == 0 else "Enter a recipient and a positive amount with up to %d decimal places." % selected.decimals); return
		if M.exceeds(atomic,coin.amount):
			notice("This exceeds the available balance."); return
		var outputs := [{"recipient":recipient,"kind":send_kind,"type":token_type,"amount":atomic}]
		if demo:
			if recipient != "Demo recipient": notice("Use the sample recipient in demo mode."); return
			preview={"outputs":outputs,"fee":"250000000000000"}
			go("review"); return
		prepare_review("previewSend",{"outputs":outputs},"review")
	,"primary","send")

func select_send_kind(kind: String) -> void:
	if busy or send_kind == kind: return
	send_kind = kind
	token_type = M.NIGHT_TYPE if kind == "unshielded" else ""
	amount = ""
	recipient = ""
	go("send")

func asset_amount(raw: String, asset: Dictionary) -> String:
	var unit: String = asset.unit
	if unit == "base units" and raw.trim_prefix("-") == "1": unit = "base unit"
	return M.units(raw, asset.decimals) + " " + unit

func describe_asset(kind: String, type: String) -> Dictionary:
	if kind == "dust":
		return {"name":"DUST", "unit":"DUST", "decimals":15}
	if kind == "unshielded" and type == M.NIGHT_TYPE:
		return {"name":"Midnight", "unit":"NIGHT", "decimals":6}
	if demo and type == M.DEMO_TYPE:
		return {"name":"Demo token", "unit":"DEMO", "decimals":0}
	var metadata: Dictionary = token_labels.get(kind + ":" + type, {})
	if metadata.is_empty() and known_types.get(kind) == type:
		return {"name":"Shielded Preview token" if kind == "shielded" else "Public Preview token","unit":"sTEST" if kind == "shielded" else "uTEST","decimals":0}
	return {"name":metadata.get("name", "Token " + type.left(6) + "…" + type.right(6)), "unit":metadata.get("symbol", "base units"), "decimals":int(metadata.get("decimals",0))}

func label_page() -> void:
	heading("Edit token label","This name appears in your wallet.",true)
	var previous: Dictionary = token_labels.get(label_asset.kind+":"+label_asset.type,{})
	D.label(body,label_asset.type,13,D.MUTED,480,true)
	D.label(body,"Name",14,D.MUTED)
	var token_name := D.field(body,"Token name")
	token_name.text = previous.get("name","")
	D.label(body,"Symbol",14,D.MUTED)
	var symbol := D.field(body,"Symbol")
	symbol.text = previous.get("symbol","")
	D.label(body,"Decimal places",14,D.MUTED)
	var decimals := D.field(body,"0")
	decimals.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	decimals.text = str(previous.get("decimals",0))
	D.button(body,"Save label",func():
		if not decimals.text.is_valid_int(): notice("Enter whole decimal places."); return
		var values := label_asset.duplicate()
		values.merge({"name":token_name.text,"symbol":symbol.text,"decimals":int(decimals.text)})
		command("setTokenLabel",values,func(result):
			token_labels[result.kind+":"+result.type] = result
			go("home")
		)
	,"primary","check")

func contracts_page() -> void:
	if page == "contract_review":
		heading("Review contract action","",true)
		var summary := D.card(body)
		for pair in [["Action",contract_title(preview.action)],["Network","Midnight Preview"],["Contract",preview.address],["Estimated fee",M.units(preview.fee,15)+" DUST"]]:
			D.label(summary,pair[0],13,D.MUTED)
			D.label(summary,pair[1],16,D.INK,560,true)
		if preview.action in ["mintShielded","mintUnshielded"]:
			D.label(summary,preview.amount+" to your "+("shielded" if preview.action == "mintShielded" else "unshielded")+" address",16,D.INK,580,true)
		D.button(body,{"deploy":"Confirm deployment","increment":"Confirm increment"}.get(preview.action,"Confirm mint"),func():
			submit_review("submitTokenAction")
		,"primary","check")
		return
	heading("Token contract" if contract_kind == "token" else "Counter contract","mdwa.local",true)
	var choices := D.row(body,6)
	for kind in ["token","counter"]:
		D.button(choices,kind.capitalize(),func():
			if busy or contract_kind == kind: return
			contract_kind = kind; token_contract = {}; go("contracts")
		,"primary" if contract_kind == kind else "normal")
	var panel := D.card(body)
	D.label(panel,"Preview test token" if contract_kind == "token" else "Public counter",19,D.INK,650,true)
	if demo:
		D.label(panel,"Open your Preview wallet to deploy and mint tokens.",15,D.MUTED,450,true)
		return
	if token_contract.is_empty():
		D.label(panel,"Loading contract…",15,D.MUTED)
		return
	if not token_contract.get("address"):
		D.label(panel,"Deploy once to mint shielded and unshielded test tokens to this wallet." if contract_kind == "token" else "Deploy a counter that anyone can read or increment on Preview.",15,D.MUTED,450,true)
		D.button(body,"Deploy contract",prepare_contract.bind("deploy"),"primary","contracts")
		return
	D.label(panel,token_contract.address,14,D.MUTED,500,true)
	D.button(panel,"Copy contract address",func(): DisplayServer.clipboard_set(token_contract.address); notice("Contract address copied."),"quiet","copy")
	if token_contract.get("pending"):
		D.label(panel,"Confirmation is pending after an interrupted submission.",14,D.MUTED,450,true)
		D.button(panel,"Check submission",func():
			command("recoverTokenAction",{"kind":contract_kind},func(result):
				refresh(); notice(result.get("message","Submission checked."))
			,"Checking the indexer…")
		,"primary")
		return
	if token_contract.get("value") is Dictionary and token_contract.value.has("error"):
		D.label(panel,token_contract.value.error,14,D.MUTED,450,true)
	elif token_contract.get("value") is Dictionary:
		D.label(panel,("Mints" if contract_kind == "token" else "Count")+"  ·  "+str(token_contract.value.count),18,D.INK,620)
		D.label(panel,"At block %d" % int(token_contract.value.block),13,D.MUTED)
	if contract_kind == "counter":
		D.button(body,"Increment counter",prepare_contract.bind("increment"),"primary","contracts")
		return
	D.label(body,"Amount to mint",14,D.MUTED)
	var quantity := D.field(body,"Whole tokens")
	quantity.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	quantity.text = mint_amount
	quantity.text_changed.connect(func(value): mint_amount = value)
	D.button(body,"Mint shielded",prepare_contract.bind("mintShielded"),"primary","shield")
	D.button(body,"Mint unshielded",prepare_contract.bind("mintUnshielded"),"normal","receive")

func contract_title(action: String) -> String:
	return {"deploy":"Deploy contract","increment":"Increment counter","mintShielded":"Mint shielded tokens","mintUnshielded":"Mint unshielded tokens"}.get(action,action)

func prepare_contract(action: String) -> void:
	var quantity := M.atomic_amount(mint_amount,0) if action in ["mintShielded","mintUnshielded"] else "1"
	if quantity.is_empty():
		notice("Enter a positive whole number."); return
	prepare_review("prepareTokenAction",{"kind":contract_kind,"action":action,"amount":quantity},"contract_review")

func prepare_review(method: String, params: Dictionary, review_page: String) -> void:
	if busy: return
	trace_origin = page
	trace = {}
	last_tx = ""
	busy = true
	go("working")
	ask(method,params,func(reply):
		busy = false
		if reply.has("error"):
			fail_transaction(reply.error.message)
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
	ask(method,{"id":id},func(reply):
		busy = false
		preview = {}
		if reply.has("error"):
			fail_transaction(reply.error.message)
			return
		last_tx = reply.result.txId
		draw_page()
		refresh()
	)

func fail_transaction(reason: String) -> void:
	trace["status"] = "error"
	trace["error"] = reason
	draw_page()

func receipt_status(item: Dictionary) -> String:
	if item.get("partial",false): return "Partially successful"
	return str(item.get("status","")).capitalize()

func duration_label(parent: Control, start, end_time, px: int, color: Color) -> void:
	var text := D.label(parent,"",px,color,570)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	text.custom_minimum_size.x = 47
	if end_time != null: text.text = seconds_text(int(end_time)-int(start))
	else: clocks.append({"label":text,"start":int(start)})

func seconds_text(ms: int) -> String:
	var seconds := maxf(0.,ms/1000.)
	return "%.1fs" % seconds if seconds < 60 else "%dm %02ds" % [int(seconds/60),int(seconds)%60]

func update_clocks() -> void:
	var now := trace_now + Time.get_ticks_msec()-trace_ticks
	for clock in clocks: clock.label.text = seconds_text(now-clock.start)

func timeline(record: Dictionary, awaiting := false) -> void:
	if not record.has("start"): return
	var group := D.card(body)
	var header_row := D.row(group)
	D.label(header_row,"Elapsed",13,D.MUTED,520).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_label(header_row,record.start,null if awaiting else record.get("end"),19,D.ACCENT)
	for step in record.get("steps",[]):
		D.divider(group)
		var row := D.row(group,6)
		var done: bool = step.has("end") and not (awaiting and step.name=="Awaiting approval")
		D.icon(row,"check" if done else "activity",D.DIM if done else D.ACCENT,15)
		D.label(row,step.name,14,D.INK,550,true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		duration_label(row,step.start,step.get("end") if done else null,13,D.MUTED)
		var proofs: Array = step.get("proofs",[])
		for proof in proofs:
			var sub := D.row(group)
			D.space(sub,0).custom_minimum_size.x = 16
			var name_ := "GPU · "+str(proof.name)
			if proof.get("failed"): name_ += " · Failed"
			D.label(sub,name_,12,D.MUTED,470,true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			duration_label(sub,proof.start,proof.get("end"),12,D.MUTED)

func progress_page() -> void:
	if demo:
		heading("Review complete")
		D.button(body,"Back to wallet",navigate.bind("home"),"primary")
		return
	var failed: bool = trace.get("status")=="error"
	var state_text := receipt_status(receipt)
	if not state_text or state_text in ["Pending","Confirmed"]:
		state_text = {"finalized":"Finalized","complete":"Submitted","error":"Transaction interrupted"}.get(trace.get("status",""),"Preparing" if page=="working" else "Submitting")
	heading(state_text,"Midnight Preview")
	timeline(trace)
	if failed: D.label(body,str(trace.get("error","")),14,Color("#ffbb9c"),500,true)
	var block = receipt.get("block") if receipt.get("block") != null else trace.get("block")
	if block != null: D.label(body,"Block %d" % int(block),15,D.INK,570)
	var hash := str(receipt.get("hash",trace.get("hash","")))
	if hash.is_valid_hex_number(false) and hash.length()==64:
		D.label(body,hash,12,D.MUTED,470,true)
		D.button(body,"On-chain receipt",open_receipt.bind(hash,"sent"),"normal","check").disabled = busy
		D.button(body,"View on explorer",open_browser.bind(EXPLORER+hash,"sent"),"quiet","explore").disabled = busy
	if not busy:
		if failed and page=="working": D.button(body,"Back",back,"normal","back")
		D.button(body,"Back to wallet",navigate.bind("home"),"primary")

func explore_page() -> void:
	heading("Explore")
	var group := D.card(body,D.SURFACE,10,0)
	explore_link(group,"contracts","mdwa test dApp","mdwa.local",open_browser.bind(LOCAL_APP,"explore"))
	D.divider(group)
	explore_link(group,"explore","Night Scan","Midnight Preview explorer",open_browser.bind(NIGHT_SCAN,"explore"))

	if not demo: D.button(body,"Find transaction",open_receipt.bind("","explore"),"normal","activity")

func open_receipt(hash: String, origin: String) -> void:
	chain_hash = hash; chain_origin = origin; chain_receipt = {}; watching_hash = ""
	go("chain")
	if hash: lookup_receipt(hash)

func lookup_receipt(hash: String) -> void:
	hash = hash.strip_edges().trim_prefix("0x")
	if hash.length()!=64 or not hash.is_valid_hex_number(false):
		notice("Enter a 64-character transaction hash."); return
	chain_hash = hash
	watching_hash = ""
	lookup_generation += 1
	var request_id := lookup_generation
	notice("Checking Preview…")
	ask("chainReceipt",{"hash":hash},func(reply):
		if page!="chain" or request_id!=lookup_generation: return
		if reply.get("result") is Dictionary:
			chain_receipt = reply.result; draw_page()
		else:
			watching_hash = hash
			notice(reply.error.message if reply.has("error") else "Waiting for the Preview indexer…")
	)

func chain_page() -> void:
	heading("On-chain receipt","Preview indexer",true)
	if chain_receipt.is_empty():
		var query := D.field(body,"Transaction hash")
		query.text = chain_hash
		query.text_changed.connect(func(_v): watching_hash = ""; lookup_generation += 1; notice(""))
		D.button(body,"Look up",func(): lookup_receipt(query.text),"primary")
		return
	var group := D.card(body)
	D.label(group,str(chain_receipt.execution).replace("_"," ").capitalize(),19,D.ACCENT,630)
	D.label(group,"Block %d" % int(chain_receipt.block),17,D.INK,560)
	D.label(group,str(chain_receipt.hash),13,D.MUTED,450,true)
	D.button(group,"Copy hash",func(): DisplayServer.clipboard_set(chain_hash); notice("Hash copied."),"quiet","copy")
	if chain_receipt.get("fee") != null: D.label(group,M.units(str(chain_receipt.fee),15)+" DUST fee",13,D.MUTED,500,true)
	D.button(body,"View on explorer",open_browser.bind(EXPLORER+chain_hash,"chain"),"normal","explore")

func explore_link(group: Control, symbol: String, title: String, subtitle: String, action: Callable) -> void:
	var row := D.list_row(group,title,action)
	D.icon(row,symbol,D.ACCENT,23)
	var names := D.vbox(row,1)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D.label(names,title,15,D.INK,610,true)
	D.label(names,subtitle,12,D.MUTED,470,true)
	D.icon(row,"next",D.DIM,16)

func open_contract(kind: String) -> void:
	if busy: return
	contract_kind = kind; token_contract = {}; go("contracts")

func open_browser(url: String, origin: String) -> void:
	if busy: return
	browser_return = origin
	explorer_url = url; browser_requested = url; browser_error = ""
	go("browser")

func url_label(url: String) -> String:
	return url.trim_prefix("https://").get_slice("/",0)

func native_explorer() -> bool:
	return bridge != null and Engine.has_singleton("WalletEngine")

func browser_page(stage: Control) -> void:
	var native := native_explorer() and not demo
	var bar := D.row(body,5)
	D.button(bar,"Back to wallet screen",func(): go(browser_return),"quiet","back",true).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	browser_location = D.label(bar,url_label(explorer_url),15,D.INK,550,true)
	browser_location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if native: D.button(bar,"Reload",func(): bridge.reloadExplorer(),"quiet","refresh",true).size_flags_horizontal = Control.SIZE_SHRINK_END
	if native:
		browser_bounds = Control.new()
		stage.add_child(browser_bounds)
		browser_bounds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		browser_bounds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		browser_bounds.offset_top = 59
		browser_bounds.resized.connect(place_browser.call_deferred)
		place_browser.call_deferred()
	elif explorer_url.begins_with(LOCAL_APP):
		heading("mdwa test dApp")
		D.button(body,"Token contract",open_contract.bind("token"),"normal","shield")
		D.button(body,"Counter contract",open_contract.bind("counter"),"normal","contracts")
	else:
		D.button(body,"Open Night Scan",func(): OS.shell_open(explorer_url),"normal","explore")

func place_browser() -> void:
	if page != "browser" or not is_instance_valid(browser_bounds) or not native_explorer(): return
	var rect := get_viewport().get_screen_transform() * browser_bounds.get_global_rect()
	if rect.size.x < 1 or rect.size.y < 1: return
	bridge.showExplorer(browser_requested,roundi(rect.position.x),roundi(rect.position.y),roundi(rect.size.x),roundi(rect.size.y))
	browser_requested = ""

func allows_removal() -> bool:
	return true

func settings_page() -> void:
	match page:
		"settings":
			heading("Settings")
			var group := D.card(body,D.SURFACE,10,0)
			for item in [["connections","explore","Connection","Preview endpoints"],["proving","shield","Proving","Proof server" if config.get("endpoints",{}).get("preview",{}).get("prover",{}).get("kind")=="server" else "On-device Vulkan"],["rescan","activity","Rescan","Wallet history"]]:
				if group.get_child_count(): D.divider(group)
				explore_link(group,item[1],item[2],item[3],navigate.bind(item[0]))
			if demo: D.button(body,"Exit demo wallet",exit_demo,"normal","back")
			else:
				D.button(body,"Lock wallet",func(): command("lock",{},func(_v): pass,"Locking…"),"normal","lock")
				if allows_removal(): D.button(body,"Remove wallet…",navigate.bind("remove"),"quiet")
		"connections","proving":
			heading("Connection" if page=="connections" else "Proving","",true)
			if demo: D.label(body,"Open a Preview wallet to edit settings.",14,D.MUTED,480,true); return
			if config_draft.is_empty(): D.label(body,"Loading…",14,D.MUTED); return
			if page=="connections":
				for item in [["node","Node RPC","wss://"],["indexerHttp","Indexer HTTP","https://"],["indexerWs","Indexer WebSocket","wss://"]]:
					D.label(body,item[1],13,D.MUTED)
					var field := D.field(body,item[2])
					field.text = config_draft[item[0]]
					field.text_changed.connect(func(v): config_draft[item[0]] = v.strip_edges())
				D.button(body,"Save connection",save_config,"primary","check")
				D.button(body,"Restore defaults",func():
					for key in ["node","indexerHttp","indexerWs"]: config_draft[key] = config.defaults.preview[key]
					save_config()
				,"quiet")
			else:
				var choices := D.row(body)
				var prover: Dictionary = config_draft.prover
				for kind in ["wasm","server"]:
					D.button(choices,"On device" if kind=="wasm" else "Proof server",func(): prover.kind=kind; draw_page(),"primary" if prover.kind==kind else "normal")
				if prover.kind=="server":
					D.label(body,"Private proof inputs go to this server.",13,D.MUTED,500,true)
					var server := D.field(body,"https://")
					server.text = prover.get("url","")
					server.text_changed.connect(func(v): prover.url=v.strip_edges())
				D.button(body,"Save proving",save_config,"primary","check")
				D.button(body,"Test local prover",test_local_prover,"normal","shield")
				if proof_status: D.label(body,proof_status,14,D.ACCENT,520,true)
		"rescan":
			heading("Rescan","Rebuild balances and activity from Preview.",true)
			if demo: return
			D.button(body,"Rescan wallet",rescan_wallet.bind(false),"normal","refresh")
			if config.get("birthday"):
				D.label(body,"A full rescan also looks for shielded funds from before this wallet’s birthday.",13,D.MUTED,450,true)
				D.button(body,"Rescan from genesis",rescan_wallet.bind(true),"normal")
		"remove":
			heading("Remove Preview wallet","You need your recovery phrase to restore access.",true)
			var password := D.field(body,"Confirm wallet password",true)
			D.button(body,"Remove from this device",func():
				if password.text.is_empty(): notice("Enter your password."); return
				command("resetWallet",{"password":password.text},func(_r): pass)
			,"normal")

func save_config() -> void:
	if not config_draft.node.begins_with("wss://") or not config_draft.indexerWs.begins_with("wss://") or not config_draft.indexerHttp.begins_with("https://"):
		notice("Use wss:// for WebSockets and https:// for HTTP."); return
	if config_draft.prover.kind=="server" and not config_draft.prover.url.begins_with("https://"):
		notice("Enter an HTTPS proof server URL."); return
	command("saveSettings",{"network":"preview","endpoints":config_draft},func(_result):
		config = {}; go("settings"); notice("Saved.")
	)

func rescan_wallet(from_start: bool) -> void:
	command("rescan",{"fromStart":from_start},func(_result): config={}; go("home"))

func test_local_prover() -> void:
	command("checkAndroidProver",{},func(result):
		proof_status = "Proof verified in %.1f seconds." % result.seconds
		draw_page()
	,"Generating and verifying a local proof…")
