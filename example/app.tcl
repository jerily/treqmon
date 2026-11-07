# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package require twebserver
package require treqmon

set store "tsvstore"
if { $store eq {valkeystore} } {
    set treqmon_store "valkeystore"
    set treqmon_store_config {
        host "localhost"
        port 6379
        ssl true
        username appuser
        password "replace-with-your-password"
    }
} elseif { $store eq {tsvstore} } {
    set treqmon_store "tsvstore"
    set treqmon_store_config {}
} elseif { $store eq {memstore} } {
    set treqmon_store "memstore"
    set treqmon_store_config {}
} else {
    error "Unknown store \"$store\""
}

set treqmon_logfile_path [file normalize [file join [file dirname [info script]] logs access.log]]
set treqmon_config {
    store {}
    logger {}
}

dict set treqmon_store_config history_max_events 1000000
dict set treqmon_config store $treqmon_store $treqmon_store_config

dict set treqmon_config logger console [list threshold 10]
#dict set treqmon_config logger logfile [list \
#    threshold 100 \
#    path $treqmon_logfile_path]

set treqmon_middleware_config [::treqmon::init_main $treqmon_config]

set tsession_config {
    save_uninitialized 0
    cookie_insecure 1
    store {
        MemoryStore {}
    }
}


# Example-only key material lives in session-keyset.json.
set channel [open [file join [file dirname [info script]] session-keyset.json] r]
try {dict set tsession_config hmac_keyset [read $channel]} finally {close $channel}

set init_script [list source [file normalize [file join [file dirname [info script]] init-thread.tcl]]]

set config_dict [dict create \
    rootdir [file dirname [info script]] \
    gzip on \
    gzip_types [list text/html text/plain application/json] \
    gzip_min_length 8192 \
    conn_timeout_millis 10000 \
    treqmon $treqmon_middleware_config \
    tsession $tsession_config]

set server_handle [::twebserver::create_server $config_dict process_conn $init_script]
::twebserver::listen_server -http -num_threads 4 $server_handle 8080

puts "Server is running, go to http://localhost:8080/"

::twebserver::wait_signal
::twebserver::destroy_server $server_handle
::treqmon::shutdown_main
