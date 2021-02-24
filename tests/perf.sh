#!/bin/sh

set -euo pipefail

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
        btrace time dnfroot --cacheonly install ${packages}
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
btrace() {
	cg=$(cgroup_path)
	# this is pretty horrible. We want to wrap a command with bpftrace, but
	# bpftrace -c doesn't handle spaces in parameters/quoting properly. Nor
	# can it handle a shell script. It wants an ELF binary as ${1} for -c.
	# the workaround is to make a temp script and tell it to run that.
	script="$(mktemp "${dest}/bpftracecmd.XXXXXX")"
	cat <<EOF > "${script}"
#!/bin/sh
. ${0} script
${*}
EOF
	# still need to use /bin/sh in the command as it assumes elf, it can't do
	# shell scripts.
	cat <<EOF | BPFTRACE_STRLEN=90 bpftrace - -c "/bin/sh ${script}"
#include <fcntl.h>
#include <limits.h>

/* remember our own pid, so that we can filter it out from the handlers */
BEGIN { @mypid = pid }

tracepoint:syscalls:sys_enter_openat* /pid != @mypid && cgroup == cgroupid("${cg}")/ {
     // printf("%s(%d) openat: %s\\n", comm, pid, str(args->filename));
     @pidfile[tid] = str(args->filename, 256);
}

tracepoint:syscalls:sys_exit_openat* /pid != @mypid && cgroup == cgroupid("${cg}")/ {
    if (args->ret > 0) {
        \$f = @pidfile[tid];
        // printf("%s(%d) openat: %s = %d\\n", comm, pid, \$f, args->ret);
        @tidfdpath[tid, args->ret] = \$f;
    }
    delete(@pidfile[tid]);
}

tracepoint:syscalls:sys_enter_close /pid != @mypid && cgroup == cgroupid("${cg}")/ {
     \$f = @tidfdpath[tid, args->fd];
     // printf("%s(%d) close: %d was %s\\n", comm, pid, args->fd, \$f);
     delete(@tidfdpath[tid, args->fd]);
}

tracepoint:syscalls:sys_enter_write /pid != @mypid && cgroup == cgroupid("${cg}")/ {
     @tidfd[tid] = args->fd;
}

tracepoint:syscalls:sys_exit_write /pid != @mypid && cgroup == cgroupid("${cg}")/ {
     \$fd = @tidfd[tid];
     if (\$fd > 2 && args->ret > 0) {
         \$f = @tidfdpath[tid, \$fd];
         if (\$f == "") {
             //printf("anonymous pid = %d, tid = %d, %d = %d\n", pid, tid, \$fd, args->ret);
         } else {
         //if (strncmp("${dest}", \$f, ${#dest}) == 0) {
             @writes[\$f] = sum(args->ret);
             // printf("%s(%d) write: %d(%s) was %d\\n", comm, pid, \$fd, \$f, \$count);
         }
     }
     delete(@tidfd[tid]);
}


END { clear(@mypid) }
EOF
	rm -f "${script}"
}
dd_unit() {
	tool="$(mktemp "${dest}/tool.XXXXXX")"
	gcc -o "${tool}" "$(dirname "${0}")/middle-reflink.c"
        before=$(before)
        time dd if=/dev/urandom of="${dest}/1" bs=1M count=1024 status=none
        diff_io_stat 'Simple dd of 1G' "${before}"
        before=$(before)
	btrace "${tool}" "${dest}/1" "${dest}/2" 1000 1000 10000 100000 $(for i in {1..80} ; do echo 10000000; done) $(for i in {1..5} ; do echo 40000000 ; done)
        diff_io_stat 'Magical reflink' "${before}"
}
case "${1:?action}" in
        *_unit)
                "${1}"
                ;;
        full|split|dd)
		dest=$(mktemp -d /root/m/dnfcowperf.XXXXXX)
		trap clean EXIT
		systemd-run --property=IOAccounting=true --property=Environment=dest="${dest}" --wait --pipe sh -c "$(realpath ${0}) ${1:?test}_unit"
                ;;
	script)
		# avoid failing when explicitly sourced.
		;;
        --help|-h|--usage)
                usage
                ;;
        *)
                fail 'Invalid action'
                ;;
esac
