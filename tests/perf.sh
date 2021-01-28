#!/bin/sh

set -euo pipefail

dest=$(mktemp -d /var/tmp/dnfcowperf.XXXXXX)
packages='bash glibc-langpack-en jq'

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
diff_io_stat() {
        after=$(io_stat)
        echo -n "${1:?message} "
        # so sorry about awk
        echo -e "${2:?before}\n${after}" | awk '{
                devices[$1] = 1
                for (i=2; i<=NF; i++) {
                        split($i, kv, "=")
                        k=kv[1]
                        v=kv[2]
                        keys[k] = 1
                        data[$1, k, FNR] = v
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
        before=$(io_stat)
        time dnfroot install ${packages}
        diff_io_stat "${before}"
}
split_unit() {
        dnfroot makecache
        before=$(io_stat)
        time dnfroot install --downloadonly ${packages}
        diff_io_stat 'Download usage:' "${before}"
        before=$(io_stat)
        time dnfroot --setopt=keepcache=True install ${packages}
        diff_io_stat 'Install usage:' "${before}"
        before=$(io_stat)
        time rpm --root "${dest}" -e jq
        diff_io_stat 'remove jq using rpm:' "${before}"
        before=$(io_stat)
        time rpm --root "${dest}" -Uhv $(find "${dest}" -name 'jq*.rpm') --define '_pkgverify_level none'
        diff_io_stat 'reinstall jq using rpm:' "${before}"
        before=$(io_stat)
        time dnfroot --setopt=keepcache=True erase jq
        diff_io_stat 'remove jq:' "${before}"
        before=$(io_stat)
        time dnfroot --setopt=keepcache=True install jq
        diff_io_stat 'reinstall jq using dnf:' "${before}"
}
dd_unit() {
        before=$(io_stat)
        time dd if=/dev/urandom of="${dest}/1" bs=1M count=1024
        diff_io_stat 'Simple dd of 1G:' "${before}"
        before=$(io_stat)
        cp -a --reflink=never "${dest}/1" "${dest}/2"
        diff_io_stat 'Simple copy of 1G:' "${before}"
        before=$(io_stat)
        cp -a --reflink=always "${dest}/1" "${dest}/3"
        diff_io_stat 'reflink copy of 1G:' "${before}"
        before=$(io_stat)
        cp -a --reflink=never "${dest}/1" "${dest}/4"
        diff_io_stat 'Another Simple copy of 1G:' "${before}"
        before=$(io_stat)
        rm -f "${dest}/1"
        diff_io_stat 'delete 1G:' "${before}"
}
trap clean EXIT
case "${1:?action}" in
        *_unit)
                "${1}"
                ;;
        full|split|dd)
                systemd-run --property=IOAccounting=true --wait --pipe sh -c "$(realpath ${0}) ${1:?test}_unit"
                ;;
        *)
                fail 'Invalid action'
                ;;
esac
