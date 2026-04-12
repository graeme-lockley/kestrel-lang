import { getProcess } from "kestrel:sys/process"
import { main } from "kestrel:tools/compiler/cli-main"

main(getProcess().args)