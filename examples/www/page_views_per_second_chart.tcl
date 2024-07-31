set page_view_stats [dict get $__data__ page_view_stats]

set second_stats_dict [dict get $page_view_stats second]
set second_stats [dict get $second_stats_dict page_views]
set second_xrange [dict get $second_stats_dict xrange]

lassign $second_xrange xmin xmax
set max_label $xmax
set min_label $xmin

# create all labels from min to max by adding 60 seconds to each
set page_view_stats_second_labels [list]
set current_label $min_label
while { $current_label <= $max_label } {
    lappend page_view_stats_second_labels [list $current_label]
    set current_label [expr {$current_label + 1}]
}

# now fill with zeros the missing values
set page_view_stats_second_data [list]
foreach label $page_view_stats_second_labels {
    if { [dict exists $second_stats $label] } {
        lassign [dict get $second_stats $label] timestamp count
        lappend page_view_stats_second_data $count
    } else {
        lappend page_view_stats_second_data 0
    }
}

# insert S before each element in the labels list
set page_view_stats_second_labels_typed [lmap x $page_view_stats_second_labels {list S [clock format $x -format "%H:%M:%S"]}]

# insert N before each element in the data list
set page_view_stats_second_data_typed [lmap x $page_view_stats_second_data {list N $x}]

set dataset_typed [list M [list \
    label {S "Page Views per Second"} \
    data [list L $page_view_stats_second_data_typed] \
    backgroundColor {S "rgba(255, 99, 132, 0.2)"} \
    borderColor {S "rgba(255, 99, 132, 1)"} \
    borderWidth {N 1} \
    fill {BOOL 1} \
    cubicInterpolationMode {S "monotone"} \
    tension {N 0.4} \
]]

set data_typed [list M [list \
   labels [list L $page_view_stats_second_labels_typed] \
   datasets [list L [list $dataset_typed]] \
]]

set options_typed {M {
    scales {M {
        x {M {title {M {display {BOOL 1} text {S "Second"}}}}}
        y {M {title {M {display {BOOL 1} text {S "Views"}}} beginAtZero {BOOL 1}}}
    }}
}}

::tjson::create [list M [list \
    type {S line} \
    data $data_typed \
    options $options_typed]] \
    chart_config_node

set chart_config_json [::tjson::to_json $chart_config_node]

# ::thtml::rendertemplate [dict merge $__data__ [list chart_config $chart_config_json]]
return [dict merge $__data__ [list chart_config $chart_config_json second_stats_dict $second_stats_dict]]
