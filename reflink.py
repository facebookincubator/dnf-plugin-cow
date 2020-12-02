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

    def __init__(self, base, cli):
        super().__init__(base, cli)
        if os.path.exists(TRANSCODER):
            os.environ["LIBREPO_TRANSCODE_RPMS"] = f"{TRANSCODER} SHA256"
            # T76079288
            rpm.addMacro("_pkgverify_level", "none")
