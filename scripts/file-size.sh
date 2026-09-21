#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Optimized: use stat(1) instead of ls -dn to avoid fork overhead
stat -c %s "$1"
