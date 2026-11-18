# SPDX-License-Identifier: MIT
# Route declarations only. This package never loads storage or handlers.
namespace eval ::treqmon {
    variable template_directory [file normalize [file join [file dirname [info script]] .. templates]]
}

# Config is opaque here: hosts may bind a placeholder and resolve it on dispatch.
proc ::treqmon::route_specs {prefix config {settings {}} {policy {}}} {
    set prefix [string trimright $prefix /]
    if {![regexp {^(/[A-Za-z0-9_-]+)*$} $prefix]} {error "mount prefix must be a literal local path"}
    set index [expr {$prefix eq {} ? "/" : $prefix}]
    set routes {}
    lappend routes [list GET $prefix/_assets/:asset [list ::treqmon::http::dispatch $config asset]]
    lappend routes [list GET $index [list ::treqmon::http::dispatch $config page]]
    if {$prefix ne {}} {
        lappend routes [list GET $prefix/ [list ::treqmon::http::dispatch $config page]]
    }
    return $routes
}
package provide treqmon::routes 1.0
