# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

namespace eval ::treqmon::console {
    variable worker_thread_id
}

proc ::treqmon::console::init_main {output_configVar config} {
    variable worker_thread_id
    upvar $output_configVar output_config

    package require Thread

    set initcmd [join [list \
        [list package require treqmon] \
        [list package require Thread] \
        [list ::treqmon::worker::console::init $config] \
        [list ::thread::wait]] "\n"]

    set worker_thread_id [thread::create -joinable $initcmd]

    dict set output_config logger "console" [list \
        worker_thread_id $worker_thread_id \
        threshold [dict get $config threshold]]
}

proc ::treqmon::console::shutdown_main {} {
    variable worker_thread_id
    thread::join $worker_thread_id
    thread::release $worker_thread_id
}

namespace eval ::treqmon::middleware::console {
    variable config {}
    variable worker_thread_id
}

proc ::treqmon::middleware::console::init {config_dict} {
    variable config
    variable worker_thread_id
    set config [dict merge $config $config_dict]
    set worker_thread_id [dict get $config worker_thread_id]
}

proc ::treqmon::middleware::console::log_event { event } {
    variable worker_thread_id
    return [thread::send -async $worker_thread_id [list ::treqmon::worker::console::log_event $event]]
}

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

    set format_string [dict get $config format_string]
    set threshold [dict get $config threshold]

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

proc ::treqmon::worker::console::shutdown {} {
    variable buffer_events
    variable format_string

    foreach event $buffer_events {
        puts [::treqmon::util::format_event $format_string $event]
    }
    set buffer_events {}
    return
}