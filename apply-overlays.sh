#!/bin/bash
#
# apply-overlays.sh <TREE_PATH>
#
# ROM CONFIGURATION ONLY. Idempotent AICP w16.2 / itel RS4 (S666LN) recipe.
# Re-run after any `repo sync`. Each step is guarded so re-running is safe.
#
# WHAT BELONGS HERE, AND WHAT DOES NOT (as in the crDroid recipe)
#   Device facts live in the three repos -- device_itel_S666LN, -kernel, vendor --
#   on branch lineage-23.2. This file holds only what is AICP's: ROM identity,
#   signing, app choices, patches to AICP's own forks. That split matters more on
#   this tree than it did on crDroid: the vendor is a SHARED base for AICP, the
#   OriginOS / One UI ports and AOSPA (decided 2026-11-12), so anything
#   AICP-only that leaks into the device repos travels to systems that are not AICP.
#
# STEP NUMBERS ARE NEVER RENUMBERED. Records refer to steps by number; a
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
# (2026-11-12: a public clone must build, and there is no from-source
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


# --- step 2: WITHDRAWN 11-13, a documented no-op ------------------------------
# It hid AOSP's prebuilts/misc/protobuf_vendorcompat (duplicates of
# hardware/lineage/compat's protobuf vendorcompat prebuilts) with a .find-ignore
# marker, after a GENERIC product's analysis died on the duplicate. Our product
# never needed it: vendor/aicp/config/common.mk:6 already sets
#     PRODUCT_SOURCE_ROOT_DIRS += -prebuilts/misc/protobuf_vendorcompat
# for every AICP product (seen in lunch's PRODUCT_SOURCE_ROOT_DIRS). This step
# now only removes a marker an earlier run may have left.
echo "== step 2: (withdrawn) remove the old protobuf .find-ignore marker if present =="
rm -f "$TREE/prebuilts/misc/protobuf_vendorcompat/.find-ignore"


# === FRAMEWORK PATCHES carried from the crDroid recipe (apply-overlays-v2.sh), each
# re-read against A16 on 2026-11-13.
# The crDroid step number is in each title. Obsolete on A16, so NOT here: crDroid 39
# (VkNativeBufferANDROID SPEC 11 carries usage3 + ahb, filled natively), 45/46/48
# (extensions native), 47 (native, conditional), 35/36 (bootctrl and the AIDL power
# impl are gone from 23.2's hardware/mediatek). Every step: guard -> anchor count == 1
# -> post-condition grep, and FATAL on any miss. Paths are listed in tree-edits.txt.
HERE="$(cd "$(dirname "$0")" && pwd)"


# --- step 3: libgui reports BufferQueue frames to ged (GPU DVFS)  [crDroid 41] --
# On MT6789 ged's DVFS loop only runs when told a frame happened; MediaTek's libgui
# does that through libged_kpi.so, AOSP's does not, so the GPU sits at the OPP it
# powered on at (crDroid v3.1: ged_dvfs_run 0 hits in 20 s of gameplay vs 12,152 job
# submits). gedkpi/GedKpiHook.h is crDroid's final header (74e6a1a: queue hands ged
# fence_fd = -1 -- a real fence panicked ged_kpi_gpu_3d_fence_sync_cb and BOOTLOOPED).
# The device tree ships libged_kpi/libged_sys (prebuilts/gedkpi).
# A16 DELTA: queueBuffer's anchor. A13 had `mCore->mDequeueCondition.notify_all();`
# where A16 has `mCore->notifyBufferReleased();`, same position; the hook still sees
# the finished item (already pushed onto mQueue; its GraphicBuffer is cleared only
# further down, as on A13). Dry run on A16 sources: 7 call sites.
echo "== step 3: libgui reports BufferQueue frames to ged (crDroid 41) =="
GUIDIR="$TREE/frameworks/native/libs/gui"
[ -d "$GUIDIR" ] || { echo "   *** FATAL: frameworks/native/libs/gui not found"; exit 1; }
# Header copied UNCONDITIONALLY, before the already-patched test (crDroid lesson: a
# header fix inside the else-branch never reached a build).
cp "$HERE/gedkpi/GedKpiHook.h" "$GUIDIR/GedKpiHook.h"
if grep -q "gedkpi::onQueue" "$GUIDIR/BufferQueueProducer.cpp"; then
  echo "   call sites already patched; GedKpiHook.h refreshed"
else
  python3 - "$GUIDIR" <<'PYGUI'
import sys, os
d = sys.argv[1]
def add_include(fn):
    p = os.path.join(d, fn); s = open(p).read()
    if '"GedKpiHook.h"' in s: return
    i = s.rindex('#include', 0, s.index('namespace android'))
    e = s.index('\n', i) + 1
    open(p, 'w').write(s[:e] + '\n#include "GedKpiHook.h"\n' + s[e:])
def once(s, a, what):
    if s.count(a) != 1: sys.exit("%s anchor count %d, expected 1" % (what, s.count(a)))
for f in ("BufferQueueCore.cpp", "BufferQueueProducer.cpp", "BufferQueueConsumer.cpp"):
    add_include(f)
p = os.path.join(d, "BufferQueueCore.cpp"); s = open(p).read()
a = "        mUnusedSlots.push_front(s);\n    }\n}\n\nBufferQueueCore::~BufferQueueCore() {}"
once(s, a, "BufferQueueCore ctor/dtor")
s = s.replace(a, "        mUnusedSlots.push_front(s);\n    }\n    gedkpi::onCreate(mUniqueId);\n}\n\n"
                 "BufferQueueCore::~BufferQueueCore() {\n    gedkpi::onDestroy(mUniqueId);\n}", 1)
open(p, 'w').write(s)
p = os.path.join(d, "BufferQueueProducer.cpp"); s = open(p).read()
a = "        mCore->mBufferHasBeenQueued = true;\n        mCore->notifyBufferReleased();\n        mCore->mLastQueuedSlot = slot;\n"
once(s, a, "queueBuffer")
s = s.replace(a, a + "\n        // Third argument is QedBuffer_length -- the QUEUE DEPTH, not the slot.\n"
                     "        // item.mGraphicBuffer is cleared further below for non-SF consumers.\n"
                     "        gedkpi::onQueue(mCore->mUniqueId, item.mGraphicBuffer, item.mFence,\n"
                     "                        static_cast<int>(mCore->mQueue.size()));\n", 1)
a = "    if (outBufferAge) {\n        *outBufferAge = mCore->mBufferAge;\n    }\n    addAndGetFrameTimestamps(nullptr, outTimestamps);\n"
once(s, a, "dequeueBuffer")
s = s.replace(a, "    if (outBufferAge) {\n        *outBufferAge = mCore->mBufferAge;\n    }\n"
                 "    gedkpi::onDequeue(mCore->mUniqueId, mSlots[*outSlot].mGraphicBuffer, *outFence);\n"
                 "    addAndGetFrameTimestamps(nullptr, outTimestamps);\n", 1)
a = "            mCore->mConnectedApi = api;\n"
once(s, a, "connect")
s = s.replace(a, a + "            // getCallingPid() directly: mCore->mConnectedPid is not assigned\n"
                     "            // until further below in this function.\n"
                     "            gedkpi::onConnect(mCore->mUniqueId, api,\n"
                     "                              BufferQueueThreadState::getCallingPid());\n", 1)
a = "                    mCore->mConnectedApi = BufferQueueCore::NO_CONNECTED_API;\n"
once(s, a, "disconnect")
s = s.replace(a, a + "                    gedkpi::onDisconnect(mCore->mUniqueId);\n", 1)
open(p, 'w').write(s)
p = os.path.join(d, "BufferQueueConsumer.cpp"); s = open(p).read()
i = s.index("status_t BufferQueueConsumer::acquireBuffer")
j = s.index("\n    return NO_ERROR;\n", i)
s = s[:j] + "\n    gedkpi::onAcquire(mCore->mUniqueId, outBuffer->mGraphicBuffer);\n" + s[j:]
open(p, 'w').write(s)
PYGUI
  [ $? -eq 0 ] || { echo "   *** FATAL: libgui gedkpi patch failed"; exit 1; }
  for c in "onQueue:BufferQueueProducer" "onDequeue:BufferQueueProducer" "onConnect:BufferQueueProducer" \
           "onDisconnect:BufferQueueProducer" "onAcquire:BufferQueueConsumer" "onCreate:BufferQueueCore" \
           "onDestroy:BufferQueueCore"; do
    grep -q "gedkpi::${c%%:*}" "$GUIDIR/${c#*:}.cpp" || { echo "   *** FATAL: gedkpi::${c%%:*} missing"; exit 1; }
  done
  echo "   patched (create/destroy, connect/disconnect, dequeue/queue, acquire)"
fi
# Post-condition on BOTH paths: queue hands ged fence_fd = -1 (the bootloop fix). The
# control is the dequeue call beside it, which legitimately passes a fence.
grep -q 'queueTag(id, -1, queuedBufferCount' "$GUIDIR/GedKpiHook.h" \
  || { echo "   *** FATAL: GedKpiHook.h onQueue is not passing fence_fd = -1 (bootloop fix missing)"; exit 1; }
grep -q 'dequeueTag(id, fd,' "$GUIDIR/GedKpiHook.h" \
  || { echo "   *** FATAL: control failed -- onDequeue not found, the grep above proves nothing"; exit 1; }
echo "   onQueue fence_fd = -1 confirmed (control: onDequeue still passes a fence)"


# --- step 4: AHardwareBuffer_allocate never leaves *outBuffer indeterminate  [crDroid 40]
# A16 still returns early without writing it (AHardwareBuffer.cpp, the gralloc
# failure path), and Mali r54p1 ignores the result of the HAL_PIXEL_FORMAT_R_8 probe
# this gralloc always fails. Defensive -- crDroid's own note: not THE r54p1 crash fix.
echo "== step 4: AHardwareBuffer_allocate clears *outBuffer (crDroid 40) =="
AHB="$TREE/frameworks/native/libs/nativewindow/AHardwareBuffer.cpp"
[ -f "$AHB" ] || { echo "   *** FATAL: $AHB not found"; exit 1; }
if grep -q 'outBuffer indeterminate' "$AHB"; then
  echo "   already patched"
else
  python3 - "$AHB" <<'PYAHB'
import sys
p = sys.argv[1]; s = open(p).read()
old = "    if (!outBuffer || !desc) return BAD_VALUE;\n"
new = old + ("    // Never leave *outBuffer indeterminate. The early returns below do not write\n"
             "    // it, so a caller that ignores the return code keeps whatever its variable\n"
             "    // held -- and AHardwareBuffer_getNativeHandle's null check cannot catch\n"
             "    // garbage, only null. Mali r54p1 ignores the result of its R_8 probe.\n"
             "    *outBuffer = nullptr;\n")
if s.count(old) != 1: sys.exit("anchor count %d, expected 1" % s.count(old))
open(p, "w").write(s.replace(old, new, 1))
PYAHB
  [ $? -eq 0 ] || { echo "   *** FATAL: AHardwareBuffer patch failed"; exit 1; }
  grep -q '\*outBuffer = nullptr;' "$AHB" || { echo "   *** FATAL: clear not present"; exit 1; }
  echo "   patched"
fi


# --- step 5: ART Heap::RecordFree saturates instead of wrapping  [crDroid 37] ----
# A positive freed_bytes larger than num_bytes_allocated_ wraps the counter to ~2^64
# and every later allocation in that process throws OOM (crDroid 2026-08-28: TikTok,
# 5/5 runs, 13 s from launch). RACING_DCHECK_LE is compiled out of user builds;
# RecordFreeRevoke() twenty lines below already guards the same subtraction. A16's
# RecordFree is unchanged upstream; ART builds from source here
# (ReleaseDefaultModuleBuildFromSource = true), so this reaches com.android.art.
echo "== step 5: ART RecordFree underflow clamp (crDroid 37) =="
HEAPCC="$TREE/art/runtime/gc/heap.cc"
[ -f "$HEAPCC" ] || { echo "   *** FATAL: $HEAPCC not found"; exit 1; }
if grep -q 'num_bytes_allocated_ underflow clamped' "$HEAPCC"; then
  echo "   already patched"
else
  python3 - "$HEAPCC" <<'PYART'
import sys
p = sys.argv[1]; s = open(p).read()
old = ("  // Note: This relies on 2s complement for handling negative freed_bytes.\n"
       "  num_bytes_allocated_.fetch_sub(static_cast<ssize_t>(freed_bytes), std::memory_order_relaxed);\n")
new = """  if (LIKELY(freed_bytes > 0)) {
    // Saturate at zero rather than wrapping. RACING_DCHECK_LE above is compiled out of user
    // builds, and a positive freed_bytes CAN exceed the counter (measured: the large object
    // space crediting more freed bytes than were ever added). Unlike the negative case below
    // that wrap is not self-correcting -- num_bytes_allocated_ becomes ~2^64 and every
    // subsequent allocation throws OutOfMemoryError for the life of the process.
    size_t cur = num_bytes_allocated_.load(std::memory_order_relaxed);
    const size_t sub = static_cast<size_t>(freed_bytes);
    size_t next;
    bool clamped;
    do {
      clamped = sub > cur;
      next = clamped ? 0u : cur - sub;
    } while (!num_bytes_allocated_.compare_exchange_weak(cur, next, std::memory_order_relaxed));
    if (UNLIKELY(clamped)) {
      LOG(WARNING) << "num_bytes_allocated_ underflow clamped: freed " << freed_bytes
                   << " bytes against a counter of " << cur;
    }
  } else {
    // Negative freed_bytes is a legitimate increase (padding/binning across space
    // transitions). Keep the original 2s-complement add.
    num_bytes_allocated_.fetch_sub(static_cast<ssize_t>(freed_bytes), std::memory_order_relaxed);
  }
"""
if s.count(old) != 1: sys.exit("anchor count %d, expected 1" % s.count(old))
open(p, "w").write(s.replace(old, new, 1))
PYART
  [ $? -eq 0 ] || { echo "   *** FATAL: ART patch failed"; exit 1; }
  grep -q 'compare_exchange_weak(cur, next' "$HEAPCC" || { echo "   *** FATAL: CAS loop missing"; exit 1; }
  echo "   patched (positive freed_bytes saturates; negative path unchanged)"
fi


# --- step 6: GameManagerService publishes sys.gamemode.active  [crDroid 38] ------
# The device tree's init.cgroup.rc triggers a game-scoped sched_pelt_multiplier on
# property:sys.gamemode.active; nothing else on this device publishes a game signal
# init can see (crDroid getprop diff, 08-28). "sys." is system_prop, settable by
# system_server. A16 DELTA: setPowerMode(Mode.GAME, ...) is called from FIVE places
# (A13: two) -- service start OFF, first non-game OFF, first game ON, no games OFF,
# only games ON -- so the property is set beside every one of them, and exactly five
# is asserted so an upstream change is a FATAL, not a silent partial port.
echo "== step 6: GameManagerService publishes sys.gamemode.active (crDroid 38) =="
GMS="$TREE/frameworks/base/services/core/java/com/android/server/app/GameManagerService.java"
[ -f "$GMS" ] || { echo "   *** FATAL: $GMS not found"; exit 1; }
if grep -q 'sys.gamemode.active' "$GMS"; then
  echo "   already patched"
else
  python3 - "$GMS" <<'PYGMS'
import re, sys
p = sys.argv[1]; s = open(p).read()
pat = re.compile(r'^(\s*)mPowerManagerInternal\.setPowerMode\(Mode\.GAME, (true|false)\);\n', re.M)
n = len(pat.findall(s))
if n != 5: sys.exit("setPowerMode(Mode.GAME, ...) count %d, expected 5" % n)
s = pat.sub(lambda m: m.group(0) + '%sandroid.os.SystemProperties.set("sys.gamemode.active", "%s");\n'
            % (m.group(1), '1' if m.group(2) == 'true' else '0'), s)
open(p, "w").write(s)
PYGMS
  [ $? -eq 0 ] || { echo "   *** FATAL: GameManagerService patch failed"; exit 1; }
  [ "$(grep -c 'sys.gamemode.active' "$GMS")" = "5" ] || { echo "   *** FATAL: expected 5 setters"; exit 1; }
  echo "   patched (5 setters beside setPowerMode(Mode.GAME, ...))"
fi


# --- step 7: bypass-charging tile in Game Space  [crDroid 19] -----------------
# Lets the adapter carry the system load instead of charging the cell, so a long
# game session on the charger does not cook the battery. A game-bar tile (not a
# QS tile): people want it while gaming, and AICP ships chaldeaprjkt's Game Space
# from source (packages/apps/GameSpace, AICP's fork) with the same tile API as
# crDroid's, so crDroid step 19 ports as is. Measured on this hardware under
# crDroid: current_now ~396 mA -> ~0 mA -> ~393 mA. Read current_now, not capacity
# or status (both stay "100" / "Charging"), and use a wall charger: a 500 mA PC
# port cannot feed a running game, so bypass then looks like a drain.
#
# WIRING, and why it is shaped this way:
#  * Game Space is platform-signed with sharedUserId=android.uid.system, so it
#    runs as system_app, a coredomain. property.te neverallows every coredomain
#    except init from setting a vendor property, so a property + init-trigger
#    bridge is not implementable from here (crDroid's precompiled_sepolicy
#    refused it). The app writes the node directly; the tile reads it back, so
#    its UI follows the hardware, and isSupported hides it where the node is
#    absent (Game Space is a shared app).
#  * The ONE sepolicy rule it needs, `allow system_app sysfs_aichg_file:file
#    rw_file_perms;`, is a device fact and already lives in the device tree
#    (sepolicy/vendor/system_app.te). This step only VERIFIES it.
#  * Nothing persists the hardware state: the node resets to 0 on reboot, and the
#    session end ALWAYS writes 0, so a crash can never leave a phone that silently
#    refuses to charge. The preference persists in AppSettings and is re-applied
#    at the next session start, the split stayAwake already uses.
#  * BOTH tiles.xml: layout/ (columnCount 2) and layout-land/ (columnCount 3) are
#    separate files, and a game runs landscape. Under crDroid the tile shipped in
#    portrait only and was invisible in-game for three builds.
echo "== step 7: Game Space bypass-charging tile (crDroid 19) =="
GS="$TREE/packages/apps/GameSpace/app/src/main"
GSJ="$GS/java/io/chaldeaprjkt/gamespace"
SEPOL_AICHG="$TREE/device/itel/S666LN/sepolicy/vendor/system_app.te"
[ -d "$GSJ" ] || { echo "   *** FATAL: Game Space source not found at $GSJ"; exit 1; }

# 7a: the three new files, kept whole in the recipe
cp "$HERE/gamespace/ChargeUtils.kt"       "$GSJ/utils/ChargeUtils.kt"
cp "$HERE/gamespace/BypassChargeTile.kt"  "$GSJ/widget/tiles/BypassChargeTile.kt"
cp "$HERE/gamespace/ic_charge_bypass.xml" "$GS/res/drawable/ic_charge_bypass.xml"
echo "   ChargeUtils.kt / BypassChargeTile.kt / ic_charge_bypass.xml staged"

# 7b: surgical edits to existing Game Space files, each guarded on its own marker.
# A marker must be a DECLARATION, never a bare name another edit writes (crDroid
# step 13/19 own goal: a guard matching the previous edit's output skipped itself).
python3 - "$GS" <<'EOP'
import sys, os
gs = sys.argv[1]
gsj = os.path.join(gs, "java/io/chaldeaprjkt/gamespace")

def patch(path, marker, anchor, addition, after=True):
    with open(path) as f:
        src = f.read()
    # dir included: layout/ and layout-land/tiles.xml would log identically
    name = "%s/%s" % (os.path.basename(os.path.dirname(path)), os.path.basename(path))
    if marker in src:
        print("   %s: already patched" % name)
        return
    if src.count(anchor) != 1:
        raise SystemExit("FATAL: anchor found %d times (need 1) in %s:\n%r" % (src.count(anchor), path, anchor))
    with open(path, "w") as f:
        f.write(src.replace(anchor, anchor + addition if after else addition + anchor))
    print("   %s: patched" % name)

patch(os.path.join(gsj, "data/AppSettings.kt"), "var chargeBypass",
      """    var lockGesture
        get() = db.getBoolean(KEY_LOCK_GESTURE, false)
        set(value) = db.edit().putBoolean(KEY_LOCK_GESTURE, value).apply()
""",
      """
    var chargeBypass
        get() = db.getBoolean(KEY_CHARGE_BYPASS, false)
        set(value) = db.edit().putBoolean(KEY_CHARGE_BYPASS, value).apply()
""")
patch(os.path.join(gsj, "data/AppSettings.kt"), "const val KEY_CHARGE_BYPASS",
      '        const val KEY_LOCK_GESTURE = "gamespace_lock_gesture"\n',
      '        const val KEY_CHARGE_BYPASS = "gamespace_charge_bypass"\n')

mm = os.path.join(gsj, "utils/di/MainModule.kt")
patch(mm, "import io.chaldeaprjkt.gamespace.utils.ChargeUtils",
      "import io.chaldeaprjkt.gamespace.utils.GameModeUtils\n",
      "import io.chaldeaprjkt.gamespace.utils.ChargeUtils\n", after=False)
patch(mm, "fun provideChargeUtils",
      """    @Provides
    @Singleton
    fun provideScreenUtils(@ApplicationContext context: Context) = ScreenUtils(context)
""",
      """
    @Provides
    @Singleton
    fun provideChargeUtils() = ChargeUtils()
""")

ep = os.path.join(gsj, "utils/di/ServiceViewEntryPoint.kt")
patch(ep, "import io.chaldeaprjkt.gamespace.utils.ChargeUtils",
      "import io.chaldeaprjkt.gamespace.utils.GameModeUtils\n",
      "import io.chaldeaprjkt.gamespace.utils.ChargeUtils\n", after=False)
patch(ep, "fun chargeUtils(): ChargeUtils",
      "    fun screenUtils(): ScreenUtils\n",
      "    fun chargeUtils(): ChargeUtils\n")

sess = os.path.join(gsj, "gamebar/SessionService.kt")
patch(sess, "import io.chaldeaprjkt.gamespace.utils.ChargeUtils",
      "import io.chaldeaprjkt.gamespace.utils.GameModeUtils\n",
      "import io.chaldeaprjkt.gamespace.utils.ChargeUtils\n", after=False)
patch(sess, "lateinit var chargeUtils",
      """    @Inject
    lateinit var screenUtils: ScreenUtils
""",
      """
    @Inject
    lateinit var chargeUtils: ChargeUtils
""")
# AICP nests this one level deeper than crDroid (inside commandIntent?.let { }):
# 16 spaces. With crDroid's 12-space anchor it matched as a SUBSTRING of the
# 16-space line -- right block, wrong indentation; the anchor is now exact.
patch(sess, "chargeUtils.bypass = appSettings.chargeBypass",
      "                screenUtils.lockGesture = appSettings.lockGesture\n",
      "                chargeUtils.bypass = appSettings.chargeBypass\n")
# the safety-critical half: always release at session end
patch(sess, "chargeUtils.bypass = false",
      "        screenUtils.unbind()\n",
      "        chargeUtils.bypass = false\n")

for tiles in ("res/layout/tiles.xml", "res/layout-land/tiles.xml"):
    patch(os.path.join(gs, tiles), "BypassChargeTile",
          """    <io.chaldeaprjkt.gamespace.widget.tiles.NotificationTile
        android:layout_width="wrap_content"
        android:layout_height="wrap_content" />
""",
          """
    <io.chaldeaprjkt.gamespace.widget.tiles.BypassChargeTile
        android:layout_width="wrap_content"
        android:layout_height="wrap_content" />
""")

patch(os.path.join(gs, "res/values/strings.xml"), 'name="bypass_charge_title"',
      '    <string name="stay_awake_title">Stay awake</string>\n',
      '    <string name="bypass_charge_title">Bypass charging</string>\n')
EOP

# 7b-verify: every layout variant of tiles.xml carries the tile (enumerated, not
# assumed: a new qualifier directory must fail here, not ship a missing tile)
for _t in "$GS"/res/layout*/tiles.xml; do
  grep -q "BypassChargeTile" "$_t" || { echo "   *** FATAL: BypassChargeTile missing from ${_t#$GS/}"; exit 1; }
done
echo "   tile present in: $(cd "$GS" && ls -d res/layout*/tiles.xml | tr '\n' ' ')"

# 7c: the device tree must already grant the write (a device fact, not this recipe's)
grep -q '^allow system_app sysfs_aichg_file:file rw_file_perms;' "$SEPOL_AICHG" \
  || { echo "   *** FATAL: device tree lacks 'allow system_app sysfs_aichg_file' ($SEPOL_AICHG)"; exit 1; }
echo "   device tree grants system_app -> sysfs_aichg_file (rw)"

echo "===================================================================="
echo " apply-overlays.sh: all steps OK"
echo "===================================================================="
