class_name DiscordSDK
extends Node

signal packet_received
signal _command_response_received

signal dispatch_ready
signal dispatch_error
signal dispatch_voice_state_update
signal dispatch_speaking_start
signal dispatch_speaking_stop
signal dispatch_activity_layout_mode_update
signal dispatch_orientation_update
signal dispatch_current_user_update
signal dispatch_thermal_state_update
signal dispatch_activity_instance_participants_update
signal dispatch_entitlement_create
signal dispatch_current_guild_member_update
signal dispatch_any

var callback_func : JavaScriptObject = JavaScriptBridge.create_callback(_handle_message);
var frame_id : String
var instance_id : String
var platform : String
var channel_id : String
var client_id : String
var guild_id : String
var user_id : String

var source : JavaScriptObject
var source_origin : String

var is_ready = false
var subscribed = false
var in_js = false

var _events = ["VOICE_STATE_UPDATE", "SPEAKING_START", "SPEAKING_STOP",
	"ACTIVITY_LAYOUT_MODE_UPDATE", "ORIENTATION_UPDATE", "CURRENT_USER_UPDATE",
	"THERMAL_STATE_UPDATE", "ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE", "ENTITLEMENT_CREATE",
	"CURRENT_GUILD_MEMBER_UPDATE"]

func _handle_message(event):
	var data_json = JavaScriptBridge.get_interface("JSON").stringify(event[0].data[1])
	var data = JSON.parse_string(data_json)
	
	# Add to the packet response buffer so we can access them from functions later on
	if (event[0].data[0] == 1): # Opcode.FRAME
		if (data["cmd"] == "DISPATCH"):
			_handle_dispatch(data)
		elif (data["nonce"] != null):
			_command_response_received.emit(data)
		else:
			packet_received.emit(event[0].data[0], data)
	else:
		packet_received.emit(event[0].data[0], data)

func _handle_dispatch(data):
	var event = data["evt"]
	dispatch_any.emit(event, data["data"])
	match event:
		"READY":
			is_ready = true
			dispatch_ready.emit(data["data"])
		"ERROR":
			dispatch_error.emit(data["data"])
		"VOICE_STATE_UPDATE":
			dispatch_voice_state_update.emit(data["data"])
		"SPEAKING_START":
			dispatch_speaking_start.emit(data["data"])
		"SPEAKING_STOP":
			dispatch_speaking_stop.emit(data["data"])
		"ACTIVITY_LAYOUT_MODE_UPDATE":
			dispatch_activity_layout_mode_update.emit(data["data"])
		"ORIENTATION_UPDATE":
			dispatch_orientation_update.emit(data["data"])
		"CURRENT_USER_UPDATE":
			user_id = data["data"]["id"]
			dispatch_current_user_update.emit(data["data"])
		"THERMAL_STATE_UPDATE":
			dispatch_thermal_state_update.emit(data["data"])
		"ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE":
			dispatch_activity_instance_participants_update.emit(data["data"])
		"ENTITLEMENT_CREATE":
			dispatch_entitlement_create.emit(data["data"])
		"CURRENT_GUILD_MEMBER_UPDATE":
			dispatch_current_guild_member_update.emit(data["data"])
		_:
			print("_handle_dispatch: Warning! Unknown event: " + str(event)) # convert to string just to be sure

func _ready():
	# For some reason, OS.has_feature("web") sometimes returns false in web
	# Added a OS.get_name() check to be sure
	in_js = OS.has_feature("web") || OS.get_name() == "Web"
	if (in_js):
		JavaScriptBridge.get_interface("window").addEventListener("message", callback_func);
	else:
		print("Not in a JavaScript environment. Discord SDK will not work.")

func init(client_id_: String):
	if (not in_js):
		print("Not in a JavaScript environment. Ignoring call to init()")
		return
	var query_parts = str(JavaScriptBridge.eval("window.location.search")).trim_prefix("?").split("&", false)
	var query_map = {}
	for part in query_parts:
		var parts = part.split("=")
		query_map[parts[0]] = parts[1]
	
	if (!query_map.has("frame_id")):
		push_error("frameId query variable is not set!")	
	if (!query_map.has("instance_id")):
		push_error("instanceId query variable is not set!")
	if (!query_map.has("platform")):
		push_error("platform query variable is not set!")
	
	frame_id = query_map["frame_id"]
	instance_id = query_map["instance_id"]
	platform = query_map["platform"]
	channel_id = query_map["channel_id"]
	guild_id = query_map["guild_id"]
	client_id = client_id_
	
	source = JavaScriptBridge.get_interface("window").parent.opener
	if (source == null):
		source = JavaScriptBridge.get_interface("window").parent
	JavaScriptBridge.eval("window.source = window.parent.opener ?? window.parent", true)
	
	source_origin = JavaScriptBridge.eval("!!document.referrer ? document.referrer : '*'")
	handshake()

func sendMessage(opcode, body):
	if (not in_js):
		print("Not in a JavaScript environment. Ignoring call to sendMessage()")
		return
	var data = [
		opcode,
		body
	]
	# note about this, source.postMessage doesn't work, because `data` somehow 
	# turns into `undefined` somewhere. not sure how to fix, but this works
	# for now.
	JavaScriptBridge.eval("window.source.postMessage(" + JSON.stringify(data).replace("'", "\\'") + ", '*')", false)
	#source.postMessage(data, "*")

func sendCommand(cmd, args, nonce):
	if (not in_js):
		print("Not in a JavaScript environment. Ignoring call to sendCommand()")
		return
	sendMessage(1, {
		"cmd": cmd,
		"args": args,
		"nonce": nonce
	})
	
func _gen_nonce():
	var chars = "0123456789abcdef"
	var output_string := ""

	for i in range(8):
		output_string += chars[randi() % chars.length()]
	output_string += "-"
	for i in range(4):
		output_string += chars[randi() % chars.length()]
	output_string += "-"
	for i in range(4):
		output_string += chars[randi() % chars.length()]
	output_string += "-"
	for i in range(4):
		output_string += chars[randi() % chars.length()]
	output_string += "-"
	for i in range(12):
		output_string += chars[randi() % chars.length()]

	return output_string

func subscribe_to_events():
	if subscribed: return
	for event in _events:
		sendMessage(1, {
			"cmd": "SUBSCRIBE",
			"evt": event,
			"args": {
				"channel_id": channel_id,
				"guild_id": guild_id
			},
			"nonce": _gen_nonce()
		})
	subscribed = true

func handshake():
	print("Shaking hands")
	sendMessage(0, {
		"v": 1,
		"encoding": "json",
		"client_id": client_id,
		"frame_id": frame_id
	})

func ready():
	if (is_ready):
		return
	else:
		await self.dispatch_ready

func close(code: int, message: String):
	# we dont wait for nonce here
	sendMessage(2, {
		"code": code,
		"message": message,
		"nonce": _gen_nonce()
	})

func _wait_for_nonce(nonce):
	var noMatches = true
	var packet = null
	while noMatches:
		# TODO: just get packet from this event instead of using a buffer
		var tmppacket = await self._command_response_received
		if (tmppacket["nonce"] == nonce):
			noMatches = false
			packet = tmppacket
			break
	return packet["data"]

func command_authorize(response_type: String, scopes: Array, state: String):
	var nonce = _gen_nonce()
	sendCommand("AUTHORIZE", {
		"client_id": client_id,
		"prompt": "none",
		"response_type": response_type,
		"scope": scopes,
		"state": state
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet

func command_authenticate(access_token: String):
	var nonce = _gen_nonce()
	sendCommand("AUTHENTICATE", {
		"access_token": access_token
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet

func command_capture_log(level: String, message: String):
	var nonce = _gen_nonce()
	sendCommand("CAPTURE_LOG", {
		"level": level,
		"message": message
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet

func command_encourage_hardware_acceleration():
	var nonce = _gen_nonce()
	sendCommand("ENCOURAGE_HW_ACCELERATION", {}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_get_channel(id: String):
	var nonce = _gen_nonce()
	sendCommand("GET_CHANNEL", {
		"channel_id": id
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_get_channel_permissions():
	var nonce = _gen_nonce()
	sendCommand("GET_CHANNEL_PERMISSIONS", {}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_get_entitlements_embedded():
	var nonce = _gen_nonce()
	sendCommand("GET_ENTITLEMENTS_EMBEDDED", {}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_get_instance_connected_participants():
	var nonce = _gen_nonce()
	sendCommand("GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS", {}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_get_platform_behaviors():
	var nonce = _gen_nonce()
	sendCommand("GET_PLATFORM_BEHAVIORS", {}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_get_skus():
	var nonce = _gen_nonce()
	sendCommand("GET_SKUS_EMBEDDED", {}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_initiate_image_upload():
	var nonce = _gen_nonce()
	sendCommand("INITIATE_IMAGE_UPLOAD", {}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_open_external_link(url: String):
	var nonce = _gen_nonce()
	sendCommand("OPEN_EXTERNAL_LINK", {
		"url": url
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_open_invite_dialog():
	var nonce = _gen_nonce()
	sendCommand("OPEN_INVITE_DIALOG", {}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_open_share_moment_dialog(media_url: String):
	var nonce = _gen_nonce()
	sendCommand("OPEN_SHARE_MOMENT_DIALOG", {
		"mediaUrl": media_url
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_set_activity(state: String, details: String, timestamps: Dictionary = {}, assets: Dictionary = {}, party: Dictionary = {}, secrets: Dictionary = {}, instance: bool = false):
	var nonce = _gen_nonce()
	sendCommand("SET_ACTIVITY", {
		"activity": {
			"state": state,
			"details": details,
			"timestamps": timestamps,
			"assets": assets,
			"party": party,
			"secrets": secrets,
			"instance": instance
		}
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_set_config(use_interactive_pip: bool):
	var nonce = _gen_nonce()
	sendCommand("SET_CONFIG", {
		"use_interactive_pip": use_interactive_pip
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet



# UNHANDLED: -1
# PORTRAIT: 0
# LANDSCAPE: 1
func command_set_orientation_lock_state(lock_state: int, pip_lock_state: int, grid_lock_state: int):
	var nonce = _gen_nonce()
	sendCommand("SET_ORIENTATION_LOCK_STATE", {
		"lock_state": lock_state,
		"pip_lock_state": pip_lock_state,
		"grid_lock_state": grid_lock_state
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_start_purchase(sku_id: String, pid: int):
	var nonce = _gen_nonce()
	sendCommand("START_PURCHASE", {
		"sku_id": sku_id,
		"pid": pid
	}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet


func command_user_settings_get_locale():
	var nonce = _gen_nonce()
	sendCommand("USER_SETTINGS_GET_LOCALE", {}, nonce)
	
	var packet = await _wait_for_nonce(nonce)
	return packet
