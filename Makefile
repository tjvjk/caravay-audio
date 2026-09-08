PREFIX ?= $(HOME)/.local
VERSION := 0.1.0
ARCH := $(shell uname -m)
ARCHIVE := caravay-audio-$(VERSION)-macos-$(ARCH)

.PHONY: build install check dist
build:
	swift build -c release -Xswiftc -warnings-as-errors

install: build
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 755 .build/release/caravay-audio "$(DESTDIR)$(PREFIX)/bin/caravay-audio"

check:
	xcrun swift-format lint --strict --recursive Sources Tests Package.swift
	sh scripts/test.sh

dist: build
	mkdir -p dist/$(ARCHIVE)
	install -m 755 .build/release/caravay-audio dist/$(ARCHIVE)/caravay-audio
	cp README.md PROTOCOL.md CHANGELOG.md ORIGIN.md dist/$(ARCHIVE)/
	if test -f LICENSE; then cp LICENSE dist/$(ARCHIVE)/; fi
	tar -czf dist/$(ARCHIVE).tar.gz -C dist $(ARCHIVE)
	cd dist && shasum -a 256 $(ARCHIVE).tar.gz > $(ARCHIVE).tar.gz.sha256
