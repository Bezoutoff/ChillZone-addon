#!/usr/bin/env bash
# 1.3.4: the launch identities in the signing script (scripts/council-sign.py): king, treasurer,
# author, realm and --group, end to end with a throwaway key in a temporary folder (never the
# author's: HOME and every path point into it, removed at the end). Invented names only. Run by
# tests/sign-roundtrip.sh; skipped without python3 (CI has it).
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v python3 >/dev/null 2>&1; then
	printf 'python3 not found: launch identities signing skipped\n'
	exit 0
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export HOME="$scratch/home"
export OLYMPUS_COUNCIL_KEY="$scratch/keys/council-key.json"
export OLYMPUS_COUNCIL_OUT="$scratch/out.lua"
export OLYMPUS_COUNCIL_JSON="$scratch/council.json"
mkdir -p "$HOME"
cd "$scratch"
signer="$repo_root/scripts/council-sign.py"
fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}
last_at() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("last_at"))' "$OLYMPUS_COUNCIL_KEY"; }
sum() { python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
python3 "$signer" keygen > /dev/null

# A council of the beta, as the author's file holds it before the launch: a Steward on the beta.
cat > "$OLYMPUS_COUNCIL_JSON" <<'JSON'
{"members": [{"name": "Test Councillor", "title": "Council Speaker"}], "stewards": ["Old Steward-ClassicBetaPvP"]}
JSON
python3 "$signer" council > /dev/null

# --group: refused while a name of another realm group is in the file, with every one of them and
# what takes it off; nothing signed, nothing changed.
before=$(last_at); file_before=$(sum "$OLYMPUS_COUNCIL_JSON")
if python3 "$signer" council --group "Launchrealm+Launchtwo" > refused.txt 2>&1; then fail 'moved to a group a Steward is not of'; fi
grep -Fq 'Old Steward-ClassicBetaPvP (steward --remove)' refused.txt || fail 'the refusal does not name the Steward and how to take him off'
if grep -Fq 'Traceback' refused.txt; then fail 'a crash, not a refusal'; fi
[ "$(last_at)" = "$before" ] || fail "a refused --group moved the key's last time"
[ "$(sum "$OLYMPUS_COUNCIL_JSON")" = "$file_before" ] || fail 'a refused --group changed the council file'
for bad in '' 'Launch realm' 'Launch-realm' 'A+A' 'A~B' 'A^B'; do
	if python3 "$signer" council --group "$bad" > refused.txt 2>&1; then fail "a realm group taken: '$bad'"; fi
	if grep -Fq 'Traceback' refused.txt; then fail "a crash, not a refusal: --group '$bad'"; fi
done
if python3 "$signer" check --group "Launchrealm" > refused.txt 2>&1; then fail '--group with a command that signs nothing'; fi
printf 'ok: --group refused while a name of another group is in the file, or for a malformed group\n'

python3 "$signer" steward --remove 'Old Steward-ClassicBetaPvP' > /dev/null
python3 "$signer" council --group 'Launchrealm+Launchtwo' > /dev/null
python3 -c 'import json, sys; assert json.load(open(sys.argv[1]))["realm"] == "Launchrealm+Launchtwo"' "$OLYMPUS_COUNCIL_JSON" \
	|| fail '--group not kept in the council file'
python3 "$signer" check > check.txt || fail 'check refused the moved list'
grep -Fq 'titles: signature good' check.txt && grep -Fq 'realm group Launchrealm+Launchtwo' check.txt || fail 'the lists are not for the launch group'
printf 'ok: the council moved to the launch realm group, kept in its file\n'

# The identities, each signing the whole council and printing the titles list to paste.
python3 "$signer" author ' Quill Maker-Launchrealm ' > author.txt
grep -Fq 'to paste in game with /oly approved paste:' author.txt || fail 'author does not print the list to paste'
python3 "$signer" author 'Quill Horde-Launchrealm' Horde > /dev/null
python3 "$signer" king 'Crown Owl-Launchrealm' > /dev/null
python3 "$signer" king 'Tusk Crown-Launchtwo' Horde > /dev/null
python3 "$signer" treasurer 'Ledger Wren-Launchrealm, Ledger Post-Launchtwo' > /dev/null
python3 "$signer" realm Launchrealm pvp NA > /dev/null
python3 "$signer" realm "Kel'thas" rppvp EU > /dev/null
python3 "$signer" realm Launchtwo hardcore NA > /dev/null
python3 "$signer" realm Launchtwo pve NA > realm.txt # (named again: changed)
pasted=$(tail -n 1 realm.txt)
python3 "$signer" check > check.txt || fail 'check refused the launch list'
for want in "the Alliance King (signed): Crown Owl-Launchrealm" "the Horde King (signed): Tusk Crown-Launchtwo" \
	"the Alliance Treasurer, then his mail characters (signed): Ledger Wren-Launchrealm,Ledger Post-Launchtwo" \
	"the Alliance author's characters (signed): Quill Maker-Launchrealm" "the Horde author's characters (signed): Quill Horde-Launchrealm" \
	"the realms of NA: Launchrealm=pvp,Launchtwo=pve" "the realms of EU: Kel'thas=rppvp"; do
	grep -Fq "$want" check.txt || fail "check does not show: $want"
done
grep -q '^  (outside any department): Test Councillor=Council Speaker$' check.txt || fail 'the council changed'
if grep -F '(outside' check.txt | grep -Fq '^'; then fail 'an identity read as a department'; fi
case "$pasted" in
	"HT1~"*"~Launchrealm+Launchtwo~0~^^Test Councillor=Council Speaker;^king^Alliance^Crown Owl-Launchrealm;^king^Horde^Tusk Crown-Launchtwo;^treasurer^Alliance^Ledger Wren-Launchrealm,Ledger Post-Launchtwo;^author^Alliance^Quill Maker-Launchrealm;^author^Horde^Quill Horde-Launchrealm;^realms^NA^Launchrealm=pvp,Launchtwo=pve;^realms^EU^Kel'thas=rppvp~"*) ;;
	*) fail "the titles list printed to paste is not in the grammar: $pasted" ;;
esac
printf 'ok: the King, the Treasurer, the author and the realms signed, read back and checked\n'

# Refused before anything is signed: nothing written, the key's time and the file unchanged.
before=$(last_at); file_before=$(sum "$OLYMPUS_COUNCIL_JSON")
refused() {
	rm -f "$OLYMPUS_COUNCIL_OUT"
	if python3 "$signer" "$@" > refused.txt 2>&1; then fail "signed: $*"; fi
	[ ! -e "$OLYMPUS_COUNCIL_OUT" ] || fail "a list was written for: $*"
	if grep -Fq 'Traceback' refused.txt; then fail "a crash, not a refusal: $*"; fi
	printf 'ok: refused, %s\n' "$*"
}
refused king 'Crown Owl'
refused king 'Crown Owl-Farrealm'
refused king 'Crown-Owl-Launchrealm'
refused king 'Three Word Crown-Launchrealm'
refused king 'Crown Owl-Launchrealm' Neutral
refused king --remove Neutral
refused treasurer 'Ledger Wren'
refused treasurer 'A Aa-Launchrealm,B Bb-Launchrealm,C Cc-Launchrealm,D Dd-Launchrealm,E Ee-Launchrealm'
refused treasurer 'Same Name-Launchrealm,same name-Launchrealm'
refused author 'Quill Maker-Launchrealm'
refused author 'Quill Maker-Farrealm'
refused author --remove 'Nobody Here-Launchrealm'
refused realm Launchrealm pvp OCE
refused realm Launchrealm pvp2 NA
refused realm 'Launch realm' pvp NA
refused realm --remove Nowhere
[ "$(last_at)" = "$before" ] || fail "a refusal moved the key's last time"
[ "$(sum "$OLYMPUS_COUNCIL_JSON")" = "$file_before" ] || fail 'a refusal changed the council file'
refused_council() {
	printf '%s' "$1" > bad.json
	rm -f "$OLYMPUS_COUNCIL_OUT"
	if python3 "$signer" council bad.json > refused.txt 2>&1; then fail "signed: $2"; fi
	if grep -Fq 'Traceback' refused.txt; then fail "a crash, not a refusal: $2"; fi
	printf 'ok: refused, %s\n' "$2"
}
refused_council '{"realm": "R", "king": ["Crown Owl-R"]}' 'a King that is not per side'
refused_council '{"realm": "R", "treasurer": {"Alliance": []}}' 'a Treasurer without a name'
refused_council '{"realm": "R", "author": [{"name": "Quill Maker-R", "side": "Horde"}]}' "an author's character with an unknown field"
refused_council "$(python3 -c 'import json; print(json.dumps({"realm": "R", "author": ["Dev %s-R" % chr(65 + i) for i in range(9)]}))')" "nine author's characters for one side"
refused_council '{"realm": "R", "realms": [{"name": "R", "kind": "pvp"}]}' 'a realm without its region'
refused_council '{"realm": "R", "realms": [{"name": "R", "kind": "pvp", "region": "NA"}, {"name": "r", "kind": "pve", "region": "EU"}]}' 'a realm twice'
refused_council "$(python3 -c 'import json; print(json.dumps({"realm": "R", "realms": [{"name": "Realm%d" % i, "kind": "pvp", "region": "NA"} for i in range(41)]}))')" '41 realms in one region'

# Taken off: newer lists without them.
python3 "$signer" king --remove Horde > /dev/null
python3 "$signer" treasurer --remove > /dev/null
python3 "$signer" author --remove 'quill horde-launchrealm' > /dev/null
python3 "$signer" realm --remove "kel'thas" > /dev/null
python3 "$signer" check > check.txt || fail 'check refused the list after the removals'
grep -Fq "the Horde King (signed): none" check.txt || fail 'the Horde King is still there'
grep -Fq "the Alliance Treasurer, then his mail characters (signed): none" check.txt || fail 'the Treasurer is still there'
grep -Fq "the Horde author's characters (signed): none" check.txt || fail "the Horde author's character is still there"
grep -Fq "the realms of EU: none" check.txt || fail 'the EU realm is still there'
grep -Fq "the Alliance King (signed): Crown Owl-Launchrealm" check.txt || fail 'a removal took the Alliance King too'
printf 'ok: each taken off by a newer list, the rest kept\n'
