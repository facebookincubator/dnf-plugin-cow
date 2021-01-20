# dnf-plugin-cow

Plugin to enable Copy on Write mechanics for RPM within `dnf`. This code, combined with changes to `rpm` and `librepo` are the technical basis for https://fedoraproject.org/wiki/Changes/RPMCoW

# Installation

```
dnf install python3-dnf-plugin-cow
```

# Requirements

* `rpm` with cow/transcoding support (see https://github.com/rpm-software-management/rpm/pull/1470)
* `rpm-plugin-reflink` installed to handle install mechanics for extent based rpms
* `librepo` with transcoding support (see https://github.com/rpm-software-management/librepo/pull/222)
* Support for reflinking between `dnf` cache (typically `/var/cache/dnf`) and the paths included in RPMs. In the most common case this means a root filesystem with btrfs.

## Background

The bulk of the code is in the `rpm` and `librepo` packages. This code turns "transcoding" on by setting an environment variable telling `librepo` to use `/usr/bin/rpm2extents` in a pipeline to convert normal RPMs to extent based ones on disk.

## License
dnf-plugin-cow is MIT licensed, as found in the LICENSE file.
