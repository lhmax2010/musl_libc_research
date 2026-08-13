Name:           allocator-shootout-demo
Version:        1.0.0
Release:        1
Summary:        rpmalloc and optional Scudo variants for the musl allocator shootout
License:        MIT AND BSD-2-Clause AND Apache-2.0 WITH LLVM-exception
Group:          Development/Tools
Source0:        micro.c
Source1:        musl-1.2.5.tar.gz.frozen
Source2:        musl-1.2.5.sha256
Source3:        rpmalloc-1.4.5.tar.gz.frozen
Source4:        rpmalloc-1.4.5.sha256
Source5:        scudo-standalone-22.1.8.tar.gz.frozen
Source6:        scudo-standalone-22.1.8.sha256
Source7:        build-allocator-shootout.sh
Source8:        rp-init.c
BuildRequires:  bash
BuildRequires:  clang
BuildRequires:  coreutils
BuildRequires:  file
BuildRequires:  make
BuildRequires:  binutils
Requires:       musl-libc-demo = 1.0.0-2
AutoReqProv:    no

%global debug_package %{nil}
%global __strip /bin/true

%description
The S5 rpmalloc variant and an optional S6 Scudo standalone variant. S1-S4 are
not rebuilt; they remain byte-for-byte supplied by musl-libc-demo release 2.

%prep
%setup -q -T -c -n %{name}-%{version}
cp -p %{SOURCE0} micro.c
cp -p %{SOURCE1} musl-1.2.5.tar.gz
cp -p %{SOURCE2} musl-1.2.5.sha256
cp -p %{SOURCE3} rpmalloc-1.4.5.tar.gz
cp -p %{SOURCE4} rpmalloc-1.4.5.sha256
cp -p %{SOURCE5} scudo-standalone-22.1.8.tar.gz
cp -p %{SOURCE6} scudo-standalone-22.1.8.sha256
cp -p %{SOURCE7} build-allocator-shootout.sh
cp -p %{SOURCE8} rp-init.c

%build
chmod +x build-allocator-shootout.sh
OPTFLAGS='%{optflags}' ./build-allocator-shootout.sh \
    "$PWD/musl-1.2.5.tar.gz" \
    "$PWD/musl-1.2.5.sha256" \
    "$PWD/micro.c" \
    "$PWD/rpmalloc-1.4.5.tar.gz" \
    "$PWD/rpmalloc-1.4.5.sha256" \
    "$PWD/scudo-standalone-22.1.8.tar.gz" \
    "$PWD/scudo-standalone-22.1.8.sha256"

%install
rm -rf %{buildroot}
install -d %{buildroot}/opt/usr/musl-demo/bin
install -d %{buildroot}/opt/usr/musl-demo/share
install -m 0755 payload/bin/micro.musl-rp %{buildroot}/opt/usr/musl-demo/bin/
if test -x payload/bin/micro.musl-scudo; then
    install -m 0755 payload/bin/micro.musl-scudo %{buildroot}/opt/usr/musl-demo/bin/
fi
install -m 0644 payload/share/shootout-artifacts.sha256 %{buildroot}/opt/usr/musl-demo/share/
install -m 0644 payload/share/shootout-build-commands.txt %{buildroot}/opt/usr/musl-demo/share/
install -m 0644 payload/share/shootout-compiler-decision.txt %{buildroot}/opt/usr/musl-demo/share/
install -m 0644 payload/share/shootout-s6-status.txt %{buildroot}/opt/usr/musl-demo/share/
install -m 0644 payload/share/micro.musl-rp.map %{buildroot}/opt/usr/musl-demo/share/
if test -f payload/share/micro.musl-scudo.map; then
    install -m 0644 payload/share/micro.musl-scudo.map %{buildroot}/opt/usr/musl-demo/share/
fi

%files
/opt/usr/musl-demo/bin/micro.musl-*
/opt/usr/musl-demo/share/shootout-*
/opt/usr/musl-demo/share/micro.musl-*.map

%changelog
* Wed Aug 12 2026 Codex <noreply@example.invalid> - 1.0.0-1
- Add rpmalloc S5 and optional Scudo standalone S6 without rebuilding S1-S4.
