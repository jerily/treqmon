# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package provide treqmon 2.2.0

set dir [file dirname [info script]]

source [file join $dir treqmon.tcl]
source [file join $dir middleware.tcl]
source [file join $dir util.tcl]
source [file join $dir output_console.tcl]
source [file join $dir output_logfile.tcl]
source [file join $dir memstore.tcl]
source [file join $dir tsvstore.tcl]
source [file join $dir valkeystore.tcl]

source [file join $dir views.tcl]
source [file join $dir http.tcl]
