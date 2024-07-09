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
    set timestamp_start [dict get $req treqmon timestamp_start]
    set timestamp_end [dict get $res treqmon timestamp_end]
    set duration [expr { $timestamp_end - $timestamp_start }]

    set event [dict create \
        remote_ip       [dict get $ctx addr] \
        remote_logname  "-" \
        remote_user     "-" \
        request         "[dict get $req httpMethod] [dict get $req url] [dict get $req version]" \
        status_code     [dict get $res statusCode] \
        response_size   [dict get $res body_size] \
        timestamp_start $timestamp_start \
        timestamp_end   $timestamp_end \
        duration        $duration \
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
        # For now, we only keep timestamps, rounded to seconds, for history.
        # If needed in the future, we can store information with additional fields.
        tsv::lappend ::treqmon::worker::history events [expr { $timestamp_start / 1000000 }]
        if { [tsv::llength ::treqmon::worker::history events] > [dict get $config -history_max_events] } {
            tsv::lpop ::treqmon::worker::history events 0
        }
    }

    } err opts] } {
        puts stderr "ERROR in ::treqmon::worker::register_event: $::errorInfo"
    }

}

