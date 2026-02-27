# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
import os

import dnf
import rpm

TRANSCODER_PATHS = [
    "/usr/libexec/rpm/rpm2extents",
    "/usr/lib/rpm/rpm2extents",
    "/usr/bin/rpm2extents",
]


def find_transcoder():
    for path in TRANSCODER_PATHS:
        if os.path.exists(path):
            return path
    return None


class DnfReflink(dnf.Plugin):

    name = "reflink"

    def config(self):
        if self.base.conf.downloadonly:
            return
        # yumdownloader uses the DownloadCommand plugin. We'll assume any
        # command that starts with "Download" wants the un-transcoded package
        if self.cli.command.__class__.__name__.lower().startswith("download"):
            return
        transcoder = find_transcoder()
        if transcoder:
            os.environ["LIBREPO_TRANSCODE_RPMS"] = f"{transcoder} SHA256"

        # deny list
        cp = self.read_config(self.base.conf)
        denylist = (cp.has_section('main') and cp.has_option('main', 'denylist')
                       and cp.get('main', 'denylist'))
        if denylist:
            os.environ["LIBREPO_TRANSCODE_RPMS_DENYLIST"] = denylist
