class_name Mutators
extends RefCounted

const ICE_STORM := "ice_storm"
const EXPLOSIVE_FRENZY := "explosive_frenzy"
const EMP_OVERLOAD := "emp_overload"
const IRON_RAM := "iron_ram"
const HARDCORE_WAVES := "hardcore_waves"
const SNIPER_ELITE := "sniper_elite"

const ALL := [ICE_STORM, EXPLOSIVE_FRENZY, EMP_OVERLOAD, IRON_RAM, HARDCORE_WAVES, SNIPER_ELITE]

static var active := ""

static func activate(id: String) -> void:
	active = id if ALL.has(id) else ""

static func is_on(id: String) -> bool:
	return active == id

static func apply_mods(mods: Dictionary) -> void:
	match active:
		IRON_RAM:
			mods["ramMult"] = float(mods["ramMult"]) * Cfg.MUT_IRON_RAM_MULT
		SNIPER_ELITE:
			mods["bulletSpeedMult"] = float(mods["bulletSpeedMult"]) * Cfg.MUT_SNIPER_SPEED_MULT
			mods["accuracyBonus"] = float(mods["accuracyBonus"]) + Cfg.MUT_SNIPER_ACCURACY

static func dash_distance(base: float) -> float:
	return base * Cfg.MUT_IRON_DASH_MULT if active == IRON_RAM else base

static func traction_scale() -> float:
	return Cfg.MUT_ICE_TRACTION if active == ICE_STORM else 1.0

static func barrel_count(base: int) -> int:
	return base * Cfg.MUT_BARREL_MULT if active == EXPLOSIVE_FRENZY else base

static func emp_charge_scale() -> float:
	return Cfg.MUT_EMP_SPEED if active == EMP_OVERLOAD else 1.0

static func wave_size(base: int) -> int:
	if active != HARDCORE_WAVES:
		return base
	return mini(Cfg.DEFENSE_WAVE_CAP, int(ceil(float(base) * Cfg.MUT_WAVE_SIZE_MULT)))

static func cryo_ticks() -> int:
	return Cfg.MUT_CRYO_TICKS if active == ICE_STORM else 0
