set stats [::treqmon::statistics \
              -count_second \
              -count_minute \
              -count_hour \
              -count_day \
              -average_second \
              -average_minute \
              -average_hour \
              -average_day \
              [clock seconds]]

set events [::treqmon::get_history_events]
set page_view_stats [::treqmon::get_page_views $events]
set response_time_stats [::treqmon::get_response_times $events]

return [dict merge $__data__ [list \
    stats $stats \
    page_view_stats $page_view_stats \
    response_time_stats $response_time_stats]]
