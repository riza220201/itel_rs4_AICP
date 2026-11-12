# itel RS4 (S666LN) → AICP w16.2 (Android 16)

Build **recipe** for AICP w16.2 (= LineageOS `lineage-23.2` + AICP's 33 repos, AOSP `android-16.0.0_r4`) on the
**itel RS4** (`S666LN`, MediaTek **MT6789 / Helio G99**). Same shape as `~/itel_rs4_Crdroid`: a local manifest
plus idempotent scripts — not the Android source tree.

AICP is the ROM that proves the lineage-23.2 device stack (operator, 2026-11-12) until it is as stable as the A13
tree; the same vendor then carries the OriginOS 6 / new One UI ports and the revived AOSPA. The project's journal
and resume point live with the device tree: `~/itel-rs4-devicetree/notes/lineage23/{JOURNAL,RESUME}.md`.

## The device stack (branch `lineage-23.2` in each)

| repo | role |
|---|---|
| `device_itel_S666LN` | device glue, sepolicy, overlays, `aicp_S666LN.mk` / `lineage_S666LN.mk` over one `product_common.mk` |
| `device_itel_S666LN-kernel` | dtb, dtbo, 198 + 206 modules, **`prebuilt/` = the published Neutron v9 vanilla** (committed; imported by the device tree's `import-kernel.sh`) |
| `vendor_itel_S666LN` | blobs from stock rev 28 via 23.2's extract-utils |

The kernel is **never compiled in the ROM**, and a missing import stops the build (no from-source fallback).

## Layout

| path | what |
|---|---|
| `local_manifests/S666LN.xml` | the tree's `.repo/local_manifests/S666LN.xml` (the build refuses to run if they differ) |
| `sync.sh` | flock'd, shallow, stall-timeout `repo sync` |
| `tools/verify-sync.sh` | read-only: worktrees, shallowness, LFS payloads, `tmp_pack_*`, AICP owns build/soong, `repo status` |
| `apply-overlays.sh` | **ROM configuration only**, numbered idempotent steps; re-run after any sync. Device facts belong in the device repos |
| `aicp-build.sh` | preflight (swap, out-dir disk, sync lock, LFS, manifest, device tree clean + on `lineage-23.2`, vendor present) → `lunch aicp_S666LN-bp4a-userdebug` → `m bacon` |
| `build-and-sign.sh` | the detached driver: verify-sync → apply-overlays → build → VERDICT. Signing comes with `sign-release.sh`, once release keys are decided |

## Reproduce

```sh
mkdir -p /mnt/Data/lineage-23.2 && cd /mnt/Data/lineage-23.2
repo init -u https://github.com/AICP/platform_manifest.git -b w16.2 --git-lfs --depth=1 --no-clone-bundle
cp ~/itel_rs4_AICP/local_manifests/S666LN.xml .repo/local_manifests/
~/itel_rs4_AICP/sync.sh && ~/itel_rs4_AICP/tools/verify-sync.sh

setsid nohup bash ~/itel_rs4_AICP/build-and-sign.sh > /dev/null 2>&1 < /dev/null &
# -> /mnt/Data/lineage-23.2/tmp-release/run-<ts>/{VERDICT,driver.log,build.log}
```

Host: 12 threads, 14 GiB RAM, **≥ 40 GiB swap free** (soong's A16 graph needs it; `/swapfile_compile` is not in
fstab — re-enable it after a power cut). The out dir is `$TOP/out`, a **symlink** to `/mnt/external_nvme/aicp-out`
(≥ 200 GB free for a fresh out) — never an absolute `OUT_DIR`: AOSP's `ci_test_package_zip.go` assumes paths start with `out`.

Not in this repo: signing keys, stock firmware and blobs, built zips, logs.
