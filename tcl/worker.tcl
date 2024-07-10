# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon::worker {}

proc ::treqmon::worker::validate_config { config } {
    dict for { k v } $config {
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

proc ::treqmon::worker::register_event { ctx req res } {

    if { [catch {

    tsv::get ::treqmon workerConfig config

    # calculate all required event properties

    # TODO:
    #     remote_hostname - try to detect real remote hostname from remote_ip

    set event [dict create \
        remote_addr          [dict get $ctx addr] \
        remote_hostname      [dict get $ctx addr] \
        remote_logname       "-" \
        remote_user          "-" \
        server_port          [dict get $ctx port] \
        server_tid           [dict get $ctx treqmon thread_id] \
        server_pid           [pid] \
        request_first_line   "[dict get $req httpMethod] [dict get $req url] [dict get $req version]" \
        request_protocol     [dict get $req version] \
        request_headers      [dict get $req headers] \
        request_method       [dict get $req httpMethod] \
        request_query        [dict get $req queryString] \
        request_path         [dict get $req path] \
        request_timestamp    [dict get $req treqmon timestamp] \
        response_status_code [dict get $res statusCode] \
        response_size        [dict get $res body_size] \
        response_timestamp   [dict get $res treqmon timestamp] \
    ]

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
            tsv::lock $var {
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

    tsv::lock ::treqmon::worker::history {
        # For now, we only keep timestamps rounded to seconds + response time
        # rounded to milliseconds.
        #
        # If needed in the future, we can store information with additional fields.
        #
        set h [list \
            [expr { [dict get $req treqmon timestamp] / 1000000 }] \
            [expr { ([dict get $res treqmon timestamp] - [dict get $req treqmon timestamp]) / 1000 }] \
        ]
        tsv::lappend ::treqmon::worker::history events
        if { [tsv::llength ::treqmon::worker::history events] > [dict get $config -history_max_events] } {
            tsv::lpop ::treqmon::worker::history events 0
        }
    }

    } err opts] } {
        puts stderr "ERROR in ::treqmon::worker::register_event: $::errorInfo"
    }

}

