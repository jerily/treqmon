# proc page_views_per_minute_chart { __data__ }

set page_view_stats [::treqmon::get_page_views $events]
set response_time_stats [::treqmon::get_response_times $events]

set minute_stats_dict [dict get $page_view_stats minute]
set minute_stats [dict get $minute_stats_dict page_views]
set minute_xrange [dict get $minute_stats_dict xrange]

set page_view_stats_minute_labels [dict keys $minute_stats]

lassign $minute_xrange xmin xmax
set max_label $xmax
set min_label $xmin

# create all labels from min to max by adding 60 seconds to each
set page_view_stats_minute_labels [list]
set current_label $min_label
while { $current_label <= $max_label } {
    lappend page_view_stats_minute_labels [list $current_label]
    set current_label [expr {$current_label + 60}]
}

# now fill with zeros the missing values
set page_view_stats_minute_data [list]
foreach label $page_view_stats_minute_labels {
    if { [dict exists $minute_stats $label] } {
        lassign [dict get $minute_stats $label] timestamp count
        lappend page_view_stats_minute_data $count
    } else {
        lappend page_view_stats_minute_data 0
    }
}

# insert S before each element in the labels list
set page_view_stats_minute_labels_typed [lmap x $page_view_stats_minute_labels {list S [clock format $x -format "%H:%M"]}]

# insert N before each element in the data list
set page_view_stats_minute_data_typed [lmap x $page_view_stats_minute_data {list N $x}]

set dataset_typed [list M [list \
    label {S "Page Views per Minute"} \
    data [list L $page_view_stats_minute_data_typed] \
    backgroundColor {S "rgba(255, 99, 132, 0.2)"} \
    borderColor {S "rgba(255, 99, 132, 1)"} \
    borderWidth {N 1} \
    fill {BOOL 1} \
    cubicInterpolationMode {S "monotone"} \
    tension {N 0.4} \
]]

set data_typed [list M [list \
   labels [list L $page_view_stats_minute_labels_typed] \
   datasets [list L [list $dataset_typed]] \
]]

set options_typed {M {
    scales {M {
        x {M {title {M {display {BOOL 1} text {S "Minute"}}}}}
        y {M {title {M {display {BOOL 1} text {S "Views"}}} beginAtZero {BOOL 1}}}
    }}
}}

::tjson::create [list M [list \
    type {S line} \
    data $data_typed \
    options $options_typed]] \
    chart_config_node

set chart_config_json [::tjson::to_json $chart_config_node]

::thtml::rendertemplate [dict merge $__data__ [list chart_config $chart_config_json]]