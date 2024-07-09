# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon::worker {
    variable default_config {
        output {
            console {
                ns ::treqmon::console
            }
        }
    }
}

proc treqmon::worker::init { config } {

        variable default_config

        set output_config [dict get $default_config output]
        if { [dict exists $config output] } {
            set output_config [dict merge $output_config [dict get $config output]]
        }

}

proc treqmon::worker::register_event { ctx req req } {
puts here=[dict get $req treqmon timestamp]
    dict set event [list \
        timestamp_ms_start [dict get $req treqmon timestamp] \
        timestamp_ms_end   $timestamp \
        duration_ms        [expr { $timestamp - [dict get $req treqmon timestamp] }] \
    ]

    dict for {output_name output_config} $output_config {
        dict with output_config {
            $ns::output_event $event
        }
    }

}
