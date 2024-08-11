namespace eval ::treqmon::middleware {
    variable store
    variable worker_id
}

proc ::treqmon::middleware::init {config_dict} {
    variable store
    variable worker_id

    set store [dict get $config_dict store]
    set worker_id [dict get $config_dict worker_id]
}

proc ::treqmon::middleware::enter { ctx req } {
    dict set req treqmon timestamp [clock microseconds]
    return $req
}

proc ::treqmon::middleware::leave { ctx req res } {
    variable worker_id
    variable store

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

    ${store}::register_event $worker_id $event

    return $res
}

proc ::treqmon::middleware::get_history_events {} {
    variable store
    variable worker_id
    return [${store}::get_history_events $worker_id]
}

proc ::treqmon::middleware::register_event_with_pool {worker_pool_id event} {
    ::tpool::post -nowait $worker_pool_id \
        [list ::treqmon::worker::register_event $event]

    return
}