export NIGHTLY ?= 0

export BUILD_STANDALONE ?= 0

ifeq ($(NIGHTLY), 1)
export COMMIT_HASH = $(shell git rev-parse HEAD)
endif

ifeq ($(BUILD_STANDALONE), 1)
export BUILD_STANDALONE = 1
endif

all:
	@if [ ! -f "Application/Dopamine/Resources/sileo.deb" ] && [ -d "sileo" ] && [ -f "sileo/Makefile" ]; then \
		$(MAKE) -C sileo package SILEO_PLATFORM=iphoneos-arm64 || true; \
		if ls sileo/packages/*.deb 1> /dev/null 2>&1; then \
			cp -f sileo/packages/*.deb Application/Dopamine/Resources/sileo.deb; \
		fi \
	fi
	@$(MAKE) -C BaseBin
	@$(MAKE) -C Packages
	@$(MAKE) -C Application
	@$(MAKE) -C Standalone

clean:
	@if [ -d "sileo" ] && [ -f "sileo/Makefile" ]; then $(MAKE) -C sileo clean || true; fi
	@$(MAKE) -C BaseBin clean
	@$(MAKE) -C Packages clean
	@$(MAKE) -C Application clean
	@$(MAKE) -C Standalone clean

update: all
	ssh $(DEVICE) "rm -rf /var/mobile/Documents/Dopamine.tipa"
	scp -C ./Application/Dopamine.tipa "$(DEVICE):/var/mobile/Documents/Dopamine.tipa"
	ssh $(DEVICE) "/var/jb/basebin/jbctl update tipa /var/mobile/Documents/Dopamine.tipa"

update-basebin: all
	ssh $(DEVICE) "rm -rf /var/mobile/Documents/basebin.tar"
	scp -C ./BaseBin/basebin.tar "$(DEVICE):/var/mobile/Documents/basebin.tar"
	ssh $(DEVICE) "/var/jb/basebin/jbctl update basebin /var/mobile/Documents/basebin.tar"

.PHONY: update clean