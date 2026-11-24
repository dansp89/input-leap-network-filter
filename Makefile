# Convenience targets for developers. End users run: bash install.sh
QT ?= 6
BUILD ?= build
VERSION := $(shell cat VERSION)
DIST := dist

.PHONY: build test sanitize lint bench clean install uninstall dist

build:
	cmake -S . -B $(BUILD) -DILNF_QT_MAJOR=$(QT) -DCMAKE_BUILD_TYPE=Release
	cmake --build $(BUILD) -j

test: build
	cd $(BUILD) && ctest --output-on-failure

sanitize:
	cmake -S . -B $(BUILD)-asan -DILNF_QT_MAJOR=$(QT) -DILNF_SANITIZE=ON -DCMAKE_BUILD_TYPE=Debug
	cmake --build $(BUILD)-asan -j
	cd $(BUILD)-asan && ctest -R unit --output-on-failure

lint:
	shellcheck -x bin/input-leap-network-filter scripts/lib/*.sh tests/integration/*.sh install.sh uninstall.sh

bench: build
	$(BUILD)/ilnf-bench

install:
	bash install.sh

uninstall:
	bash uninstall.sh

# Release archive + checksums, as expected by `input-leap-network-filter update`.
dist:
	mkdir -p $(DIST)
	git archive --format=tar.gz --prefix=input-leap-network-filter-$(VERSION)/ \
		-o $(DIST)/input-leap-network-filter-$(VERSION).tar.gz HEAD
	cd $(DIST) && sha256sum input-leap-network-filter-$(VERSION).tar.gz > SHA256SUMS

clean:
	rm -rf $(BUILD) $(BUILD)-asan build-qt5 build-qt6 $(DIST)
