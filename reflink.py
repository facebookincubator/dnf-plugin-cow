# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
import ctypes
import ctypes.util
import os

import dnf
import hawkey


TRANSCODER_PATHS = [
    "/usr/libexec/rpm/rpm2extents",
    "/usr/lib/rpm/rpm2extents",
    "/usr/bin/rpm2extents",
]

# Filesystem magic numbers for filesystems supporting reflinks
XFS_SUPER_MAGIC = 0x58465342
BTRFS_SUPER_MAGIC = 0x9123683E

REFLINK_FILESYSTEMS = {XFS_SUPER_MAGIC, BTRFS_SUPER_MAGIC}


class _statfs(ctypes.Structure):
    _fields_ = [
        ("f_type", ctypes.c_long),
        ("f_bsize", ctypes.c_long),
        ("f_blocks", ctypes.c_ulong),
        ("f_bfree", ctypes.c_ulong),
        ("f_bavail", ctypes.c_ulong),
        ("f_files", ctypes.c_ulong),
        ("f_ffree", ctypes.c_ulong),
        ("f_fsid", ctypes.c_long * 2),
        ("f_namelen", ctypes.c_long),
        ("f_frsize", ctypes.c_long),
        ("f_flags", ctypes.c_long),
        ("f_spare", ctypes.c_long * 4),
    ]


_libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)


def _get_fs_type(path):
    buf = _statfs()
    if _libc.statfs(path.encode(), ctypes.byref(buf)) != 0:
        return 0
    return buf.f_type


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
