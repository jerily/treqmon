package require jinja2 0.1.0
package require tjson 1.0.26

# Build typed JSON fields for the Jinja statistics templates.
namespace eval ::treqmon::view {}

proc ::treqmon::view::chart {stats interval metric title unit top_key} {
    set period [dict get $stats $interval]
    set step [dict get {second 1 minute 60 hour 3600} $interval]
    lassign [dict get $period xrange] first last
    set labels {}
    set values {}
    for {set timestamp $first} {$timestamp <= $last} {incr timestamp $step} {
        lappend labels [list S [clock format $timestamp -format %H:%M:%S]]
        set value 0
        if {[dict exists $period $metric $timestamp]} {
            set value [lindex [dict get $period $metric $timestamp] 1]
        }
        lappend values [list N $value]
    }

    set chart_title "$title per [string totitle $interval]"
    set dataset [list M [list label [list S $chart_title] data [list L $values] \
        backgroundColor {S {rgba(255, 99, 132, 0.2)}} \
        borderColor {S {rgba(255, 99, 132, 1)}} borderWidth {N 1} \
        fill {BOOL 1} cubicInterpolationMode {S monotone} tension {N 0.4}]]
    set data [list M [list labels [list L $labels] datasets [list L [list $dataset]]]]
    set x_title [list M [list display {BOOL 1} text [list S [string totitle $interval]]]]
    set y_title [list M [list display {BOOL 1} text [list S $unit]]]
    set scales [list M [list x [list M [list title $x_title]] \
        y [list M [list title $y_title beginAtZero {BOOL 1}]]]]
    set config [::tjson::typed_to_json [list M [list type {S line} data $data \
        options [list M [list scales $scales]]]]]

    set top {}
    foreach point [dict get $period $top_key] {
        lassign $point timestamp value
        lappend top [list M [list time [list S [clock format $timestamp]] value [list N $value]]]
    }
    # JSON stays a string here and is HTML-escaped into a data attribute.
    return [list M [list title [list S $chart_title] config [list S $config] top [list L $top]]]
}

proc ::treqmon::view::group {stats metric title unit top_key} {
    set charts {}
    foreach interval {second minute hour} {
        lappend charts [chart $stats $interval $metric $title $unit $top_key]
    }
    return [list M [list title [list S $title] charts [list L $charts]]]
}

proc ::treqmon::view::context {events {include_active_users false}} {
    set summary {}
    dict for {key value} [::treqmon::get_summary $events] {
        dict set summary $key [list N $value]
    }
    set groups [list [group [::treqmon::get_page_views $events] \
        page_views {Page Views} Views top_k_views]]
    if {$include_active_users} {
        lappend groups [group [::treqmon::get_active_users $events] \
            active_users {Active Users} Users top_k_users]
    }
    lappend groups [group [::treqmon::get_response_times $events] \
        response_times {Average Response Times} Milliseconds top_k_times]
    return [dict create summary [list M $summary] groups [list L $groups]]
}


namespace eval ::treqmon::view {
    variable templates {}
    variable template_dir [file normalize [file join [file dirname [info script]] .. templates]]
    variable asset_dir [file normalize [file join [file dirname [info script]] .. assets]]
}

proc ::treqmon::view::init {} {
    variable templates
    variable template_dir
    set loaded {}
    foreach path [glob -directory $template_dir *.html.jinja] {
        set channel [open $path r]
        try {
            chan configure $channel -encoding utf-8
            dict set loaded [file tail $path] [read $channel]
        } finally {
            close $channel
        }
    }
    dict for {name template} $loaded {
        ::jinja2::validate $template -templates $loaded -path $name
    }
    set templates $loaded
}

proc ::treqmon::render_stats {events {include_active_users false}} {
    if {![dict size $::treqmon::view::templates]} {::treqmon::view::init}
    set fields [::treqmon::view::context $events $include_active_users]
    return [::jinja2::render [dict get $::treqmon::view::templates stats.html.jinja] \
        [::tjson::typed_to_json [list M $fields]] \
        -templates $::treqmon::view::templates -path stats.html.jinja]
}
