Name:           ffmpeg-musl-demo
Version:        8.0.1
Release:        1
Summary:        Isolated Tizen ffmpeg software-decode comparison
License:        LGPL-2.1+ AND MIT AND BSD-2-Clause AND BSD-3-Clause
Group:          Development/Tools
# Frozen suffixes prevent GBS source-export archive substitution.
Source0:        ffmpeg-tizen-src.tar.gz.frozen
Source1:        ffmpeg-tizen-src.sha256
Source2:        ffmpeg-tizen.commit
Source3:        musl-1.2.5.tar.gz.frozen
Source4:        musl-1.2.5.sha256
Source5:        mimalloc-2.1.7.tar.gz.frozen
Source6:        mimalloc-2.1.7.sha256
Source7:        timer.c
Source8:        build-ffmpeg-demo.sh
BuildRequires:  bash
BuildRequires:  binutils
BuildRequires:  clang
BuildRequires:  coreutils
BuildRequires:  diffutils
BuildRequires:  file
BuildRequires:  findutils
BuildRequires:  make
AutoReqProv:    no

%global debug_package %{nil}
%global __debug_install_post %{nil}
%global __strip /bin/true

%description
Three isolated ffmpeg 8.0.1 CLI variants built from the frozen Tizen source
tree: glibc dynamic, musl static with mallocng, and musl static with mimalloc.
Only the native H.264 software decoder and the minimum local-file decode path
are enabled. All files are installed below /opt/usr/ffmpeg-demo.

%prep
%setup -q -T -c -n %{name}-%{version}
cp -p %{SOURCE0} ffmpeg-tizen-src.tar.gz
cp -p %{SOURCE1} ffmpeg-tizen-src.sha256
cp -p %{SOURCE2} ffmpeg-tizen.commit
cp -p %{SOURCE3} musl-1.2.5.tar.gz
cp -p %{SOURCE4} musl-1.2.5.sha256
cp -p %{SOURCE5} mimalloc-2.1.7.tar.gz
cp -p %{SOURCE6} mimalloc-2.1.7.sha256
cp -p %{SOURCE7} timer.c
cp -p %{SOURCE8} build-ffmpeg-demo.sh

%build
chmod +x build-ffmpeg-demo.sh
OPTFLAGS='%{optflags}' ./build-ffmpeg-demo.sh \
    "$PWD/ffmpeg-tizen-src.tar.gz" \
    "$PWD/ffmpeg-tizen-src.sha256" \
    "$PWD/ffmpeg-tizen.commit" \
    "$PWD/musl-1.2.5.tar.gz" \
    "$PWD/musl-1.2.5.sha256" \
    "$PWD/mimalloc-2.1.7.tar.gz" \
    "$PWD/mimalloc-2.1.7.sha256" \
    "$PWD/timer.c"

%install
rm -rf %{buildroot}
install -d %{buildroot}/opt/usr/ffmpeg-demo/bin
install -d %{buildroot}/opt/usr/ffmpeg-demo/share
install -m 0755 payload/bin/* %{buildroot}/opt/usr/ffmpeg-demo/bin/
install -m 0644 payload/share/* %{buildroot}/opt/usr/ffmpeg-demo/share/

%files
/opt/usr/ffmpeg-demo/bin/*
/opt/usr/ffmpeg-demo/share/*

%changelog
* Tue Aug 11 2026 Codex <noreply@example.invalid> - 8.0.1-1
- Initial frozen Tizen ffmpeg software-decode island package.
