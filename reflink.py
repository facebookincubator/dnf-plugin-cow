# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
import os

import dnf
import rpm

TRANSCODER = "/usr/bin/rpm2extents"


class DnfReflink(dnf.Plugin):

    name = "reflink"

    def config(self):
        if self.base.conf.downloadonly:
            return
        # yumdownloader uses the DownloadCommand plugin. We'll assume any
        # command that starts with "Download" wants the un-transcoded package
        if self.cli.command.__class__.__name__.lower().startswith("download"):
            return
        if os.path.exists(TRANSCODER):
            os.environ["LIBREPO_TRANSCODE_RPMS"] = f"{TRANSCODER} SHA256"
            # T76079288
            rpm.addMacro("_pkgverify_level", "none")
