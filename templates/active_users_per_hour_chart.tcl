package require tjson

set active_users_stats [dict get $__data__ active_users_stats]
set element_id [dict get $__data__ element_id]

set hour_stats_dict [dict get $active_users_stats hour]
set hour_xrange [dict get $hour_stats_dict xrange]
set hour_stats [dict get $hour_stats_dict active_users]

set top_k [dict get $hour_stats_dict top_k]
set hour_top_k_users [list]
foreach pair [dict get $hour_stats_dict top_k_users] {
    lassign $pair t v
    lappend hour_top_k_users [clock format $t] $v
}

lassign $hour_xrange xmin xmax
set max_label $xmax
set min_label $xmin

# create all labels from min to max by adding 60 hours to each
set active_users_hour_labels [list]
set current_label $min_label
while { $current_label <= $max_label } {
    lappend active_users_hour_labels [list $current_label]
    set current_label [expr {$current_label + 3600}]
}

# now fill with zeros the missing values
set active_users_hour_data [list]
foreach label $active_users_hour_labels {
    if { [dict exists $hour_stats $label] } {
        lassign [dict get $hour_stats $label] timestamp count
        lappend active_users_hour_data $count
    } else {
        lappend active_users_hour_data 0
    }
}

# insert S before each element in the labels list
set active_users_hour_labels_typed [lmap x $active_users_hour_labels {list S [clock format $x -format "%H:%M:%S"]}]

# insert N before each element in the data list
set active_users_hour_data_typed [lmap x $active_users_hour_data {list N $x}]

set dataset_typed [list M [list \
    label {S "Active Users per Hour"} \
    data [list L $active_users_hour_data_typed] \
    backgroundColor {S "rgba(255, 99, 132, 0.2)"} \
    borderColor {S "rgba(255, 99, 132, 1)"} \
    borderWidth {N 1} \
    fill {BOOL 1} \
    cubicInterpolationMode {S "monotone"} \
    tension {N 0.4} \
]]

set data_typed [list M [list \
   labels [list L $active_users_hour_labels_typed] \
   datasets [list L [list $dataset_typed]] \
]]

set options_typed {M {
    scales {M {
        x {M {title {M {display {BOOL 1} text {S "Hour"}}}}}
        y {M {title {M {display {BOOL 1} text {S "Users"}}} beginAtZero {BOOL 1}}}
    }}
}}

::tjson::create [list M [list \
    type {S line} \
    data $data_typed \
    options $options_typed]] \
    chart_config_node

set chart_config_json [::tjson::to_json $chart_config_node]
set element_id_json [::tjson::typed_to_json [list S $element_id]]

return [list \
    chart_config $chart_config_json \
    hour_stats_dict $hour_stats_dict \
    top_k $top_k \
    hour_top_k_users $hour_top_k_users \
    element_id $element_id \
    element_id_json $element_id_json]
