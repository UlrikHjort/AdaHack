.PHONY: all clean run install uninstall

# Toolchain config generated locally: pins Ada to GNAT and C to GCC so that
# gprbuild does not auto-select another C compiler (e.g. clang) from PATH.
CONFIG := obj/default.cgpr

# Install locations - override on the command line, e.g.
#   make install PREFIX=$HOME/.local BINDIR=$HOME/.local/bin
PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/games
MANDIR  ?= $(PREFIX)/share/man
INSTALL ?= install

all: $(CONFIG)
	gprbuild --config=$(CONFIG) -P adahack.gpr

$(CONFIG):
	mkdir -p obj
	gprconfig --batch --config=Ada --config=C,,,,GCC -o $(CONFIG)

run: all
	./adahack

install: all
	$(INSTALL) -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(MANDIR)/man6
	$(INSTALL) -m 755 adahack $(DESTDIR)$(BINDIR)/adahack
	$(INSTALL) -m 644 doc/adahack.6 $(DESTDIR)$(MANDIR)/man6/adahack.6

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/adahack $(DESTDIR)$(MANDIR)/man6/adahack.6

clean:
	rm -rf obj adahack
