#!/usr/bin/env bash
# Play track guard: nothing in this repo may release to a Google Play track
# other than "internal", move a release between tracks, or stage a release.
# Defence in depth: the real control is the play-internal environment.
#
#   play-track-guard.sh          checks every tracked file in the repo
#   play-track-guard.sh <dir>    checks every file under <dir> as if it were
#                                the repo root (used by the self-test)
#
# Only Markdown files (*.md) and binary files are skipped; nothing else, this
# script included. So the words it refuses are written below as regex
# classes (for example [t]) that don't match themselves.
#
# Fails on:
#   1. a track setting (plain or quoted key; colon, equals or => form; a
#      command-line flag; any key built on the word, such as the one naming a
#      track to move to) whose value is not the literal "internal";
#   2. the words for moving or staging a release anywhere, and the name of
#      the public release channel in CI, fastlane, Gradle and script files;
#   3. fastlane config outside android/fastlane/, a Play upload tool outside
#      the upload job and android/fastlane/, the Gradle Play Publisher plugin;
#   4. any workflow or script running a Markdown file or naming the old
#      fixtures folder;
#   5. a workflow `uses:` that is not on the allow-list below or a ./ path.
set -uo pipefail

# Exact actions allowed in `uses:` (owner/repo@sha). actions/checkout@v4 is
# what secret-scan.yml uses (that file is kept as it is).
allowed_uses=(
  "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
  "actions/checkout@v4"
  "actions/setup-java@b843ebf9b913146b38da2eaa7aeddf76074ae1ad"
  "subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2"
  "actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9"
  "r0adkll/upload-google-""play@e738b9dd8f2476ea806d921b64aacd24f34515a5"
)

root=${1:-.}
cd "$root" || { echo "::error::no such directory: $root"; exit 2; }

if [ $# -ge 1 ]; then
  mapfile -t all < <(find . -type f ! -name '.expect' | sed 's|^\./||' | sort)
else
  mapfile -t all < <(git ls-files)
fi

files=()
for f in "${all[@]}"; do
  case "$f" in *.md) continue ;; esac
  [ -f "$f" ] || continue
  grep -Iq . "$f" 2>/dev/null || continue   # text files only
  files+=("$f")
done
if [ "${#files[@]}" -eq 0 ]; then echo "::error::no files to check"; exit 1; fi

fail=0
err() { echo "::error::$1"; fail=1; }
q="[\"']"

# 1. Track values.
key_re="(?:--(?:\\w+-)*[t]racks?(?:-[\\w-]+)?[= ]+|\\b(?:\\w+_)?[t]racks?(?:_\\w+)?${q}?\\s*(?::|=>?)\\s*)\\K${q}?[^\\s\"',#)\\]}]+"
hits=$(grep -HnoPi -- "$key_re" "${files[@]}" || true)
echo "Track settings found:"
echo "${hits:-none}"
bad=$(printf '%s\n' "$hits" | awk -F: 'NF { v = $NF; gsub(/["'\'']/, "", v); if (v != "internal") print }')
[ -z "$bad" ] || { err "Play track other than internal:"; echo "$bad"; }

# 2. Moving or staging a release anywhere; the public channel name in CI,
#    fastlane, Gradle and script files.
if grep -HnPi 'pro[m]ote|roll[o]ut|user[f]raction|pro[m]ote[_-]?[t]rack|[t]rack[_-]?pro[m]ote' "${files[@]}"; then
  err "moving or staging a release is not allowed"
fi
release_files=()
for f in "${files[@]}"; do
  case "$f" in
    .github/*|*/fastlane/*|fastlane/*|*Fastfile|*Appfile|*Pluginfile|*Gemfile|*.sh|*.bash|*.rb|*.ps1|*.py|*.gradle|*.gradle.kts) release_files+=("$f") ;;
  esac
done
if [ "${#release_files[@]}" -gt 0 ] && grep -HnPi 'produc[t]ion' "${release_files[@]}"; then
  err "the public release channel is named in a CI, fastlane, Gradle or script file"
fi

# 3. Play upload tools and config only in the expected places.
for f in "${files[@]}"; do
  case "$f" in
    android/fastlane/*) ;;
    *Fastfile|*Appfile|*Pluginfile|*/fastlane/*|fastlane/*) err "fastlane config outside android/fastlane/: $f" ;;
  esac
done
upload_re='fastlane\s+(?:run\s+)?(?:sup[p]ly|upload_to_play_stor[e])|\bsup[p]ly\s*\(|upload_to_play_stor[e]|upload-google-pla[y]|androidpublishe[r]|com[.]github[.]triplet[.]pla[y]|gradle-play-publishe[r]|publish\w*Bundl[e]|publish\w*Ap[k]'
for f in "${files[@]}"; do
  case "$f" in .github/workflows/android.yml|android/fastlane/*) continue ;; esac
  if grep -HnPi -- "$upload_re" "$f"; then err "Play upload tool outside the upload job or android/fastlane/: $f"; fi
done
gradle=()
for f in "${files[@]}"; do case "$f" in *.gradle|*.gradle.kts) gradle+=("$f") ;; esac; done
if [ "${#gradle[@]}" -gt 0 ] && grep -HnP '^\s*pla[y]\s*\{' "${gradle[@]}"; then
  err "Gradle Play Publisher play { } block"
fi

# 4. Nothing runs a Markdown file or names the old fixtures folder.
md_run_re='(?:\b(?:bash|sh|zsh|dash|ksh|source|exec|python3?|ruby|node|perl|pwsh|powershell)\s+(?:-\S+\s+)*|(?:^|[\s;&|("'\''])\.\s+|(?:^|[\s;&|("'\''])\./)\S*\.m[d]\b'
if grep -HnPi -- "$md_run_re" "${files[@]}"; then
  err "a workflow or script runs a Markdown file"
fi
if grep -HnF -- 'play-track-guard-fixture''s' "${files[@]}"; then
  err "a file names the fixtures folder"
fi

# 5. `uses:` allow-list, in every YAML file.
yml=()
for f in "${files[@]}"; do case "$f" in *.yml|*.yaml) yml+=("$f") ;; esac; done
if [ "${#yml[@]}" -gt 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    v=${line##*:}; v=${v//\"/}; v=${v//\'/}
    case "$v" in ./*) continue ;; esac
    ok=0
    for a in "${allowed_uses[@]}"; do [ "$v" = "$a" ] && ok=1 && break; done
    [ "$ok" -eq 1 ] || err "action not on the allow-list: $line"
  done < <(grep -HnoP -- "\\buses${q}?\\s*:\\s*\\K${q}?[^\\s\"'#]+" "${yml[@]}" || true)
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "OK: every Play track named is internal; no stray upload tool; every action allowed."
