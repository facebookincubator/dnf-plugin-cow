# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
%{!?dnf_lowest_compatible: %global dnf_lowest_compatible 4.4.3}
Name:    python3-dnf-plugin-cow
Version: 0.0.1
Release: 1%{?dist}
Summary: DNF plugin to enable Copy on Write
URL:     https://github.com/facebookincubator/dnf-plugin-cow
License: MIT

Source0: https://github.com/facebookincubator/dnf-plugin-cow/archive/%{version}/%{name}-%{version}.tar.gz

BuildArch: noarch
BuildRequires: python3-devel
BuildRequires: python3-dnf >= %{dnf_lowest_compatible}

Requires: python3-dnf >= %{dnf_lowest_compatible}
Requires: /usr/bin/rpm2extents
Requires: rpm-plugin-reflink

%description
Enables Copy On Write for dnf/rpm

%prep
%autosetup -n %{name}-%{version}

%build

%install
install -D -p reflink.conf %{buildroot}/%{_sysconfdir}/dnf/plugins/reflink.conf
install -D -p reflink.py %{buildroot}/%{python3_sitelib}/dnf-plugins/reflink.py

%files
%license LICENSE
%doc README.md
%config(noreplace) %{_sysconfdir}/dnf/plugins/reflink.conf
%{python3_sitelib}/dnf-plugins/reflink.py
%{python3_sitelib}/dnf-plugins/__pycache__/reflink.*

%changelog
* Tue Jan 19 2021 Matthew Almond <malmond@fb.com> 0.0.1-2
- Prefixed name with python3- to follow guidelines

* Tue Dec 23 2020 Matthew Almond <malmond@fb.com> 0.0.1-1
- Initial version
