namespace eval ::treqmon::tsvstore {}

namespace eval ::treqmon::middleware::tsvstore {}

namespace eval ::treqmon::worker::tsvstore {
    variable config {}
}

proc ::treqmon::worker::tsvstore::init {config_dict} {
    variable config
    set config [dict merge $config $config_dict]
    tsv::set history_events events {}
}

proc ::treqmon::worker::tsvstore::push_event { event } {
    tsv::lappend history_events events $event
}

proc ::treqmon::worker::tsvstore::get_num_events {} {
    return [tsv::llength history_events events]
}

proc ::treqmon::worker::tsvstore::drop_oldest_events { num_drop_events } {
    tsv::lock history_events {
        tsv::set history_events events [tsv::lreplace history_events events 0 $num_drop_events]
    }
}

proc ::treqmon::worker::tsvstore::get_history_events {} {
    return [tsv::get history_events events]
}

proc ::treqmon::middleware::tsvstore::get_history_events {worker_thread_id} {
    # Unused: worker_thread_id
    return [tsv::get history_events events]
}
