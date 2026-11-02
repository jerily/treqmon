# treqmon example

## Principles

Use the package's Jinja templates and serve browser assets locally.

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
