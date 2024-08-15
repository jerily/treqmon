namespace eval ::treqmon::tsvstore {}

proc ::treqmon::tsvstore::init_main {output_configVar config} {
    upvar $output_configVar output_config

    dict set output_config store "tsvstore" history_max_events [dict get $config history_max_events]
}

proc ::treqmon::tsvstore::shutdown_main {} {}

namespace eval ::treqmon::middleware::tsvstore {
    variable config {}
    variable history_max_events 1000000
}

proc ::treqmon::middleware::tsvstore::init {config_dict} {
    variable config
    variable history_max_events

    package require Thread

    set config [dict merge $config $config_dict]
    if { [dict exists $config history_max_events] } {
        set history_max_events [dict get $config history_max_events]
    }

    tsv::set history_events events [list]
}

proc ::treqmon::middleware::tsvstore::get_history_events {} {
    return [tsv::get history_events events]
}

proc ::treqmon::middleware::tsvstore::register_datapoint {datapoint} {
    variable valkey_client
    variable history_max_events

    tsv::lpush history_events events $datapoint
    set len [tsv::llength history_events events]
    if { $len > [expr { 1.5 * $history_max_events }] } {
        set num_drop_events [expr { $len - $history_max_events - 1 }]
        # unfortunately tsv does not have a command that can drop elements without returning anything
        tsv::lreplace history_events events 0 $num_drop_events
    }

}

proc ::treqmon::middleware::tsvstore::shutdown {} {}