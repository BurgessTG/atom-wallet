# Run with godot --path android/ui --script ../check-ui.gd
extends SceneTree

const M = preload("res://model.gd")
var wallet: Control
var failed := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func tap(title: String) -> void:
	await process_frame
	await process_frame
	for item in wallet.find_children("*","Button",true,false):
		if item.accessibility_name == title and item.is_visible_in_tree():
			var pos: Vector2 = item.get_global_rect().get_center()
			for pressed in [true,false]:
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				event.position = pos
				root.push_input(event, true)
			await process_frame
			return
	check(false, "Missing button " + title)

func run() -> void:
	wallet = load("res://wallet.tscn").instantiate()
	root.add_child(wallet)
	check(M.stars("10000000000000000.000001") == "10000000000000000000001","Large amount changed")
	check(M.stars("0.0000001") == "" and M.stars("-1") == "" and M.stars("0") == "","Invalid amount accepted")
	check(M.units("42600000000000000",15) == "42.6","Incorrect DUST precision")
	await tap("Explore demo wallet")
	check(wallet.page == "home","Demo did not open")
	wallet._message(JSON.stringify({"type":"fatal","message":"Test worker stopped"}))
	check(wallet.demo and wallet.page == "home","Worker failure interrupted the offline demo")
	if OS.get_cmdline_user_args().size() and DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	await tap("Send")
	await tap("Use sample transfer")
	await tap("Review transfer")
	check(wallet.page == "review","Review not reached")
	await tap("Finish demo")
	check(wallet.page == "sent","Demo confirmation failed")
	await tap("Back to wallet")
	await tap("Receive")
	await tap("Shielded")
	check(wallet.receive_kind == "shielded","Address selector failed")
	await tap("Back")
	await tap("View DUST generation")
	check(wallet.page == "dust","DUST view failed")
	await tap("Register NIGHT")
	check(wallet.page == "dust_review","DUST review failed")
	await tap("Confirm registration")
	check(wallet.page == "dust","DUST confirmation failed")
	await tap("Activity")
	await tap("Details")
	check(wallet.detail.get("kind") == "receive","Activity did not open the selected item")
	await tap("Back")
	await tap("Session")
	await tap("Exit demo wallet")
	check(wallet.page == "welcome" and wallet.overview.is_empty(),"Demo data escaped its session")
	if not failed: print("Wallet UI checks passed")
	quit(1 if failed else 0)
