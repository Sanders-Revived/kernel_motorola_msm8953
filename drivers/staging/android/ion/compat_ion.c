/*
 * drivers/staging/android/ion/compat_ion.c
 *
 * Copyright (C) 2013 Google, Inc.
 *
 * This software is licensed under the terms of the GNU General Public
 * License version 2, as published by the Free Software Foundation, and
 * may be copied, distributed, and modified under those terms.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

#include <linux/compat.h>
#include <linux/fs.h>
#include <linux/msm_ion.h>
#include <linux/uaccess.h>

#include "ion.h"
#include "compat_ion.h"
#include "ion_legacy.h"

/* See drivers/staging/android/uapi/ion.h for the definition of these structs */
struct compat_ion_old_allocation_data {
	compat_size_t len;
	compat_size_t align;
	compat_uint_t heap_id_mask;
	compat_uint_t flags;
	compat_int_t handle;
};

struct compat_ion_handle_data {
	compat_int_t handle;
};

struct compat_ion_flush_data {
	compat_int_t handle;
	compat_int_t fd;
	compat_uptr_t vaddr;
	compat_uint_t offset;
	compat_uint_t length;
};

struct compat_ion_custom_data {
	compat_uint_t cmd;
	compat_uptr_t arg;
};

#define COMPAT_ION_IOC_ALLOC	_IOWR(ION_IOC_MAGIC, 0, \
				      struct compat_ion_old_allocation_data)
#define COMPAT_ION_IOC_FREE	_IOWR(ION_IOC_MAGIC, 1, \
				      struct compat_ion_handle_data)
#define COMPAT_ION_IOC_CLEAN_CACHES	_IOWR(ION_IOC_MSM_MAGIC, 0, \
					     struct compat_ion_flush_data)
#define COMPAT_ION_IOC_INV_CACHES	_IOWR(ION_IOC_MSM_MAGIC, 1, \
					     struct compat_ion_flush_data)
#define COMPAT_ION_IOC_CLEAN_INV_CACHES	_IOWR(ION_IOC_MSM_MAGIC, 2, \
						 struct compat_ion_flush_data)

#define COMPAT_ION_IOC_CUSTOM	_IOWR(ION_IOC_MAGIC, 6, struct compat_ion_custom_data)

static int compat_get_ion_allocation_data(
			struct compat_ion_old_allocation_data __user *data32,
			struct ion_old_allocation_data __user *data)
{
	compat_size_t s;
	compat_uint_t u;
	compat_int_t i;
	int err;

	err = get_user(s, &data32->len);
	err |= put_user(s, &data->len);
	err |= get_user(s, &data32->align);
	err |= put_user(s, &data->align);
	err |= get_user(u, &data32->heap_id_mask);
	err |= put_user(u, &data->heap_id_mask);
	err |= get_user(u, &data32->flags);
	err |= put_user(u, &data->flags);
	err |= get_user(i, &data32->handle);
	err |= put_user(i, &data->handle);

	return err;
}

static int compat_get_ion_handle_data(
			struct compat_ion_handle_data __user *data32,
			struct ion_handle_data __user *data)
{
	compat_int_t i;
	int err;

	err = get_user(i, &data32->handle);
	err |= put_user(i, &data->handle);

	return err;
}

static int compat_get_ion_flush_data(
			struct compat_ion_flush_data __user *data32,
			struct ion_flush_data __user *data)
{
	compat_int_t i;
	compat_uptr_t u;
	compat_uint_t v;
	int err;

	err = get_user(i, &data32->handle);
	err |= put_user(i, &data->handle);
	err |= get_user(i, &data32->fd);
	err |= put_user(i, &data->fd);
	err |= get_user(u, &data32->vaddr);
	err |= put_user((__u64)u, &data->vaddr);
	err |= get_user(v, &data32->offset);
	err |= put_user(v, &data->offset);
	err |= get_user(v, &data32->length);
	err |= put_user(v, &data->length);

	return err;
}

static int compat_put_ion_allocation_data(
			struct compat_ion_old_allocation_data __user *data32,
			struct ion_old_allocation_data __user *data)
{
	compat_size_t s;
	compat_uint_t u;
	compat_int_t i;
	int err;

	err = get_user(s, &data->len);
	err |= put_user(s, &data32->len);
	err |= get_user(s, &data->align);
	err |= put_user(s, &data32->align);
	err |= get_user(u, &data->heap_id_mask);
	err |= put_user(u, &data32->heap_id_mask);
	err |= get_user(u, &data->flags);
	err |= put_user(u, &data32->flags);
	err |= get_user(i, &data->handle);
	err |= put_user(i, &data32->handle);

	return err;
}

long compat_ion_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
	long ret;

	if (!filp->f_op->unlocked_ioctl)
		return -ENOTTY;

	switch (cmd) {
	case COMPAT_ION_IOC_ALLOC:
	{
		struct compat_ion_old_allocation_data __user *data32;
		struct ion_old_allocation_data __user *data;
		int err;

		data32 = compat_ptr(arg);
		data = compat_alloc_user_space(sizeof(*data));
		if (!data)
			return -EFAULT;

		err = compat_get_ion_allocation_data(data32, data);
		if (err)
			return err;
		ret = filp->f_op->unlocked_ioctl(filp, ION_OLD_IOC_ALLOC,
							(unsigned long)data);
		err = compat_put_ion_allocation_data(data32, data);
		return ret ? ret : err;
	}
	case COMPAT_ION_IOC_FREE:
	{
		struct compat_ion_handle_data __user *data32;
		struct ion_handle_data __user *data;
		int err;

		data32 = compat_ptr(arg);
		data = compat_alloc_user_space(sizeof(*data));
		if (!data)
			return -EFAULT;

		err = compat_get_ion_handle_data(data32, data);
		if (err)
			return err;

		return filp->f_op->unlocked_ioctl(filp, ION_IOC_FREE,
							(unsigned long)data);
	}
	case COMPAT_ION_IOC_CUSTOM:
	{
		struct compat_ion_custom_data __user *custom32;
		struct ion_custom_data __user *custom;
		struct compat_ion_flush_data __user *flush32;
		struct ion_flush_data __user *flush;
		compat_uint_t custom_cmd;
		compat_uptr_t custom_arg;
		unsigned int native_cmd;
		int err;

		custom32 = compat_ptr(arg);
		custom = compat_alloc_user_space(sizeof(*custom));
		if (!custom)
			return -EFAULT;

		err = get_user(custom_cmd, &custom32->cmd);
		err |= get_user(custom_arg, &custom32->arg);
		if (err)
			return err;

		switch (custom_cmd) {
		case COMPAT_ION_IOC_CLEAN_CACHES:
			native_cmd = ION_IOC_CLEAN_CACHES;
			break;
		case COMPAT_ION_IOC_INV_CACHES:
			native_cmd = ION_IOC_INV_CACHES;
			break;
		case COMPAT_ION_IOC_CLEAN_INV_CACHES:
			native_cmd = ION_IOC_CLEAN_INV_CACHES;
			break;
		default:
			return -ENOIOCTLCMD;
		}

		flush32 = compat_ptr(custom_arg);
		flush = compat_alloc_user_space(sizeof(*flush));
		if (!flush)
			return -EFAULT;

		err = compat_get_ion_flush_data(flush32, flush);
		err |= put_user(native_cmd, &custom->cmd);
		err |= put_user((unsigned long)flush, &custom->arg);
		if (err)
			return err;

		return filp->f_op->unlocked_ioctl(filp, ION_IOC_CUSTOM,
							(unsigned long)custom);
	}
	case COMPAT_ION_IOC_INV_CACHES:
	case COMPAT_ION_IOC_CLEAN_CACHES:
	case COMPAT_ION_IOC_CLEAN_INV_CACHES:
	{
		struct compat_ion_flush_data __user *data32;
		struct ion_flush_data __user *data;
		unsigned int native_cmd;
		int err;

		data32 = compat_ptr(arg);
		data = compat_alloc_user_space(sizeof(*data));
		if (!data)
			return -EFAULT;

		err = compat_get_ion_flush_data(data32, data);
		if (err)
			return err;

		switch (cmd) {
		case COMPAT_ION_IOC_CLEAN_CACHES:
			native_cmd = ION_IOC_CLEAN_CACHES;
			break;
		case COMPAT_ION_IOC_INV_CACHES:
			native_cmd = ION_IOC_INV_CACHES;
			break;
		default:
			native_cmd = ION_IOC_CLEAN_INV_CACHES;
			break;
		}

		return filp->f_op->unlocked_ioctl(filp, native_cmd,
							(unsigned long)data);
	}
	case ION_IOC_SHARE:
	case ION_IOC_MAP:
	case ION_IOC_IMPORT:
	case ION_IOC_ALLOC:
	case ION_IOC_HEAP_QUERY:
	case ION_IOC_PREFETCH:
	case ION_IOC_DRAIN:
		return filp->f_op->unlocked_ioctl(filp, cmd,
						(unsigned long)compat_ptr(arg));
	default:
		return -ENOIOCTLCMD;
	}
}
