Name:           musl-libc-demo
Version:        1.0.0
Release:        2
Summary:        GBS-built musl versus glibc comparison probes
License:        MIT AND BSD-2-Clause AND BSD-3-Clause
Group:          Development/Tools
Source0:        micro.c
# The .frozen suffix avoids gbs export's gbp orig archive heuristic and prevents
# a git-tree-generated archive from clobbering the official source; prep restores the canonical name.
Source1:        musl-1.2.5.tar.gz.frozen
Source2:        timer.c
Source3:        musl-1.2.5.sha256
Source4:        build-demo.sh
# The .frozen suffix avoids the same export archive heuristic as Source1.
Source5:        mimalloc-2.1.7.tar.gz.frozen
Source6:        mimalloc-2.1.7.sha256
BuildRequires:  bash
BuildRequires:  clang
BuildRequires:  coreutils
BuildRequires:  file
BuildRequires:  make
BuildRequires:  binutils
AutoReqProv:    no

%global debug_package %{nil}
%global __strip /bin/true

%description
Four C probe variants built inside one Tizen GBS chroot with the platform
clang: glibc dynamic, musl static, musl dynamic with a package-private loader,
and musl static with mimalloc. The package is isolated below
/opt/usr/musl-demo.

%prep
%setup -q -T -c -n %{name}-%{version}
cp -p %{SOURCE0} micro.c
cp -p %{SOURCE1} musl-1.2.5.tar.gz
cp -p %{SOURCE2} timer.c
cp -p %{SOURCE3} musl-1.2.5.sha256
cp -p %{SOURCE4} build-demo.sh
cp -p %{SOURCE5} mimalloc-2.1.7.tar.gz
cp -p %{SOURCE6} mimalloc-2.1.7.sha256

%build
chmod +x build-demo.sh
OPTFLAGS='%{optflags}' ./build-demo.sh \
    "$PWD/musl-1.2.5.tar.gz" \
    "$PWD/musl-1.2.5.sha256" \
    "$PWD/micro.c" \
    "$PWD/timer.c" \
    "$PWD/mimalloc-2.1.7.tar.gz" \
    "$PWD/mimalloc-2.1.7.sha256"

%install
rm -rf %{buildroot}
install -d %{buildroot}/opt/usr/musl-demo/bin
install -d %{buildroot}/opt/usr/musl-demo/lib
install -d %{buildroot}/opt/usr/musl-demo/share
install -m 0755 payload/bin/micro.glibc-dyn %{buildroot}/opt/usr/musl-demo/bin/
install -m 0755 payload/bin/micro.musl-static %{buildroot}/opt/usr/musl-demo/bin/
install -m 0755 payload/bin/micro.musl-dyn %{buildroot}/opt/usr/musl-demo/bin/
install -m 0755 payload/bin/micro.musl-mi %{buildroot}/opt/usr/musl-demo/bin/
install -m 0755 payload/bin/timer %{buildroot}/opt/usr/musl-demo/bin/
install -m 0755 payload/lib/libc.so %{buildroot}/opt/usr/musl-demo/lib/libc.so
ln -s libc.so %{buildroot}/opt/usr/musl-demo/lib/ld-musl-arm.so.1
install -m 0644 payload/share/build-commands.txt %{buildroot}/opt/usr/musl-demo/share/
install -m 0644 payload/share/artifacts.sha256 %{buildroot}/opt/usr/musl-demo/share/
install -m 0644 payload/share/sizes-prestrip.txt %{buildroot}/opt/usr/musl-demo/share/
install -m 0644 payload/share/compiler-decision.txt %{buildroot}/opt/usr/musl-demo/share/
install -m 0644 payload/share/micro.musl-mi.map %{buildroot}/opt/usr/musl-demo/share/

%files
/opt/usr/musl-demo/bin/micro.glibc-dyn
/opt/usr/musl-demo/bin/micro.musl-static
/opt/usr/musl-demo/bin/micro.musl-dyn
/opt/usr/musl-demo/bin/micro.musl-mi
/opt/usr/musl-demo/bin/timer
/opt/usr/musl-demo/lib/libc.so
/opt/usr/musl-demo/lib/ld-musl-arm.so.1
/opt/usr/musl-demo/share/build-commands.txt
/opt/usr/musl-demo/share/artifacts.sha256
/opt/usr/musl-demo/share/sizes-prestrip.txt
/opt/usr/musl-demo/share/compiler-decision.txt
/opt/usr/musl-demo/share/micro.musl-mi.map

%changelog
* Thu Aug 06 2026 Codex <noreply@example.invalid> - 1.0.0-2
- Add the musl-static plus mimalloc comparison variant.

* Thu Aug 06 2026 Codex <noreply@example.invalid> - 1.0.0-1
- Initial reproducible GBS musl/glibc comparison demo.
