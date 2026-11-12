#!/bin/bash
# sync.sh [repo sync args...] -- AICP w16.2 (= LineageOS 23.2 + 33 AICP repos) for the itel RS4.
#
#   TOP=/mnt/Data/lineage-23.2 (default)
#
# First time (once per checkout):
#   repo init -u https://github.com/AICP/platform_manifest.git -b w16.2 --git-lfs --depth=1 --no-clone-bundle
#   cp <recipe>/local_manifests/S666LN.xml .repo/local_manifests/
#
# Why it looks like this (project JOURNAL 11-12 (a), (d), (g)):
# - single instance (flock): two repo syncs on one .repo is a known trap
# - shallow: depth comes from `repo init --depth=1`; repo has no --depth flag, and a
#   retry into a half-fetched project goes FULL depth -> delete its .repo/projects AND
#   .repo/project-objects entries before re-syncing it
# - stall timeout via env, per run: the global git config has http.lowspeedlimit 0
#   (never times out), and the 08-18 fix is not set globally any more
# - rc 0 is not verification: run tools/verify-sync.sh afterwards
set -u
TOP="${TOP:-/mnt/Data/lineage-23.2}"
exec 9>"$TOP/.sync.lock"
flock -n 9 || { echo "another sync holds $TOP/.sync.lock"; exit 1; }
export GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=60
cd "$TOP" || exit 1
echo "$(date '+%F %T') start"
repo sync -c -j8 --no-tags --no-clone-bundle --optimized-fetch --retry-fetches=5 "$@"
rc=$?
echo "$(date '+%F %T') end rc=$rc"
echo "$rc" > "$TOP/.sync-rc"
exit $rc
