
set events [::treqmon::get_history_events]
set summary [::treqmon::get_summary $events]
set page_view_stats [::treqmon::get_page_views $events]
set response_time_stats [::treqmon::get_response_times $events]

set tsession_present_version ""
catch { set tsession_present_version [package present tsession] }
set tsession_present [expr { $tsession_present_version ne "" }]

set result [list \
   summary $summary \
   page_view_stats $page_view_stats \
   response_time_stats $response_time_stats \
   tsession_present $tsession_present]

if { $tsession_present } {
    set active_users_stats [::treqmon::get_active_users $events]
    lappend result active_users_stats $active_users_stats
}

return $result
