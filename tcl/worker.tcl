# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon::worker {
    variable config {
        store "memstore"
        store_config {}
        output {
            console {
                threshold 100
            }
        }
        history_max_events 1000000
    }
    variable output_types {}
    variable history_max_events
    variable history_events {}
}

proc ::treqmon::worker::init { config_dict } {
    variable config
    variable output_types
    variable history_max_events
    variable store
    variable store_config

    validate_config $config_dict

    set config [dict merge $config $config_dict]
    set store [dict get $config store]
    set store_config [dict get $config store_config]
    set history_max_events [dict get $config history_max_events]

    foreach { output_type output_config } [dict get $config output] {
        ${output_type}::init $output_config
        lappend output_types $output_type
    }

    ${store}::init $store_config
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
    variable store

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

    ${store}::push_event $h

    # Drop oldest events if the buffer is full
    set len [${store}::get_num_events]
    if { $len > [expr { 1.5 * $history_max_events }] } {
        set num_drop_events [expr { $len - $history_max_events }]
        ${store}::drop_events $num_drop_events
    }

    return
}

proc ::treqmon::worker::get_history_events {} {
    variable store
    return [${store}::get_history_events]
}

proc ::treqmon::worker::shutdown {} {
    variable output_types
    foreach output_type $output_types {
        # e.g. console::shutdown
        ${output_type}::shutdown
    }
    return
}