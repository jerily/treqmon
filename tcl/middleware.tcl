namespace eval ::treqmon::middleware {
    variable config {}
    variable store
    variable loggers {}
}

proc ::treqmon::middleware::init {config_dict} {
    variable config
    variable store
    variable loggers

    set config [dict merge $config $config_dict]

    dict for {store store_config} [dict get $config store] {
        ${store}::init $store_config
    }

    if {[dict exists $config logger]} {
        dict for {logger logger_config} [dict get $config logger] {
            ${logger}::init $logger_config
            lappend loggers $logger
        }
    }
}

proc ::treqmon::middleware::enter { ctx req } {
    dict set req treqmon timestamp [clock microseconds]
    return $req
}

proc ::treqmon::middleware::leave { ctx req res } {

    if { [dict exists $req session loggedin] } {
        set session_id [dict get $req session id]
    } else {
        set session_id ""
    }

    set event [dict create \
        session_id           $session_id \
        remote_addr          [dict get $ctx addr] \
        remote_hostname      [dict get $ctx addr] \
        remote_logname       "-" \
        remote_user          "-" \
        server_port          [dict get $ctx port] \
        server_pid           [pid] \
        request_first_line   "[dict get $req httpMethod] [dict get $req url] [dict get $req version]" \
        request_protocol     [dict get $req version] \
        request_headers      [dict get $req headers] \
        request_method       [dict get $req httpMethod] \
        request_query        [dict get $req queryString] \
        request_path         [dict get $req path] \
        request_timestamp    [dict get $req treqmon timestamp] \
        response_status_code [dict get $res statusCode] \
        response_size        [string length [dict get $res body]] \
        response_timestamp   [clock microseconds] \
    ]

    register_event $event

    return $res
}

proc ::treqmon::middleware::get_history_events {} {
    variable store
    return [${store}::get_history_events]
}

proc ::treqmon::middleware::register_event {event} {
    variable store
    variable loggers

    foreach logger $loggers {
        ${logger}::log_event $event
    }

    set session_id [dict get $event session_id]
    set req_timestamp [dict get $event request_timestamp]
    set res_timestamp [dict get $event response_timestamp]

    set h [list \
        [expr { $req_timestamp / 1000000 }] \
        [expr { ( $res_timestamp - $req_timestamp ) / 1000 }] \
        $session_id \
    ]

    ${store}::register_datapoint $h
}
