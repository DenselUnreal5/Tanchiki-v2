extends Node

var failures := 0

func check(value: bool, label: String) -> void:
	print("OK: " if value else "FAIL: ", label)
	if not value:
		failures += 1

func _ready() -> void:
	Net.set_transport(NetTransport.EnetTransport.new())
	check(not Net.host_game(65536), "invalid port rejected")
	check(not Net.join_game("   "), "empty address rejected")
	check(Net.role == "", "invalid address leaves no session")
	check(Net.host_game(18124), "host opens port")
	var other := NetTransport.EnetTransport.new(18124)
	check(other.host(1) == null, "occupied port rejected")
	Net.leave()
	check(Net.join_game("127.0.0.1", 18125), "connection attempt starts")
	Net._connect_deadline = Time.get_ticks_msec() - 1
	Net._process(0.0)
	check(Net.role == "" and Net._peer == null, "timeout closes peer and session")
	check(Net.host_game(18124), "hosting works after timeout")
	Net.leave()
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for i in 3:
		await get_tree().process_frame
	game.ui.open_net()
	await get_tree().process_frame
	var address_found := false
	for field in game.ui._net_body.find_children("*", "LineEdit", true, false):
		if field.placeholder_text == "IP / hostname":
			address_found = true
	check(address_found, "network menu exposes direct connection without Steam")
	game.ui.close_net()
	print("CONNECTION CHECK failures: ", failures)
	get_tree().quit(1 if failures else 0)
