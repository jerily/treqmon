namespace eval ::treqmon::memstore {
    variable worker_thread_id
}

proc ::treqmon::memstore::init_main {output_configVar config} {
    variable worker_thread_id
    upvar $output_configVar output_config

    package require Thread

    set initcmd [join [list \
        [list package require treqmon] \
        [list package require Thread] \
        [list ::treqmon::worker::memstore::init $config] \
        [list ::thread::wait]] "\n"]

    set worker_thread_id [thread::create -joinable $initcmd]

    dict set output_config store "memstore" [list \
        worker_thread_id $worker_thread_id \
        history_max_events [dict get $config history_max_events]]
}

namespace eval ::treqmon::middleware::memstore {
    variable config {}
    variable history_max_events 1000000
    variable worker_thread_id
}

proc ::treqmon::middleware::memstore::init {config_dict} {
    variable config
    variable history_max_events
    variable worker_thread_id

    package require Thread

    set config [dict merge $config $config_dict]
    if { [dict exists $config history_max_events] } {
        set history_max_events [dict get $config history_max_events]
    }
    set worker_thread_id [dict get $config worker_thread_id]
}

proc ::treqmon::middleware::memstore::get_history_events {} {
    variable worker_thread_id
    return [thread::send $worker_thread_id [list ::treqmon::worker::memstore::get_history_events]]
}

proc ::treqmon::middleware::memstore::register_datapoint {datapoint} {
    variable worker_thread_id
    return [thread::send -async $worker_thread_id [list ::treqmon::worker::memstore::register_datapoint $datapoint]]
}

proc ::treqmon::middleware::memstore::shutdown {} {}

namespace eval ::treqmon::worker::memstore {
    variable config {}
    variable history_events {}
    variable history_max_events 1000000
}

proc ::treqmon::worker::memstore::init {config_dict} {
    variable config
    variable history_max_events
    set config [dict merge $config $config_dict]
    if { [dict exists $config history_max_events] } {
        set history_max_events [dict get $config history_max_events]
    }
}

proc ::treqmon::worker::memstore::register_datapoint { datapoint } {
    variable history_events
    variable history_max_events

    set len [llength [lappend history_events $datapoint]]
    if { $len > [expr { 1.5 * $history_max_events }] } {
        set num_drop_events [expr { $len - $history_max_events - 1 }]
        # unfortunately tsv does not have a command that can drop elements without returning anything
        set history_events [lreplace $history_events 0 $num_drop_events]
    }

}

proc ::treqmon::worker::memstore::get_history_events {} {
    variable history_events
    return $history_events
}
