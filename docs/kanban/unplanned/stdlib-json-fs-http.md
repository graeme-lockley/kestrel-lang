# Stdlib: Implement kestrel:json, kestrel:fs, kestrel:http

## Description

`stdlib/kestrel/json.ks`, `fs.ks`, `http.ks` are stubs. Per spec 02:

- **json**: parse(String): Value, stringify(Value): String
- **fs**: readText(String): Task\<String\>
- **http**: createServer, listen, get, bodyText, queryParam, requestId, nowMs

These require VM primitives for JSON, async file read, and HTTP. Can be split into separate stories if preferred.

## Acceptance Criteria

- [ ] kestrel:json: parse, stringify calling __json_parse, __json_stringify
- [ ] kestrel:fs: readText calling __read_file_async
- [ ] kestrel:http: createServer, listen, get, bodyText, queryParam, requestId, nowMs (or minimal subset)
- [ ] E2E for each: parse/stringify, read fixture file, minimal HTTP server/client
