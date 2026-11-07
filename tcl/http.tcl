package require tpathexp 1.1.0

namespace eval ::treqmon::http {}

proc ::treqmon::http::options {defaults args} {
    if {[llength $args] % 2} {error "options must be name/value pairs"}
    foreach {key value} $args {
        if {![dict exists $defaults $key]} {error "unknown option: $key"}
        dict set defaults $key $value
    }
    return $defaults
}

# Mount configuration and templates belong to this router, not package globals.
proc ::treqmon::mount {router args} {
    set config [http::options {-prefix /request-monitor -title {Request Monitor} \
        -include_active_users false -config {}} {*}$args]
    set settings [http::options {master_template {} templates {} chart_script /js/chart.umd.js} \
        {*}[dict get $config -config]]
    set prefix [string trimright [dict get $config -prefix] /]
    if {![regexp {^(/[a-zA-Z0-9_-]+)*$} $prefix]} {
        error "-prefix must be a literal local path"
    }
    if {![string is boolean -strict [dict get $config -include_active_users]]} {
        error "-include_active_users must be a boolean"
    }
    dict set config -prefix $prefix
    dict set config -config $settings
    ::treqmon::view::init
    set templates [dict merge $::treqmon::view::templates [dict get $settings templates]]
    if {[dict get $settings master_template] ne {}} {
        dict set templates page.html.jinja [dict get $settings master_template]
    }
    dict for {name template} $templates {
        ::jinja2::validate $template -templates $templates -path $name
    }
    dict set config templates $templates
    set index [expr {$prefix eq {} ? "/" : $prefix}]
    foreach path [list $index $prefix/ $prefix/_assets/charts.css $prefix/_assets/charts.js] {
        if {[dict get [$router match GET $path] statusCode] != 404} {
            error "mount prefix is already handled; mount treqmon before catch-all routes"
        }
    }
    $router add GET $prefix/_assets/:asset [list ::treqmon::http::dispatch $config asset] -strict true
    $router add GET $index [list ::treqmon::http::dispatch $config page] -strict true
    if {$prefix ne {}} {
        $router add GET $prefix/ [list ::treqmon::http::dispatch $config page] -strict true
    }
    return $config
}

proc ::treqmon::http::response {status body {type {text/html; charset=utf-8}}} {
    dict create statusCode $status body $body headers [dict create \
        content-type $type x-content-type-options nosniff cache-control no-store \
        content-security-policy {default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'}]
}

proc ::treqmon::http::asset {name} {
    set types {charts.css text/css charts.js application/javascript}
    if {![dict exists $types $name]} {
        return [response 404 {Asset not found.} {text/plain; charset=utf-8}]
    }
    set channel [open [file join $::treqmon::view::asset_dir $name] r]
    try {
        chan configure $channel -encoding utf-8
        set body [read $channel]
    } finally {close $channel}
    set result [response 200 $body "[dict get $types $name]; charset=utf-8"]
    dict set result headers cache-control {public, max-age=3600}
    return $result
}

proc ::treqmon::http::dispatch {config action request context params} {
    if {$action eq "asset"} {return [asset [dict get $params asset]]}
    set fields [::treqmon::view::context [::treqmon::get_history_events] \
        [dict get $config -include_active_users]]
    dict set fields title [list S [dict get $config -title]]
    dict set fields assets [list S [dict get $config -prefix]/_assets]
    dict set fields chart_script [list S [dict get $config -config chart_script]]
    set templates [dict get $config templates]
    set html [::jinja2::render [dict get $templates monitor.html.jinja] \
        [::tjson::typed_to_json [list M $fields]] -templates $templates -path monitor.html.jinja]
    return [response 200 $html]
}
