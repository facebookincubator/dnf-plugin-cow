%{!?dnf_lowest_compatible: %global dnf_lowest_compatible 4.2.23}
Name:    dnf-plugin-cow
Version: 0.0.2
Release: 1%{?dist}
Summary: DNF plugin to enable Copy on Write in RPM
URL:     https://github.com/facebookincubator/dnf-plugin-cow
License: MIT

Source0: %{url}/archive/%{version}/%{name}-%{version}.tar.gz

BuildArch: noarch
BuildRequires: python3-devel
BuildRequires: python3-dnf >= %{dnf_lowest_compatible}

%description
Source package for DNF plugin to enable Copy on Write in DNF and RPM.

%package -n python3-%{name}
Summary: DNF plugin to enable Copy on Write in RPM - Python3
Requires: python3-dnf >= %{dnf_lowest_compatible}
# Using recommends to allow the plugin to be installed even if the requirements
# are not packaged/available yet.
Recommends: /usr/bin/rpm2extents
Recommends: rpm-plugin-reflink

%description -n python3-%{name}
Installing this package enables a DNF plugin which changes the behaviour of
librepo. Instead of downloading rpm files directly into cache before
installation they will be "transcoded" into "extent based" rpms which contain
all the constituent files of the rpm already uncompressed. This package
depends on a version of rpm which includes /usr/bin/rpm2extents and the
sub-package rpm-plugin-reflink which understands these "extent based" rpms
and can install files without copying the underlying data.

This package broadly assumes the root filesystem supports copy on write /
reflink'ing. Today this means btrfs or xfs.

%prep
%autosetup -n %{name}-%{version}

%build

%install
install -D -p reflink.conf %{buildroot}%{_sysconfdir}/dnf/plugins/reflink.conf
install -D -p reflink.py %{buildroot}%{python3_sitelib}/dnf-plugins/reflink.py

%files -n python3-%{name}
%license LICENSE
%doc README.md
%config(noreplace) %{_sysconfdir}/dnf/plugins/reflink.conf
%{python3_sitelib}/dnf-plugins/reflink.py
%{python3_sitelib}/dnf-plugins/__pycache__/reflink.*

%changelog
* Fri Jan 22 2021 Matthew Almond <malmond@fb.com> 0.0.2-1
- Minor version bump.

* Wed Jan 20 2021 Matthew Almond <malmond@fb.com> 0.0.1-3
- Separated package into top level "dnf-plugin-cow" concept with implementation
  "python3-dnf-plugin-cow". This allows for "libdnf-plugin-cow" later without
  renaming this package.

* Tue Jan 19 2021 Matthew Almond <malmond@fb.com> 0.0.1-2
- Prefixed name with python3- to follow guidelines

* Wed Dec 23 2020 Matthew Almond <malmond@fb.com> 0.0.1-1
- Initial version
