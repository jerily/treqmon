# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

namespace eval ::treqmon::console {
}

proc ::treqmon::console::init { config } {
}

proc ::treqmon::console::output_event { ev } {
    puts "Event: $ev"
}
