.PHONY: all dart java kotlin typescript generate-all compile-all clean

all: generate-all compile-all

generate-all:
	-$(MAKE) -C dart generate
	-$(MAKE) -C java generate
	-$(MAKE) -C kotlin generate
	-$(MAKE) -C typescript generate

compile-all:
	-$(MAKE) -C dart analyze
	-$(MAKE) -C java compile
	-$(MAKE) -C kotlin compile
	-$(MAKE) -C typescript compile

clean:
	-$(MAKE) -C dart clean
	-$(MAKE) -C java clean
	-$(MAKE) -C kotlin clean
	-$(MAKE) -C typescript clean

dart:
	$(MAKE) -C dart analyze

java:
	$(MAKE) -C java compile

kotlin:
	$(MAKE) -C kotlin compile

typescript:
	$(MAKE) -C typescript compile
