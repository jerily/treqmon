# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon {

    variable main_config {
        tpool {
            -minworkers 1
            -maxworkers 4
            -idletime 30
        }
        worker {
            output {
                console {
                    ns ::treqmon::output::console
                }
            }
        }
    }

    variable middleware_config {
        poolId ""
    }
}

proc ::treqmon::init_main { config } {

    variable main_config

    set tpool_config [dict get $main_config tpool]
    if { [dict exists $config tpool] } {
        set tpool_config [dict merge $tpool_config [dict get $config tpool]]
    }

    set worker_config [dict get $main_config worker]

    dict set tpool_conf -initcmd [list package require treqmon::worker ; ::treqmon::worker::init $worker_config]

    return [dict create poolId [tpool::create {*}$tpool_conf]]
}

proc ::treqmon::init_middleware { config } {
    variable middleware_config

    if { [dict exists $config poolId] } {
        dict set middleware_config poolId [dict get $config poolId]
    }
}

proc ::treqmon::enter { ctx req } {
    dict set req treqmon timestamp_start [clock milliseconds]
}

proc ::treqmon::leave { ctx req res } {
    variable middleware_config

    set poolId [dict get $middleware_config poolId]
    if { $poolId eq {} } {
        error "Middleware not initialized."
    }

    dict set req treqmon timestamp_end [clock milliseconds]
    tpool::post -detached -nowait $poolId \
        [list treqmon::register_event $ctx $req $res]

    return $res

}
