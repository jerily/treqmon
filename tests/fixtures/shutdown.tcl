package require treqmon 2.1.0
lassign $argv kind path
set config {}
switch $kind {
    console {
        ::treqmon::console::init_main config {threshold 100 format_string {%h}}
        set worker [dict get $config logger console worker_thread_id]
        thread::send $worker {::treqmon::worker::console::log_event {remote_hostname example}}
    }
    logfile {
        ::treqmon::logfile::init_main config [dict create threshold 100 format_string {%h} path $path]
        set worker [dict get $config logger logfile worker_thread_id]
        thread::send $worker {::treqmon::worker::logfile::log_event {remote_hostname example}}
    }
    memstore {
        ::treqmon::memstore::init_main config {history_max_events 10}
        set worker [dict get $config store memstore worker_thread_id]
        thread::send $worker {::treqmon::worker::memstore::register_datapoint {100 12 user}}
        if {[thread::send $worker {::treqmon::worker::memstore::get_history_events}] ne {{100 12 user}}} {
            error "memory worker lost history"
        }
    }
}
::treqmon::${kind}::shutdown_main
puts stopped
