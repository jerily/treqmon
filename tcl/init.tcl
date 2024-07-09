# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package provide treqmon 1.0.0

set dir [file dirname [info script]]

source [file join ${dir} treqmon.tcl]
source [file join ${dir} worker.tcl]
source [file join ${dir} output_console.tcl]
source [file join ${dir} output_file.tcl]
