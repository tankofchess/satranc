%global __strip /bin/true
%global debug_package %{nil}
%global _build_id_links none

Name:           satranj
Version:        1.0
Release:        1%{?dist}
Summary:        Tam kurallı satranç oyunu ve analiz aracı
License:        Freeware
URL:            https://github.com/
Source0:        %{name}-%{version}.tar.gz

ExclusiveArch:  x86_64

%description
Lazarus/FPC ile yazılmış masaüstü satranç uygulaması.
İnsan-insan ve insan-bilgisayar oynama, analiz, ilk beş hamle önerisi,
pozisyon düzenleyici ve ayarlanabilir arama derinliği (1-6) içerir.
Yedi kesin oyun sonu tablosu gömülüdür.

%prep
%setup -q

%build
# Önceden derlenmiş x86-64 ikilisi kullanılır.

%install
mkdir -p %{buildroot}%{_bindir} \
         %{buildroot}%{_datadir}/applications \
         %{buildroot}%{_datadir}/icons/hicolor/scalable/apps \
         %{buildroot}%{_datadir}/doc/%{name}
install -m 0755 satranj %{buildroot}%{_bindir}/satranj
install -m 0644 satranj.desktop %{buildroot}%{_datadir}/applications/satranj.desktop
install -m 0644 satranj.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/satranj.svg
install -m 0644 README.md %{buildroot}%{_datadir}/doc/%{name}/README.md

%post
if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database /usr/share/applications >/dev/null 2>&1 || :
fi
if [ -x /usr/bin/update-icon-caches ]; then
  /usr/bin/update-icon-caches /usr/share/icons/hicolor >/dev/null 2>&1 || :
elif [ -x /usr/bin/gtk-update-icon-cache ]; then
  /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || :
fi

%postun
if [ "$1" -eq 0 ]; then
  if [ -x /usr/bin/update-desktop-database ]; then
    /usr/bin/update-desktop-database /usr/share/applications >/dev/null 2>&1 || :
  fi
  if [ -x /usr/bin/update-icon-caches ]; then
    /usr/bin/update-icon-caches /usr/share/icons/hicolor >/dev/null 2>&1 || :
  elif [ -x /usr/bin/gtk-update-icon-cache ]; then
    /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || :
  fi
fi

%files
%{_bindir}/satranj
%{_datadir}/applications/satranj.desktop
%{_datadir}/icons/hicolor/scalable/apps/satranj.svg
%{_datadir}/doc/%{name}/README.md

%changelog
* Sat Nov 21 2026 Satranç Geliştirici <satranc@example.com> - 1.0-1
- İlk RPM paketi; K+R+A tablosu ve menü/ikon düzeltmeleri.
