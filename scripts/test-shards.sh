#!/usr/bin/env bash
# ChillZone: tests/run.lua in parallel shards (a test runs in shard k of N by a hash of its name,
# CHILLZONE_TEST_SHARD=k/N), a check in about two minutes instead of half an hour.
# Some tests lean on what earlier tests left behind, so they fail away from them: those are listed
# in tests/fixtures/shard-known-failures.txt, and only a failure not on that list fails this run.
# The full sequential run (luajit tests/run.lua, scripts/check.sh without CHILLZONE_TEST_SHARDS)
# remains the gate.
#   bash scripts/test-shards.sh            the check (CHILLZONE_TEST_SHARDS shards, 16 by default)
#   bash scripts/test-shards.sh --record   this run's failures become the known list
#   CHILLZONE_TEST_SHARDS=16 bash scripts/check.sh   check.sh with this in place of tests/run.lua
set -euo pipefail
cd "$(dirname "$0")/.."
shards=${CHILLZONE_TEST_SHARDS:-16}
known=tests/fixtures/shard-known-failures.txt
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
pids=()
for k in $(seq 0 $((shards - 1))); do
	CHILLZONE_TEST_SHARD="$k/$shards" luajit tests/run.lua > "$out/$k.txt" 2>&1 &
	pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid" || true; done
passed=0 failed=0 broken=0
for k in $(seq 0 $((shards - 1))); do
	summary=$(tail -n 1 "$out/$k.txt")
	if [[ $summary =~ ^([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]]; then
		passed=$((passed + BASH_REMATCH[1]))
		failed=$((failed + BASH_REMATCH[2]))
	else
		printf 'Shard %d/%d did not finish:\n' "$k" "$shards"
		tail -n 20 "$out/$k.txt"
		broken=1
	fi
done
sed -n 's/^  FAIL //p' "$out"/[0-9]*.txt | LC_ALL=C sort -u > "$out/failed"
if [ "${1:-}" = "--record" ]; then
	cp "$out/failed" "$known"
	printf '%d passed, %d failed in %d shards; %s recorded (%d names)\n' "$passed" "$failed" "$shards" "$known" "$(wc -l < "$known")"
	exit "$broken"
fi
if [ -f "$known" ]; then LC_ALL=C sort -u "$known" > "$out/known"; else : > "$out/known"; fi
unexpected=$(LC_ALL=C comm -23 "$out/failed" "$out/known")
gone=$(LC_ALL=C comm -13 "$out/failed" "$out/known")
printf '%d passed, %d failed in %d shards (%d known shard-order failures)\n' "$passed" "$failed" "$shards" "$(wc -l < "$out/known")"
[ -z "$gone" ] || printf 'Known failures that passed this time (fine):\n%s\n' "$gone"
if [ -n "$unexpected" ]; then
	printf 'Unexpected failures:\n'
	while IFS= read -r name; do
		grep -h -A1 -F "  FAIL $name" "$out"/[0-9]*.txt
	done <<< "$unexpected"
	exit 1
fi
exit "$broken"
