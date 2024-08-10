# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon::worker::file {

    variable default_config {
        -format {%h %l %u %t "%r" %>s %b}
    }

    namespace import ::treqmon::utils::*

}

proc ::treqmon::worker::file::process_event { config chan event } {
    puts $chan [format_event [dict get $config -format] $event]
}

proc ::treqmon::worker::file::process_events { output_id config events } {

    variable default_config

    set config [dict merge $default_config $config]

    if { [dict exists $config -path] } {
        set path [dict get $config -path]
    } else {
        set path "stdout"
    }

    if { $path in {stdout stderr} } {
        set lockvar "console"
    } else {
        set lockvar $path
    }

    # Ensure that all events for specific file path are mutex-protected
    if {1} {

        if { $lockvar eq "console" } {
            set chan $path
        } else {
            set chan [open $path a 0644]
        }

        foreach event $events {
            ::treqmon::worker::file::process_event $config $chan $event
        }

        if { $lockvar ne "console" } {
            close $chan
        }

    }

}


