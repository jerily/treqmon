package require tpathexp 1.2.0

namespace eval ::treqmon::http {
    variable monitored_routers {}
}

proc ::treqmon::http::router_changed {old new operation} {
    variable monitored_routers
    dict unset monitored_routers $old
    if {$operation eq "rename"} {dict set monitored_routers $new 1}
}

proc ::treqmon::http::options {defaults args} {
    if {[llength $args] % 2} {error "options must be name/value pairs"}
    foreach {key value} $args {
        if {![dict exists $defaults $key]} {error "unknown option: $key"}
        dict set defaults $key $value
    }
    return $defaults
}

# Mount configuration and templates belong to this router, not package globals.
proc ::treqmon::prepare_mount {args} {
    set config [http::options {-prefix /request-monitor -title {Request Monitor} \
        -include_active_users false -middleware true -config {} -secret_config {}} {*}$args]
    # Backend credentials are configured separately; do not capture unused
    # mount secrets in routes or return them to the caller.
    dict size [dict get $config -secret_config]
    dict unset config -secret_config
    set settings [http::options {master_template {} templates {} template_renderer {} chart_script /js/chart.umd.js validate_templates true} \
        {*}[dict get $config -config]]
    set prefix [string trimright [dict get $config -prefix] /]
    if {![regexp {^(/[a-zA-Z0-9_-]+)*$} $prefix]} {
        error "-prefix must be a literal local path"
    }
    if {![string is boolean -strict [dict get $config -include_active_users]]} {
        error "-include_active_users must be a boolean"
    }
    if {![string is boolean -strict [dict get $config -middleware]]} {
        error "-middleware must be a boolean"
    }
    dict set config -prefix $prefix
    dict set config -config $settings
    if {[dict get $settings template_renderer] eq {}} {
        dict set config templates [::treqmon::view::prepare_templates $settings]
    }
    return $config
}

proc ::treqmon::mount {router args} {
    set config [prepare_mount {*}$args]
    set prefix [dict get $config -prefix]
    set settings [dict get $config -config]
    set index [expr {$prefix eq {} ? "/" : $prefix}]
    foreach path [list $index $prefix/ $prefix/_assets/charts.css $prefix/_assets/charts.js] {
        if {[dict get [$router match GET $path] statusCode] != 404} {
            error "mount prefix is already handled; mount treqmon before catch-all routes"
        }
    }
    foreach route [::treqmon::route_specs $prefix $config $settings] {
        lassign $route method path handler
        $router add $method $path $handler -strict true
    }
    # Multiple dashboard mounts share one collection layer. Track command
    # renames/deletion so the registration follows the router's lifetime.
    variable ::treqmon::http::monitored_routers
    set command [namespace which -command $router]
    if {[dict get $config -middleware] && ![dict exists $monitored_routers $command]} {
        $router add_middleware -enter_proc ::treqmon::middleware::enter \
            -leave_proc ::treqmon::middleware::leave
        dict set monitored_routers $command 1
        trace add command $command {rename delete} ::treqmon::http::router_changed
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
    set renderer [dict get $config -config template_renderer]
    set json [::tjson::typed_to_json [list M $fields]]
    if {$renderer ne {}} {return [response 200 [{*}$renderer monitor.html.jinja $json]]}
    package require jinja2 0.2.0
    set templates [dict get $config templates]
    set html [::jinja2::render [dict get $templates monitor.html.jinja] \
        [::tjson::typed_to_json [list M $fields]] -templates $templates -path monitor.html.jinja]
    return [response 200 $html]
}
