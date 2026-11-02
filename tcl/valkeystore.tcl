namespace eval ::treqmon::valkeystore {}

proc ::treqmon::valkeystore::init_main {output_configVar config} {
    upvar $output_configVar output_config

    set outconf [list \
        host [dict get $config host] \
        port [dict get $config port] \
        history_max_events [dict get $config history_max_events]]

    foreach key {ssl username password ssl_ca_file ssl_cert_file ssl_key_file timeout} {
        if {[dict exists $config $key]} {
            lappend outconf $key [dict get $config $key]
        }
    }

    dict set output_config store "valkeystore" $outconf

}

namespace eval ::treqmon::middleware::valkeystore {
    variable valkey_client
    variable config {
        host "localhost"
        port 6379
    }
    variable history_max_events 1000000
}

proc ::treqmon::middleware::valkeystore::init {config_dict} {
    variable valkey_client
    variable config
    variable history_max_events

    package require valkey 1.0.1

    set config [dict merge $config $config_dict]
    set host [dict get $config host]
    set port [dict get $config port]
    set vk_args {}
    if {[dict exists $config ssl] && [dict get $config ssl]} {
        lappend vk_args -ssl
    }
    foreach key {username password ssl_ca_file ssl_cert_file ssl_key_file timeout} {
        if {[dict exists $config $key]} {
            lappend vk_args -$key [dict get $config $key]
        }
    }

    if { [dict exists $config history_max_events] } {
        set history_max_events [dict get $config history_max_events]
    }

    set valkey_client [valkey -host $host -port $port {*}${vk_args}]

}

proc ::treqmon::middleware::valkeystore::get_history_events {} {
    variable valkey_client
    return [$valkey_client LRANGE history_events 0 -1]
}

proc ::treqmon::middleware::valkeystore::register_datapoint {datapoint} {
    variable valkey_client
    variable history_max_events

    set len [$valkey_client RPUSH history_events $datapoint]
    if { $len > [expr { 1.5 * $history_max_events }] } {
        set num_drop_events [expr { $len - $history_max_events }]
        $valkey_client LTRIM history_events $num_drop_events -1
    }
}

proc ::treqmon::middleware::valkeystore::shutdown {} {
    variable valkey_client
    #$valkey_client DEL history_events
    $valkey_client destroy
    return
}

proc ::treqmon::valkeystore::shutdown_main {} {}