package require twebserver
package require treqmon
package require jinja2
package require tsession

::treqmon::view::init
set channel [open [file join [::twebserver::get_rootdir] www app.html.jinja] r]
try {set page_template [read $channel]} finally {close $channel}
set templates [dict merge $::treqmon::view::templates [dict create app.html.jinja $page_template]]
::jinja2::validate $page_template -templates $templates -path app.html.jinja

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
::twebserver::add_route -prefix $router GET /(css|js)/ get_assets_handler
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
    set dir [file normalize [::twebserver::get_rootdir]]
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
    set fields [::treqmon::view::context [::treqmon::get_history_events] true]
    set html [::jinja2::render $::page_template [::tjson::typed_to_json [list M $fields]] \
        -templates $::templates -path app.html.jinja]
    set res [::twebserver::build_response 200 "text/html; charset=utf-8" $html]
    return $res
}

proc get_catchall_handler {ctx req} {
    return [::twebserver::build_response 404 "text/plain" "not found"]
}
