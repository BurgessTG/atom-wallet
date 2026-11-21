# Run with godot --path android/ui --script ../check-ui.gd
extends SceneTree

const M = preload("res://model.gd")
var wallet: Control
var failed := false
var touch_count := 0

# Drive the normal bridge callbacks without spending funds or storing a seed.
class TestEngine extends RefCounted:
	var wallet: Control
	var deployed := {}
	var contract_params := {}
	var calls := []
	var retries := 0
	var receipt_reads := 0
	var entry := {"node":"wss://node.example","indexerHttp":"https://indexer.example","indexerWs":"wss://indexer.example","prover":{"kind":"wasm","url":"https://proof.example"}}
	var available := M.SAMPLE.duplicate(true)
	var second_token := "e".repeat(64)

	func retryEngine():
		retries += 1

	func request(raw: String):
		var message: Dictionary = JSON.parse_string(raw)
		calls.append(message)
		var result
		match message.method:
			"generateMnemonic":
				var words := []
				words.resize(24)
				words.fill("abstract")
				result = {"words":words}
			"overview": result = available
			"walletHome": result = {"overview":available,"recent":M.HISTORY.slice(0,3)}
			"settings": result = {"birthday":{"height":100},"endpoints":{"preview":entry},"defaults":{"preview":entry}}
			"chainReceipt":
				receipt_reads += 1
				result = {"hash":message.params.hash,"block":123,"execution":"SUCCESS","fee":"100"} if receipt_reads>1 else null
			"saveSettings": entry=message.params.endpoints; result = {}
			"activityItem":
				result = {"hash":"a".repeat(64),"partial":true,"status":"finalized","block":123} if message.params.hash=="test-id" else null
			"tokenLabels": result = [{"kind":"shielded","type":second_token,"name":"Test asset","symbol":"TEST","decimals":3}]
			"history": result = {"items": M.HISTORY if message.params.offset == 0 else [M.HISTORY[2]], "total":13}
			"previewTokenContract": result = {"address":"1".repeat(64) if deployed.has(message.params.kind) else null}
			"prepareTokenAction":
				contract_params = message.params
				result = {"id":"contract-recipe","address":"1".repeat(64),"amount":message.params.amount,"action":message.params.action,"fee":"50000"}
			"submitTokenAction":
				deployed[contract_params.kind] = true
				result = {"txId":"contract-id"}
			"setTokenLabel": result = message.params
			"checkAndroidProver": result = {"seconds":2.5}
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

func tap(title: String, occurrence := 0) -> void:
	await process_frame
	await process_frame
	if wallet.sheet_tween and wallet.sheet_tween.is_running(): await create_timer(.24).timeout
	for item in wallet.find_children("*","Button",true,false):
		if item.accessibility_name == title and item.is_visible_in_tree():
			if wallet.page in wallet.DRAWERS and not wallet.sheet.is_ancestor_of(item) and not wallet.header.is_ancestor_of(item): continue
			if occurrence > 0:
				occurrence -= 1
				continue
			if wallet.scroll.is_ancestor_of(item):
				wallet.scroll.ensure_control_visible(item)
				await process_frame
			check(item.size.x >= 48 and item.size.y >= 48, "Undersized tap target "+title)
			var pos: Vector2 = item.get_global_rect().get_center()
			check(root.get_visible_rect().has_point(pos), "Unreachable tap target "+title)
			check(not item.disabled, "Disabled tap target "+title)
			for control in wallet.frame.find_children("*","Control",true,false):
				if control.is_visible_in_tree() and (control is Label or control is BaseButton or control is LineEdit):
					var bounds: Rect2 = control.get_global_rect()
					check(bounds.position.x >= -1 and bounds.end.x <= wallet.size.x+1, "Horizontal overflow on "+wallet.page+" ("+control.get_class()+") "+str(bounds))
			for pressed in [true,false]:
				var event := InputEventScreenTouch.new()
				event.index = 0
				event.pressed = pressed
				event.position = pos
				root.push_input(event, true)
			await process_frame
			if wallet.sheet_tween and wallet.sheet_tween.is_running(): await create_timer(.24).timeout
			touch_count += 1
			return
	check(false, "Missing button " + title)

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
	var down := InputEventScreenTouch.new()
	down.pressed = true; down.position = at
	root.push_input(down,true)
	var motion := InputEventScreenDrag.new()
	motion.position = at-Vector2(0,60); motion.relative = Vector2(0,-60)
	root.push_input(motion,true)
	var up := InputEventScreenTouch.new()
	up.position = motion.position; root.push_input(up,true)
	check(wallet.page==original_page and area.scroll_vertical>0,"Swipe starting on a control activated it or failed to scroll")
	area.scroll_vertical=0

func run() -> void:
	var dimensions := OS.get_environment("MDWA_TEST_VIEWPORT").split("x")
	if dimensions.size()==2:
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		root.size=Vector2i(int(dimensions[0]),int(dimensions[1]))
	wallet = load("res://wallet.tscn").instantiate()
	root.add_child(wallet)
	check(M.atomic_amount("10000000000000000.000001",6) == "10000000000000000000001","Large amount changed")
	check(M.atomic_amount("0.0000001",6) == "" and M.atomic_amount("-1",6) == "" and M.atomic_amount("0",6) == "","Invalid amount accepted")
	check(M.atomic_amount("1.1",0) == "" and M.atomic_amount("0.001",3) == "1","Token units changed")
	check(M.exceeds("100000000000000000001","100000000000000000000"),"Large overspend accepted")
	check(M.units("42600000000000000",15) == "42.6","Incorrect DUST precision")
	await tap("Explore demo wallet")
	check(wallet.page == "home","Demo did not open")
	await process_frame
	for label in wallet.body.find_children("*","Label",true,false):
		if label.text=="2,840.75": check(label.get_line_count()==1,"Balance wrapped across multiple lines")
	wallet._message(JSON.stringify({"type":"fatal","message":"Test worker stopped"}))
	check(wallet.demo and wallet.page == "home","Worker failure interrupted the offline demo")
	if OS.get_cmdline_user_args().size() and DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	await tap("Send")
	await drag_from_button()
	await tap("Use sample transfer")
	await tap("Review transfer")
	check(wallet.page == "review","Review not reached")
	await tap("Finish demo")
	check(wallet.page == "sent","Demo confirmation failed")
	await tap("Back to wallet")
	await tap("Send")
	await tap("Shielded")
	await tap("Use sample transfer")
	await tap("Review transfer")
	check(wallet.page == "review" and wallet.preview.outputs[0].kind == "shielded" and wallet.preview.outputs[0].type == M.DEMO_TYPE and wallet.preview.outputs[0].amount == "1","Shielded review used the wrong asset")
	await tap("Back")
	check(wallet.recipient == "Demo recipient" and wallet.amount == "1","Review lost its draft")
	await tap("Review transfer")
	await tap("Finish demo")
	await tap("Back to wallet")
	await tap("Receive")
	await tap("Shielded")
	check(wallet.receive_kind == "shielded","Address selector failed")
	await tap("Back")
	await tap("DUST generation")
	check(wallet.page == "dust","DUST view failed")
	await tap("Register NIGHT")
	check(wallet.page == "dust_review","DUST review failed")
	await tap("Confirm registration")
	check(wallet.page == "dust","DUST confirmation failed")
	await tap("Activity")
	await tap("Details")
	check(wallet.detail.get("kind") == "receive","Activity did not open the selected item")
	await tap("Back")
	await tap("Settings")
	await tap("Exit demo wallet")
	check(wallet.page == "welcome" and wallet.overview.is_empty(),"Demo data escaped its session")
	await bridge_checks()
	if not failed: print("Wallet UI checks passed at ",root.get_visible_rect().size,": ",touch_count," taps")
	quit(1 if failed else 0)

func bridge_checks():
	var engine := TestEngine.new()
	engine.wallet = wallet
	engine.available.shielded.append({"type":engine.second_token,"amount":"12345"})
	var state := {"network":"preview","hasWallet":false,"locked":true,"sync":{"status":"synced"},"addresses":{"shielded":"test shielded address","unshielded":"test public address","dust":"test dust address"}}
	wallet.bridge = engine
	wallet._message(JSON.stringify({"type":"state", "state":state}))
	await tap("Test local prover")
	check("verified" in wallet.proof_status,"Missing proof check result")
	await tap("Create wallet")
	await tap("I saved my phrase")
	await tap("Create wallet")
	check("last word" in wallet.feedback.text,"Missing phrase confirmation")
	var fields: Array = wallet.body.find_children("*","LineEdit",true,false)
	fields[0].text="abstract"; fields[1].text="test password"; fields[2].text="test password"
	await tap("Create wallet")
	check(engine.calls.back().method=="createWallet" and not engine.calls.back().params.restore,"Create request failed")
	wallet.go("welcome")
	await tap("Restore wallet")
	fields = wallet.body.find_children("*","LineEdit",true,false)
	fields[0].text="fixture"; fields[1].text="test password"; fields[2].text="test password"
	await tap("Restore wallet")
	check(engine.calls.back().params.restore,"Restore request failed")
	state.hasWallet=true
	wallet._message(JSON.stringify({"type":"state","state":state}))
	wallet.body.find_children("*","LineEdit",true,false)[0].text="test password"
	await tap("Unlock wallet")
	check(engine.calls.back().method=="unlock","Unlock request failed")
	state.locked=false
	wallet._message(JSON.stringify({"type":"state","state":state}))
	await process_frame
	await tap("Send")
	await tap("Shielded")
	await tap("Choose token")
	await tap("Select",1)
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(state.addresses.shielded)
		await tap("Paste")
		check(wallet.recipient==state.addresses.shielded,"Clipboard recipient did not populate")
	await tap("Use my address")
	fields = wallet.body.find_children("*","LineEdit",true,false)
	fields[1].text="12.346"
	await tap("Review transfer")
	check(wallet.page=="send" and "exceeds" in wallet.feedback.text,"Overspend accepted")
	fields[1].text="12.345"
	await tap("Review transfer")
	check(wallet.page=="review" and wallet.preview.outputs==[{"kind":"shielded","type":engine.second_token,"recipient":state.addresses.shielded,"amount":"12345"}],"Shielded token label, recipient or precision lost")
	await tap("Back")
	check(engine.calls.any(func(c):return c.method=="cancel" and c.params.id=="recipe"),"Back did not release booked coins")
	await tap("Review transfer")
	await tap("Confirm and send")
	check(wallet.page=="sent" and wallet.last_tx=="test-id","Send did not reach receipt")
	await process_frame
	var timed: Array = wallet.body.find_children("*","Label",true,false).map(func(label):return label.text)
	check("GPU · output" in timed and "1.7s" in timed and "Partially successful" in timed,"Finalized timing or indexed execution status missing")
	await tap("Back to wallet")
	await tap("Receive")
	await tap("DUST")
	await tap("Unshielded")
	await tap("Back")
	await tap("DUST generation")
	await tap("Stop generation")
	await tap("Confirm deregistration")
	check(engine.calls.any(func(c):return c.method=="dustApply"),"DUST request missing")
	await tap("Back to wallet")
	await tap("Activity")
	await tap("Next")
	check(wallet.history_offset==12 and wallet.history.size()==1,"Next page not loaded")
	await tap("Previous")
	check(wallet.history_offset==0 and wallet.history.size()==3,"Previous page not loaded")
	await tap("Settings")
	await tap("Wallet")
	check(wallet.page=="home","Wallet tab did not restore the overview")
	await tap("Explore")
	await tap("mdwa test dApp")
	await tap("Token contract")
	await tap("Deploy contract")
	check(wallet.page=="contract_review" and wallet.preview.action=="deploy","Deployment review missing")
	await tap("Confirm deployment")
	await tap("Back to wallet")
	await tap("Explore")
	await tap("mdwa test dApp")
	await tap("Token contract")
	await tap("Mint unshielded")
	check(wallet.preview.action=="mintUnshielded","Wrong public mint action")
	await tap("Back")
	await tap("Mint shielded")
	check(wallet.preview.action=="mintShielded","Wrong shielded mint action")
	await tap("Confirm mint")
	await tap("Back to wallet")
	await tap("Explore")
	await tap("mdwa test dApp")
	await tap("Counter contract")
	await tap("Deploy contract")
	await tap("Confirm deployment")
	await tap("Back to wallet")
	await tap("Explore")
	await tap("mdwa test dApp")
	await tap("Counter contract")
	await tap("Increment counter")
	check(wallet.preview.action=="increment","Incorrect counter call")
	await tap("Confirm increment")
	await tap("Back to wallet")
	await tap("Edit token label")
	fields = wallet.body.find_children("*","LineEdit",true,false)
	fields[0].text="Glass token"; fields[1].text="GLASS"; fields[2].text="0"
	await tap("Save label")
	check(wallet.page=="home" and engine.calls.any(func(c):return c.method=="setTokenLabel"),"Label not saved")
	engine.available.unshielded = []
	await tap("Send")
	await tap("Receive unshielded tokens")
	check(wallet.page=="receive" and wallet.receive_kind=="unshielded","Empty public balance opened the wrong receive form")
	await tap("Back")
	await tap("Settings")
	await tap("Connection")
	await tap("Save connection")
	await tap("Connection")
	await tap("Restore defaults")
	await tap("Proving")
	await tap("Proof server")
	await tap("Save proving")
	check(engine.entry.prover.kind=="server","Prover setting did not persist")
	await tap("Proving")
	await tap("On device")
	await tap("Save proving")
	await tap("Rescan")
	await tap("Back")
	await tap("Remove wallet…")
	await tap("Remove from this device")
	check("password" in wallet.feedback.text,"Removal guard missing")
	await tap("Back")
	await tap("Explore")
	await tap("Find transaction")
	await tap("Look up")
	check("64-character" in wallet.feedback.text,"Invalid hash accepted")
	wallet.body.find_children("*","LineEdit",true,false)[0].text="a".repeat(64)
	await tap("Look up")
	check(wallet.chain_receipt.is_empty() and wallet.watching_hash=="a".repeat(64),"Unindexed receipt did not subscribe")
	state.sync.tip=124
	wallet._message(JSON.stringify({"type":"state","state":state}))
	await process_frame
	check(wallet.chain_receipt.block==123 and wallet.chain_receipt.execution=="SUCCESS","WebSocket head did not update receipt")
	if DisplayServer.get_name() != "headless":
		await tap("Copy hash")
		check(DisplayServer.clipboard_get()=="a".repeat(64),"Receipt hash copy failed")
	await tap("Back")
	await tap("Settings")
	await tap("Lock wallet")
	check(engine.calls.back().method=="lock","Lock request failed")
	wallet._message(JSON.stringify({"type":"fatal","message":"Interrupted test startup"}))
	await tap("Retry")
	check(engine.retries==1,"Retry did not restart the worker")
