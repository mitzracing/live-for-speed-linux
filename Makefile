PREFIX ?= /usr
DESTDIR ?=

BINDIR := $(DESTDIR)$(PREFIX)/bin
LIBEXECDIR := $(DESTDIR)$(PREFIX)/lib/lfs-linux
DATADIR := $(DESTDIR)$(PREFIX)/share
MANDIR := $(DATADIR)/man

.PHONY: install test package-check release-archive deb deb-check

install:
	install -Dm755 bin/lfs-linux $(BINDIR)/lfs-linux
	install -Dm755 bin/lfs-linux-desktop $(BINDIR)/lfs-linux-desktop
	install -Dm755 libexec/lfs-linux-core $(LIBEXECDIR)/lfs-linux-core
	install -Dm644 share/lfs-linux/release.env $(DATADIR)/lfs-linux/release.env
	install -Dm644 share/lfs-linux/lfs-0.8C20-stock.manifest $(DATADIR)/lfs-linux/lfs-0.8C20-stock.manifest
	install -Dm644 share/lfs-linux/lfs-0.8C20-seed.manifest $(DATADIR)/lfs-linux/lfs-0.8C20-seed.manifest
	install -Dm644 share/lfs-linux/lfs-0.8C20-nested.manifest $(DATADIR)/lfs-linux/lfs-0.8C20-nested.manifest
	install -Dm644 share/lfs-linux/lfs-0.8C19-stock.manifest $(DATADIR)/lfs-linux/lfs-0.8C19-stock.manifest
	install -Dm644 share/lfs-linux/lfs-0.8C19-seed.manifest $(DATADIR)/lfs-linux/lfs-0.8C19-seed.manifest
	install -Dm644 share/lfs-linux/wine-11.15-1-runtime.manifest $(DATADIR)/lfs-linux/wine-11.15-1-runtime.manifest
	install -Dm644 share/applications/io.github.mitzracing.live_for_speed_linux.desktop $(DATADIR)/applications/io.github.mitzracing.live_for_speed_linux.desktop
	install -Dm644 share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml $(DATADIR)/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml
	install -Dm644 share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg $(DATADIR)/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg
	install -Dm644 LICENSE $(DATADIR)/licenses/live-for-speed-linux/LICENSE
	install -Dm644 docs/LEGAL.md $(DATADIR)/doc/live-for-speed-linux/LEGAL.md
	install -Dm644 docs/TROUBLESHOOTING.md $(DATADIR)/doc/live-for-speed-linux/TROUBLESHOOTING.md
	install -Dm644 docs/ARCHITECTURE.md $(DATADIR)/doc/live-for-speed-linux/ARCHITECTURE.md
	install -Dm644 docs/MAINTENANCE.md $(DATADIR)/doc/live-for-speed-linux/MAINTENANCE.md
	install -Dm644 docs/lfs-linux.1 $(MANDIR)/man1/lfs-linux.1
	ln -sfn lfs-linux.1 $(MANDIR)/man1/lfs-linux-desktop.1

test:
	./tests/test-public-static.sh
	./tests/test-public-core.sh
	./tests/test-upgrade.sh
	python3 tests/test-support-static.py
	python3 tests/test-triage-feedback.py
	python3 tests/test-upstream-drift.py
	./tests/test-website.sh
	./tests/test-release-archive.sh

package-check:
	rm -rf artifacts/pkgroot
	$(MAKE) DESTDIR=$(CURDIR)/artifacts/pkgroot PREFIX=/usr install
	./tests/test-package-boundary.sh artifacts/pkgroot

release-archive:
	./scripts/build-release-archive.sh

deb:
	./packaging/debian/build-deb.sh

deb-check:
	./tests/test-debian-package.sh
