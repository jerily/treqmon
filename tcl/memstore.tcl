namespace eval ::treqmon::worker::memstore {
    variable config {}
    variable history_events {}
}

proc ::treqmon::worker::memstore::init {config_dict} {
    variable config
    set config [dict merge $config $config_dict]
}

proc ::treqmon::worker::memstore::push_event { event } {
    variable history_events
    lappend history_events $event
}

proc ::treqmon::worker::memstore::get_num_events {} {
    variable history_events
    return [llength $history_events]
}

proc ::treqmon::worker::memstore::drop_oldest_events { num_drop_events } {
    variable history_events
    set history_events [lreplace $history_events 0 $num_drop_events]
}

proc ::treqmon::worker::memstore::get_history_events {} {
    variable history_events
    return $history_events
}