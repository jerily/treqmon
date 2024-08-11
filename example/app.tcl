# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require twebserver
package require treqmon

set store "tsvstore"

if { $store eq {tsvstore} } {
    set treqmon_store "tsvstore"
    set treqmon_store_config {}
} elseif { $store eq {memstore} } {
    set treqmon_store "memstore"
    set treqmon_store_config {}
} else {
    error "Unknown store \"$store\""
}


set treqmon_logfile_path [file normalize [file join [file dirname [info script]] logs access.log]]
set treqmon_config_dict {
    tpool {
        minworkers 1
        maxworkers 4
        idletime 30
    }
    worker {
        output {
        }
        history_max_events 1000000
    }
}

dict set treqmon_config_dict worker store $treqmon_store
# dict set treqmon_config_dict worker output console {}
# dict set treqmon_config_dict worker output logfile path $treqmon_logfile_path

set treqmon_worker_id [::treqmon::init_main $treqmon_config_dict]

set init_script {
    package require twebserver
    package require treqmon
    package require thtml

    ::thtml::init [dict create \
        debug 1 \
        cache 1 \
        target_lang tcl \
        rootdir [::twebserver::get_rootdir] \
        bundle_outdir [file join [::twebserver::get_rootdir] public bundle]]

    set config_dict [::twebserver::get_config_dict]

    ::treqmon::init_middleware [dict create \
        store [dict get $config_dict treqmon store] \
        worker_id [dict get $config_dict treqmon worker_id]]

    ::twebserver::create_router -command_name process_conn router

    ::twebserver::add_middleware \
        -enter_proc ::treqmon::middleware::enter \
        -leave_proc ::treqmon::middleware::leave \
        $router

    ::twebserver::add_route -prefix $router GET /(css|js|assets|bundle)/ get_assets_handler
    ::twebserver::add_route $router GET "/stats" get_stats_handler
    ::twebserver::add_route $router GET "*" get_catchall_handler

    #interp alias {} process_conn {} $router


    proc path_join {args} {
        set rootdir [file normalize [::twebserver::get_rootdir]]
        set path ""
        foreach arg $args {
            set parts [file split $arg]
            foreach part $parts {
                if { $part eq {..} } {
                    error "path_join: path \"$arg\" contains \"..\""
                }
                append path "/" $part
            }
        }
        set normalized_path [file normalize $path]
        if { [string range $normalized_path 0 [expr { [string length $rootdir] - 1}]] ne $rootdir } {
            error "path_join: path \"$normalized_path\" is not under rootdir \"$rootdir\""
        }
        return $normalized_path
    }

    proc get_assets_handler {ctx req} {
        set path [dict get $req path]
        set dir [file normalize [::thtml::get_rootdir]]
        set filepath [path_join $dir public $path]
    #    puts filepath=$filepath
        set ext [file extension $filepath]
        if { $ext eq {.css} } {
            set mimetype text/css
        } elseif { $ext eq {.js} } {
            set mimetype application/javascript
        } elseif { $ext eq {.svg} } {
            set mimetype image/svg+xml
        } else {
            error "get_assets_handler: unsupported extension \"$ext\""
        }
        set res [::twebserver::build_response -return_file 200 $mimetype $filepath]
        return $res
    }

    proc get_stats_handler {ctx req} {
        set data [dict merge $req [list bundle_js_url_prefix "/bundle" bundle_css_url_prefix "/bundle"]]
        set html [::thtml::renderfile app.thtml $data]
        set res [::twebserver::build_response 200 "text/html; charset=utf-8" $html]
        return $res
    }

    proc get_catchall_handler {ctx req} {
        set html "Hello [dict get $req path]<br /><br /><a href=\"/stats\">Stats</a>"
        set res [::twebserver::build_response 200 "text/html; charset=utf-8" $html]
        return $res
    }

}

set config_dict [dict create \
    rootdir [file dirname [info script]] \
    gzip on \
    gzip_types [list text/html text/plain application/json] \
    gzip_min_length 8192 \
    conn_timeout_millis 10000 \
    treqmon [list store $treqmon_store worker_id $treqmon_worker_id]]

set server_handle [::twebserver::create_server -with_router $config_dict process_conn $init_script]
::twebserver::listen_server -http -num_threads 4 $server_handle 8080

puts "Server is running, go to http://localhost:8080/"

::twebserver::wait_signal
::twebserver::destroy_server $server_handle
::treqmon::shutdown