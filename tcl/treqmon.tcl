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
        worker {
            -output {
                console {
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

    ::treqmon::worker::validate_config $worker_config

    tsv::set ::treqmon workerConfig $worker_config

    dict set tpool_config -initcmd [list package require treqmon]

    tsv::set ::treqmon workerPoolId [tpool::create {*}$tpool_config]

}

proc ::treqmon::enter { ctx req } {
    dict set req treqmon timestamp [clock microseconds]
    return $req
}

proc ::treqmon::leave { ctx req res } {
    dict set res treqmon timestamp [clock microseconds]
    dict set ctx treqmon thread_id [thread::id]
    if { [tsv::get ::treqmon workerPoolId poolId] } {
        ::tpool::post -detached -nowait $poolId \
            [list ::treqmon::worker::register_event $ctx [filter_body $req] [filter_body $res]]
    }
    return $res
}

# This function filters the "body" field in the dictionary and replaces it
# with "body_size", corresponding to the size of the deleted body field.
# The "body" field can be very large in size. With this procedure,
# we won't be transferring large amounts of memory between threads.
proc ::treqmon::filter_body { d } {
    if { ![dict exists $d body] } {
        return $d
    }
    dict set d body_size [string length [dict get $d body]]
    dict unset d body
    return $d
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

    if { $now_in_seconds eq {} } {
        set now_in_seconds [clock seconds]
    }

    if { ![tsv::get ::treqmon::worker::history events history_events] } {
        # error "Failed to retrieve events"
        set history_events [list]
    }

    set events [lsort -integer -index 0 $history_events]
    return [filter_events $events $now_in_seconds $from_seconds $to_seconds]
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

    set result [dict create]
    foreach ev $events {
        # timestamp is in seconds
        lassign $ev timestamp duration
        set key [expr { $timestamp - ($timestamp % $interval_seconds) }]
        if { [dict exists $result $key] } {
            set evs [dict get $result $key]
        } else {
            set evs [list]
        }
        set evs [lsort -integer -index 0 [lappend evs $ev]]
        dict set result $key $evs
    }
    return $result
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
    return [expr { $sum / [llength $events] }]
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

proc ::treqmon::statistics_series { args } {

    # Check if the last argument is a relative time
    set timestamp_current [lindex $args end]
    if { $timestamp_current eq "now" || [string is integer -strict $timestamp_current] } {
        # Remove the last argument from the argument list
        set args [lreplace $args end end]
    } else {
        set timestamp_current "now"
    }

    if { $timestamp_current eq "now" } {
        set timestamp_current [clock seconds]
    }

    # Max number of events in the heavy_requests list
    set heavy_requests_max_count 5
    # The default interval
    set interval "minute"

    for { set i 0 } { $i < [llength $args] } { incr i } {
        set arg [lindex $args $i]
        if { $arg ni {-interval -heavy_requests} } {
            return -code error "unknown option \"$arg\", must be\
                -interval or -heavy_requests"
        }
        incr i
        if { $i == [llength $args] } {
            return -code error "missing value for option \"$arg\""
        }
        if { $arg eq "-interval" } {
            set interval [lindex $args $i]
            if { $interval ni {minute hour day} } {
                return -code error "unknown interval \"$interval\",\
                    should be minute, hour or day"
            }
        } else {
            set heavy_requests_max_count [lindex $args $i]
            if { ![string is integer -strict $heavy_requests_max_count] } {
                return -code error "option -heavy_requests requires an integer\
                    value, but got \"$heavy_requests_max_count\""
            }
        }

    }

    if { $interval eq "minute" } {
        set timestamp_end [expr { $timestamp_current - 60 + 1 }]
        # interval is 1 second
        set interval 1
    } elseif { $interval eq "hour" } {
        set timestamp_end [expr { $timestamp_current - 60*60 + 1 }]
        # interval is 1 minute
        set interval 60
    } elseif { $interval eq "day" } {
        set timestamp_end [expr { $timestamp_current - 24*60*60 + 1 }]
        # interval is 1 hour
        set interval [expr { 60*60 }]
    }

    # Getting the request statistics into a variable so as not to block
    # other threads from adding new records.
    if { ![tsv::get ::treqmon::worker::history events events] } {
        # Failed to retrieve events. Let's use an empty list.
        set events [list]
    }

    # Initialize series dict.
    #     count - number of events
    #     average - average response time
    #     duration_max - max request duration
    #     duration_min - min request duration
    for { set i $timestamp_current } { $i >= $timestamp_end } { incr i -$interval } {
        dict set series $i [dict create {*}{
            count 0
            average 0
            duration_max -1
            duration_min -1
        }]
    }

    set heavy_requests [list]

    set events [lreverse $events]
    foreach ev $events {

        lassign $ev timestamp duration

        # Skip events registered before the time stamp of interest.
        if { $timestamp > $timestamp_current } {
            continue
        }

        if { $timestamp < $timestamp_end } {
            break
        }

        # squash the timestamp to the required interval
        if { $interval > 1 } {
            set x [expr { ($timestamp_current - $timestamp) / $interval }]
            set timestamp [expr { $timestamp_current - $x * $interval }]
        }

        # Calculate total number of events for the current timestamp
        dict set series $timestamp count [set count [expr { [dict get $series $timestamp count] + 1 }]]

        # Calculate average duration for the current timestamp
        dict set series $timestamp average [expr \
            { 1.0 * ((1.0 * [dict get $series $timestamp average] * ($count - 1)) + $duration) / $count }]

        set max [dict get $series $timestamp duration_max]
        if { $max == -1 || $max < $duration } {
            dict set series $timestamp duration_max $duration
        }

        set min [dict get $series $timestamp duration_min]
        if { $min == -1 || $min > $duration } {
            dict set series $timestamp duration_min $duration
        }

        if { [llength $heavy_requests] < $heavy_requests_max_count } {

            lappend heavy_requests $ev
            # Keep the list sorted
            set heavy_requests [lsort -integer -index 1 -decreasing $heavy_requests]

        } else {

            set min_duration [lindex $heavy_requests {end 1}]

            if { $duration > $min_duration } {
                # If the duration of the current event is longer than the minimum
                # duration in heavy_requests_min, then add this event to
                # heavy_requests_min.

                # Our heavy_requests list is sorted in decreasing order. Replace
                # the last element as it is the element with the shortest duration.
                set heavy_requests [lreplace $heavy_requests end end $ev]

                # Keep the list sorted
                set heavy_requests [lsort -integer -index 1 -decreasing $heavy_requests]
            }

        }

    }

    set sum [dict create {*}{
        count 0
        count_min -1
        count_max -1
        average_max -1
        average_min -1
        duration_max -1
        duration_min -1
    }]
    # round all average values and calculate summary
    dict for { k v } $series {

        # skip entry if its counter is zero
        if { ![dict get $v count] } {
            continue
        }

        dict set v average [expr { round([dict get $v average]) }]
        dict set series $k $v

        dict incr sum count [dict get $v count]

        if { [dict get $sum count_max] == -1 || [dict get $v count] > [dict get $sum count_max] } {
            dict set sum count_max [dict get $v count]
        }
        if { [dict get $sum count_min] == -1 || [dict get $v count] < [dict get $sum count_min] } {
            dict set sum count_min [dict get $v count]
        }

        if { [dict get $sum average_max] == -1 || [dict get $v average] > [dict get $sum average_max] } {
            dict set sum average_max [dict get $v average]
        }
        if { [dict get $sum average_min] == -1 || [dict get $v average] < [dict get $sum average_min] } {
            dict set sum average_min [dict get $v average]
        }

        if { [dict get $sum duration_max] == -1 || [dict get $v duration_max] > [dict get $sum duration_max] } {
            dict set sum duration_max [dict get $v duration_max]
        }
        if { [dict get $sum duration_min] == -1 || [dict get $v duration_min] < [dict get $sum duration_min] } {
            dict set sum duration_min [dict get $v duration_min]
        }

    }

    return [dict create series $series heavy_requests $heavy_requests summary $sum]

}

proc ::treqmon::statistics { args } {

    # Time window in seconds for which we want to get statistics.
    # It is necessary not to look through all statistics, but only a specified
    # interval (for example, last second or last minute).
    set time_window 0

    # A list of metrics to be returned, and in the order in which they
    # appear in the arguments.
    set metric_interval_list [list]

    # Known time intervals
    array set intervals {
        second 0
        minute 59
        hour   3599
        day    86399
    }

    unset -nocomplain timestamp_current

    # Check if the last argument is a relative time
    set timestamp_current [lindex $args end]
    if { $timestamp_current eq "now" || [string is integer -strict $timestamp_current] } {
        # Remove the last argument from the argument list
        set args [lreplace $args end end]
    } else {
        set timestamp_current "now"
    }

    if { $timestamp_current eq "now" } {
        set timestamp_current [clock seconds]
    }

    foreach arg $args {
        lassign [split [string trimleft $arg -] _] metric interval
        if { $metric ni {count average} || $interval ni {second minute hour day} } {
            return -code error "unknown metric type \"$arg\""
        }
        dict set metric_count $interval $metric 0

        lappend metric_interval_list [list $metric $interval]

        set interval $intervals($interval)
        if { $interval > $time_window } {
            set time_window $interval
        }
    }

    # Getting the request statistics into a variable so as not to block
    # other threads from adding new records.
    if { ![tsv::get ::treqmon::worker::history events events] } {
        # Failed to retrieve events. Let's use an empty list.
        set events [list]
    }

    set events [lreverse $events]
    set count 0
    foreach ev $events {

        lassign $ev timestamp duration

        if { $timestamp > $timestamp_current } {
            continue
        }

        # The age of the current record in seconds.
        set age [expr { $timestamp_current - $timestamp }]
        # First, check to make sure we haven't reached a timestamp outside
        # of our time window.
        if { $age > $time_window } {
            break
        }

        foreach interval [array names intervals] {
            # Do we have metrics that need to be calculated within the interval?
            if { $age <= $intervals($interval) && [dict exists $metric_count $interval] } {
                if { [dict exists $metric_count $interval count] } {
                    dict set metric_count $interval count [expr \
                        { [dict get $metric_count $interval count] + 1 }]
                }
                if { [dict exists $metric_count $interval average] } {
                    dict set metric_count $interval average [expr \
                        { 1.0 * ((1.0 * [dict get $metric_count $interval average] * $count) + $duration) / ($count + 1) }]
                }
            }
        }

        incr count

    }

    # Generate results
    set result [dict create]
    foreach metric_interval_pair $metric_interval_list {
        lassign $metric_interval_pair metric interval
        dict set result [join $metric_interval_pair {_}] [expr { round([dict get $metric_count $interval $metric]) }]
    }
    return $result

}

