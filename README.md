# dnf-plugin-cow

A `libdnf5` plugin that enables RPM Copy-on-Write (CoW) / reflink mechanics when using `dnf`.

This repository contains the `reflink` plugin module. The plugin enables RPM “transcoding” (converting downloaded RPMs into extent-based RPMs on disk) by setting environment variables that instruct `librepo` to use `rpm2extents`. Together with changes to `rpm` and `librepo`, this is part of the technical basis for:
https://fedoraproject.org/wiki/Changes/RPMCoW

## How it works (high level)

When `dnf` resolves a transaction, the plugin may set:

- `LIBREPO_TRANSCODE_RPMS` to a value like:  
  `</path/to/rpm2extents> <CHECKSUM_ALGO> [<CHECKSUM_ALGO> ...]`

Optionally, it can also set:

- `LIBREPO_TRANSCODE_RPMS_DENYLIST` (a comma-separated package list)

The plugin intentionally does nothing when:

- `dnf` is running with `downloadonly=1`
- the DNF cache directory is **not** on a reflink-capable filesystem
- `rpm2extents` is not found on the system

## Installation (from packages)

If your distro provides a packaged build, install it via `dnf`:

```bash
sudo dnf install python3-dnf-plugin-cow
```

> Note: packaging names can differ across distributions. If you are building from source, see the next section.

## Build and install from source

This repo builds a `libdnf5` plugin module using CMake.

### Build prerequisites

You’ll need at least:

- `cmake` (>= 3.16)
- a C++20 compiler
- `pkg-config`
- `libdnf5` development files (often packaged as `libdnf5-devel`)

Example (Fedora):

```bash
sudo dnf install -y cmake gcc-c++ pkgconf-pkg-config libdnf5-devel
```

### Build

```bash
mkdir -p build
cd build
cmake ..
make -j"$(nproc)"
```

### Install

```bash
sudo make install
```

Install locations are determined from `libdnf5`’s configured plugin directory and typically include:

- the plugin module: `reflink` (installed into the `libdnf5` plugin directory)
- the config file: `/etc/dnf/libdnf5-plugins/reflink.conf`

## Configuration

The plugin installs a config file named:

- `/etc/dnf/libdnf5-plugins/reflink.conf`

Default content:

- `enabled=1` enables the plugin
- `denylist=...` (optional) provides a comma-separated list of package names that should not be transcoded

Example:

```ini
[main]
enabled=1
denylist=kernel,kernel-core
```

## Requirements / when it activates

In order to do anything, you typically need:

- `rpm` with CoW/transcoding support  
  https://github.com/rpm-software-management/rpm/pull/1470
- `librepo` with transcoding support  
  https://github.com/rpm-software-management/librepo/pull/222
- `rpm2extents` available on the host. The plugin checks common paths such as:
  - `/usr/libexec/rpm/rpm2extents`
  - `/usr/lib/rpm/rpm2extents`
  - `/usr/bin/rpm2extents`
- reflink support between the DNF cache (often `/var/cache/dnf`) and target paths. The plugin currently enables transcoding only when the cache directory is on a reflink-capable filesystem (notably **btrfs** or **xfs**).

## Basic verification / troubleshooting

1. Check whether `rpm2extents` exists:

```bash
ls -l /usr/libexec/rpm/rpm2extents /usr/lib/rpm/rpm2extents /usr/bin/rpm2extents 2>/dev/null || true
```

2. Check the filesystem type of the DNF cache directory (example uses `/var/cache/dnf`):

```bash
stat -f -c %T /var/cache/dnf
```

If it’s not `btrfs` or `xfs`, the plugin will skip enabling transcoding.

3. Confirm the plugin config is present and enabled:

```bash
sudo cat /etc/dnf/libdnf5-plugins/reflink.conf
```

## License

dnf-plugin-cow is MIT licensed, as found in the LICENSE file.