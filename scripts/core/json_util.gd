class_name JsonUtil
extends RefCounted
## JSON.stringify drops float precision by default, which made resumed
## fights drift from the original. Always save through this.


static func s(data: Variant) -> String:
	return JSON.stringify(data, "", false, true)


## Same data, same text: sorted keys, and ints and floats normalised the way
## a save round trip sees them. Used to compare states in tests.
static func canonical(data: Variant) -> String:
	return JSON.stringify(JSON.parse_string(s(data)), "", true, true)
