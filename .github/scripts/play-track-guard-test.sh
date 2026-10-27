#!/usr/bin/env bash
# Self-test for play-track-guard.sh. Each fixtures/bad-*/ must fail with the
# message in its .expect file; each fixtures/good*/ must pass.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
guard="$here/play-track-guard.sh"
fx="$here/play-track-guard-fixtures"
failed=0 n=0

for d in "$fx"/*/; do
  name=$(basename "$d")
  n=$((n+1))
  out=$(bash "$guard" "$d" 2>&1); rc=$?
  case "$name" in
    bad-*)
      want=$(head -n1 "$d/.expect")
      if [ "$rc" -ne 0 ] && grep -qF -- "$want" <<<"$out"; then
        echo "ok   $name (refused: $want)"
      else
        echo "FAIL $name: expected refusal with \"$want\", got rc=$rc"; echo "$out" | sed 's/^/     /'; failed=1
      fi ;;
    good*)
      if [ "$rc" -eq 0 ]; then echo "ok   $name (passed)"
      else echo "FAIL $name: expected pass, got rc=$rc"; echo "$out" | sed 's/^/     /'; failed=1; fi ;;
    *) echo "FAIL $name: fixture names start with bad- or good"; failed=1 ;;
  esac
done

[ "$n" -gt 0 ] || { echo "no fixtures found"; exit 1; }
exit "$failed"
