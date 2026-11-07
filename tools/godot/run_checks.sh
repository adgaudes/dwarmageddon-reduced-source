#!/usr/bin/env bash
# Quality gate for Linux/headless environments. Port of the checks of the original Windows gate:
# import, --check-only on every project script, every test suite, headless smoke test.
#
# Prerequisites: bash, coreutils `timeout`, xargs and Godot 4.7.2 standard (not .NET, not bundled).
# Set GODOT_BIN=/path/to/Godot_v4.7.2-stable_linux.x86_64 or put `godot` / `godot4` on PATH.
#
# Limits: headless only. Terrain3D's renderer and the shaders are NOT exercised here, and no
# windowed step runs. A suite counts as OK only with exit code 0, the PASS marker and no runtime
# errors: PASS alone is never enough. Exit codes: 0 all OK, 1 at least one failure, 2 bad setup.
# A suite can print PASS and then never exit (see docs/COPY_NOTES.md). Such a run is killed after
# --exit-grace seconds and repeated --exit-hang-retries times; it stays not OK if it never exits.
#
# Usage:
#   tools/godot/run_checks.sh                      everything
#   tools/godot/run_checks.sh --suite audio_tests  one suite (repeatable)
#   tools/godot/run_checks.sh --jobs 4 --timeout 300 --seed 20261014 --out output/checks
#   tools/godot/run_checks.sh --no-import --no-check-only --no-smoke
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PROJECT="$ROOT/godot"
SELF="$ROOT/tools/godot/run_checks.sh"

# Runtime error lines allowed per suite: each one is provoked on purpose by that suite.
# Same list as the original gate. The smoke test allows nothing.
allowed_errors() {
	case "$1" in
		settings_tests) printf '%s\n' 'Parameter "material" is null' 'ConfigFile parse error at user://settings_test_' ;;
		workshop_tests) printf '%s\n' 'ConfigFile parse error at user://test_profile_recovery.cfg' ;;
	esac
}

runtime_errors() { # <log> <suite>
	local log=$1 suite=$2 allow
	allow=$(allowed_errors "$suite")
	if [ -n "$allow" ]; then
		grep -E 'SCRIPT ERROR|SHADER ERROR|^ERROR:' "$log" | grep -v -F -f <(printf '%s\n' "$allow")
	else
		grep -E 'SCRIPT ERROR|SHADER ERROR|^ERROR:' "$log"
	fi
}

# Runs one Godot process with its own user:// directory, so parallel suites cannot share files.
run_godot() { # <log> <timeout> <args...>
	local log=$1 limit=$2; shift 2
	local home; home=$(mktemp -d)
	XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
		timeout -k 5 "$limit" "$GODOT_BIN" "$@" >"$log" 2>&1 </dev/null
	local code=$?
	rm -rf "$home"
	return $code
}

# Suite process. Once the PASS line is out, the process gets EXIT_GRACE seconds to end; if it is
# still alive it is killed and reported with code 124, so an exit hang does not cost the full timeout.
run_suite_process() { # <log> <suite>
	local log=$1 suite=$2 home pid waited=0 code
	home=$(mktemp -d)
	XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
		timeout -k 5 "$TIMEOUT" "$GODOT_BIN" --headless --path "$PROJECT" --fixed-fps 60 --script "res://tests/$suite.gd" >"$log" 2>&1 </dev/null &
	pid=$!
	while kill -0 "$pid" 2>/dev/null; do
		if grep -q 'PROTOTYPE01_TESTS ' "$log"; then
			waited=$((waited + 1))
			if [ "$waited" -gt $((EXIT_GRACE * 2)) ]; then
				pkill -KILL -P "$pid" 2>/dev/null
				wait "$pid" 2>/dev/null
				rm -rf "$home"
				return 124
			fi
		fi
		sleep 0.5
	done
	wait "$pid"
	code=$?
	rm -rf "$home"
	return $code
}

run_suite() { # internal: <suite> appends one TSV line
	local suite=$1 log started code errors status hangs=0 pass
	log="$OUT/suites/$suite.log"
	started=$(date +%s)
	while true; do
		run_suite_process "$log" "$suite"
		code=$?
		errors=$(runtime_errors "$log" "$suite" | wc -l)
		pass=no; grep -q 'PROTOTYPE01_TESTS PASS' "$log" && pass=yes
		# Known exit hang: PASS printed, no runtime error, process alive after the grace time.
		# Only this case is retried, and every first log is kept. A FAIL is never retried.
		if { [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; } && [ "$pass" = yes ] && [ "$errors" -eq 0 ] && [ "$hangs" -lt "$EXIT_HANG_RETRIES" ]; then
			hangs=$((hangs + 1))
			mv "$log" "$OUT/suites/$suite.exit-hang-$hangs.log"
			continue
		fi
		break
	done
	if [ "$code" -eq 0 ] && [ "$pass" = yes ] && [ "$errors" -eq 0 ]; then
		status=OK; [ "$hangs" -gt 0 ] && status=OK_AFTER_EXIT_HANG
	elif { [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; } && [ "$pass" = yes ] && [ "$errors" -eq 0 ]; then
		status=EXIT_HANG_ALWAYS
	elif grep -q 'PROTOTYPE01_TESTS FAIL' "$log"; then
		status=FAIL
	elif [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
		status=TIMEOUT
	else
		status=FAIL
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$suite" "$status" "$code" "$pass" "$errors" "$(($(date +%s) - started))" "$hangs" >>"$OUT/suites.tsv"
	printf '  %-20s %-34s exit=%s pass=%s runtime_errors=%s exit_hangs=%s %ss\n' "$status" "$suite" "$code" "$pass" "$errors" "$hangs" "$(($(date +%s) - started))"
}

check_script() { # internal: <res path>
	local res=$1 name log code
	name=$(printf '%s' "$res" | tr '/:' '__')
	log="$OUT/check_only/$name.log"
	run_godot "$log" "$TIMEOUT" --headless --path "$PROJECT" --check-only --script "$res"
	code=$?
	printf '%s\t%s\n' "$res" "$code" >>"$OUT/check_only.tsv"
	if [ "$code" -ne 0 ]; then echo "  FAIL exit=$code $res"; else rm -f "$log"; fi
}

if [ "${1:-}" = "--internal-suite" ] || [ "${1:-}" = "--internal-check" ]; then
	mode=$1; item=$2
	if [ "$mode" = "--internal-suite" ]; then run_suite "$item"; else check_script "$item"; fi
	exit 0
fi

DO_IMPORT=1 DO_CHECK=1 DO_SUITES=1 DO_SMOKE=1
JOBS=$(( $(nproc 2>/dev/null || echo 2) / 2 )); [ "$JOBS" -lt 1 ] && JOBS=1
export TIMEOUT=300
export EXIT_GRACE=20
export EXIT_HANG_RETRIES=1
SEED=20261014
OUT="$ROOT/output/checks"
SUITES=()
while [ $# -gt 0 ]; do
	case "$1" in
		--suite) SUITES+=("$2"); shift 2 ;;
		--jobs) JOBS=$2; shift 2 ;;
		--timeout) TIMEOUT=$2; shift 2 ;;
		--exit-grace) EXIT_GRACE=$2; shift 2 ;;
		--exit-hang-retries) EXIT_HANG_RETRIES=$2; shift 2 ;;
		--seed) SEED=$2; shift 2 ;;
		--out) OUT=$2; shift 2 ;;
		--no-import) DO_IMPORT=0; shift ;;
		--no-check-only) DO_CHECK=0; shift ;;
		--no-suites) DO_SUITES=0; shift ;;
		--no-smoke) DO_SMOKE=0; shift ;;
		-h|--help) sed -n '2,19p' "$SELF"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

if [ -z "${GODOT_BIN:-}" ]; then
	GODOT_BIN=$(command -v godot4 || command -v godot || true)
fi
if [ -z "$GODOT_BIN" ] || [ ! -x "$GODOT_BIN" ]; then
	echo "Godot not found: set GODOT_BIN to a Godot 4.7.2 standard executable." >&2
	exit 2
fi
export GODOT_BIN OUT
export PROTOTYPE01_SEED=$SEED
mkdir -p "$OUT/suites" "$OUT/check_only"
: >"$OUT/suites.tsv"; : >"$OUT/check_only.tsv"
echo "godot: $("$GODOT_BIN" --version 2>/dev/null | tail -1)  seed=$SEED jobs=$JOBS timeout=${TIMEOUT}s"
case "$("$GODOT_BIN" --version 2>/dev/null | tail -1)" in
	4.7.2.*) ;;
	*) echo "WARNING: the project is verified only on Godot 4.7.2" ;;
esac
failures=0

if [ "$DO_IMPORT" = 1 ]; then
	echo "== import"
	started=$(date +%s)
	timeout -k 5 1800 "$GODOT_BIN" --headless --path "$PROJECT" --import >"$OUT/import.log" 2>&1 </dev/null
	code=$?
	errors=$(grep -cE 'SCRIPT ERROR|SHADER ERROR|^ERROR:' "$OUT/import.log")
	echo "  exit=$code error_lines=$errors $(($(date +%s) - started))s (log: $OUT/import.log)"
	[ "$code" -eq 0 ] || failures=$((failures + 1))
fi

if [ "$DO_CHECK" = 1 ]; then
	echo "== check-only (project scripts, addons excluded)"
	(cd "$PROJECT" && find . -name '*.gd' -not -path './addons/*' -not -path './.godot/*' | sed 's#^\./#res://#' | sort) \
		| xargs -P "$JOBS" -I{} bash "$SELF" --internal-check {}
	total=$(wc -l <"$OUT/check_only.tsv")
	bad=$(awk -F'\t' '$2 != 0' "$OUT/check_only.tsv" | wc -l)
	echo "  scripts=$total failed=$bad"
	failures=$((failures + bad))
	[ "$total" -gt 0 ] || failures=$((failures + 1))
fi

if [ "$DO_SUITES" = 1 ]; then
	echo "== test suites"
	if [ ${#SUITES[@]} -eq 0 ]; then
		mapfile -t SUITES < <(cd "$PROJECT/tests" && ls ./*.gd | sed 's#^\./##; s#\.gd$##')
	fi
	printf '%s\n' "${SUITES[@]}" | xargs -P "$JOBS" -I{} bash "$SELF" --internal-suite {}
	sort -o "$OUT/suites.tsv" "$OUT/suites.tsv"
	awk -F'\t' '{c[$2]++} END {for (k in c) printf "  %s=%d", k, c[k]; print ""}' "$OUT/suites.tsv"
	bad=$(awk -F'\t' '$2 != "OK" && $2 != "OK_AFTER_EXIT_HANG"' "$OUT/suites.tsv" | wc -l)
	failures=$((failures + bad))
	# A suite that left no result line is a failure of the gate itself, never a pass.
	reported=$(wc -l <"$OUT/suites.tsv")
	echo "  suites requested=${#SUITES[@]} reported=$reported"
	[ "$reported" -eq "${#SUITES[@]}" ] || failures=$((failures + 1))
fi

if [ "$DO_SMOKE" = 1 ]; then
	echo "== smoke test (headless, --autostart)"
	run_godot "$OUT/smoke.log" "$TIMEOUT" --headless --path "$PROJECT" --quit-after 180 -- --autostart
	code=$?
	missing=0
	for marker in PROTOTYPE01_MENU_READY PROTOTYPE01_SMOKE_TEST_OK PROTOTYPE01_INPUT_READY PROTOTYPE01_EXPOSURE_READY \
		PROTOTYPE01_ARENA_READY PROTOTYPE01_TERRAIN_FIELD_READY PROTOTYPE01_CHARACTER_READY "PROTOTYPE01_TERRAIN_MODE Dig" \
		PROTOTYPE01_CAMERA_READY PROTOTYPE01_CARAVAN_READY PROTOTYPE01_RUN_START PROTOTYPE01_PATH_FIELD_READY; do
		if ! grep -q "$marker" "$OUT/smoke.log"; then echo "  missing marker: $marker"; missing=$((missing + 1)); fi
	done
	errors=$(runtime_errors "$OUT/smoke.log" smoke | wc -l)
	echo "  exit=$code missing_markers=$missing runtime_errors=$errors"
	if [ "$code" -ne 0 ] || [ "$missing" -ne 0 ] || [ "$errors" -ne 0 ]; then failures=$((failures + 1)); fi
fi

echo "details: $OUT"
if [ "$failures" -eq 0 ]; then echo "CHECKS PASS"; exit 0; fi
echo "CHECKS FAIL ($failures)"
exit 1
