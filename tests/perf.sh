#!/bin/sh

set -euo pipefail

dest=$(mktemp -d /var/tmp/dnfcowperf.XXXXXX)
packages='bash glibc-langpack-en jq'
usage() {
        cat >&2 <<END
Ohai! This is performance test suite tool for measuring RPMCoW. This is work in
progress, so please mind your step. See
https://fedoraproject.org/wiki/Changes/RPMCoW#Performance_Metrics
for more context.

Setup:

# Enable the rpmcow COPR repo with f33 packages (so far)
dnf copr enable malmond/rpmcow
# get everything up to date, including the test versions of rpm, librepo
dnf upgrade --refresh
# Get some other cool tools
dnf install bpftrace sysstat blktrace compsize strace

Examples:

${0} dd         Creates a single 1G file then copies, reflinks, and deletes
${0} full       Downloads and installs a few packages in a temporary directory
${0} split      Downloads a few packages into cache, then in a seperate step,
                installs them.

Once you've run tests, you can add in CoW using:

# enable plugin, add in rpm-plugin-reflink (because a recommend not a requires)
dnf install python3-dnf-plugin-cow rpm-plugin-reflink

then re-run the full or split tests, and you should see some differences.

The program shows standard 'time' output, along with block I/O deltas for each
step. Good luck!
END
}
clean() {
        rm "${dest}" -rf
}
fail() {
        echo "${*}" >&2
        exit 1
}
dnfroot() {
        # strace -Tfo /var/tmp/trace.$$.${RANDOM}
        dnf --quiet --releasever=33 --setopt=keepcache=True --setopt=history_record=False --assumeyes --installroot "${dest}" ${*}
}
cgroup_path() {
        echo /sys/fs/cgroup$(awk -F\: '{print $3}' /proc/self/cgroup)
}
io_stat() {
        sync
        echo 3 > /proc/sys/vm/drop_caches
        cat $(cgroup_path)/io.stat
}
warm_cache() {
        # 3 > drop_caches means all pages, including those of programs you just
        # ran. Running these a bit might re-read some of the pages in so we
        # don't count them in the measurement.
        {
                dnf --version
                awk --version
                sync --version
                dd --version
        } > /dev/null
}
before() {
        warm_cache
        io_stat
}
diff_io_stat() {
        echo "${1:?message}:"
        # so sorry about awk
        echo -e "${2:?before}\n$(io_stat)" | awk '{
                devices[$1]++
                for (i=2; i<=NF; i++) {
                        split($i, kv, "=")
                        k=kv[1]
                        v=kv[2]
                        keys[k] = 1
                        data[$1, k, devices[$1]] = v
                }
        }
        END {
                for (d in devices) {
                        printf(d)
                        for (k in keys) {
                                v = data[d, k, 2] - data[d, k, 1]
                                if (v == 0) {
                                        continue
                                }
                                suffix=""
                                if (k ~ /bytes$/) {
                                        v = v / 2 ** 20
                                        suffix="MiB"
                                }
                                printf(" %s=%.2f%s", k, v, suffix)
                        }
                        printf("\n")
                }
        }'
}
full_unit() {
        dnfroot makecache
        before=$(before)
        time dnfroot install ${packages}
        diff_io_stat 'full copy' "${before}"
}
split_unit() {
        dnfroot makecache
        before=$(before)
        time dnfroot install --downloadonly ${packages}
        diff_io_stat 'Download usage' "${before}"
        before=$(before)
        time dnfroot install ${packages}
        diff_io_stat 'Install usage' "${before}"
        before=$(before)
        time rpm --root "${dest}" -e jq
        diff_io_stat 'remove jq using rpm' "${before}"
        before=$(before)
        time rpm --root "${dest}" -Uhv $(find "${dest}" -name 'jq*.rpm') --define '_pkgverify_level none'
        diff_io_stat 'reinstall jq using rpm' "${before}"
        before=$(before)
        time dnfroot erase jq
        diff_io_stat 'remove jq' "${before}"
        before=$(before)
        time dnfroot install jq
        diff_io_stat 'reinstall jq using dnf' "${before}"
}
dd_unit() {
        before=$(before)
        time dd if=/dev/urandom of="${dest}/1" bs=1M count=1024 status=none
        diff_io_stat 'Simple dd of 1G' "${before}"
        before=$(before)
        cp -a --reflink=never "${dest}/1" "${dest}/2"
        diff_io_stat 'Simple copy of 1G' "${before}"
        before=$(before)
        cp -a --reflink=always "${dest}/1" "${dest}/3"
        diff_io_stat 'reflink copy of 1G' "${before}"
        before=$(before)
        cp -a --reflink=never "${dest}/1" "${dest}/4"
        diff_io_stat 'Another Simple copy of 1G' "${before}"
        before=$(before)
        rm -f "${dest}/1"
        diff_io_stat 'delete 1G' "${before}"
}
trap clean EXIT
case "${1:?action}" in
        *_unit)
                "${1}"
                ;;
        full|split|dd)
                systemd-run --property=IOAccounting=true --wait --pipe sh -c "$(realpath ${0}) ${1:?test}_unit"
                ;;
        --help|-h|--usage)
                usage
                ;;
        *)
                fail 'Invalid action'
                ;;
esac
