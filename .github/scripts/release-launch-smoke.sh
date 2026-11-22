#!/usr/bin/env bash
# Release launch smoke test (task 421; follow-up "no release-mode test in CI",
# after build 369 crashed at launch). Installs a release APK on a running
# emulator, starts it, and fails unless, within the wait:
#   - Android reports the main activity displayed,
#   - the app logs its own first-frame marker (VP_FIRST_FRAME, lib/main.dart),
#   - the process is still alive, and
#   - logcat has no FATAL EXCEPTION or native fatal signal for the app.
# The phone check before every upload stays the rule; this is an extra net.
#
#   .github/scripts/release-launch-smoke.sh <apk> <adb serial> [wait seconds, default 40]
#
# The serial is required, so it never acts on a phone that happens to be
# plugged in. Writes the app's logcat to release-launch-logcat.txt.
set -euo pipefail
apk=${1:?usage: release-launch-smoke.sh <apk> <adb serial> [wait seconds]}
serial=${2:?usage: release-launch-smoke.sh <apk> <adb serial> [wait seconds]}
wait_s=${3:-40}
app=au.com.voiceplatform.app
out=release-launch-logcat.txt
a() { adb -s "$serial" "$@"; }
crashed() { # the app's own crash only, not another process's
  grep -A3 "FATAL EXCEPTION" "$out" | grep -q "Process: $app" || grep -Eq "Fatal signal .*\($app\)" "$out"
}

case "$serial" in emulator-*) ;; *) echo "refusing $serial: emulators only" >&2; exit 2 ;; esac
[ -f "$apk" ] || { echo "no APK at $apk" >&2; exit 2; }

# A clean install: an emulator may hold a newer build of the app.
a uninstall "$app" >/dev/null 2>&1 || true
a install -g "$apk" >/dev/null
a logcat -c
a shell am start -W -n "$app/.MainActivity" | tr -d '\r'

ok=0
for _ in $(seq 1 "$wait_s"); do
  sleep 1
  a logcat -d -v brief > "$out" 2>/dev/null || true
  if grep -q "VP_FIRST_FRAME" "$out"; then ok=1; break; fi
  if crashed; then break; fi
done
sleep 5
a logcat -d -v brief > "$out" 2>/dev/null || true
pid=$(a shell pidof "$app" | tr -d '\r' || true)

fail=0
if crashed; then
  echo "::error::the release build crashed at launch"
  grep -E -A25 "FATAL EXCEPTION|Fatal signal" "$out" | head -60
  fail=1
fi
grep -Eq "Displayed $app/\.MainActivity" "$out" || { echo "::error::the main activity was never displayed"; fail=1; }
[ "$ok" = 1 ] || { echo "::error::no VP_FIRST_FRAME marker from the app within ${wait_s} s"; fail=1; }
[ -n "$pid" ] || { echo "::error::the app is not running after launch"; fail=1; }

if [ "$fail" = 0 ]; then
  echo "release launch: displayed, first frame drawn, pid $pid, no crash"
fi
exit "$fail"
