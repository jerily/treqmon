package require twebserver
package require treqmon 2.2.0
package require jinja2
package require tsession

set channel [open [file join [::twebserver::get_rootdir] www app.html.jinja] r]
try {set page_template [read $channel]} finally {close $channel}

set config_dict [::twebserver::get_config_dict]

::treqmon::init_middleware [dict get $config_dict treqmon]
::tsession::init [dict get $config_dict tsession]

set router [::tpathexp::router]
::treqmon::mount $router -prefix /stats -include_active_users true \
    -config [dict create master_template $page_template]
$router add_middleware -enter_proc ::tsession::enter -leave_proc ::tsession::leave
foreach {method path handler} {
    GET / get_index_handler
    POST /login post_login_handler
    POST /logout post_logout_handler
    GET /:type(css|js)/:path(.*) get_assets_handler
    GET /:path(.*) get_catchall_handler
} {
    $router add $method $path [list invoke $handler] -strict true
}

proc invoke {handler request context params} {$handler $context $request}

proc process_conn {context request} {
    dict set request method [dict get $request httpMethod]
    set response [$::router dispatch $request $context]
    ::twebserver::return_response [dict get $context conn] $response
}

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

proc get_catchall_handler {ctx req} {
    return [::twebserver::build_response 404 "text/plain" "not found"]
}
