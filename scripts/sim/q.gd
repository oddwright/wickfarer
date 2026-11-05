class_name Q
extends RefCounted
## Fixed-step quantiser for simulation numbers. See Ship.quantize().

const STEP := 1.0 / 1024.0


static func q(x: float) -> float:
	return roundf(x / STEP) * STEP
