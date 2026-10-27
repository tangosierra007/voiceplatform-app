#!/usr/bin/env bash
# Play track guard: nothing in this repo may release to a Google Play track
# other than "internal", promote a release, or stage a rollout.
#
#   play-track-guard.sh          checks every tracked text file in the repo
#   play-track-guard.sh <dir>    checks every file under <dir> as if it were
#                                the repo root (used by the self-test)
#
# Not checked: docs (docs/, *.md), this script, the self-test and its fixtures.
#
# Fails on:
#   1. any track setting (track:, tracks:, track =, track_promote_to:,
#      --track, --track=, --track-promote-to ...) whose value is not the
#      literal "internal" (an expression or variable fails too);
#   2. promote, rollout, userFraction, promote_track or track_promote anywhere,
#      and "production" in CI, fastlane or script files;
#   3. a Play upload tool or its config anywhere except the upload job
#      (.github/workflows/android.yml) and android/fastlane/: fastlane files
#      elsewhere, fastlane supply / upload_to_play_store, the Gradle Play
#      Publisher plugin or a play { } block in Gradle, other upload actions.
set -uo pipefail

root=${1:-.}
cd "$root" || { echo "::error::no such directory: $root"; exit 2; }

if [ $# -ge 1 ]; then
  mapfile -t all < <(find . -type f ! -name '.expect' | sed 's|^\./||' | sort)
else
  mapfile -t all < <(git ls-files)
fi

files=()
for f in "${all[@]}"; do
  case "$f" in
    docs/*|*.md) continue ;;
    .github/scripts/play-track-guard.sh|.github/scripts/play-track-guard-test.sh) continue ;;
    .github/scripts/play-track-guard-fixtures/*) continue ;;
  esac
  [ -f "$f" ] || continue
  # Text files only.
  grep -Iq . "$f" 2>/dev/null || continue
  files+=("$f")
done
if [ "${#files[@]}" -eq 0 ]; then echo "::error::no files to check"; exit 1; fi

fail=0
err() { echo "::error::$1"; fail=1; }

# 1. Track values.
track_re='(?:--(?:\w+-)*tracks?(?:-[\w-]+)?[= ]+|\b(?:\w+_)?tracks?(?:_\w+)?\s*(?::|=>?)\s*)\K["'\'']?[^\s"'\'',#)\]}]+'
hits=$(grep -HnoPi -- "$track_re" "${files[@]}" || true)
echo "Track settings found:"
echo "${hits:-none}"
bad=$(printf '%s\n' "$hits" | awk -F: 'NF { v = $NF; gsub(/["'\'']/, "", v); if (v != "internal") print }')
[ -z "$bad" ] || { err "Play track other than internal:"; echo "$bad"; }

# 2. Promotion and rollout anywhere; "production" in CI, fastlane and script files.
if grep -HnPi 'promote|rollout|userfraction|promote[_-]?track|track[_-]?promote' "${files[@]}"; then
  err "promotion or rollout settings are not allowed"
fi
release_files=()
for f in "${files[@]}"; do
  case "$f" in
    .github/*|*/fastlane/*|fastlane/*|*Fastfile|*Appfile|*Pluginfile|*Gemfile|*.sh|*.bash|*.rb|*.ps1|*.py|*.gradle|*.gradle.kts) release_files+=("$f") ;;
  esac
done
if [ "${#release_files[@]}" -gt 0 ] && grep -HnPi 'production' "${release_files[@]}"; then
  err "\"production\" in a CI, fastlane, Gradle or script file"
fi

# 3. Play upload tools and config only in the expected places.
for f in "${files[@]}"; do
  case "$f" in
    android/fastlane/*) ;;
    *Fastfile|*Appfile|*Pluginfile|*/fastlane/*|fastlane/*) err "fastlane config outside android/fastlane/: $f" ;;
  esac
done
upload_re='fastlane\s+(?:run\s+)?(?:supply|upload_to_play_store)|\bsupply\s*\(|upload_to_play_store|upload-google-play|androidpublisher|com\.github\.triplet\.play|gradle-play-publisher|publish\w*Bundle|publish\w*Apk'
for f in "${files[@]}"; do
  case "$f" in
    .github/workflows/android.yml|android/fastlane/*) continue ;;
  esac
  if grep -HnPi -- "$upload_re" "$f"; then err "Play upload tool outside the upload job or android/fastlane/: $f"; fi
done
gradle=()
for f in "${files[@]}"; do case "$f" in *.gradle|*.gradle.kts) gradle+=("$f") ;; esac; done
if [ "${#gradle[@]}" -gt 0 ] && grep -HnP '^\s*play\s*\{' "${gradle[@]}"; then
  err "Gradle Play Publisher play { } block"
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "OK: every Play track named is internal; no promotion, rollout or stray upload tool."
