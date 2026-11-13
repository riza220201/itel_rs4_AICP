#!/bin/bash
# aicp-build.sh -- build AICP w16.2 for the itel RS4 on THIS box (operator 11-13: no rented server).
#
#   TOP=/mnt/Data/lineage-23.2            source tree
#   OUT_TARGET=/mnt/external_nvme/aicp-out   where $TOP/out (a symlink) points; see OUT below
#   PRODUCT=aicp_S666LN RELEASE=bp4a VARIANT=userdebug GOAL=bacon
#   DIRTY_OK=1                            build an uncommitted device tree (loud; never for a release)
#   KEEP_GOING=1                          m -k: build everything not behind a failure and report ALL
#                                         walls in one run (a first build's walls are independent)
#
# apply-overlays.sh MUST have been run against TOP first (build-and-sign.sh does both).
#
# GOAL=bacon is safe here, unlike crDroid 13: AICP's vendor/aicp/build/tasks/bacon.mk only
# hard-links the OTA package to $(AICP_VERSION).zip; it does NOT rm -rf the target-files
# (lineage-20's bacon.mk did, which is why the crDroid recipe built target-files-package).
#
# OUT: /mnt/Data holds the source (155 GB free after the sync); one A16 out was estimated at
# 130-180 GB (estimate of 2026-11-12), which leaves no margin there. /mnt/external_nvme (USB NVMe,
# ext4) had 256 GB free on 11-13. So the out dir lives there -- but as $TOP/out, a SYMLINK,
# with OUT_DIR left at its default. An absolute OUT_DIR outside the tree breaks soong:
#   platform_testing/Android.bp:728 "continuous_instrumentation_metric_tests": Path is outside
#   directory: /mnt/external_nvme/aicp-out/host/linux-x86/bin/perfetto_trace_processor_shell
# because build/soong/ci_tests/ci_test_package_zip.go:300 skips host files only when their path
# starts with "out" (it assumes OUT_DIR=out). Soong resolves a symlinked out itself
# (ui/build/sandbox_linux.go EvalSymlinks(outDir)).
#
# Every preflight below has cost a real build before (Knowledge build-system-gotchas,
# crDroid build-and-sign.sh, Advan 09-29).
set -u
TOP="${TOP:-/mnt/Data/lineage-23.2}"
REC="$(cd "$(dirname "$0")" && pwd)"
OUT_TARGET="${OUT_TARGET:-/mnt/external_nvme/aicp-out}"
unset OUT_DIR OUT_DIR_COMMON_BASE
PRODUCT="${PRODUCT:-aicp_S666LN}"
RELEASE="${RELEASE:-bp4a}"
VARIANT="${VARIANT:-userdebug}"
GOAL="${GOAL:-bacon}"
DT="$TOP/device/itel/S666LN"

die(){ echo "FATAL: $*"; exit 3; }
cd "$TOP" || exit 2

echo "== preflight"
# soong holds the whole module graph: ~40-47 GB working set on a 14 GiB host (A16 AOSPA),
# OOM-killed at 8.76 GiB without swap, and misreported as "bootstrap failed".
# /swapfile_compile is not in fstab: a power cut drops it silently.
grep -q '^/swapfile_compile ' /proc/swaps || die "/swapfile_compile is not active (not in fstab): sudo swapon /swapfile_compile"
SWAP=$(awk '/SwapFree/{print int($2/1048576)}' /proc/meminfo)
[ "${SWAP:-0}" -ge 40 ] || die "only ${SWAP} GiB swap free; soong's graph needs RAM+swap of ~50+ GiB"

mkdir -p "$OUT_TARGET" || die "cannot create $OUT_TARGET"
if [ -L "$TOP/out" ]; then
  [ "$(readlink -f "$TOP/out")" = "$(readlink -f "$OUT_TARGET")" ] || die "$TOP/out points at $(readlink -f "$TOP/out"), not $OUT_TARGET"
elif [ -e "$TOP/out" ]; then
  die "$TOP/out is a real directory; move it and make it a symlink to $OUT_TARGET"
else
  ln -s "$OUT_TARGET" "$TOP/out"
fi
FREE=$(df -BG --output=avail "$OUT_TARGET" | tail -1 | tr -dc 0-9)
if [ -d "$OUT_TARGET/soong" ]; then NEED=40; else NEED=200; fi
[ "${FREE:-0}" -ge "$NEED" ] || die "only ${FREE} GB free for the out dir $OUT_TARGET (need ${NEED} for a $( [ $NEED = 200 ] && echo fresh || echo warm) out)"

# Host tools the tree's makefiles shell out to at PARSE time -- a missing one costs a whole
# analysis before kati says so (analysis-7: vendor/aicp/bootanimation/Android.mk:64 "stop",
# ImageMagick's mogrify generates AICP's boot animation). Debian: apt install imagemagick.
command -v mogrify >/dev/null || die "ImageMagick (mogrify) is not installed: sudo apt install imagemagick"

# a sync and a build on one tree: the build reads a half-updated source
( exec 9>"$TOP/.sync.lock"; flock -n 9 ) || die "a repo sync holds $TOP/.sync.lock"

# 08-18: chromium-webview synced as empty LFS pointers once
for a in arm arm64; do
  [ "$(stat -c %s "external/chromium-webview/prebuilt/$a/webview.apk" 2>/dev/null || echo 0)" -gt 1000000 ] \
    || die "external/chromium-webview/prebuilt/$a/webview.apk is not a payload (git lfs pull there)"
done

# the local manifest the tree was synced with is the recipe's
cmp -s "$REC/local_manifests/S666LN.xml" .repo/local_manifests/S666LN.xml \
  || die ".repo/local_manifests/S666LN.xml differs from the recipe's local_manifests/S666LN.xml"

# the tree soong reads is the tree we commit to (crDroid 08-19/08-28: a build carried work that
# had been reverted in git). device/itel/S666LN is a git worktree of the one device repo.
[ "$(git -C "$DT" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "lineage-23.2" ] || die "$DT is not on branch lineage-23.2"
if [ -n "$(git -C "$DT" status --porcelain)" ]; then
  [ "${DIRTY_OK:-0}" = 1 ] || die "$DT has uncommitted changes (commit them, or DIRTY_OK=1 for a throwaway test)"
  echo "🔴 DIRTY_OK=1: building UNCOMMITTED device-tree changes; this build is not reproducible"
fi
[ -d vendor/itel/S666LN ] || die "vendor/itel/S666LN is missing (vendor tree not generated yet)"
echo "   swap ${SWAP} GiB free, out -> $OUT_TARGET ${FREE} GB free, webview ok, manifest ok"
echo "   device tree $(git -C "$DT" rev-parse --short HEAD) $(git -C "$DT" log -1 --format=%s | cut -c1-70)"

# envsetup.sh and lunch read unset variables (ANDROID_GLOBAL_BUILD_PATHS, ...): no set -u past here.
set +u
source build/envsetup.sh
lunch "${PRODUCT}-${RELEASE}-${VARIANT}" || { echo "LUNCH_FAILED"; exit 2; }
date "+BUILD_START %F %T"
if [ "${KEEP_GOING:-0}" = 1 ]; then echo "KEEP_GOING=1: m -k"; m -k "$GOAL"; else m "$GOAL"; fi
rc=$?
echo "BUILD_RC=$rc"
date "+BUILD_END %F %T"
[ "$rc" -eq 0 ] && ls -la "$TOP/out/target/product/S666LN/"*.zip 2>/dev/null
exit $rc
