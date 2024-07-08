# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon {}

proc treqmon::process_request { ctx req req } {

    dict set event [list \
        timestamp_ms_start [dict get $req treqmon timestamp] \
        timestamp_ms_end   $timestamp \
        duration_ms        [expr { $timestamp - [dict get $req treqmon timestamp] }] \
    ]

    if { [tsv::get ::treqmon outputThreadIds tids] } {
        foreach tid $tids {
            thread::send -async [list treqmon::register_event $event]
        }
    }

}

package provide treqmon::worker 1.0.0
