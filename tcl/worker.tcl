# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon::worker {
    variable config
    variable output_types {}
    variable history_max_events
    variable history_events {}
}

proc ::treqmon::worker::init { config_dict } {
    variable config
    variable output_types
    variable history_max_events

    validate_config $config_dict

    set config $config_dict

    set history_max_events [dict get $config history_max_events]

    foreach { output_type output_config } [dict get $config output] {
        ${output_type}::init $output_config
        lappend output_types $output_type
    }
}

proc ::treqmon::worker::validate_config { config_dict } {
    dict for { k v } $config_dict {
       switch -exact -- $k {
           history_max_events {
               if { ![string is integer -strict $v] || $v < 0 } {
                   return -code error "$k option expects unsigned integer value,\
                       but got \"$v\""
               }
           }
           output {
               foreach { output_type output_config } $v {
                   if { ![llength [info commands ${output_type}::log_event]] } {
                       return -code error "unknown output type \"$output_type\""
                   }
               }
           }
           default {
               return -code error "unknown option \"$k\" for ::treqmon::worker"
           }
       }
    }
}

proc ::treqmon::worker::register_event { event } {
    variable config
    variable history_max_events
    variable history_events

    dict lappend event server_tid [thread::id]

    if { [catch {

        # Stream the event to the output
        log_history_event $event

        # Store the event in the history buffer
        push_history_event $event

    } err opts] } {
        puts stderr "ERROR in ::treqmon::worker::register_event: $::errorInfo"
    }

}

proc ::treqmon::worker::log_history_event {event} {
    variable output_types
    foreach output_type $output_types {
        # e.g. console::log_event
        ${output_type}::log_event $event
    }
}

proc ::treqmon::worker::push_history_event {event} {
    variable history_events
    variable history_max_events

    # For now, we only keep timestamps rounded to seconds + response time
    # rounded to milliseconds.
    #
    # If needed in the future, we can store information with additional fields.
    #
    set req_timestamp [dict get $event request_timestamp]
    set res_timestamp [dict get $event response_timestamp]

    set h [list \
        [expr { $req_timestamp / 1000000 }] \
        [expr { ( $res_timestamp - $req_timestamp ) / 1000 }] \
    ]

    lappend history_events $h

    # Drop oldest events if the buffer is full
    set len [llength $history_events]
    if { $len > [expr { 1.5 * $history_max_events }] } {
        set num_drop_events [expr { $len - $history_max_events }]
        set history_events [lrange $history_events $num_drop_events end]
    }

    return
}

proc ::treqmon::worker::get_history_events {} {
    variable history_events
    return $history_events
}