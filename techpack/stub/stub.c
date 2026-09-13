// SPDX-License-Identifier: GPL-2.0-only

#include <linux/types.h>

bool gesture_incall = false;

static void _techpack_stub(void)
{
}

#include <linux/kconfig.h>

#include <linux/err.h>
#include <linux/of.h>

struct drm_panel;

#if !IS_ENABLED(CONFIG_DRM_PANEL)
struct drm_panel *of_drm_find_panel(const struct device_node *np)
{
	(void)np;
	return ERR_PTR(-ENODEV);
}
#endif

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
