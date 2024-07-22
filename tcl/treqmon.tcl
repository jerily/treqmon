# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon {

    variable default_config {
        tpool {
            -minworkers 1
            -maxworkers 4
            -idletime 30
        }
        worker {
            -output {
                console {
                }
            }
            -history_max_events 1000000
        }
    }

}

proc ::treqmon::init { {config {}} } {

    variable default_config

    # Validate specified configuration
    foreach key [dict keys $config] {
        if { $key ni { tpool worker } } {
            return -code error "unknown key in configuration dictionary \"$key\""
        }
    }

    set tpool_config [dict get $default_config tpool]
    if { [dict exists $config tpool] } {
        set tpool_config [dict merge $tpool_config [dict get $config tpool]]
    }

    set worker_config [dict get $default_config worker]
    if { [dict exists $config worker] } {
        set worker_config [dict merge $worker_config [dict get $config worker]]
    }

    ::treqmon::worker::validate_config $worker_config

    tsv::set ::treqmon workerConfig $worker_config

    dict set tpool_config -initcmd [list package require treqmon]

    tsv::set ::treqmon workerPoolId [tpool::create {*}$tpool_config]

}

proc ::treqmon::enter { ctx req } {
    dict set req treqmon timestamp [clock microseconds]
    return $req
}

proc ::treqmon::leave { ctx req res } {
    dict set res treqmon timestamp [clock microseconds]
    dict set ctx treqmon thread_id [thread::id]
    if { [tsv::get ::treqmon workerPoolId poolId] } {
        ::tpool::post -detached -nowait $poolId \
            [list ::treqmon::worker::register_event $ctx [filter_body $req] [filter_body $res]]
    }
    return $res
}

# This function filters the "body" field in the dictionary and replaces it
# with "body_size", corresponding to the size of the deleted body field.
# The "body" field can be very large in size. With this procedure,
# we won't be transferring large amounts of memory between threads.
proc ::treqmon::filter_body { d } {
    if { ![dict exists $d body] } {
        return $d
    }
    dict set d body_size [string length [dict get $d body]]
    dict unset d body
    return $d
}

proc ::treqmon::statistics { args } {

    # Time window in seconds for which we want to get statistics.
    # It is necessary not to look through all statistics, but only a specified
    # interval (for example, last second or last minute).
    set time_window 0

    # A list of metrics to be returned, and in the order in which they
    # appear in the arguments.
    set metric_interval_list [list]

    # Known time intervals
    array set intervals {
        second 0
        minute 59
        hour   3599
        day    86399
    }

    unset -nocomplain timestamp_current

    # Check if the last argument is a relative time
    set timestamp_current [lindex $args end]
    if { $timestamp_current eq "now" || [string is integer -strict $timestamp_current] } {
        # Remove the last argument from the argument list
        set args [lreplace $args end end]
    } else {
        set timestamp_current "now"
    }

    if { $timestamp_current eq "now" } {
        set timestamp_current [clock seconds]
    }

    foreach arg $args {
        lassign [split [string trimleft $arg -] _] metric interval
        if { $metric ni {count average} || $interval ni {second minute hour day} } {
            return -code error "unknown metric type \"$arg\""
        }
        dict set metric_count $interval $metric 0

        lappend metric_interval_list [list $metric $interval]

        set interval $intervals($interval)
        if { $interval > $time_window } {
            set time_window $interval
        }
    }

    # Getting the request statistics into a variable so as not to block
    # other threads from adding new records.
    if { ![tsv::get ::treqmon::worker::history events events] } {
        # Failed to retrieve events. Let's use an empty list.
        set events [list]
    }

    set events [lreverse $events]
    set count 0
    foreach ev $events {

        lassign $ev timestamp duration

        if { $timestamp > $timestamp_current } {
            continue
        }

        # The age of the current record in seconds.
        set age [expr { $timestamp_current - $timestamp }]
        # First, check to make sure we haven't reached a timestamp outside
        # of our time window.
        if { $age > $time_window } {
            break
        }

        foreach interval [array names intervals] {
            # Do we have metrics that need to be calculated within the interval?
            if { $age <= $intervals($interval) && [dict exists $metric_count $interval] } {
                if { [dict exists $metric_count $interval count] } {
                    dict set metric_count $interval count [expr \
                        { [dict get $metric_count $interval count] + 1 }]
                }
                if { [dict exists $metric_count $interval average] } {
                    dict set metric_count $interval average [expr \
                        { 1.0 * ((1.0 * [dict get $metric_count $interval average] * $count) + $duration) / ($count + 1) }]
                }
            }
        }

        incr count

    }

    # Generate results
    set result [dict create]
    foreach metric_interval_pair $metric_interval_list {
        lassign $metric_interval_pair metric interval
        dict set result [join $metric_interval_pair {_}] [expr { round([dict get $metric_count $interval $metric]) }]
    }
    return $result

}

