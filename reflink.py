# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
import os

import dnf
import hawkey


TRANSCODER_PATHS = [
    "/usr/libexec/rpm/rpm2extents",
    "/usr/lib/rpm/rpm2extents",
    "/usr/bin/rpm2extents",
]

REFLINK_FILESYSTEMS = {"xfs", "btrfs"}


def _get_fs_type(path):
    path = os.path.realpath(path)
    best = ""
    fstype = ""
    with open("/proc/mounts") as f:
        for line in f:
            fields = line.split()
            mountpoint = fields[1]
            if path.startswith(mountpoint) and len(mountpoint) > len(best):
                best = mountpoint
                fstype = fields[2]
    return fstype


def find_transcoder():
    for path in TRANSCODER_PATHS:
        if os.path.exists(path):
            return path
    return None


class DnfReflink(dnf.Plugin):

    name = "reflink"

    def config(self):
        # deny list
        cp = self.read_config(self.base.conf)
        denylist = (cp.has_section('main') and cp.has_option('main', 'denylist')
                       and cp.get('main', 'denylist'))
        if denylist:
            os.environ["LIBREPO_TRANSCODE_RPMS_DENYLIST"] = denylist

    def resolved(self):
        if self.base.conf.downloadonly:
            return
        # yumdownloader uses the DownloadCommand plugin. We'll assume any
        # command that starts with "Download" wants the un-transcoded package
        if self.cli.command.__class__.__name__.lower().startswith("download"):
            return

        # Skip transcoding if the cache filesystem doesn't support reflinks
        if _get_fs_type(self.base.conf.cachedir) not in REFLINK_FILESYSTEMS:
            return

        transcoder = find_transcoder()
        if not transcoder:
            return

        # Detect the checksum algorithms from the repo metadata
        algos = set()
        for pkg in self.base.transaction.install_set:
            chksum = pkg.chksum
            if chksum:
                algo_name = hawkey.chksum_name(chksum[0])
                if algo_name:
                    algos.add(algo_name.upper())

        if not algos:
            return

        os.environ["LIBREPO_TRANSCODE_RPMS"] = transcoder + " " + " ".join(sorted(algos))
