#!/bin/bash
#
# apply-overlays.sh <TREE_PATH>
#
# ROM CONFIGURATION ONLY. Idempotent AICP w16.2 / itel RS4 (S666LN) recipe.
# Re-run after any `repo sync`. Each step is guarded so re-running is safe.
#
# WHAT BELONGS HERE, AND WHAT DOES NOT (crDroid recipe, BLUEPRINT §10)
#   Device facts live in the three repos -- device_itel_S666LN, -kernel, vendor --
#   on branch lineage-23.2. This file holds only what is AICP's: ROM identity,
#   signing, app choices, patches to AICP's own forks. That split matters more on
#   this tree than it did on crDroid: the vendor is a SHARED base for AICP, the
#   OriginOS / One UI ports and AOSPA (project JOURNAL 11-12 (h)), so anything
#   AICP-only that leaks into the device repos travels to systems that are not AICP.
#
# STEP NUMBERS ARE NEVER RENUMBERED. Journals reference steps by number; a
# withdrawn step keeps its number and becomes a documented no-op.
#
set -euo pipefail
TREE="${1:?usage: apply-overlays.sh <path-to-aicp-tree>}"
cd "$TREE"

echo "===================================================================="
echo " apply-overlays.sh  tree=$TREE"
echo "===================================================================="


# --- step 1: the kernel is the imported Neutron v9 vanilla -------------------
# Not an import. On lineage-23.2 the kernel package COMMITS its prebuilt/
# (JOURNAL 11-12 (e): a public clone must build, and there is no from-source
# fallback), so the import happens once, in the package, by the device tree's
# import-kernel.sh -- which proves the Image is the one inside the published
# boot image and runs the KMI gate on both module sets. This step re-checks the
# result on every run: the three files are present, still hash to what
# IMPORTED recorded, came from a PUBLISHED image, and are committed.
# BoardConfig.mk $(error)s without them anyway; this says why, earlier.
echo "== step 1: imported kernel present and unchanged =="
KPKG="$TREE/device/itel/S666LN-kernel"
P="$KPKG/prebuilt"
for f in Image.gz vmlinux.symvers kernel.config IMPORTED; do
  [ -s "$P/$f" ] || { echo "   *** FATAL: $P/$f missing -- run device/itel/S666LN/import-kernel.sh vanilla in the kernel package and commit prebuilt/"; exit 1; }
done
( cd "$P" && sed -n 's/^  \([0-9a-f]\{64\}\)  /\1  /p' IMPORTED | sha256sum --quiet -c - ) || {
  echo "   *** FATAL: prebuilt/ no longer matches the sha256 list in IMPORTED"; exit 1; }
grep -q '^published: NONE' "$P/IMPORTED" && {
  echo "   *** FATAL: the imported kernel was never published (ALLOW_UNPUBLISHED=1 import)"; exit 1; }
[ -z "$(git -C "$KPKG" status --porcelain -- prebuilt)" ] || {
  echo "   *** FATAL: prebuilt/ has uncommitted changes in the kernel package"; exit 1; }
sed -n 's/^\(published\|kernel\):  */   \1: /p' "$P/IMPORTED"
echo "   kernel package @ $(git -C "$KPKG" rev-parse --short HEAD) ($(git -C "$KPKG" rev-parse --abbrev-ref HEAD))"


# --- step 2: one definition of the protobuf vendorcompat prebuilts ----------
# Soong analysis of ANY product stops in under a minute on this tree:
#   error: hardware/lineage/compat/Android.bp:679:1: module
#     "prebuilt_libprotobuf-cpp-full-3.9.1-vendorcompat" already defined
#     prebuilts/misc/protobuf_vendorcompat/Android.bp:13:1 <-- previous definition here
# (x4: full/lite x 3.9.1/21.12). Both are upstream: AOSP's prebuilts/misc at
# android-16.0.0_r4 (AICP w16.2's AOSP tag) and LineageOS's hardware/lineage/
# compat at lineage-23.2. Keep LineageOS's -- extract-utils' lib_fixups map the
# protobuf sonames to these -vendorcompat names precisely for it -- and hide
# AOSP's with soong's own Finder marker (build/soong/ui/build/finder.go:
# `.find-ignore` prunes the directory it sits in), an untracked file, so no
# tracked AOSP file is edited and a sync never conflicts with it.
# What it costs this device, measured on stock rev 28: our blobs need only the
# 3.9.1 pair (6 full + 11 lite references), and both 3.9.1 copies are
# byte-identical to AOSP's; only the 21.12 pair differs, and nothing of ours
# links it. tools/verify-sync.sh accepts exactly this marker (tree-edits.txt).
echo "== step 2: hide AOSP's duplicate protobuf vendorcompat prebuilts =="
PV="$TREE/prebuilts/misc/protobuf_vendorcompat"
HL="$TREE/hardware/lineage/compat/Android.bp"
if grep -q '"libprotobuf-cpp-full-3.9.1-vendorcompat"' "$HL" 2>/dev/null; then
  [ -f "$PV/.find-ignore" ] || : > "$PV/.find-ignore"
  echo "   $PV/.find-ignore present (LineageOS's copies are the definition)"
else
  # Upstream resolved it (LineageOS dropped theirs): the marker would now hide the ONLY copy.
  rm -f "$PV/.find-ignore"
  echo "   hardware/lineage/compat no longer defines them -- marker removed, AOSP's copies stay"
fi


echo "===================================================================="
echo " apply-overlays.sh: all steps OK"
echo "===================================================================="
