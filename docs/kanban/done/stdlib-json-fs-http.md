# Stdlib: Implement kestrel:json, kestrel:fs, kestrel:http

## Description

`stdlib/kestrel/json.ks`, `fs.ks`, `http.ks` are stubs. Per spec 02:

- **json**: parse(String): Value, stringify(Value): String
- **fs**: readText(String): Task\<String\>
- **http**: createServer, listen, get, bodyText, queryParam, requestId, nowMs

These require VM primitives for JSON, async file read, and HTTP. Can be split into separate stories if preferred.

## Acceptance Criteria

- [x] kestrel:json: parse, stringify calling __json_parse, __json_stringify
- [x] kestrel:fs: readText calling __read_file_async
- [x] kestrel:http: createServer, listen, get, bodyText, queryParam, requestId, nowMs (or minimal subset)
- [x] E2E for each: parse/stringify, read fixture file, minimal HTTP server/client

## Tasks

- [x] VM + compiler: __json_parse, __json_stringify primitives; kestrel:json parse/stringify; E2E
- [x] VM + compiler: __read_file_async; kestrel:fs readText; E2E read fixture
- [x] kestrel:http: minimal subset or stubs; E2E if feasible
