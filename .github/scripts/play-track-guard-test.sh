#!/usr/bin/env bash
# Self-test for play-track-guard.sh. Writes its fixtures to a temporary
# directory outside the repo (RUNNER_TEMP in CI), so the real scan never sees
# them. Each bad-* case must fail with its message; each good* case must pass.
#
# This file is scanned like any other, so the words the guard refuses appear
# here only as @PLACEHOLDERS@, filled in when the fixtures are written.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
guard="$here/play-track-guard.sh"
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/play-guard-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

T='tr''ack'
P='produc''tion'
PR='pro''mote'
RO='roll''out'
SUP='sup''ply'
UPS='upload_to_play_''store'
UGP='r0adkll/upload-google-''play@e738b9dd8f2476ea806d921b64aacd24f34515a5'
CO='actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
FX='play-track-guard-fixture''s'
TT='Tr''ack'
MD='m''d'
LO='OFL.tx''t'
LL='LICENS''E'
LN='NOTIC''E'

# fixture <case> <path>, content on stdin
fixture() {
  mkdir -p "$work/$1/$(dirname "$2")"
  sed -e "s|@T@|$T|g" -e "s|@P@|$P|g" -e "s|@PR@|$PR|g" -e "s|@RO@|$RO|g" \
      -e "s|@SUP@|$SUP|g" -e "s|@UPS@|$UPS|g" -e "s|@UGP@|$UGP|g" -e "s|@CO@|$CO|g" \
      -e "s|@FX@|$FX|g" -e "s|@TT@|$TT|g" -e "s|@MD@|$MD|g" -e "s|@LO@|$LO|g" -e "s|@LL@|$LL|g" -e "s|@LN@|$LN|g" > "$work/$1/$2"
}
expect() { mkdir -p "$work/$1"; printf '%s\n' "$2" > "$work/$1/.expect"; }

MSG_T='Play track other than internal'
MSG_U='Play upload tool outside'

expect bad-script-staged "$MSG_T"
fixture bad-script-staged tool/release.sh <<'EOF'
fastlane @SUP@ --@T@ @P@ --@RO@ 0.1
EOF
fixture bad-script-staged .github/workflows/release.yml <<'EOF'
jobs:
  r:
    steps:
      - run: bash tool/release.sh
EOF

expect bad-script-internal "$MSG_U"
fixture bad-script-internal tool/release.sh <<'EOF'
fastlane @SUP@ --@T@ internal
EOF

expect bad-docs-script "$MSG_U"
fixture bad-docs-script docs/release.sh <<'EOF'
fastlane @SUP@ --@T@ internal
EOF
fixture bad-docs-script .github/workflows/release.yml <<'EOF'
jobs:
  r:
    steps:
      - run: bash docs/release.sh
EOF

expect bad-md-run 'runs a Markdown file'
fixture bad-md-run .github/workflows/release.yml <<'EOF'
jobs:
  r:
    steps:
      - run: bash docs/release.@MD@
EOF
fixture bad-md-run docs/release.$MD <<'EOF'
fastlane @SUP@ --@T@ @P@
EOF

expect bad-fixtures-ref 'names the fixtures folder'
fixture bad-fixtures-ref .github/workflows/release.yml <<'EOF'
jobs:
  r:
    steps:
      - run: bash .github/scripts/@FX@/x/run.sh
EOF

expect bad-move-to "$MSG_T"
fixture bad-move-to android/fastlane/Fastfile <<'EOF'
lane :x do
  @UPS@(@T@: 'internal', @T@_@PR@_to: 'alpha')
end
EOF

expect bad-move-word 'moving or staging a release'
fixture bad-move-word android/fastlane/Fastfile <<'EOF'
lane :x do
  @UPS@(@T@: 'internal', @PR@@TT@: true)
end
EOF

expect bad-track-colon "$MSG_T"
fixture bad-track-colon .github/workflows/android.yml <<'EOF'
steps:
  - uses: @UGP@
    with:
      @T@: beta
EOF

expect bad-track-double-quoted-key "$MSG_T"
fixture bad-track-double-quoted-key android/fastlane/config.json <<'EOF'
{ "@T@": beta }
EOF

expect bad-track-single-quoted-key "$MSG_T"
fixture bad-track-single-quoted-key .github/workflows/android.yml <<'EOF'
with: { '@T@': beta }
EOF

expect bad-tracks-quoted-key "$MSG_T"
fixture bad-tracks-quoted-key android/fastlane/config.json <<'EOF'
{ "@T@s": "alpha" }
EOF

expect bad-track-flag-eq "$MSG_T"
fixture bad-track-flag-eq android/fastlane/upload.sh <<'EOF'
fastlane @SUP@ --@T@=alpha
EOF

expect bad-track-expr "$MSG_T"
fixture bad-track-expr .github/workflows/android.yml <<'EOF'
with:
  @T@: ${{ inputs.t }}
EOF

expect bad-gradle-track "$MSG_T"
fixture bad-gradle-track android/app/build.gradle.kts <<'EOF'
val @T@ = "beta"
EOF

expect bad-gradle-play 'Gradle Play Publisher'
fixture bad-gradle-play android/app/build.gradle.kts <<'EOF'
play {
    @T@ = "internal"
}
EOF

expect bad-fastlane-outside 'fastlane config outside android/fastlane/'
fixture bad-fastlane-outside fastlane/Fastfile <<'EOF'
lane :x do
  @UPS@(@T@: 'internal')
end
EOF

expect bad-uses-other-action 'action not on the allow-list'
fixture bad-uses-other-action .github/workflows/ci.yml <<'EOF'
steps:
  - uses: someone/play-uploader@0123456789abcdef0123456789abcdef01234567
EOF

expect bad-uses-quoted-key 'action not on the allow-list'
fixture bad-uses-quoted-key .github/workflows/ci.yml <<'EOF'
steps:
  - "uses": someone/play-deploy@0123456789abcdef0123456789abcdef01234567
  - 'uses': someone/play-deploy@0123456789abcdef0123456789abcdef01234567
EOF

expect bad-uses-tag 'action not on the allow-list'
fixture bad-uses-tag .github/workflows/ci.yml <<'EOF'
steps:
  - uses: actions/setup-java@v6
EOF

expect bad-uses-reusable-workflow 'action not on the allow-list'
fixture bad-uses-reusable-workflow .github/workflows/ci.yml <<'EOF'
jobs:
  x:
    uses: other-org/release/.github/workflows/play.yml@main
EOF

expect bad-licence-run 'runs or sources a licence file'
fixture bad-licence-run .github/workflows/ci.yml <<'EOF'
jobs:
  x:
    steps:
      - run: bash assets/fonts/Inter/@LO@
EOF
fixture bad-licence-run assets/fonts/Inter/OFL.txt <<'EOF'
fastlane @SUP@ --@T@ @P@
EOF

expect bad-licence-source 'runs or sources a licence file'
fixture bad-licence-source tool/build.sh <<'EOF'
source ./@LL@
EOF

expect bad-licence-dot 'runs or sources a licence file'
fixture bad-licence-dot tool/build.sh <<'EOF'
cd x && . @LN@
EOF

expect bad-licence-name-not-exact 'moving or staging a release'
fixture bad-licence-name-not-exact assets/fonts/Inter/OFL-notes.txt <<'EOF'
permission to @PR@ the font
EOF

fixture good assets/fonts/Inter/OFL.txt <<'EOF'
The name of the Copyright Holder may not be used to @PR@ or advertise.
EOF
fixture good LICENSE <<'EOF'
Use it to @PR@ the software; staged @RO@ is not mentioned here.
EOF
fixture good NOTICE <<'EOF'
Third-party notices. @RO@ and @PR@ appear in quoted licence texts.
EOF
fixture good packages/x/LICENSE.txt <<'EOF'
@PR@
EOF

fixture good .github/workflows/android.yml <<'EOF'
steps:
  - uses: @CO@
  - uses: ./.github/actions/local
  - uses: "@UGP@"
    with:
      @T@: internal
      status: draft
EOF
fixture good android/fastlane/Fastfile <<'EOF'
lane :internal do
  @UPS@(@T@: 'internal', aab: 'app-release.aab')
end
EOF
fixture good lib/config.dart <<'EOF'
// Tracked by WS5.
const environment = '@P@';
EOF
fixture good docs/notes.md <<'EOF'
Never use @T@: @P@.
EOF

failed=0 n=0
for d in "$work"/*/; do
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
  esac
done

[ "$n" -gt 0 ] || { echo "no fixtures written"; exit 1; }
exit "$failed"
