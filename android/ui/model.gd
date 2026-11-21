extends RefCounted

# Amounts stay in decimal strings across the mobile bridge, including values
# beyond the integer and floating-point precision of the rendering runtime.
static func units(raw: String, decimals: int) -> String:
	var neg := raw.begins_with("-")
	var digits := raw.trim_prefix("-").lpad(decimals + 1, "0")
	var split := digits.length() - decimals
	var whole := digits.left(split)
	var grouped := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0: grouped += ","
		grouped += whole[i]
	var fraction := digits.substr(split).rstrip("0")
	return ("−" if neg else "") + grouped + ("" if fraction.is_empty() else "." + fraction)

static func atomic_amount(input: String, decimals: int) -> String:
	var amount := input.strip_edges()
	var parts := amount.split(".", true)
	if parts.size() > 2 or parts[0].is_empty(): return ""
	for i in amount.length():
		if amount[i] != "." and (amount.unicode_at(i) < 48 or amount.unicode_at(i) > 57): return ""
	var fraction := "" if parts.size() == 1 else parts[1]
	if fraction.length() > decimals: return ""
	return (parts[0] + fraction.rpad(decimals, "0")).lstrip("0")

static func exceeds(atomic: String, available: String) -> bool:
	return atomic.length() > available.length() or (atomic.length() == available.length() and atomic > available)

const NIGHT_TYPE := "0000000000000000000000000000000000000000000000000000000000000000"
const DEMO_TYPE := "d1b3f32e66ba000000000000000000000000000000000000000000000000fe91"
const SAMPLE := {
	"night": {"available":"2840750000","pending":"0"},
	"dust": {"balance":"42600000000000000","cap":"60000000000000000","registeredNight":"1200000000","unregisteredNight":"1640750000"},
	"unshielded": [{"type": NIGHT_TYPE,"amount":"2840750000"}], "shielded":[{"type": DEMO_TYPE,"amount":"125"}]
}
const HISTORY := [
	{"kind":"receive","status":"finalized","hash":"Sample receipt 01","deltas":[{"type":NIGHT_TYPE,"amount":"125000000","kind":"unshielded"}]},
	{"kind":"send","status":"finalized","hash":"Sample payment 02","deltas":[{"type":NIGHT_TYPE,"amount":"-34250000","kind":"unshielded"}]},
	{"kind":"dust","status":"confirmed","hash":"Sample registration 03","deltas":[]}
]

const BIP39 = preload("res://bip39.gd")
static var _word_set := {}

static func wordlist() -> Array:
	return BIP39.WORDS.duplicate()

static func is_word(word: String) -> bool:
	if _word_set.is_empty():
		for w in BIP39.WORDS: _word_set[w] = true
	return _word_set.has(word)

# Up to `limit` list words that start with `prefix`, in list order.
static func complete(prefix: String, limit := 4) -> Array:
	var out := []
	for w in BIP39.WORDS:
		if w.begins_with(prefix):
			out.append(w)
			if out.size() >= limit: break
	return out
