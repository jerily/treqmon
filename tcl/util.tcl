# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

namespace eval ::treqmon::util {

    namespace export format_event format_get format_escape

}

proc ::treqmon::util::format_escape { str } {
    set output ""
    foreach ch [split $str ""] {
        switch -exact -- $ch {
            "\"" - "\\" {
                append output "\\" $ch
            }
            "\n" { append output {\n} }
            "\r" { append output {\r} }
            "\t" { append output {\t} }
            default {
                scan $ch %c c
                if { $c >= 0x20 && $c <= 0x7e } {
                    append output $ch
                } else {
                    append output [format "\\x%02X" $c]
                }
            }
        }
    }
    return $output
}

proc ::treqmon::util::format_get { type modifier varname ev } {
    set r ""
    switch -exact -- $type {
        "%" {
            set r "%"
        }
        "h" {
            set r [dict get $ev remote_hostname]
        }
        "a" {
            set r [dict get $ev remote_addr]
        }
        "l" {
            set r [dict get $ev remote_logname]
        }
        "u" {
            set r [dict get $ev remote_user]
        }
        "r" {
            set r [dict get $ev request_first_line]
            set r [format_escape $r]
        }
        "H" {
            set r [dict get $ev request_protocol]
        }
        "s" {
            set r [dict get $ev response_status_code]
        }
        "b" {
            set r [expr { [dict get $ev response_size] ? [dict get $ev response_size] : "-" }]
        }
        "B" {
            set r [dict get $ev response_size]
        }
        "D" {
            set r [expr { [dict get $ev response_timestamp] - [dict get $ev request_timestamp] }]
        }
        "T" {
            if { $varname eq "" || $varname eq "s" } {
                set r [expr { ([dict get $ev response_timestamp] - [dict get $ev request_timestamp]) / 1000000 }]
            } elseif { $varname eq "ms" } {
                set r [expr { ([dict get $ev response_timestamp] - [dict get $ev request_timestamp]) / 1000 }]
            } elseif { $varname eq "us" } {
                set r [expr { [dict get $ev response_timestamp] - [dict get $ev request_timestamp] }]
            } else {
                return $varname
            }
        }
        "t" {

            if { [string range $varname 0 5] eq "begin:" } {
                set timestamp [dict get $ev request_timestamp]
                set varname [string range $varname 6 end]
            } elseif { [string range $varname 0 3] eq "end:" } {
                set timestamp [dict get $ev response_timestamp]
                set varname [string range $varname 4 end]
            } else {
                set timestamp [dict get $ev request_timestamp]
            }

            if { $varname eq "sec" } {
                set r [expr { $timestamp / 1000000 }]
            } elseif { $varname eq "msec" } {
                set r [expr { $timestamp / 1000 }]
            } elseif { $varname eq "usec" } {
                set r $timestamp
            } elseif { $varname eq "msec_frac" } {
                set r [expr { ($timestamp / 1000) % 1000 }]
            } elseif { $varname eq "usec_frac" } {
                set r [expr { $timestamp % 1000 }]
            } else {
                if { $varname eq "" } {
                    set varname {[%d/%b/%Y:%H:%M:%S %z]}
                }
                set timestamp [expr { $timestamp / 1000000 }]
                set r [clock format $timestamp -format $varname]
            }

        }
        "e" {
            if { [info exists ::env($varname)] } {
                set r $::env($varname)
            }
        }
        "i" {
            set varname [string tolower $varname]
            if { [dict exists $ev request_headers $varname] } {
                set r [dict get $ev request_headers $varname]
            }
            set r [format_escape $r]
        }
        "o" {
            set varname [string tolower $varname]
            set header_keys [dict keys [dict get $ev response_headers]]
            if { [set pos [lsearch -exact -nocase $header_keys $varname]] != -1 } {
                set r [dict get $ev response_headers [lindex $header_keys $pos]]
            }
            set r [format_escape $r]
        }
        "m" {
            set r [dict get $ev request_method]
        }
        "p" {
            set r [dict get $ev server_port]
        }
        "P" {
            if { $varname eq "" || $varname eq "pid" } {
                set r [dict get $ev server_pid]
            } elseif { $varname eq "tid" } {
                # Event contains thread id in format: tid0x7fe9e913f040.
                # Convert it to a decimal number.
                set r [expr { 0 + [string range [dict get $ev server_tid] 3 end] }]
            } elseif { $varname eq "hextid" } {
                # Event contains thread id in format: tid0x7fe9e913f040.
                # Expected output: only hex digits.
                set r [string range [dict get $ev server_tid] 5 end]
            } else {
                set r $varname
            }
        }
        "q" {
            set r [dict get $ev request_query]
            if { ![string length $r] } {
                # According to specs, we should return an empty string if query
                # string is empty. Thus, return now to not replace an empty
                # string to "-" at the end of this procedure.
                return ""
            }
            set r "?$r"
        }
        "U" {
            set r [dict get $ev request_path]
        }
    }
    return [expr { [string length $r] ? $r : "-" }]
}

proc ::treqmon::util::format_event { frm ev } {

    set cache [dict create]
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
        # Maybe we want to start defining a variable?
        if { $c eq "\{" } {
            set state 2
            continue
        }
        # If we are here, then we have encountered the placeholder type.
        # Let's check if we need to filter this placeholder by status code.
        if { [string length $status_filter_code_curr] } {
            lappend status_filter_code_list $status_filter_code_curr
            set status_filter_code_curr ""
        }
        if { [llength $status_filter_code_list] } {
            # Skip if current status code is not in specified list.
            set skip [expr { [dict get $ev response_status_code] ni $status_filter_code_list }]
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
