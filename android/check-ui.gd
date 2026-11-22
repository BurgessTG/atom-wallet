# Run with godot --path android/ui --script ../check-ui.gd
# Set MDWA_TEST_VIEWPORT=WxH to check another size; widths of 600 or more use
# the unfolded layout (side rail, centred dialogs, two columns).
extends SceneTree

const M = preload("res://model.gd")
const D = preload("res://design.gd")
var wallet: Control
var failed := false
var touch_count := 0

const OTHER_TOKEN := "d1b3f32e66ba000000000000000000000000000000000000000000000000fe91"
const SAMPLE := {
	"night": {"available":"2840750000","pending":"0"},
	"dust": {"balance":"42600000000000000","cap":"60000000000000000","registeredNight":"1200000000","unregisteredNight":"1640750000"},
	"unshielded": [{"type": M.NIGHT_TYPE,"amount":"2840750000"}], "shielded":[{"type": OTHER_TOKEN,"amount":"125"}]
}
const HISTORY := [
	{"kind":"receive","status":"finalized","hash":"Sample receipt 01","deltas":[{"type":M.NIGHT_TYPE,"amount":"125000000","kind":"unshielded"}]},
	{"kind":"send","status":"finalized","hash":"Sample payment 02","deltas":[{"type":M.NIGHT_TYPE,"amount":"-34250000","kind":"unshielded"}]},
	{"kind":"dust","status":"confirmed","hash":"Sample registration 03","deltas":[]}
]

# Drive the normal bridge callbacks without spending funds or storing a seed.
class TestEngine extends RefCounted:
	var wallet: Control
	var calls := []
	var retries := 0
	var receipt_reads := 0
	var entry := {"node":"wss://node.example","indexerHttp":"https://indexer.example","indexerWs":"wss://indexer.example","prover":{"kind":"wasm","url":"https://proof.example"}}
	var available := SAMPLE.duplicate(true)
	var second_token := "e".repeat(64)

	var bio_enabled := false
	var bio_password := ""
	var shared := []
	var haptics := 0
	var auto_lock := -1

	func retryEngine():
		retries += 1

	# Android plugin methods the UI reaches through native().
	func biometricStatus(_network): return JSON.stringify({"available":true,"enabled":bio_enabled})
	func enableBiometric(_network, password):
		bio_password = password; bio_enabled = true
		wallet._message.call_deferred(JSON.stringify({"type":"biometric","event":"enabled"}))
	func disableBiometric(_network): bio_enabled = false
	func unlockWithBiometric(_network):
		wallet._message.call_deferred(JSON.stringify({"type":"biometric","event":"password","password":bio_password}))
	func haptic(_kind): haptics += 1
	func share(text): shared.append(text)
	func scanQr(): wallet._message.call_deferred(JSON.stringify({"type":"scan","value":"midnight:mn_addr_preview1scanned"}))
	func setAutoLock(seconds): auto_lock = seconds

	func request(raw: String):
		var message: Dictionary = JSON.parse_string(raw)
		calls.append(message)
		var result
		match message.method:
			"generateMnemonic":
				result = {"words":M.wordlist().slice(100,124)}
			"overview": result = available
			"walletHome": result = {"overview":available,"recent":HISTORY.slice(0,3)}
			"settings": result = {"birthday":{"height":100},"endpoints":{"preview":entry,"preprod":entry,"mainnet":entry},"defaults":{"preview":entry,"preprod":entry,"mainnet":entry}}
			"chainReceipt":
				receipt_reads += 1
				result = {"hash":message.params.hash,"block":123,"execution":"SUCCESS","fee":"100"} if receipt_reads>1 else null
			"saveSettings": entry=message.params.endpoints; result = {}
			"activityItem":
				result = {"hash":"a".repeat(64),"partial":true,"status":"finalized","block":123} if message.params.hash=="test-id" else null
			"tokenLabels": result = [{"kind":"shielded","type":second_token,"name":"Test asset","symbol":"TEST","decimals":3}]
			"history": result = {"items": HISTORY if message.params.offset == 0 else [HISTORY[2]], "total":13}
			"setTokenLabel": result = message.params
			"previewSend": result = {"id":"recipe","outputs":message.params.outputs,"fee":"10000"}
			"send","dustApply":
				var now := int(Time.get_unix_time_from_system()*1000)
				var trace := {"key":"fixture","status":"finalized","start":now-1700,"end":now,"hash":"a".repeat(64),"block":123,
					"steps":[{"name":"Proving","start":now-1700,"end":now-500,"proofs":[{"name":"output","start":now-1530,"end":now-510}]},{"name":"Finalized","start":now,"end":now}]}
				wallet._message.call_deferred(JSON.stringify({"type":"transaction","trace":trace,"at":now}))
				result = {"txId":"test-id"}
			"dustPreview": result = {"id":"dust","action":message.params.action,"canPay":true,"fee":"1","utxos":[]}
			"qr": result = {"rows":["10","01"]}
			_: result = {}
		wallet._message.call_deferred(JSON.stringify({"id":message.id,"result":result}))


func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func settle() -> void:
	for i in 3: await process_frame

func find_button(title: String, occurrence := 0) -> Button:
	for item in wallet.find_children("*","Button",true,false):
		if item.accessibility_name == title and item.is_visible_in_tree():
			if wallet.page in wallet.DRAWERS and is_instance_valid(wallet.sheet) and not wallet.sheet.is_ancestor_of(item) and not wallet.header.is_ancestor_of(item): continue
			if occurrence > 0:
				occurrence -= 1
				continue
			return item
	return null

func reach(item: Button, title: String) -> Vector2:
	if is_instance_valid(wallet.scroll) and wallet.scroll.is_ancestor_of(item):
		wallet.scroll.ensure_control_visible(item)
		await settle()
	check(item.size.x >= 48 and item.size.y >= 48, "Undersized tap target "+title)
	var pos: Vector2 = item.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(pos), "Unreachable tap target "+title)
	check(not item.disabled, "Disabled tap target "+title)
	for control in wallet.frame.find_children("*","Control",true,false):
		if control.is_visible_in_tree() and (control is Label or control is BaseButton or control is LineEdit):
			var bounds: Rect2 = control.get_global_rect()
			check(bounds.position.x >= -1 and bounds.end.x <= wallet.size.x+1, "Horizontal overflow on "+wallet.page+" ("+control.get_class()+" "+str(control.get("text")).left(30)+") "+str(bounds))
	return pos

func touch(pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.position = pos
	root.push_input(event, true)

func tap(title: String, occurrence := 0) -> void:
	await settle()
	var item := find_button(title, occurrence)
	if not item:
		check(false, "Missing button " + title + " on " + wallet.page)
		return
	var pos: Vector2 = await reach(item, title)
	touch(pos, true); touch(pos, false)
	await settle()
	touch_count += 1

# Press and hold a confirmation button until it completes.
func hold(title: String) -> void:
	await settle()
	var item := find_button(title)
	if not item:
		check(false, "Missing hold button " + title + " on " + wallet.page)
		return
	var pos: Vector2 = await reach(item, title)
	touch(pos, true)
	await create_timer(0.3).timeout
	check(not item.done, "Hold completed too early: " + title)
	await create_timer(0.75).timeout
	touch(pos, false)
	await settle()
	touch_count += 1

func fields() -> Array:
	return wallet.body.find_children("*","LineEdit",true,false)

func texts() -> Array:
	return wallet.frame.find_children("*","Label",true,false).filter(func(l): return l.is_visible_in_tree()).map(func(l): return l.text)

func drag_from_button() -> void:
	var area: ScrollContainer = wallet.scroll
	var original_page: String = wallet.page
	var candidate: Button
	for node in wallet.body.find_children("*","Button",true,false):
		if area.get_global_rect().encloses(node.get_global_rect()) and node.get_global_rect().get_center().y > area.global_position.y+65:
			candidate = node
			break
	if not candidate or area.get_v_scroll_bar().max_value <= area.size.y: return
	var at := candidate.get_global_rect().get_center()
	touch(at, true)
	var motion := InputEventScreenDrag.new()
	motion.position = at-Vector2(0,60); motion.relative = Vector2(0,-60)
	root.push_input(motion,true)
	touch(motion.position, false)
	check(wallet.page==original_page and area.scroll_vertical>0,"Swipe starting on a control activated it or failed to scroll")
	area.scroll_vertical=0

func run() -> void:
	var dimensions := OS.get_environment("MDWA_TEST_VIEWPORT").split("x")
	if dimensions.size()==2:
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		root.size=Vector2i(int(dimensions[0]),int(dimensions[1]))
	D.motion = 0.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://check-prefs.cfg"))
	wallet = load("res://wallet.tscn").instantiate()
	wallet.prefs_path = "user://check-prefs.cfg"
	root.add_child(wallet)
	check(M.atomic_amount("10000000000000000.000001",6) == "10000000000000000000001","Large amount changed")
	check(M.atomic_amount("0.0000001",6) == "" and M.atomic_amount("-1",6) == "" and M.atomic_amount("0",6) == "","Invalid amount accepted")
	check(M.atomic_amount("1.1",0) == "" and M.atomic_amount("0.001",3) == "1","Token units changed")
	check(M.exceeds("100000000000000000001","100000000000000000000"),"Large overspend accepted")
	check(M.units("42600000000000000",15) == "42.6","Incorrect DUST precision")
	check(M.wordlist().size() == 2048 and M.is_word("zoo") and not M.is_word("zooo") and M.complete("aba") == ["abandon"],"BIP-39 word list wrong")
	await bridge_checks()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://check-prefs.cfg"))
	if not failed: print("Wallet UI checks passed at ",root.get_visible_rect().size,": ",touch_count," taps")
	quit(1 if failed else 0)

func bridge_checks():
	var engine := TestEngine.new()
	engine.wallet = wallet
	engine.available.shielded.append({"type":engine.second_token,"amount":"12345"})
	var state := {"network":"preview","hasWallet":false,"locked":true,"sync":{"status":"synced","tip":100},
		"networks":[{"id":"preview","name":"Preview","hasWallet":false},{"id":"preprod","name":"Preprod","hasWallet":false},{"id":"mainnet","name":"Mainnet","hasWallet":false}],
		"addresses":{"shielded":"test shielded address","unshielded":"test public address","dust":"test dust address"}}
	wallet.bridge = engine
	wallet._message(JSON.stringify({"type":"state", "state":state}))
	await tap("Create a new wallet")
	check(wallet.page == "phrase" and wallet.words.size() == 24,"Phrase page missing")
	check(find_button("I've written it down").disabled,"Phrase could be confirmed before it was revealed")
	await tap("Reveal phrase")
	check(wallet.phrase_revealed,"Phrase did not reveal")
	await tap("I've written it down")
	check(wallet.page == "verify" and wallet.verify_slots.size() == 3,"Verify step missing")
	var first: Dictionary = wallet.verify_slots[0]
	var wrong: String = first.options.filter(func(o): return o != wallet.words[first.index])[0]
	await tap(wrong)
	check(wallet.verify_slots[0].picked == "","Wrong word accepted")
	for i in 3:
		var right: String = wallet.words[wallet.verify_slots[i].index]
		var before := 0
		for j in i: before += int(right in wallet.verify_slots[j].options)
		await tap(right, before)
	check(wallet.verify_slots.all(func(s): return s.picked == wallet.words[s.index]),"Correct words not accepted")
	await tap("Continue")
	check(wallet.page == "create","Password step missing")
	await tap("Create wallet")
	check("passwords" in wallet.feedback.text,"Missing password check")
	var f := fields()
	f[0].text="test password"; f[1].text="test password"
	await tap("Create wallet")
	var created = engine.calls.filter(func(c): return c.method=="createWallet")
	check(created.size()==1 and not created[0].params.restore and created[0].params.mnemonic == " ".join(M.wordlist().slice(100,124)),"Create request failed")
	check(engine.bio_enabled and engine.bio_password == "test password","Biometric unlock was not enabled at creation")
	wallet.go("welcome")
	await tap("I already have a wallet")
	f = fields()
	f[0].text="fixture"; f[1].text="test password"; f[2].text="test password"
	await tap("Restore wallet")
	check("12 or 24" in wallet.feedback.text,"Short phrase accepted")
	f[0].text=" ".join(M.wordlist().slice(0,12))
	await tap("Restore wallet")
	check(engine.calls.back().method == "createWallet" and engine.calls.back().params.restore,"Restore request failed")
	state.hasWallet=true
	wallet._message(JSON.stringify({"type":"state","state":state}))
	await settle()
	check(engine.calls.any(func(c): return c.method=="unlock" and c.params.password=="test password"),"Biometric unlock did not open the wallet")
	await create_timer(0.1).timeout
	fields()[0].text="test password"
	await tap("Unlock")
	check(engine.calls.back().method=="unlock","Password unlock failed")
	state.locked=false
	wallet._message(JSON.stringify({"type":"state","state":state}))
	await settle()
	for label in wallet.body.find_children("*","Label",true,false):
		if label.text=="2,840.75": check(label.get_line_count()==1,"Balance wrapped across multiple lines")
	if OS.get_cmdline_user_args().size() and DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	await tap("Send")
	check(wallet.page == "send" and wallet.sheet_open,"Send sheet did not open")
	await drag_from_button()
	await tap("Choose asset")
	check(wallet.page == "choose_token","Asset picker did not open")
	await tap("Select Test asset")
	check(wallet.send_kind == "shielded" and wallet.token_type == engine.second_token,"Labelled private token not selected")
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(state.addresses.shielded)
		await tap("Paste")
		check(wallet.recipient==state.addresses.shielded,"Clipboard recipient did not populate")
	f = fields()
	if f[0].text.is_empty(): f[0].text=state.addresses.shielded
	f[1].text="12.346"
	await tap("Review")
	check(wallet.page=="send" and "available" in wallet.feedback.text,"Overspend accepted")
	f[1].text="12.345"
	await tap("Review")
	check(wallet.page=="review" and wallet.preview.outputs==[{"kind":"shielded","type":engine.second_token,"recipient":state.addresses.shielded,"amount":"12345"}],"Private token label, recipient or precision lost")
	await tap("Back")
	check(engine.calls.any(func(c):return c.method=="cancel" and c.params.id=="recipe"),"Back did not release booked coins")
	await tap("Review")
	await hold("Hold to send")
	check(wallet.page=="sent" and wallet.last_tx=="test-id","Send did not reach receipt")
	await settle()
	var timed := texts()
	check("1.7s" in timed and "Partially successful" in timed and not ("GPU · output" in timed),"Finalized timing or indexed execution status missing")
	check(engine.haptics > 0,"No haptic feedback")
	await tap("Done")
	await tap("Scan")
	await settle()
	check(wallet.page=="send" and wallet.recipient=="mn_addr_preview1scanned" and wallet.send_kind=="unshielded","Scanned payment link did not fill Send")
	await tap("Close")
	await tap("Receive")
	await tap("Share")
	check(engine.shared == ["test public address"],"Share sheet did not get the address")
	await tap("Private")
	check(wallet.receive_kind == "shielded","Address selector failed")
	await tap("Close")
	check(wallet.page == "home" and not wallet.sheet_open,"Receive sheet did not close")
	await tap("Hide balances")
	check("••••••" in texts(),"Balances not hidden")
	await tap("Show balances")
	await tap("DUST generation")
	await tap("Stop generation")
	await hold("Hold to confirm")
	check(engine.calls.any(func(c):return c.method=="dustApply"),"DUST request missing")
	await tap("Done")
	await tap("Activity")
	await tap("Details")
	check(wallet.detail.get("kind") == "receive","Activity did not open the selected item")
	if wallet.page == "detail": await tap("Back")
	await tap("Show more")
	check(engine.calls.back().method=="history" and engine.calls.back().params.limit==60,"More history not requested")
	await tap("Explore")
	check(find_button("Find transaction") == null,"Developer tools visible without developer mode")
	check(wallet.browser_target(" midnight.network/docs ") == "https://midnight.network/docs" and wallet.browser_target("http://example.org") == "https://example.org","Address not opened over HTTPS")
	check(wallet.browser_target("night token price") == wallet.SEARCH + "night%20token%20price" and wallet.browser_target("midnight") == wallet.SEARCH + "midnight" and wallet.browser_target("  ") == "","Search text not sent to the search engine")
	await tap("Block explorer")
	check(wallet.page=="browser" and wallet.explorer_url==wallet.EXPLORERS.preview,"Suggested link did not open the browser")
	check(find_button("Go back").disabled and find_button("Go forward").disabled and not find_button("Share page").disabled,"Browser controls in the wrong state")
	wallet._message(JSON.stringify({"type":"browser","url":"https://example.org/a","title":"A","loading":true,"progress":40,"back":true,"forward":false}))
	await settle()
	check(fields()[0].text=="https://example.org/a" and not find_button("Go back").disabled and wallet.browser_fill.visible,"Browser did not follow the page")
	await tap("Share page")
	check(engine.shared.back()=="https://example.org/a","Page link not shared")
	fields()[0].text="docs.midnight.network"
	fields()[0].text_submitted.emit(fields()[0].text)
	await settle()
	check(wallet.page=="browser" and wallet.explorer_url=="https://docs.midnight.network","Address bar did not navigate")
	await tap("Close browser")
	check(wallet.page=="explore","Browser did not close")
	fields()[0].text="midnight wallet"
	await tap("Go")
	check(wallet.page=="browser" and wallet.explorer_url==wallet.SEARCH+"midnight%20wallet","Explore search did not open the browser")
	await tap("Close browser")
	await tap("Settings")
	await tap("Developer mode")
	check(wallet.prefs.developer,"Developer mode did not turn on")
	await tap("Change password")
	check(wallet.page=="password","Change password page missing")
	f = fields()
	f[0].text="test password"; f[1].text="new test password"; f[2].text="mismatched"
	await tap("Change password")
	check("matching" in wallet.feedback.text,"Mismatched new passwords accepted")
	f[2].text="new test password"
	await tap("Change password")
	await settle()
	check(engine.calls.any(func(c):return c.method=="changePassword" and c.params.password=="test password" and c.params.next=="new test password"),"Password change not requested")
	check(wallet.page=="settings" and engine.bio_enabled and engine.bio_password=="new test password","Biometric unlock kept the old password")
	await tap("Wallet")
	await tap("Edit token label", 1)
	f = fields()
	check(wallet.page=="token_label" and f[2].text=="3","Saved decimals did not load as a whole number")
	f[0].text="Glass token"; f[1].text="GLASS"
	await tap("Save label")
	check(wallet.page=="home" and engine.calls.any(func(c):return c.method=="setTokenLabel" and c.params.decimals==3),"Label not saved")
	engine.available.unshielded = []
	engine.available.shielded = []
	await tap("Send")
	await tap("Receive tokens")
	check(wallet.page=="receive","Empty balance did not offer Receive")
	await tap("Close")
	await tap("Settings")
	await tap("Chain")
	await tap("Preprod")
	check(engine.calls.any(func(c):return c.method=="selectNetwork" and c.params.network=="preprod"),"Chain switch not requested")
	await tap("Custom endpoints")
	await tap("Save endpoints")
	await tap("Custom endpoints")
	await tap("Restore defaults")
	await tap("Back")
	await tap("Proving")
	await tap("Proof server")
	await tap("Save proving")
	check(engine.entry.prover.kind=="server","Prover setting did not persist")
	await tap("Proving")
	await tap("On this phone")
	await tap("Save proving")
	check(engine.entry.prover.kind=="wasm","Prover setting did not return to the phone")
	await tap("1 min")
	check(engine.auto_lock==60 and wallet.prefs.auto_lock==60,"Auto-lock not set")
	await tap("Biometric unlock")
	check(not engine.bio_enabled,"Biometric unlock did not turn off")
	await tap("Rescan wallet")
	await tap("Back")
	await tap("Remove wallet from this phone")
	await tap("Remove from this phone")
	check("password" in wallet.feedback.text,"Removal guard missing")
	await tap("Back")
	await tap("Explore")
	await tap("Find transaction")
	await tap("Look up")
	check("64-character" in wallet.feedback.text,"Invalid hash accepted")
	fields()[0].text="a".repeat(64)
	await tap("Look up")
	check(wallet.chain_receipt.is_empty() and wallet.watching_hash=="a".repeat(64),"Unindexed receipt did not subscribe")
	state.sync.tip=124
	wallet._message(JSON.stringify({"type":"state","state":state}))
	await settle()
	check(wallet.chain_receipt.get("block")==123 and wallet.chain_receipt.get("execution")=="SUCCESS","WebSocket head did not update receipt")
	if DisplayServer.get_name() != "headless":
		await tap("Copy hash")
		check(DisplayServer.clipboard_get()=="a".repeat(64),"Receipt hash copy failed")
	await tap("Back")
	await tap("Settings")
	await tap("Lock now")
	check(engine.calls.back().method=="lock","Lock request failed")
	state.locked=true
	wallet._message(JSON.stringify({"type":"state","state":state}))
	await settle()
	await tap("Forgot password?")
	check(wallet.page=="forgot","Forgot password page missing")
	await tap("Keep my wallet")
	check(wallet.page=="unlock" and not engine.calls.any(func(c):return c.method=="eraseWallet"),"Leaving the forgot page erased the wallet")
	await tap("Forgot password?")
	await hold("Hold to erase wallet")
	check(engine.calls.back().method=="eraseWallet" and engine.calls.back().params.confirm=="erase","Erase request missing")
	wallet._message(JSON.stringify({"type":"fatal","message":"Interrupted test startup"}))
	await tap("Retry")
	check(engine.retries==1,"Retry did not restart the worker")
