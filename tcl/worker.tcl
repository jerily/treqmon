# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon::worker {
    variable config
    variable history_max_events
}

proc ::treqmon::worker::init { config_dict } {
    variable config
    variable history_max_events

    validate_config $config_dict

    set config $config_dict

    set history_max_events [dict get $config -history_max_events]

}

proc ::treqmon::worker::validate_config { config_dict } {
    dict for { k v } $config_dict {
       switch -exact -- $k {
           -history_max_events {
               if { ![string is integer -strict $v] || $v < 0 } {
                   return -code error "$k option expects unsigned integer value,\
                       but got \"$v\""
               }
           }
           -output {
               foreach { output_type output_config } $v {
                   if { ![llength [info commands ${output_type}::process_events]] } {
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

    dict lappend event server_tid [thread::id]

    if { [catch {

    # calculate all required event properties

    # TODO:
    #     remote_hostname - try to detect real remote hostname from remote_ip

    unset -nocomplain output_id
    foreach { output_type output_config } [dict get $config -output] {

        incr output_id

        unset -nocomplain events
        # Check if the output is configured to store the last N events
        # in the buffer and process buffered events in one shot
        if {
            [dict exists $output_config -threshold] &&
                [set threshold [dict get $output_config -threshold]] > 1
        } {
            set var ::treqmon::worker::output::buffer$output_id
            if {1} {
                if { [tsv::exists $var buffer] && [tsv::llength $var buffer] >= [incr threshold -1] } {
                    set events [tsv::pop $var buffer]
                } else {
                    tsv::lappend $var buffer $event
                    continue
                }
            }
        }

        if { [info exists events] } {
            ${output_type}::process_events $output_id $output_config [concat $events [list $event]]
        } else {
            ${output_type}::process_events $output_id $output_config [list $event]
        }

    }

    if {1} {
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

        tsv::lappend ::treqmon::worker::history events $h

        if { [tsv::llength ::treqmon::worker::history events] > $history_max_events } {
            tsv::lpop ::treqmon::worker::history events 0
        }
    }

    } err opts] } {
        puts stderr "ERROR in ::treqmon::worker::register_event: $::errorInfo"
    }

}

