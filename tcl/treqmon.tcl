# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require Thread

namespace eval ::treqmon {

    variable worker_thread_id

    variable default_config {
        tpool {
            -minworkers 1
            -maxworkers 4
            -idletime 30
        }
        worker {
            -output {
                console {
                    threshold 100
                }
            }
            -history_max_events 1000000
        }
    }

    array set last_seconds_by_interval {
        second 60
        minute 3600
        hour   86400
        day    86400
    }

    array set seconds_by_interval {
        second 1
        minute 60
        hour   3600
        day    86400
    }

}

proc ::treqmon::init { {config {}} } {

    variable default_config
    variable worker_thread_id

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

    set initcmd [join [list \
        [list package require treqmon] \
        [list ::treqmon::worker::init $worker_config] \
        [list ::thread::wait]] "\n"]

    #puts initcmd=$initcmd
#    dict set tpool_config -initcmd $initcmd
#    set tpool_id [tpool::create {*}$tpool_config]

    set worker_thread_id [thread::create -preserved $initcmd]
    return $worker_thread_id
}

proc ::treqmon::filter_events {events now_in_seconds {from_seconds ""} {to_seconds ""}} {

    if { $from_seconds ne {} && ![string is integer -strict $from_seconds] } {
        error "from_seconds must be an integer"
    } elseif { $from_seconds ne {} && $from_seconds < 0 } {
        set from_seconds [expr { $now_in_seconds + $from_seconds }]
    }

    if { $to_seconds ne {} && ![string is integer -strict $to_seconds] } {
        error "to_seconds must be an integer"
    } elseif { $to_seconds ne {} && $to_seconds < 0 } {
        set to_seconds [expr { $now_in_seconds + $to_seconds }]
    }

    set result [list]
    foreach ev $events {
        lassign $ev timestamp duration
        if { $from_seconds ne {} && $timestamp < $from_seconds } {
            continue
        }
        if { $to_seconds ne {} && $timestamp > $to_seconds } {
            continue
        }
        lappend result $ev
    }
    return $result

}

# Get the history of events
# The function takes two optional arguments: from_seconds and to_seconds.
# If the arguments are not specified, the function returns all events.
# If the arguments are specified, the function returns events that fall
# within the specified time interval.
#
# Example:
#     set events {
#         { 100 1 }
#         { 200 2 }
#         { 300 3 }
#         { 400 4 }
#         { 500 5 }
#         { 600 6 }
#     }
#     set result [get_history_events 200 500]
#     # The result will be:
#     #     { 200 2 }
#     #     { 300 3 }
#     #     { 400 4 }
#     #     { 500 5 }
#     set result [get_history_events]
#     # The result will be:
#     #     { 100 1 }
#     #     { 200 2 }
#     #     { 300 3 }
#     #     { 400 4 }
#     #     { 500 5 }
#     #     { 600 6 }
#
proc ::treqmon::get_history_events {{now_in_seconds ""} {from_seconds ""} {to_seconds ""} } {
    variable ::treqmon::middleware::global_thread_id

    if { $now_in_seconds eq {} } {
        set now_in_seconds [clock seconds]
    }

    set history_events [thread::send $global_thread_id [list ::treqmon::worker::get_history_events]]
    set result [filter_events $history_events $now_in_seconds $from_seconds $to_seconds]

    return $result
}

# Split events by interval
# The function takes a list of events and an interval (second, minute, hour, day)
# and returns a dictionary where the keys are the timestamps of the beginning of
# the interval and the values are lists of events that fall into this interval.
# The events are sorted by timestamp.
#
# Example:
#     set events {
#         { 100 1 }
#         { 200 2 }
#         { 300 3 }
#         { 400 4 }
#         { 500 5 }
#         { 600 6 }
#     }
#     set result [split_by_interval $events minute]
#     # The result will be:
#     #     0 { { 100 1 } { 200 2 } }
#     #     300 { { 300 3 } { 400 4 } }
#     #     600 { { 500 5 } { 600 6 } }
#
proc ::treqmon::split_by_interval { events interval} {

    if { $interval ni {second minute hour day} } {
        return -code error "unknown interval \"$interval\", should be second, minute, hour or day"
    }

    variable seconds_by_interval

    set interval_seconds $seconds_by_interval($interval)

    array set result [list]
    foreach ev $events {
        # timestamp is in seconds
        lassign $ev timestamp duration
        set key [expr { $timestamp - ($timestamp % $interval_seconds) }]
        lappend result($key) $ev
    }

    foreach k [array names result] {
        set result($k) [lsort -integer -index 0 $result($k)]
    }

    return [array get result]
}


proc ::treqmon::max_k_page_views {top_k events} {
    set sorted_events [lsort -integer -stride 2 -index {1 1} -decreasing $events]
    set values [lmap {k v} $sorted_events { set v }]
    return [lrange $values 0 [expr { $top_k - 1}]]
}

# Get the number of page views for all given intervals
# The function takes three arguments: events, now_in_seconds and intervals (optional)
# If the intervals are not specified, the function returns the number of page views
# for all intervals (second, minute, hour).
# If the intervals are specified, the function returns the number of page views
# for the specified intervals.
#
proc ::treqmon::get_page_views { events {now_in_seconds ""} {intervals "second minute hour"} {top_k "5"}} {
    variable last_seconds_by_interval
    variable seconds_by_interval

    if { $now_in_seconds eq {} } {
        set now_in_seconds [clock seconds]
    }

    set result [list]
    foreach interval $intervals {

        set xmax [expr { $now_in_seconds - ($now_in_seconds % $seconds_by_interval($interval)) + $seconds_by_interval($interval) }]
        set xmin [expr { $xmax - $last_seconds_by_interval($interval) }]
        set xrange [list $xmin $xmax]

        set filtered_events [filter_events $events $now_in_seconds "-$last_seconds_by_interval($interval)"]
        set filtered_events_by_interval [::treqmon::split_by_interval $filtered_events $interval]
        set page_views_for_chart [dict map { k v } $filtered_events_by_interval {list $k [llength $v]}]

        set events_by_interval [::treqmon::split_by_interval $events $interval]
        set page_views_for_top_k [dict map { k v } $events_by_interval {list $k [llength $v]}]

        lappend result $interval [list \
            xrange $xrange \
            page_views $page_views_for_chart \
            top_k $top_k \
            top_k_views [max_k_page_views $top_k $page_views_for_top_k]]
    }

    return $result
}

proc ::treqmon::avg_response_time {events} {
    set sum 0
    foreach ev $events {
        lassign $ev timestamp duration
        if { ![string is integer -strict $duration] } {
            puts "duration must be an integer: $duration"
            continue
        }
        incr sum $duration
    }
    set len [llength $events]
    if { $len == 0 } {
        return 0
    }
    return [expr { $sum / $len }]
}

proc ::treqmon::max_k_response_times {top_k events} {
    set sorted_events [lsort -integer -stride 2 -index {1 1} -decreasing $events]
    set values [lmap {k v} $sorted_events { set v }]
    return [lrange $values 0 [expr { $top_k - 1}]]
}

# Get the average response time for all given intervals
# The function takes two arguments: events and intervals (optional)
# If the intervals are not specified, the function returns the average response time
# for all intervals (second, minute, hour).
# If the intervals are specified, the function returns the average response time
# for the specified intervals.
#
# Example:
#     set events {
#         { 100 1 }
#         { 200 2 }
#         { 300 3 }
#         { 400 4 }
#         { 500 5 }
#         { 600 6 }
#     }
#     set events [get_history_events 200 500]
#     set result [get_response_times $events {second minute}]
#     # The result will be:
#     #     second { { 200 2 } { 300 3 } { 400 4 } { 500 5 } }
#     #     minute { { 200 2 } { 400 5.5 } }
#
proc ::treqmon::get_response_times {events {now_in_seconds ""} {intervals "second minute hour"} {top_k "5"}} {
    variable last_seconds_by_interval
    variable seconds_by_interval

    if { $now_in_seconds eq {} } {
        set now_in_seconds [clock seconds]
    }

    set result [list]
    foreach interval $intervals {
        set filtered_events [filter_events $events $now_in_seconds "-$last_seconds_by_interval($interval)"]
        set xmax [expr { $now_in_seconds - ($now_in_seconds % $seconds_by_interval($interval)) + $seconds_by_interval($interval) }]
        set xmin [expr { $xmax - $last_seconds_by_interval($interval) }]
        set xrange [list $xmin $xmax]
        set events_by_interval [::treqmon::split_by_interval $filtered_events $interval]
        set response_times [dict map { k v } $events_by_interval { list $k [avg_response_time $v] }]
        lappend result $interval [list \
            xrange $xrange \
            response_times $response_times \
            top_k $top_k \
            top_k_times [max_k_response_times $top_k $response_times]]
    }
    return $result
}

proc ::treqmon::get_summary {events {now_in_seconds ""}} {

    if { $now_in_seconds eq {} } {
        set now_in_seconds [clock seconds]
    }

    set last_minute_events [filter_events $events $now_in_seconds "-60"]
    set last_half_hour_events [filter_events $events $now_in_seconds "-[expr { 30 * 60 }]"]
    set last_hour_events [filter_events $events $now_in_seconds "-3600"]
    set last_day_events [filter_events $events $now_in_seconds "-86400"]

    set last_minute_avg_response_time [avg_response_time $last_minute_events]
    set last_half_hour_avg_response_time [avg_response_time $last_half_hour_events]
    set last_hour_avg_response_time [avg_response_time $last_hour_events]
    set last_day_avg_response_time [avg_response_time $last_day_events]

    set result [list]
    lappend result last_minute_avg_response_time $last_minute_avg_response_time
    lappend result last_half_hour_avg_response_time $last_half_hour_avg_response_time
    lappend result last_hour_avg_response_time $last_hour_avg_response_time
    lappend result last_day_avg_response_time $last_day_avg_response_time
    return $result
}

proc ::treqmon::shutdown {} {
    variable worker_thread_id
    return [thread::release $worker_thread_id]
}