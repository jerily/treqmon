
set events [::treqmon::get_history_events]
set summary [::treqmon::get_summary $events]
set page_view_stats [::treqmon::get_page_views $events]
set response_time_stats [::treqmon::get_response_times $events]

return [dict merge $__data__ [list \
    summary $summary \
    page_view_stats $page_view_stats \
    response_time_stats $response_time_stats]]
