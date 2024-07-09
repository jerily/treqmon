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
            -history_max_events 1000
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
    dict set req treqmon timestamp_start [clock microseconds]
    return $req
}

proc ::treqmon::leave { ctx req res } {
    dict set res treqmon timestamp_end [clock microseconds]
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
