#!/bin/bash
# build-and-sign.sh -- the whole path, detached, with a VERDICT file.
#
#   setsid nohup bash ~/itel_rs4_AICP/build-and-sign.sh > /dev/null 2>&1 < /dev/null &
#   (it prints its run dir first; poll <run>/VERDICT, never the PID: setsid forks)
#
#   SIGN=1   release-sign after the build. NOT WRITTEN YET: test builds are test-keys,
#            and release keys stay out of the recipe until a release is decided.
#   Every aicp-build.sh variable (TOP, OUT_TARGET, PRODUCT, RELEASE, VARIANT, GOAL, DIRTY_OK)
#   passes through.
#
# WHY (crDroid recipe, 08-19 / 08-28): the steps were correct on paper and nowhere
# executable, and a build ran on a tree that no longer matched git. So verification comes
# first and the script REFUSES to build when it fails. Any exit leaves a verdict: silence
# must never read as success.
set -u
TOP="${TOP:-/mnt/Data/lineage-23.2}"
REC="${REC:-$(cd "$(dirname "$0")" && pwd)}"
export TOP
SIGN="${SIGN:-0}"

RUN="$TOP/tmp-release/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN" || exit 2
D="$RUN/driver.log"; V="$RUN/VERDICT"; B="$RUN/build.log"
say(){ echo ">>> $*" | tee -a "$D"; }
die(){ echo "FAIL $1" > "$V"; say "VERDICT FAIL $1"; exit 1; }
trap '[ -s "$V" ] || { echo "FAIL unexpected-exit" > "$V"; say "VERDICT FAIL unexpected-exit"; }' EXIT

echo "$RUN"
say "RUN $RUN"
say "START $(date -u +%FT%TZ)"
[ "$SIGN" = 1 ] && die "SIGN=1 requested but sign-release.sh is not written yet"

say "STAGE verify-sync"
bash "$REC/tools/verify-sync.sh" > "$RUN/verify-sync.log" 2>&1 \
  || { say "$(grep '^FAIL' "$RUN/verify-sync.log" | tr '\n' '|')"; die "verify-sync"; }
say "verify-sync OK"

say "STAGE apply-overlays"
bash "$REC/apply-overlays.sh" "$TOP" > "$RUN/overlays.log" 2>&1 || {
  say "TAIL: $(grep -E 'FATAL' "$RUN/overlays.log" | tail -2 | tr '\n' '|')"; die "apply-overlays"; }
say "apply-overlays OK"

# Trust BOTH the exit status and the printed BUILD_RC.
say "STAGE build"
bash "$REC/aicp-build.sh" > "$B" 2>&1
BRC=$?
IRC=$(grep -oE '^BUILD_RC=[0-9]+' "$B" | tail -1 | cut -d= -f2)
say "BUILD_RC=$BRC inner=${IRC:-none}"
if [ "$BRC" -ne 0 ] || [ "${IRC:-1}" != "0" ]; then
  say "TAIL: $(grep -E 'FATAL|FAILED:|ninja: error|error:|LUNCH_FAILED' "$B" | tail -3 | tr '\n' '|')"
  die "build rc=$BRC inner=${IRC:-none}"
fi

OUTP="$TOP/out/target/product/S666LN"
Z=$(ls -t "$OUTP"/aicp_S666LN*.zip 2>/dev/null | head -1)
[ -n "$Z" ] || die "artifact-not-found in $OUTP"
say "ARTIFACT $Z  $(stat -c %s "$Z") B"
say "SHA256 $(sha256sum "$Z" | cut -d' ' -f1)"
echo "OK artifact=$Z" > "$V"
say "VERDICT OK $(date -u +%FT%TZ)"
