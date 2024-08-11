namespace eval ::treqmon::middleware {
    variable worker_thread_id
}

proc ::treqmon::middleware::init {config_dict} {
    variable worker_thread_id
    set worker_thread_id [dict get $config_dict worker_thread_id]
}

proc ::treqmon::middleware::enter { ctx req } {
    dict set req treqmon timestamp [clock microseconds]
    return $req
}

proc ::treqmon::middleware::leave { ctx req res } {
    variable worker_thread_id

    set event [dict create \
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

    ::thread::send -async $worker_thread_id [list ::treqmon::worker::register_event $event]

    return $res
}
