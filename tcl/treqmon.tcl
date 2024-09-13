# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

namespace eval ::treqmon {

    variable config {
        store {}
        logger {}
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

proc ::treqmon::init_main {{config_dict {}}} {

    variable config

    set config [dict merge $config $config_dict]

    # Validate specified configuration
    foreach key [dict keys $config] {
        if { $key ni { store logger } } {
            error "unknown key in configuration dictionary \"$key\""
        }
    }

    set config_store_section [dict get $config store]
    set config_logger_section [dict get $config logger]

    if { [dict size $config_store_section] != 1 } {
        error "store section must contain exactly one key"
    }

    set output_config [dict create]

    dict for {store store_config} $config_store_section {
        ${store}::init_main output_config $store_config
    }

    dict for {logger logger_config} $config_logger_section {
        ${logger}::init_main output_config $logger_config
    }

    return $output_config
}

proc ::treqmon::init_middleware {config} {
    middleware::init $config
}

# Filter Events
#
# filter_events accepts a list of events, a boolean active_session, a timestamp now_in_seconds,
# and two optional arguments from_seconds and to_seconds.
# The function returns a list of events that satisfy the following conditions:
# - If from_seconds is specified, the function keeps only events with a timestamp greater than or equal to from_seconds.
# - If to_seconds is specified, the function keeps only events with a timestamp less than or equal to to_seconds.
# - If active_session is true, the function keeps only events with a session_id.
# - If active_session is false, the function keeps only events without a session_id.
# - If active_session is not specified, the function keeps all events.
#
proc ::treqmon::filter_events {events active_session now_in_seconds {from_seconds ""} {to_seconds ""}} {

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
        lassign $ev timestamp duration session_id
        if { $from_seconds ne {} && $timestamp < $from_seconds } {
            continue
        }
        if { $to_seconds ne {} && $timestamp > $to_seconds } {
            continue
        }
        if { $active_session ne {} } {
            # active_session is a boolean
            # if active_session is true, we want to keep only events with session_id
            # if active_session is false, we want to keep only events without session_id
            if { (!$active_session && $session_id ne {}) || ($active_session && $session_id eq {}) } {
                continue
            }
        }
        lappend result $ev
    }
    return $result

}

# Get the history of events
#
# get_history_events invokes the middleware to get the history of events
# and then filters the events based on the active_session, now_in_seconds, from_seconds and to_seconds.
#
proc ::treqmon::get_history_events {{active_session ""} {now_in_seconds ""} {from_seconds ""} {to_seconds ""} } {
    if { $now_in_seconds eq {} } {
        set now_in_seconds [clock seconds]
    }

    set history_events [::treqmon::middleware::get_history_events]
    set result [filter_events $history_events $active_session $now_in_seconds $from_seconds $to_seconds]

    return $result
}

# Split events by interval
#
# split_by_interval accepts a list of events and an interval.
# The function returns a dictionary where the keys are the timestamps of the events
# rounded to the nearest interval and the values are lists of events that fall into the same interval.
#
proc ::treqmon::split_by_interval {events interval} {

    if { $interval ni {second minute hour day} } {
        return -code error "unknown interval \"$interval\", should be second, minute, hour or day"
    }

    variable seconds_by_interval

    set interval_seconds $seconds_by_interval($interval)

    array set result [list]
    foreach ev $events {
        # timestamp is in seconds
        lassign $ev timestamp duration session_id
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
# The function takes four arguments: events, now_in_seconds, intervals (optional) and top_k (optional)
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

        set filtered_events [filter_events $events "" $now_in_seconds "-$last_seconds_by_interval($interval)"]
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
# The function takes four arguments: events, now_in_seconds, intervals (optional) and top_k (optional)
# If the intervals are not specified, the function returns the average response time
# for all intervals (second, minute, hour).
# If the intervals are specified, the function returns the average response time
# for the specified intervals.
# The function also returns the top_k response times for each interval.
# The top_k response times are the k largest response times for each interval.
#
proc ::treqmon::get_response_times {events {now_in_seconds ""} {intervals "second minute hour"} {top_k "5"}} {
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

        set filtered_events [filter_events $events "" $now_in_seconds "-$last_seconds_by_interval($interval)"]
        set filtered_events_by_interval [::treqmon::split_by_interval $filtered_events $interval]
        set response_times_for_chart [dict map { k v } $filtered_events_by_interval { list $k [avg_response_time $v] }]

        set events_by_interval [::treqmon::split_by_interval $events $interval]
        set response_times_for_top_k [dict map { k v } $events_by_interval { list $k [avg_response_time $v] }]

        lappend result $interval [list \
            xrange $xrange \
            response_times $response_times_for_chart \
            top_k $top_k \
            top_k_times [max_k_response_times $top_k $response_times_for_top_k]]
    }
    return $result
}

proc ::treqmon::max_k_active_users {top_k events} {
    set sorted_events [lsort -integer -stride 2 -index {1 1} -decreasing $events]
    set values [lmap {k v} $sorted_events { set v }]
    return [lrange $values 0 [expr { $top_k - 1}]]
}

proc ::treqmon::filter_with_session {v} {
    set filtered_v [list]
    foreach ev $v {
        lassign $ev timestamp duration session_id
        if { $session_id ne {} } {
            lappend filtered_v $ev
        }
    }
    return $filtered_v
}

proc ::treqmon::get_active_users { events {now_in_seconds ""} {intervals "second minute hour"} {top_k "5"}} {
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

        set active_session "1"
        set filtered_events [filter_events $events $active_session $now_in_seconds "-$last_seconds_by_interval($interval)"]
        set filtered_events_by_interval [::treqmon::split_by_interval $filtered_events $interval]
        set active_users_for_chart [dict map { k v } $filtered_events_by_interval {list $k [llength [lsort -unique -index 2 [filter_with_session $v]]]}]


        set events [filter_events $events $active_session $now_in_seconds]
        set events_by_interval [::treqmon::split_by_interval $events $interval]
        set active_users_for_top_k [dict map { k v } $events_by_interval {list $k [llength [lsort -unique -index 2 [filter_with_session $v]]]}]

        lappend result $interval [list \
            xrange $xrange \
            active_users $active_users_for_chart \
            top_k $top_k \
            top_k_users [max_k_active_users $top_k $active_users_for_top_k]]
    }

    return $result
}

proc ::treqmon::get_summary {events {now_in_seconds ""}} {

    if { $now_in_seconds eq {} } {
        set now_in_seconds [clock seconds]
    }

    set last_minute_events [filter_events $events "" $now_in_seconds "-60"]
    set last_half_hour_events [filter_events $events "" $now_in_seconds "-[expr { 30 * 60 }]"]
    set last_hour_events [filter_events $events "" $now_in_seconds "-3600"]
    set last_day_events [filter_events $events "" $now_in_seconds "-86400"]

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

proc ::treqmon::shutdown_main {} {
    variable config

    set config_store_section [dict get $config store]
    set config_logger_section [dict get $config logger]

    dict for {store store_config} $config_store_section {
        ${store}::shutdown_main
    }

    dict for {logger logger_config} $config_logger_section {
        ${logger}::shutdown_main
    }
}
