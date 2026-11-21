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
var busy := false
var demo := false
var page := "welcome"
var words := PackedStringArray()
var receive_kind := "unshielded"
var preview := {}
var recipient := ""
var amount := ""
var last_tx := ""
var boot_error := ""
var proof_status := ""

var frame: MarginContainer
var body: VBoxContainer
var column: VBoxContainer
var scroll: ScrollContainer
var feedback: Label
var status_line: Label

func _ready() -> void:
	get_tree().auto_accept_quit = false
	if Engine.has_singleton("WalletEngine"):
		bridge = Engine.get_singleton("WalletEngine")
		bridge.connect("message", _message)
		bridge.startEngine()
	draw_page()
	var timer := Timer.new()
	timer.wait_time = 5
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(refresh)

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
			live_state = msg.state
			boot_error = ""
			if demo: return
			if first or had != live_state.hasWallet or locked != live_state.locked:
				wipe()
				if live_state.hasWallet: go("unlock" if live_state.locked else "home")
				else: go("welcome")
			elif is_instance_valid(status_line):
				status_line.text = sync_text()
		_:
			var key := str(msg.get("id",""))
			if not pending.has(key): return
			var callback: Callable = pending[key]
			pending.erase(key)
			callback.call(msg)

func wipe() -> void:
	proof_status = ""
	words.clear()
	overview = {}
	history = []
	history_loaded = false
	history_total = 0
	history_offset = 0
	preview = {}
	detail = {}
	recipient = ""
	amount = ""
	last_tx = ""

func go(target: String) -> void:
	if page in ["review","dust_review"] and target != "sent" and preview.has("id") and not demo:
		ask("cancel", {"id":preview.id}, func(_reply): pass)
	if target not in ["review","dust_review"]: preview = {}
	if target in ["home","welcome","unlock"]:
		recipient = ""; amount = ""; words.clear()
	page = target
	draw_page()
	refresh()

func navigate(target: String) -> void:
	if not busy:
		go(target)

func back() -> void:
	if busy: return
	match page:
		"review": go("send")
		"dust_review": go("dust")
		"detail": go("activity")
		"create": go("phrase")
		"restore","phrase","unlock","welcome":
			if page == "welcome" or page == "unlock": get_tree().quit()
			else: go("welcome")
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

func notice(value: String) -> void:
	if is_instance_valid(feedback):
		feedback.text = value
		feedback.visible = not value.is_empty()
		if feedback.visible: scroll.ensure_control_visible.call_deferred(feedback)

func sync_text() -> String:
	if demo: return "Sample balances"
	var sync: Dictionary = live_state.get("sync",{})
	match sync.get("status","idle"):
		"synced": return "Synced with Midnight"
		"syncing": return "Syncing  ·  %d%%" % int(sync.get("percent",0))
		"error": return str(sync.get("error","Connection interrupted"))
	return str(sync.get("error") if sync.get("error") else "Connecting to Preview…")

func refresh() -> void:
	if demo or not bridge or refreshing or not live_state.get("hasWallet") or live_state.get("locked"): return
	if page not in ["home","dust","activity"]: return
	var target := page
	var offset := history_offset
	refreshing = true
	var method := "history" if target == "activity" else "overview"
	ask(method, {"offset":offset,"limit":12} if method == "history" else {}, func(reply):
		refreshing = false
		if page != target or demo or history_offset != offset: return
		if reply.has("error"):
			if target == "activity" or overview.is_empty(): notice(reply.error.message)
			return
		notice("")
		if target == "activity":
			if not history_loaded or history != reply.result.items or history_total != int(reply.result.total):
				history_loaded = true
				history = reply.result.items; history_total = int(reply.result.total); draw_page()
		elif overview != reply.result:
			overview = reply.result; draw_page()
	)

func enter_demo() -> void:
	if busy: return
	demo = true
	wipe()
	overview = M.SAMPLE.duplicate(true)
	history = M.HISTORY.duplicate(true)
	history_total = history.size()
	history_loaded = true
	go("home")

func exit_demo() -> void:
	demo = false
	wipe()
	go("unlock" if live_state.get("hasWallet") else "welcome")

func draw_page() -> void:
	if is_instance_valid(frame):
		remove_child(frame); frame.queue_free()
	status_line = null
	frame = MarginContainer.new()
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	update_insets()
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(center)
	column = D.vbox(center, 0)
	column.custom_minimum_size.x = minf(maxf(100, size.x - frame.get_theme_constant("margin_left") - frame.get_theme_constant("margin_right")), 560)
	var top := D.row(D.inset(column, 20, 10), 8)
	D.icon(top, "mark", D.ACCENT, 29)
	D.label(top, "mdwa", 24, D.INK, 750)
	D.space(top,0,true)
	var badge := D.card(top, Color("#242137"), 10, 4)
	D.label(badge, "Demo wallet" if demo else "Preview network", 12, D.ACCENT, 580)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	var margin := D.inset(scroll,20,9)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body = D.vbox(margin,13)
	match page:
		"welcome","unlock": welcome()
		"phrase","restore","create": onboarding()
		"home": home()
		"dust","dust_review": dust_page()
		"activity": activity_page()
		"detail": detail_page()
		"receive": receive_page()
		"send","review","sent": send_page()
		"settings": settings_page()
	feedback = D.label(body, "", 14, Color("#f0c29d"), 500, true)
	feedback.hide()
	if page in ["home","dust","activity","settings"]:
		var nav_panel := PanelContainer.new()
		nav_panel.add_theme_stylebox_override("panel", D.style(Color("#13141d"),0,D.LINE))
		column.add_child(nav_panel)
		var nav := D.row(D.inset(nav_panel, 9, 7), 4)
		for item in [["home","Wallet","wallet"],["activity","Activity","activity"],["settings","Session","shield"]]:
			D.button(nav, item[1], navigate.bind(item[0]), "primary" if page == item[0] else "quiet", item[2])

func _on_size_changed() -> void:
	if not is_instance_valid(frame): return
	update_insets()
	column.custom_minimum_size.x = minf(maxf(100,size.x - frame.get_theme_constant("margin_left") - frame.get_theme_constant("margin_right")),560)

func update_insets() -> void:
	var margins := [0,0,0,0]
	if OS.get_name() == "Android":
		var safe := DisplayServer.get_display_safe_area()
		var win := DisplayServer.window_get_size()
		var origin := DisplayServer.window_get_position()
		var scale_factor := get_viewport().get_screen_transform().get_scale()
		if win.x > 0 and safe.size.x > 0:
			margins = [maxi(0,roundi((safe.position.x-origin.x)/scale_factor.x)),maxi(0,roundi((safe.position.y-origin.y)/scale_factor.y)),maxi(0,roundi((win.x+origin.x-safe.end.x)/scale_factor.x)),maxi(0,roundi((win.y+origin.y-safe.end.y)/scale_factor.y))]
	for i in 4: frame.add_theme_constant_override("margin_"+["left","top","right","bottom"][i],margins[i])

func heading(title: String, subtitle := "", back_button := false) -> void:
	if back_button:
		var h := D.row(body)
		D.button(h,"Back",back,"quiet","back").size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	D.label(body, title, 30, D.INK, 680, true)
	if subtitle != "": D.label(body, subtitle, 15, D.MUTED, 440, true)

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

func onboarding() -> void:
	if page == "phrase":
		heading("Recovery phrase","Write down these words in order. Anyone with this phrase can access your wallet.",true)
		var g := GridContainer.new()
		g.columns = 3
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
	heading("Overview")
	var hero := artwork(179)
	var hi := D.inset(hero,19,16)
	hi.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var block := D.vbox(hi,1)
	D.label(block,"Available balance",14,Color("#dfdaf2"),530)
	D.space(block,5)
	var balance_text := M.units(overview.night.available,6) if overview.has("night") else "—"
	D.label(block,balance_text,37 if balance_text.length() <= 12 else 24,D.INK,690,true)
	D.label(block,"NIGHT",14,D.ACCENT,640)
	D.space(block,0,true)
	status_line = D.label(block,sync_text(),12,D.MUTED,500,true)
	var actions := D.row(body,9)
	D.button(actions,"Send",func(): go("send"),"primary","send")
	D.button(actions,"Receive",func(): go("receive"),"normal","receive")
	D.space(body,3)
	D.label(body,"Assets",20,D.INK,650)
	if overview.is_empty():
		D.label(body,"Waiting for balances from the wallet engine.",14,D.MUTED,450,true)
		return
	var assets := D.card(body)
	asset_row(assets,"night","Midnight","Unshielded",balance_text,"NIGHT")
	var divider := ColorRect.new()
	divider.color = D.LINE; divider.custom_minimum_size.y = 1
	assets.add_child(divider)
	asset_row(assets,"dust","DUST","Network fees",M.units(overview.dust.balance,15),"DUST")
	for kind in ["shielded","unshielded"]:
		for token in overview.get(kind,[]):
			if kind == "unshielded" and token.type == M.NIGHT_TYPE: continue
			asset_row(assets,"shield",token.type.left(10)+"…",kind.capitalize(),token.amount,"units")
	var generation := D.card(body,Color("#182021"))
	var head := D.row(generation,6)
	D.icon(head,"dust",D.GREEN,17)
	D.label(head,"DUST generation",15,D.INK,610)
	var meter := ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size.y = 6
	meter.add_theme_stylebox_override("background",D.style(Color("#2c3638"),3))
	meter.add_theme_stylebox_override("fill",D.style(D.GREEN,3))
	var capacity := float(overview.dust.cap)
	meter.value = 100.0 * float(overview.dust.balance) / capacity if capacity > 0 else 0
	generation.add_child(meter)
	D.label(generation, M.units(overview.dust.registeredNight,6)+" NIGHT registered",13,D.MUTED,500,true)
	D.button(generation,"View DUST generation",func(): go("dust"),"quiet","next")

func asset_row(parent: Control, symbol: String, title: String, subtitle: String, value: String, unit: String) -> void:
	var r := D.row(parent,10)
	r.custom_minimum_size.y = 54
	D.icon(r,symbol,D.ACCENT if symbol != "dust" else D.GREEN,28)
	var names := D.vbox(r,1)
	D.label(names,title,15,D.INK,620)
	D.label(names,subtitle,12,D.MUTED)
	D.space(r,0,true)
	var values := D.vbox(r,1)
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := D.label(values,value,15,D.INK,600,true)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	D.label(values,unit,11,D.DIM,600).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

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
			if busy: return
			busy = true
			notice("Submitting…")
			ask("dustApply",{"id":preview.id},func(reply):
				busy = false
				preview = {}
				go("dust")
				notice(reply.error.message if reply.has("error") else "Submitted. Follow confirmation in Activity.")
			)
		,"primary")
		return
	heading("DUST generation","Registered NIGHT generates the DUST used to pay network fees.",true)
	if overview.is_empty(): return
	for line in [["Available DUST","balance",15],["Generation cap","cap",15],["Registered NIGHT","registeredNight",6],["Unregistered NIGHT","unregisteredNight",6]]:
		var box := D.card(body)
		D.label(box,line[0],13,D.MUTED)
		D.label(box,M.units(overview.dust[line[1]],line[2]),24,D.INK,640,true)

	for action in ["register","deregister"]:
		var key := "unregisteredNight" if action == "register" else "registeredNight"
		if overview.dust[key] == "0": continue
		D.button(body,"Register NIGHT" if action == "register" else "Stop generation",func():
			if demo:
				preview = {"action":action,"canPay":true,"fee":"250000000000000","utxos":[{"ref":"Sample output","amount":overview.dust[key]}]}
				go("dust_review")
				return
			command("dustPreview",{"action":action},func(built): preview = built; go("dust_review"), "Preparing review…")
		,"normal")

func activity_page() -> void:
	heading("Activity")
	if history.is_empty():
		var empty := D.card(body)
		D.label(empty,"No transactions to show" if history_loaded else "Loading transactions…",18,D.INK,600)
		status_line = D.label(empty,sync_text(),14,D.MUTED,450,true)
		return
	for tx in history:
		var box := D.card(body)
		var r := D.row(box,10)
		D.icon(r,"receive" if tx.kind == "receive" else ("dust" if tx.kind == "dust" else "send"),D.GREEN if tx.kind=="receive" else D.ACCENT,22)
		var info := D.vbox(r,2)
		D.label(info,tx_title(tx),16,D.INK,600)
		D.label(info,str(tx.status).capitalize(),13,D.MUTED)
		D.space(r,0,true)
		var btn := D.button(r,"Details",func(): detail = tx; go("detail"),"quiet","next")
		btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	if history_total > 12:
		var pager := D.row(body)
		for step in [-12,12]:
			var offset: int = history_offset + step
			var b := D.button(pager,"Previous" if step < 0 else "Next",func(): history_offset=offset; refresh())
			b.disabled = offset < 0 or offset >= history_total

func tx_title(tx: Dictionary) -> String:
	return {"receive":"Received","send":"Sent","dust":"DUST registration" if tx.get("action") != "deregister" else "DUST deregistration"}.get(tx.kind,"Transaction")

func detail_page() -> void:
	heading(tx_title(detail),str(detail.status).capitalize(),true)
	var info := D.card(body)
	D.label(info,"Transaction ID",13,D.MUTED)
	D.label(info,str(detail.hash),15,D.INK,500,true)
	if detail.get("time"):
		D.label(info,Time.get_datetime_string_from_unix_time(int(detail.time/1000.0),true)+" UTC",13,D.MUTED)
	for change in detail.get("deltas",[]):
		var night: bool = change.kind=="unshielded" and change.type==M.NIGHT_TYPE
		var unit: String = "NIGHT" if night else ("DUST" if change.kind=="dust" else str(change.type))
		D.label(info,M.units(change.amount,6 if night else (15 if change.kind=="dust" else 0))+" "+unit,16,D.INK,550,true)

func receive_page() -> void:
	heading("Receive","Choose the address for the asset you want to receive.",true)
	var kinds := D.row(body,4)
	for kind in ["unshielded","shielded","dust"]:
		D.button(kinds,"DUST" if kind=="dust" else kind.capitalize(),func(): receive_kind=kind; draw_page(),"primary" if kind==receive_kind else "normal")
	var about: String = {"shielded":"For private tokens.","unshielded":"For NIGHT and other public tokens.","dust":"For directing DUST generation to this wallet."}[receive_kind]
	var panel := D.card(body)
	D.label(panel,about,15,D.INK,530,true)
	if demo:
		D.label(panel,"Demo addresses cannot receive funds. Open a Preview wallet to show its address and QR code.",14,D.MUTED,450,true)
		return
	var address: String = live_state.get("addresses",{}).get(receive_kind,"")
	if address.is_empty(): return
	var qr_box := CenterContainer.new()
	panel.add_child(qr_box)
	var qr := TextureRect.new()
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.custom_minimum_size = Vector2(210,210)
	qr_box.add_child(qr)
	ask("qr",{"address":address},func(reply):
		if not is_instance_valid(qr) or not qr.is_inside_tree() or not reply.has("result"): return
		var rows: Array = reply.result.rows
		var img := Image.create_empty(rows.size()+8,rows.size()+8,false,Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		for y in rows.size():
			for x in rows.size():
				if rows[y][x]=="1": img.set_pixel(x+4,y+4,Color.BLACK)
		qr.texture = ImageTexture.create_from_image(img)
	)
	D.label(panel,address,14,D.INK,450,true)
	D.button(body,"Copy address",func(): DisplayServer.clipboard_set(address); notice("Address copied."),"primary","copy")

func send_page() -> void:
	if page == "sent":
		heading("Review complete" if demo else "Transaction submitted","You reviewed a sample transfer." if demo else "Track confirmation in Activity.")
		if not demo:
			D.label(body,last_tx,14,D.MUTED,500,true)
		D.button(body,"Back to wallet",func(): go("home"),"primary")
		return
	if page == "review":
		heading("Review transfer","Check the recipient, amount and network fee.",true)
		var box := D.card(body)
		var output: Dictionary = preview.outputs[0]
		for entry in [["You send",M.units(output.amount,6)+" NIGHT"],["Recipient",output.recipient],["Network","Demo" if demo else "Midnight Preview"],["Network fee",M.units(str(preview.fee),15)+" DUST"]]:
			D.label(box,entry[0],13,D.MUTED)
			D.label(box,entry[1],17,D.INK,580,true)
		D.button(body,"Finish demo" if demo else "Confirm and send",func():
			if demo: go("sent"); return
			if busy: return
			var id = preview.id
			busy = true
			notice("Proving and submitting…")
			ask("send",{"id":id},func(reply):
				busy = false
				preview = {}
				if reply.has("error"):
					go("send"); notice(reply.error.message); return
				last_tx = reply.result.txId; go("sent")
			)
		,"primary","send")
		return
	heading("Send NIGHT","Enter a public Preview address and the amount to send.",true)
	D.label(body,"Recipient address",14,D.MUTED)
	var address_field := D.field(body,"Unshielded address")
	address_field.text = recipient
	D.label(body,"Amount in NIGHT",14,D.MUTED)
	var value_field := D.field(body,"0.00")
	value_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	value_field.text = amount
	if demo:
		D.button(body,"Use sample transfer",func(): address_field.text="Demo recipient"; value_field.text="12.50","quiet")
	D.button(body,"Review transfer",func():
		recipient = address_field.text.strip_edges()
		amount = value_field.text.strip_edges()
		var atomic := M.stars(amount)
		if recipient.is_empty() or atomic.is_empty():
			notice("Enter a recipient and a positive amount with up to six decimal places."); return
		var outputs := [{"recipient":recipient,"kind":"unshielded","type":M.NIGHT_TYPE,"amount":atomic}]
		if demo:
			if recipient != "Demo recipient": notice("Use the sample recipient in demo mode."); return
			if atomic.length() > 10 or int(atomic) > int(M.SAMPLE.night.available):
				notice("This exceeds the sample balance."); return
			preview={"outputs":outputs,"fee":"250000000000000"}
			go("review"); return
		command("previewSend",{"outputs":outputs},func(built):
			preview = built; go("review")
		,"Preparing the transfer…")
	,"primary","send")

func settings_page() -> void:
	heading("Session")
	var box := D.card(body)
	D.label(box,"Network",13,D.MUTED)
	D.label(box,"Demo wallet" if demo else "Midnight Preview",19,D.INK,620)
	D.label(box,"Sample balances and transactions." if demo else "Your wallet locks when MDWA leaves the foreground.",14,D.MUTED,450,true)
	if not demo:
		var prover := D.card(body)
		D.label(prover,"Local Vulkan prover",19,D.INK,620)
		D.label(prover,proof_status if proof_status else "Verify a sample shielded output on this device. No funds are used.",14,D.MUTED,450,true)
		D.button(prover,"Test local prover",func():
			command("checkAndroidProver",{},func(result):
				proof_status = "Proof verified in %.1f seconds." % result.seconds
				draw_page()
			,"Generating and verifying a local proof…")
		,"secondary","shield")
	if demo: D.button(body,"Exit demo wallet",exit_demo,"primary","back")
	else: D.button(body,"Lock wallet",func(): command("lock",{},func(_v): pass,"Locking…"),"primary","lock")
