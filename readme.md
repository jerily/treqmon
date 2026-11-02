# treqmon

Request monitoring for twebserver.

## Principles

- Store events in the configured Valkey, shared-variable or memory store.
- Render trusted Jinja templates with typed JSON. Templates contain no Tcl code.
- Keep credentials in application configuration.

## Requirements

Tcl 8.6+, twebserver 1.47.53+, valkey-tcl 1.0.1+, jinja2-tcl 0.1.0+
and tjson 1.0.26+. Thread is required for memory/shared-variable stores.

```sh
make install PREFIX=/path/to/install
```

## Middleware

In the main thread, initialize one store and pass the returned configuration
to each worker:

```tcl
package require treqmon 2.0.0
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

Tests cover statistics, rendering, escaping and TLS configuration forwarding.

## Security

### Surface

Valkey connections, request data and rendered statistics.

### Protections

With `ssl true`, valkey-tcl verifies certificates and server identity on every
connection. Jinja escapes HTML; chart JSON is escaped into data attributes.

### Pending

Configure TLS credentials and protect the statistics endpoint in deployment.
