// kestrel:http — spec 02. Minimal subset: nowMs. createServer, listen, get, bodyText, queryParam, requestId require VM primitives (future).
import * as Basics from "kestrel:basics"

export fun nowMs(): Int = Basics.nowMs()
