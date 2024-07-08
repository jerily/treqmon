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
        output {
            console {
            }
        }
    }

}

proc ::treqmon::init { config } {

    variable default_config

    if { [dict exists $config output] } {
        set conf [dict get $config output]
    } else {
        set conf [dict get $default_config output]
    }

    if { [dict size $conf] } {
        dict for { output conf } $conf {
            if { ![llength [package versions treqmon::output::$output]] } {
                return -code error "unknown output type \"$output\""
            }
            set tid [thread::create thread::wait]
            thread::send $tid [list package require treqmon::output::$output]
            thread::send $tid [list treqmon::init $conf]
            tsv::lappend ::treqmon outputThreadIds $tid
        }
    }

    set conf [dict get $default_config tpool]
    if { [dict exists $config tpool] } {
        set conf [dict merge $conf [dict get $config tpool]]
    }
    dict set conf -initcmd [list package require treqmon::worker]

    tsv::set ::treqmon workerTpoolId [tpool::create {*}$conf]

}

proc ::treqmon::enter { ctx req } {
    dict set req treqmon timestamp_start [clock milliseconds]
}

proc ::treqmon::leave { ctx req res } {
    dict set req treqmon timestamp_end [clock milliseconds]
    tpool::post -detached -nowait [tsw::get ::treqmon workerTpoolId] \
        [list treqmon::process_request $ctx $req $res]


    set timestamp [clock milliseconds]


    return $res

}

package provide treqmon 1.0.0