# SPDX-License-Identifier: GPL-2.0
dtstree		:= $(srctree)/$(src)
DTB_NAMES := $(subst $\",,$(CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES))

ifeq ($(DTB_NAMES),)
vendor := $(dtstree)/vendor
ifeq "$(wildcard $(vendor)/Makefile)" ""
subdir-y += actions
subdir-y += al
subdir-y += allwinner
subdir-y += altera
subdir-y += amd
subdir-y += amlogic
subdir-y += apm
subdir-y += arm
subdir-y += broadcom
subdir-y += cavium
subdir-y += exynos
subdir-y += freescale
subdir-y += hisilicon
subdir-y += lg
subdir-y += marvell
subdir-y += mediatek
subdir-y += nvidia
subdir-y += qcom
subdir-y += realtek
subdir-y += renesas
subdir-y += rockchip
subdir-y += socionext
subdir-y += sprd
subdir-y += synaptics
subdir-y += ti
subdir-y += xilinx
subdir-y += zte


else
        subdir-y += vendor
endif
endif

dtb-$(CONFIG_OF_ALL_DTBS) := $(patsubst $(dtstree)/%.dts,%.dtb, $(foreach d,$(subdir), $(wildcard $(dtstree)/$(d)/*.dts)))

targets += dtbs

ifneq ($(DTB_NAMES),)
DTB_LIST := $(addsuffix .dtb,$(DTB_NAMES))
else
DTB_LIST := $(dtb-y)
endif
always := $(DTB_LIST)
targets += $(DTB_LIST)

dtbs: $(addprefix $(obj)/, $(DTB_LIST))

clean-files := dts/*.dtb *.dtb
