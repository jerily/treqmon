# treqmon example

## Principles

Mount the package on a `tpathexp` router with a trusted master template.
The package owns the monitor page and chart assets; only Chart.js is copied locally.

## Run

Install the dependencies in `ttrek.json`, then:

```sh
npm ci --ignore-scripts
npm run build
tclsh app.tcl
```

Open `/stats` on port 8080. The example uses a shared-variable event store;
select `valkeystore` in `app.tcl` and configure TLS credentials to use Valkey.

## Security

### Surface

Local HTTP server, login demonstration and statistics routes.

### Protections

Jinja escapes rendered values; templates contain no Tcl code.

### Pending

The session key in `session-keyset.json` is a public test fixture.
Replace it and configure access controls before deployment.
