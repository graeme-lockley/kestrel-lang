import { Suite, group, eq } from "kestrel:test"

export fun run(s: Suite): Unit =
  group(s, "strings", (s1: Suite) => {
    eq(s1, "greeting", "Hello, World!", "Hello, World!");
    eq(s1, "message", "Kestrel strings work!", "Kestrel strings work!");
    eq(s1, "empty string", "", "");
    eq(s1, "with spaces", "  spaces  ", "  spaces  ");
    eq(s1, "newline", "Line1\nLine2", "Line1\nLine2");
    eq(s1, "tab", "Tab\there", "Tab\there");
    eq(s1, "quote", "She said \"hello\"", "She said \"hello\"");
    ()
  })
