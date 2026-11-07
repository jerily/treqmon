# treqmon

Request monitoring for twebserver.

## Principles

- Store events in the configured Valkey, shared-variable or memory store.
- Render trusted Jinja templates with typed JSON. Templates contain no Tcl code.
- The package owns monitor routes, statistics rendering and chart assets. Hosts
  supply storage configuration, authentication policy and optional master layouts.
- Mount on the host's `tpathexp` router before its catch-all routes.
- Keep credentials in application configuration.

## Requirements

Tcl 8.6+, twebserver 1.47.53+, valkey-tcl 1.0.1+, jinja2-tcl 0.1.0+
and tjson 1.0.26+, plus tpathexp 1.1.0+. Thread is required for memory/shared-variable stores.

```sh
make install PREFIX=/path/to/install
```

## Middleware

In the main thread, initialize one store and pass the returned configuration
to each worker:

```tcl
package require treqmon 2.1.0
set config [dict create store [dict create valkeystore [dict create \
    host $host port 6379 ssl true username appuser password $password \
    history_max_events 100000]]]
set worker_config [::treqmon::init_main $config]
```

In each worker:

```tcl
::treqmon::init_middleware $worker_config
::twebserver::add_middleware \
    -enter_proc ::treqmon::middleware::enter \
    -leave_proc ::treqmon::middleware::leave $router
```

Valkey also accepts `ssl_ca_file`, `ssl_cert_file`, `ssl_key_file`, and `timeout`
(milliseconds). Build valkey-tcl and libvalkey with `-DENABLE_SSL=ON`.
The optional `logger` dictionary selects `console` or `logfile`, with a
`threshold` and, for files, a `path`.

For local, process-local memory shared by Tcl worker threads, initialize each
worker with `::treqmon::init_middleware {store {tsvstore {history_max_events 10000}}}`.
Starting another worker preserves existing history. Independent processes need
Valkey to share history. Storage is separate from the page mount, so the same
middleware works with direct HTTP servers and Lambda adapters.

## Mounted monitor

```tcl
set router [::tpathexp::router]
::treqmon::mount $router -prefix /request-monitor -title {Request Monitor} \
    -include_active_users false \
    -config [dict create master_template $monitor_master \
        templates [dict create master.html.jinja $site_master]]
```

`master_template` is trusted Jinja source containing a `body` block; `templates`
maps names to additional trusted template sources. This follows the host-layout
configuration of `web-static-wiki` and `web-static-blog`. Configuration is isolated
per mount and validated before installing routes. Omit `-config` to use the
package's standalone layout. `-title` defaults to `Request Monitor`, and session
charts are enabled only when `-include_active_users` is true.

The package handles GET and HEAD at the prefix (and its trailing-slash form),
with 405 for unsupported methods. It serves `charts.js` and `charts.css` under
`<prefix>/_assets/`. Other asset names return 404. Pages use fresh history and
`Cache-Control: no-store`; no application-local monitor handler is needed.

Layout fields include `title`, `assets` (the package asset URL prefix), and
`chart_script`. Serve Chart.js locally at `/js/chart.umd.js`, or select another
local URL with `-config {chart_script /path/to/chart.umd.js}`. Custom masters must
load Chart.js followed by `{{ assets }}/charts.js`, both deferred. They can use
the package CSS or provide site-specific styles. Chart fonts inherit the canvas
font; `--treqmon-chart-color` and `--treqmon-chart-fill` customize chart colors.

## Rendering

Load and validate templates once in each worker with `::treqmon::view::init`.
Render a statistics fragment with:

```tcl
set html [::treqmon::render_stats [::treqmon::get_history_events]]
```

Pass `true` as the second argument to include active-user charts when events
contain session IDs. Page views, average response times and active users each
have second/minute/hour charts and maxima.

For a page wrapper, merge `::treqmon::view::templates` into your template
dictionary and include `stats.html.jinja`. `::treqmon::view::context events
?include_active_users?` returns typed fields for `::tjson::typed_to_json`.
Serve Chart.js and the package's `assets/charts.js` and `assets/charts.css`
locally. The asset directory is `::treqmon::view::asset_dir`.
See [example/readme.md](example/readme.md) for a complete application.

## Validation

```sh
make test TCLSH=/path/to/tclsh
```

Tests cover statistics, rendering, escaping, router methods, host-layout isolation,
asset allowlisting, shared-memory initialization and TLS configuration forwarding.

## Security

### Surface

Valkey connections, request data, mounted monitor/asset routes and rendered statistics.

### Protections

With `ssl true`, valkey-tcl verifies certificates and server identity on every
connection. Jinja escapes HTML; chart JSON is escaped into data attributes.
Mounts validate trusted templates at startup. Asset routes serve only the two
named package files. Responses use nosniff and a same-origin content security policy.

### Pending

Configure TLS credentials and protect the statistics endpoint in deployment.
