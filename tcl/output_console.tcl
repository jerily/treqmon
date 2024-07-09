# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

# This is just an alias for ::treqmon::worker::file

package require Thread

namespace eval ::treqmon::worker::console {}

proc ::treqmon::worker::console::process_events { output_id config events } {
    dict set config -path stdout
    ::treqmon::worker::file::process_events $output_id $config $events
}
