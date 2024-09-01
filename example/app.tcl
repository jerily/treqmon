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
        password "foobared"
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
    hmac_keyset {{"primaryKeyId": 691856985, "key": [{"keyData": {"typeUrl": "type.googleapis.com/google.crypto.tink.HmacKey","keyMaterialType": "SYMMETRIC","value": "EgQIAxAgGiDZsmkTufMG/XlKlk9m7bqxustjUPT2YULEVm8mOp2mSA=="},"outputPrefixType": "TINK","keyId": 691856985,"status": "ENABLED"}]}}
    save_uninitialized 0
    cookie_insecure 1
    store {
        MemoryStore {}
    }
}


set init_script {
    package require twebserver
    package require treqmon
    package require thtml
    package require tsession

    ::thtml::init [dict create \
        debug 1 \
        cache 1 \
        rootdir [::twebserver::get_rootdir] \
        bundle_outdir [file join [::twebserver::get_rootdir] public bundle]]

    set config_dict [::twebserver::get_config_dict]

    ::treqmon::init_middleware [dict get $config_dict treqmon]
    ::tsession::init [dict get $config_dict tsession]

    ::twebserver::create_router -command_name process_conn router

    ::twebserver::add_middleware \
        -enter_proc ::treqmon::middleware::enter \
        -leave_proc ::treqmon::middleware::leave \
        $router

    ::twebserver::add_middleware \
        -enter_proc ::tsession::enter \
        -leave_proc ::tsession::leave \
        $router

    ::twebserver::add_route -strict $router GET / get_index_handler
    ::twebserver::add_route -strict $router POST /login post_login_handler
    ::twebserver::add_route -strict $router POST /logout post_logout_handler
    ::twebserver::add_route -prefix $router GET /(css|js|assets|bundle)/ get_assets_handler
    ::twebserver::add_route $router GET "/stats" get_stats_handler
    ::twebserver::add_route $router GET "*" get_catchall_handler

    proc get_index_handler {ctx req} {
        set loggedin [dict exists $req session loggedin]

        set html [subst -nocommands -nobackslashes {
            <html><body>
                <p>Logged In: $loggedin</p>
                <p><form method=post action=/login><button>Login</button></form></p>
                <p><form method=post action=/logout><button>Logout</button></form></p>
                <p><a href=/stats>Stats</a></p>
            </body></html>
        }]
        return [::twebserver::build_response 200 text/html $html]
    }

    proc post_login_handler {ctx req} {
        set res [::twebserver::build_redirect 302 /]
        ::tsession::amend_session_with_changes res loggedin true
        return $res
    }

    proc post_logout_handler {ctx req} {
        set res [::twebserver::build_redirect 302 /]
        ::tsession::mark_session_to_be_destroyed res
        return $res
    }

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
        return [::twebserver::build_response 404 "text/plain" "not found"]
    }

}

set config_dict [dict create \
    rootdir [file dirname [info script]] \
    gzip on \
    gzip_types [list text/html text/plain application/json] \
    gzip_min_length 8192 \
    conn_timeout_millis 10000 \
    treqmon $treqmon_middleware_config \
    tsession $tsession_config]

set server_handle [::twebserver::create_server -with_router $config_dict process_conn $init_script]
::twebserver::listen_server -http -num_threads 4 $server_handle 8080

puts "Server is running, go to http://localhost:8080/"

::twebserver::wait_signal
::twebserver::destroy_server $server_handle
::treqmon::shutdown_main