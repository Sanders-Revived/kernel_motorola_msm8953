// SPDX-License-Identifier: GPL-2.0-only

#include <linux/types.h>

bool gesture_incall = false;

static void _techpack_stub(void)
{
}

#include <linux/kconfig.h>

#if !IS_ENABLED(CONFIG_MSMB_CAMERA) && \
	!IS_ENABLED(CONFIG_MSMB_CAMERA_LEGACY) && \
	!IS_ENABLED(CONFIG_MSMB_CAMERA_LEGACY_N)
struct avtimer_fptr_t {
	int (*fptr_avtimer_open)(void);
	int (*fptr_avtimer_enable)(int enable);
	int (*fptr_avtimer_get_time)(uint64_t *avtimer_tick);
};

void msm_isp_set_avtimer_fptr(struct avtimer_fptr_t fptr)
{
	(void)fptr;
}
#endif
