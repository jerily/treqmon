# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package ifneeded treqmon 2.3.2 [list source [file join $dir tcl init.tcl]]

package ifneeded treqmon::routes 1.0 [list source [file join $dir tcl routes.tcl]]
