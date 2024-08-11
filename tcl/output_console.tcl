# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

# This is just an alias for ::treqmon::worker::file

package require Thread

namespace eval ::treqmon::worker::console {
    variable config {
        threshold 100
        format_string {%h %l %u %t "%r" %>s %b}
    }
    variable format_string
    variable threshold

    variable buffer_events {}
}

proc ::treqmon::worker::console::init {config_dict} {
    variable config
    variable format_string
    variable threshold

    set config [dict merge $config $config_dict]

    if { [dict exists $config format_string] } {
        set format_string [dict get $config format_string]
    }

    if { [dict exists $config threshold] } {
        set threshold [dict get $config threshold]
    }
}

proc ::treqmon::worker::console::log_event { event } {
    variable buffer_events
    variable format_string
    variable threshold

    lappend buffer_events $event

    if { [llength $buffer_events] > $threshold } {
        foreach event $buffer_events {
            puts [::treqmon::util::format_event $format_string $event]
        }
        set buffer_events {}
    }

}
