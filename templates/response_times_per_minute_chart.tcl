package require tjson

set response_time_stats [dict get $__data__ response_time_stats]

set minute_stats_dict [dict get $response_time_stats minute]
set minute_stats [dict get $minute_stats_dict response_times]
set minute_xrange [dict get $minute_stats_dict xrange]

set top_k [dict get $minute_stats_dict top_k]
set minute_top_k_times [list]
foreach pair [dict get $minute_stats_dict top_k_times] {
    lassign $pair t v
    lappend minute_top_k_times [clock format $t] $v
}

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
set page_view_stats_minute_labels_typed [lmap x $page_view_stats_minute_labels {list S [clock format $x -format "%H:%M:%S"]}]

# insert N before each element in the data list
set page_view_stats_minute_data_typed [lmap x $page_view_stats_minute_data {list N $x}]

set dataset_typed [list M [list \
    label {S "Average Response Time per Minute"} \
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
        y {M {title {M {display {BOOL 1} text {S "Avg Response Time (in ms)"}}} beginAtZero {BOOL 1}}}
    }}
}}

::tjson::create [list M [list \
    type {S line} \
    data $data_typed \
    options $options_typed]] \
    chart_config_node

set chart_config_json [::tjson::to_json $chart_config_node]

# ::thtml::rendertemplate [dict merge $__data__ [list chart_config $chart_config_json]]
return [dict merge $__data__ [list \
    chart_config $chart_config_json \
    minute_stats_dict $minute_stats_dict \
    top_k $top_k \
    minute_top_k_times $minute_top_k_times]]
