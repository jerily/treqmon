set page_view_stats [dict get $__data__ page_view_stats]

set hour_stats_dict [dict get $page_view_stats hour]
set hour_stats [dict get $hour_stats_dict page_views]
set hour_xrange [dict get $hour_stats_dict xrange]

set top_k [dict get $hour_stats_dict top_k]
set hour_top_k_views [list]
foreach pair [dict get $hour_stats_dict top_k_views] {
    lassign $pair t v
    lappend hour_top_k_views [clock format $t] $v
}

lassign $hour_xrange xmin xmax
set max_label $xmax
set min_label $xmin

# create all labels from min to max by adding 3600 seconds to each
set page_view_stats_hour_labels [list]
set current_label $min_label
while { $current_label <= $max_label } {
    lappend page_view_stats_hour_labels [list $current_label]
    set current_label [expr {$current_label + 3600}]
}

# now fill with zeros the missing values
set page_view_stats_hour_data [list]
foreach label $page_view_stats_hour_labels {
    if { [dict exists $hour_stats $label] } {
        lassign [dict get $hour_stats $label] timestamp count
        lappend page_view_stats_hour_data $count
    } else {
        lappend page_view_stats_hour_data 0
    }
}

# insert S before each element in the labels list
set page_view_stats_hour_labels_typed [lmap x $page_view_stats_hour_labels {list S [clock format $x -format "%H:%M"]}]

# insert N before each element in the data list
set page_view_stats_hour_data_typed [lmap x $page_view_stats_hour_data {list N $x}]

set dataset_typed [list M [list \
    label {S "Page Views per hour"} \
    data [list L $page_view_stats_hour_data_typed] \
    backgroundColor {S "rgba(255, 99, 132, 0.2)"} \
    borderColor {S "rgba(255, 99, 132, 1)"} \
    borderWidth {N 1} \
    fill {BOOL 1} \
    cubicInterpolationMode {S "monotone"} \
    tension {N 0.4} \
]]

set data_typed [list M [list \
   labels [list L $page_view_stats_hour_labels_typed] \
   datasets [list L [list $dataset_typed]] \
]]

set options_typed {M {
    scales {M {
        x {M {title {M {display {BOOL 1} text {S "Hour"}}}}}
        y {M {title {M {display {BOOL 1} text {S "Views"}}} beginAtZero {BOOL 1}}}
    }}
}}

::tjson::create [list M [list \
    type {S line} \
    data $data_typed \
    options $options_typed]] \
    chart_config_node

set chart_config_json [::tjson::to_json $chart_config_node]

return [dict merge $__data__ [list \
    chart_config $chart_config_json \
    hour_stats_dict $hour_stats_dict \
    top_k $top_k \
    hour_top_k_views $hour_top_k_views]]
