# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

namespace eval ::treqmon::utils {

    namespace export format_event format_get

}

proc ::treqmon::utils::format_get { type modifier varname ev } {
    switch -exact -- $type {
        "h" {
            return [dict get $ev remote_ip]
        }
        "l" {
            return [dict get $ev remote_logname]
        }
        "u" {
            return [dict get $ev remote_user]
        }
        "t" {
            set timestamp [expr { [dict get $ev timestamp_start] / 1000000 }]
            return [clock format $timestamp -format {[%d/%b/%Y:%H:%M:%S %z]} -locale en]
        }
        "r" {
            return [dict get $ev request]
        }
        "s" {
            return [dict get $ev status_code]
        }
        "b" {
            return [expr { [dict get $ev response_size] ? [dict get $ev response_size] : "-" }]
        }
    }
}

proc ::treqmon::utils::format_event { frm ev } {

    set cache [dict create "%" "%"]
    set output ""

    # state:
    #   0 - nothing
    #   1 - % char
    #   2 - in variable name ({...})
    set state 0
    set varname ""
    set modifier ""

    # Should we skip the placeholder because of status filtering?
    set status_filter_code_list [list]
    set status_filter_code_curr ""
    set status_filter_code_not 0

    foreach c [split $frm ""] {
        if { !$state } {
            if { $c eq "%" } {
                set state 1
            } else {
                append output $c
            }
            continue
        }
        # if we are in a variable name
        if { $state == 2 } {
            if { $c eq "\}" } {
                set state 1
            } else {
                append varname $c
            }
            continue
        }
        # If we are here, that means we are in % placeholder. First, check to see
        # if there is a modifier.
        if { $c in {< > ^} && ![string length $modifier] } {
            set modifier $c
            continue
        }
        # Second, check to see if we have an inverse state code check (!).
        if { $c eq "!" } {
            set status_filter_code_not 1
            continue
        }
        # Third, check if we want to filter by status code
        if { $c in {0 1 2 3 4 5 6 7 8 9} } {
            append status_filter_code_curr $c
            continue
        }
        # Maybe we have an enumeration to check the status code?
        if { $c eq "," } {
            # Do we have a status code for filtering?
            if { [string length $status_filter_code_curr] } {
                lappend status_filter_code_list $status_filter_code_curr
                set status_filter_code_curr ""
            }
            continue
        }
        # If we are here, then we have encountered the placeholder type.
        # Let's check if we need to filter this placeholder by status code.
        if { [llength $status_filter_code_list] } {
            # Skip if current status code is not in specified list.
            set skip [expr { [dict get $ev status_code] ni $status_filter_code_list }]
            # But wait... may be we want to invert the above condition?
            if { $status_filter_code_not } {
                set skip [expr { !$skip }]
            }
        } else {
            set skip 0
        }
        # Finally, we can insert a replacement for the placeholder. But only
        # do this if we don't filter it by status code.
        if { $skip } {
            append output "-"
        } else {
            set key [list $c $modifier $varname]
            if { ![dict exists $cache $key] } {
                # We haven't met this holder yet and need to figure out
                # how to replace it.
                dict set cache $key [format_get $c $modifier $varname $ev]
            }
            append output [dict get $cache $key]
        }
        # reset the state
        set state 0
        set varname ""
        set modifier ""
        set status_filter_code_list [list]
        set status_filter_code_curr ""
        set status_filter_code_not 0
    }

    return $output

}
