VALAC ?= valac
PREFIX ?= /usr/local
LIBEXECDIR ?= libexec
DATADIR ?= share
IFLAGS = --pkg gio-2.0
DBUS := org.freedesktop.impl.portal.desktop.scriptfm

.PHONY: all install

all: scriptfm $(DBUS).service

install: scriptfm $(DBUS).service scriptfm.portal
	install -Dm755 scriptfm $(DESTDIR)$(PREFIX)/$(LIBEXECDIR)/scriptfm
	install -Dm644 $(DBUS).service $(DESTDIR)$(PREFIX)/$(DATADIR)/dbus-1/services/$(DBUS).service
	install -Dm644 scriptfm.portal $(DESTDIR)$(PREFIX)/$(DATADIR)/xdg-desktop-portal/portals/scriptfm.portal

$(DBUS).service:
	printf '%s\n' '[DBUS Service]' 'Name=$(DBUS)' 'Exec=$(PREFIX)/$(LIBEXECDIR)/scriptfm' > $(DBUS).service

scriptfm: src/scriptfm.vala
	$(VALAC) $(IFLAGS) -o $@ $<
