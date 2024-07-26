# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require twebserver
package require treqmon

set pool_config [::treqmon::init {}]
puts "pool_config=$pool_config"

set init_script {

    package require twebserver
    package require treqmon
    package require thtml
    package require tjson

    ::thtml::init [dict create \
        debug 1 \
        cache 0 \
        target_lang tcl \
        rootdir [::twebserver::get_rootdir] \
        cachedir "/tmp/cache/thtml/"]

    ::twebserver::create_router router

    ::twebserver::add_middleware \
        -enter_proc ::treqmon::enter \
        -leave_proc ::treqmon::leave \
        $router

    ::twebserver::add_route $router GET "/stats" get_stats_handler
    ::twebserver::add_route $router GET "*" get_catchall_handler

    interp alias {} process_conn {} $router

    proc get_stats_handler {ctx req} {
        set stats [::treqmon::statistics \
                      -count_second \
                      -count_minute \
                      -count_hour \
                      -count_day \
                      -average_second \
                      -average_minute \
                      -average_hour \
                      -average_day \
                      [clock seconds]]

        set events [::treqmon::get_history_events]
        set page_view_stats [::treqmon::get_page_views $events]
        set response_time_stats [::treqmon::get_response_times $events]

        set minute_stats_dict [dict get $page_view_stats minute]
        set minute_stats [dict get $minute_stats_dict page_views]
        set minute_xrange [dict get $minute_stats_dict xrange]

        set page_view_stats_minute_labels [dict keys $minute_stats]

        lassign $minute_xrange xmin xmax
        set max_label $xmax
        set min_label $xmin

        # create all labels from min to max by adding 60 seconds to each
        set page_view_stats_minute_labels [list]
        set current_label $min_label
        while { $current_label <= $max_label } {
            lappend page_view_stats_minute_labels [list $current_label]
            set current_label [expr {$current_label + 60}]
        }

        # now fill with zeros the missing values
        set page_view_stats_minute_data [list]
        foreach label $page_view_stats_minute_labels {
            if { [dict exists $minute_stats $label] } {
                lassign [dict get $minute_stats $label] timestamp count
                lappend page_view_stats_minute_data $count
            } else {
                lappend page_view_stats_minute_data 0
            }
        }

        # insert S before each element in the labels list
        set page_view_stats_minute_labels_typed [lmap x $page_view_stats_minute_labels {list S [clock format $x]}]

        # insert N before each element in the data list
        set page_view_stats_minute_data_typed [lmap x $page_view_stats_minute_data {list N $x}]

        set dataset_typed [list M [list \
            label {S "Page Views per Minute"} \
            data [list L $page_view_stats_minute_data_typed] \
            backgroundColor {S "rgba(255, 99, 132, 0.2)"} \
            borderColor {S "rgba(255, 99, 132, 1)"} \
            borderWidth {N 1} \
        ]]

        set data_typed [list M [list \
           labels [list L $page_view_stats_minute_labels_typed] \
           datasets [list L [list $dataset_typed]] \
       ]]

        ::tjson::create [list M [list \
            type {S line} \
            data $data_typed \
            options {M {scales {M {y {M {beginAtZero {BOOL 1}}}}}}}]] \
            chart_config_node

        set data [dict merge $req \
            [list \
                stats $stats \
                page_view_stats $page_view_stats \
                chart_config [::tjson::to_json $chart_config_node] \
                response_time_stats $response_time_stats]]

        set html [::thtml::renderfile stats.thtml $data]
        set res [::twebserver::build_response 200 text/html $html]
        return $res
    }

    proc get_catchall_handler {ctx req} {
        set res [::twebserver::build_response 200 text/plain "Hello [dict get $req path]"]
        return $res
    }

}

set config_dict [dict create \
    rootdir [file dirname [info script]] \
    gzip on \
    gzip_types [list text/html text/plain application/json] \
    gzip_min_length 8192 \
    conn_timeout_millis 10000 \
    treqmon $pool_config]

set server_handle [::twebserver::create_server -with_router $config_dict process_conn $init_script]
::twebserver::listen_server -http -num_threads 4 $server_handle 8080

puts "Server is running, go to http://localhost:8080/"

::twebserver::wait_signal
::twebserver::destroy_server $server_handle
