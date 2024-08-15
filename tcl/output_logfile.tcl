# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

namespace eval ::treqmon::worker::logfile {

    variable config {
        format_string {%h %l %u %t "%r" %>s %b}
        threshold 100
    }

    variable format_string
    variable threshold
    variable path
    variable chan

    variable buffer_events {}
}

proc ::treqmon::worker::logfile::init {config_dict} {
    variable config
    variable format_string
    variable threshold
    variable path
    variable chan

    set config [dict merge $config $config_dict]

    set path [dict get $config path]

    if { [dict exists $config format_string] } {
        set format_string [dict get $config format_string]
    }

    if { [dict exists $config threshold] } {
        set threshold [dict get $config threshold]
    }

    set chan [open $path a 0644]
}

proc ::treqmon::worker::logfile::log_event { event } {
    variable buffer_events
    variable threshold
    variable format_string
    variable chan

    lappend buffer_events $event

    if { [llength $buffer_events] > $threshold } {
        tsv::lock access_log {
            foreach event $buffer_events {
                puts $chan [::treqmon::util::format_event $format_string $event]
            }
        }
        set buffer_events {}
    }
}

proc ::treqmon::worker::logfile::shutdown {} {
    variable format_string
    variable chan
    variable buffer_events

    foreach event $buffer_events {
        puts $chan [::treqmon::util::format_event $format_string $event]
    }
    set buffer_events {}

    close $chan

    return
}