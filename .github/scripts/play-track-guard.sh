#!/usr/bin/env bash
# Fails if any CI or fastlane file names a Google Play track other than
# "internal", or mentions production, promotion or staged rollout.
# Checks every tracked file under .github/ and android/fastlane/ except this one.
# A track given as an expression or variable fails too: it must be the literal.
set -euo pipefail

self=.github/scripts/play-track-guard.sh
mapfile -t files < <(git ls-files .github android/fastlane | grep -vxF "$self" | grep -Ev '\.(png|jpg|jar)$' || true)
if [ "${#files[@]}" -eq 0 ]; then echo "::error::no files to check"; exit 1; fi

# Values of track settings in YAML, Ruby or shell form.
hits=$(grep -noPi -- '(--track[= ]+|\btracks?\s*(:|=>?)\s*)\K["'\'']?[^\s"'\'',#)]+' "${files[@]}" || true)
echo "Track settings found:"
echo "${hits:-none}"
if [ -z "$hits" ]; then
  echo "::error::no track setting found; the upload step must say track: internal"
  exit 1
fi

bad=$(echo "$hits" | awk -F: '{ v = $NF; gsub(/["'\'']/, "", v); if (v != "internal") print }')
if [ -n "$bad" ]; then
  echo "::error::Play track other than internal:"
  echo "$bad"
  exit 1
fi

if grep -nPi '\b(production|promote|userFraction|rollout)\b' "${files[@]}"; then
  echo "::error::production, promotion or rollout settings are not allowed"
  exit 1
fi

echo "OK: every Play track named is internal."
