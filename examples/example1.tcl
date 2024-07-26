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
        set data [dict merge $req [list stats $stats page_view_stats $page_view_stats response_time_stats $response_time_stats]]
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
