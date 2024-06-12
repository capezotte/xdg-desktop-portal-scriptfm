VALAC = valac
PREFIX = /usr/local
LIBEXECDIR = $(PREFIX)/libexec
DATADIR = $(PREFIX)/share
IFLAGS = --pkg gio-2.0

DBUS := org.freedesktop.impl.portal.desktop.scriptfm

.PHONY: all install

all: scriptfm $(DBUS).service

install: scriptfm $(DBUS).service scriptfm.portal
	install -Dm755 scriptfm $(DESTDIR)$(LIBEXECDIR)/scriptfm
	install -Dm644 $(DBUS).service $(DESTDIR)$(DATADIR)/dbus-1/services/$(DBUS).service
	install -Dm644 scriptfm.portal $(DESTDIR)$(DATADIR)/xdg-desktop-portal/portals/scriptfm.portal

$(DBUS).service:
	printf '%s\n' '[DBUS Service]' 'Name=$(DBUS)' 'Exec=$(LIBEXECDIR)/scriptfm' > $(DBUS).service

scriptfm: src/scriptfm.vala
	$(VALAC) $(IFLAGS) -o $@ $<
