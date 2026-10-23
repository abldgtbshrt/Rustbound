extends Node

## One-shot sound effects. Sounds are files in res://assets/audio/sfx/ named
## after their id (`enemy_die.wav`, `fire_gun_nail.ogg`...). A missing file
## is simply silent, so code can reference a sound before anyone has made it.
##
##   Sfx.play(&"scrap")
##
## Each sound has a voice cap and a minimum gap so a horde of identical events
## (40 nails hitting at once) stays readable instead of turning into noise.
## Weapons get "fire_<part id>", falling back to "fire_default".

const SFX_DIR := "res://assets/audio/sfx/"
const EXTENSIONS := ["wav", "ogg"]
const POOL_SIZE := 24

## id -> {bus, cap (voices at once), gap (s between starts), db, jitter (pitch)}
const SOUNDS := {
	&"fire_default": {"cap": 3, "gap": 0.05, "db": -8.0},
	&"fire_gun_nail": {"cap": 3, "gap": 0.05, "db": -10.0},
	&"fire_gun_rivet": {"cap": 2, "gap": 0.08, "db": -6.0},
	&"fire_gun_laser": {"cap": 2, "gap": 0.1, "db": -6.0},
	&"fire_gun_flamethrower": {"cap": 1, "gap": 0.12, "db": -12.0},
	&"fire_gun_boomerang": {"cap": 2, "gap": 0.1, "db": -8.0},
	&"fire_gun_drone_bay": {"cap": 3, "gap": 0.06, "db": -12.0},
	&"fire_melee_chain_sword": {"cap": 2, "gap": 0.1, "db": -6.0},
	&"fire_sig_tesla_coil": {"cap": 2, "gap": 0.1, "db": -6.0},
	&"fire_sig_mortar": {"cap": 2, "gap": 0.1, "db": -4.0},
	&"enemy_die": {"cap": 4, "gap": 0.03, "db": -8.0, "jitter": 0.15},
	&"robot_hit": {"cap": 1, "gap": 0.18, "db": -6.0},
	&"robot_die": {"cap": 1, "gap": 0.5, "db": 0.0, "jitter": 0.0},
	&"scrap": {"cap": 3, "gap": 0.03, "db": -10.0, "jitter": 0.0},
	&"part_pickup": {"cap": 1, "gap": 0.1, "db": -4.0},
	&"attach": {"cap": 1, "gap": 0.05, "db": -6.0, "bus": "UI"},
	&"level_up": {"cap": 1, "gap": 0.3, "db": -2.0, "jitter": 0.0, "bus": "UI"},
	&"vent": {"cap": 1, "gap": 0.2, "db": -2.0},
	&"stomp": {"cap": 2, "gap": 0.1, "db": -4.0},
	&"warn_heat": {"cap": 1, "gap": 1.0, "db": -4.0, "jitter": 0.0, "bus": "UI"},
	&"warn_power": {"cap": 1, "gap": 1.0, "db": -4.0, "jitter": 0.0, "bus": "UI"},
	&"ui_open": {"cap": 1, "gap": 0.05, "db": -8.0, "jitter": 0.0, "bus": "UI"},
	&"ui_close": {"cap": 1, "gap": 0.05, "db": -8.0, "jitter": 0.0, "bus": "UI"},
}
const DEFAULTS := {"bus": "SFX", "cap": 2, "gap": 0.05, "db": 0.0, "jitter": 0.08}

## Scrap pickups in quick succession climb in pitch (up to an octave).
const SCRAP_CHAIN_WINDOW := 0.45
const SCRAP_CHAIN_STEP := 0.04

## Starts that actually played, and ones dropped by caps (tests, F3).
var played: int = 0
var dropped: int = 0
var last_id: StringName = &""

var _streams: Dictionary = {} # id -> AudioStream or null (missing)
var _last_start: Dictionary = {} # id -> msec
var _pool: Array[AudioStreamPlayer] = []
var _owner_id: Array[StringName] = []
var _rng := RandomNumberGenerator.new()
## Headless (tests, CI): voices are tracked but nothing is sent to the audio
## server, which has no real output there anyway.
var _virtual := false
var _virtual_until: Array[int] = []
var _scrap_chain := 0
var _scrap_last := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # menus make sounds while paused
	_virtual = DisplayServer.get_name() == "headless"
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_pool.append(p)
		_owner_id.append(&"")
		_virtual_until.append(0)
	EventBus.weapon_fired.connect(func(part_id: StringName, _at: Vector3) -> void: play_weapon(part_id))
	EventBus.enemy_killed.connect(func(_e: EnemyData, _at: Vector3) -> void: play(&"enemy_die"))
	EventBus.robot_damaged.connect(func(_a: float) -> void: play(&"robot_hit"))
	EventBus.robot_destroyed.connect(func() -> void: play(&"robot_die"))
	EventBus.scrap_collected.connect(func(_n: int) -> void: _play_scrap())
	EventBus.part_picked_up.connect(func(_p: PartData, _a: bool) -> void: play(&"part_pickup"))
	EventBus.part_attached.connect(func(_id: StringName) -> void: play(&"attach"))
	EventBus.robot_vented.connect(func(_a: float, _h: int) -> void: play(&"vent"))
	EventBus.robot_stomped.connect(func(_d: float, _h: int) -> void: play(&"stomp"))
	EventBus.robot_overheat.connect(func() -> void: play(&"warn_heat"))
	EventBus.robot_brownout.connect(func() -> void: play(&"warn_power"))
	RunState.leveled_up.connect(func(_l: int) -> void: play(&"level_up"))


func _exit_tree() -> void:
	stop_all()
	_streams.clear()


## Stops every voice and lets go of its stream.
func stop_all() -> void:
	for i in _pool.size():
		_pool[i].stop()
		_pool[i].stream = null
		_virtual_until[i] = 0


## True if a file exists for this sound id.
func has_sound(id: StringName) -> bool:
	return _stream(id) != null


func play_weapon(part_id: StringName) -> bool:
	var id := StringName("fire_" + String(part_id))
	return play(id if has_sound(id) else &"fire_default")


## Plays a sound if it exists and isn't over its voice cap or too soon after
## the last start. Returns true if it started.
func play(id: StringName, pitch: float = 1.0, volume_db: float = 0.0) -> bool:
	var stream := _stream(id)
	if stream == null:
		return false
	var def := _def(id)
	var now := Time.get_ticks_msec()
	if now - int(_last_start.get(id, -100000)) < int(float(def["gap"]) * 1000.0):
		dropped += 1
		return false
	var voices := 0
	var slot := -1
	for i in _pool.size():
		var busy := (now < _virtual_until[i]) if _virtual else _pool[i].playing
		if busy and _owner_id[i] == id:
			voices += 1
		elif not busy and slot < 0:
			slot = i
	if voices >= int(def["cap"]) or slot < 0:
		dropped += 1
		return false
	var p := _pool[slot]
	p.stream = stream
	p.bus = String(def["bus"])
	p.volume_db = float(def["db"]) + volume_db
	var j := float(def["jitter"])
	p.pitch_scale = maxf(pitch * (1.0 + _rng.randf_range(-j, j)), 0.05)
	if _virtual:
		_virtual_until[slot] = now + int(stream.get_length() / p.pitch_scale * 1000.0)
	else:
		p.play()
	_owner_id[slot] = id
	_last_start[id] = now
	played += 1
	last_id = id
	return true


func _play_scrap() -> void:
	var now := Time.get_ticks_msec()
	_scrap_chain = _scrap_chain + 1 if now - _scrap_last < int(SCRAP_CHAIN_WINDOW * 1000.0) else 0
	_scrap_last = now
	play(&"scrap", pow(2.0, minf(_scrap_chain * SCRAP_CHAIN_STEP, 1.0)))


func _def(id: StringName) -> Dictionary:
	var d: Dictionary = DEFAULTS.duplicate()
	d.merge(SOUNDS.get(id, {}), true)
	return d


func _stream(id: StringName) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var s: AudioStream = null
	for ext in EXTENSIONS:
		var path := "%s%s.%s" % [SFX_DIR, id, ext]
		if ResourceLoader.exists(path):
			s = load(path) as AudioStream
			break
	_streams[id] = s
	return s
