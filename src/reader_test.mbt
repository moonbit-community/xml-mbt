// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// Tests for XML Reader (pull parser)
/// Reference: https://github.com/tafia/quick-xml

// ============================================================================
// Basic Element Parsing
// ============================================================================

///|
test "parse simple element" {
  let reader = @xml.Reader::from_string("<root></root>")
  let event1 = reader.read_event()
  @debug.debug_inspect(
    event1,
    content=(
      #|Start({ name: "root", attributes: [] })
    ),
  )
  let event2 = reader.read_event()
  @debug.debug_inspect(event2, content="End(\"root\")")
  let event3 = reader.read_event()
  @debug.debug_inspect(event3, content="Eof")
}

///|
test "parse self-closing element" {
  let reader = @xml.Reader::from_string("<br/>")
  let event = reader.read_event()
  @debug.debug_inspect(
    event,
    content=(
      #|Empty({ name: "br", attributes: [] })
    ),
  )
}

///|
test "preserve explicit start and end tags for empty nested element" {
  let reader = @xml.Reader::from_string("<root><child></child></root>")
  let events = reader.read_events_until_eof()
  @debug.debug_inspect(
    events,
    content=(
      #|[
      #|  Start({ name: "root", attributes: [] }),
      #|  Start({ name: "child", attributes: [] }),
      #|  End("child"),
      #|  End("root"),
      #|  Eof,
      #|]
    ),
  )
}

///|
test "parse element with text" {
  let reader = @xml.Reader::from_string("<p>Hello World</p>")
  let event1 = reader.read_event()
  @debug.debug_inspect(
    event1,
    content=(
      #|Start({ name: "p", attributes: [] })
    ),
  )
  let event2 = reader.read_event()
  @debug.debug_inspect(event2, content="Text(\"Hello World\")")
  let event3 = reader.read_event()
  @debug.debug_inspect(event3, content="End(\"p\")")
}

///|
test "parse nested elements" {
  let reader = @xml.Reader::from_string("<div><span>text</span></div>")
  let event1 = reader.read_event()
  @debug.debug_inspect(
    event1,
    content=(
      #|Start({ name: "div", attributes: [] })
    ),
  )
  let event2 = reader.read_event()
  @debug.debug_inspect(
    event2,
    content=(
      #|Start({ name: "span", attributes: [] })
    ),
  )
  let event3 = reader.read_event()
  @debug.debug_inspect(event3, content="Text(\"text\")")
  let event4 = reader.read_event()
  @debug.debug_inspect(event4, content="End(\"span\")")
  let event5 = reader.read_event()
  @debug.debug_inspect(event5, content="End(\"div\")")
}

// ============================================================================
// Attributes
// ============================================================================

///|
test "parse element with single attribute" {
  let reader = @xml.Reader::from_string("<div id=\"main\"></div>")
  let event = reader.read_event()
  @debug.debug_inspect(
    event,
    content=(
      #|Start({ name: "div", attributes: [("id", "main")] })
    ),
  )
}

///|
test "parse element with multiple attributes" {
  let reader = @xml.Reader::from_string(
    "<input type=\"text\" name=\"field\" value=\"hello\"/>",
  )
  let event = reader.read_event()
  @debug.debug_inspect(
    event,
    content=(
      #|Empty(
      #|  {
      #|    name: "input",
      #|    attributes: [("type", "text"), ("name", "field"), ("value", "hello")],
      #|  },
      #|)
    ),
  )
}

///|
test "parse attribute with single quotes" {
  let reader = @xml.Reader::from_string("<div class='container'></div>")
  let event = reader.read_event()
  @debug.debug_inspect(
    event,
    content=(
      #|Start({ name: "div", attributes: [("class", "container")] })
    ),
  )
}

// ============================================================================
// Special Content
// ============================================================================

///|
test "parse XML comment" {
  let reader = @xml.Reader::from_string("<!-- This is a comment -->")
  let event = reader.read_event()
  @debug.debug_inspect(event, content="Comment(\" This is a comment \")")
}

///|
test "parse CDATA section" {
  let reader = @xml.Reader::from_string(
    "<root><![CDATA[<html>raw content</html>]]></root>",
  )
  let _ = reader.read_event() // Start(root)
  let event = reader.read_event() // CDATA
  @debug.debug_inspect(event, content="CData(\"<html>raw content</html>\")")
}

///|
test "preserve text and CDATA boundaries" {
  let reader = @xml.Reader::from_string("<root>a<![CDATA[b]]>c</root>")
  let events = reader.read_events_until_eof()
  @debug.debug_inspect(
    events,
    content=(
      #|[
      #|  Start({ name: "root", attributes: [] }),
      #|  Text("a"),
      #|  CData("b"),
      #|  Text("c"),
      #|  End("root"),
      #|  Eof,
      #|]
    ),
  )
}

///|
test "parse processing instruction" {
  let reader = @xml.Reader::from_string(
    "<?xml-stylesheet type=\"text/xsl\" href=\"style.xsl\"?>",
  )
  let event = reader.read_event()
  @debug.debug_inspect(
    event,
    content=(
      #|PI(
      #|  target="xml-stylesheet",
      #|  data="type=\"text/xsl\" href=\"style.xsl\"",
      #|)
    ),
  )
}

///|
test "parse XML declaration" {
  let reader = @xml.Reader::from_string(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
  )
  let event = reader.read_event()
  @debug.debug_inspect(
    event,
    content="Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=None)",
  )
}

///|
test "parse DOCTYPE" {
  let reader = @xml.Reader::from_string("<!DOCTYPE html>")
  let event = reader.read_event()
  @debug.debug_inspect(event, content="DocType(\"html\")")
}

// ============================================================================
// Entity Handling
// ============================================================================

///|
test "parse text with entities" {
  // Entities are split into separate Text events (lxml behavior)
  let reader = @xml.Reader::from_string(
    "<p>&lt;hello&gt; &amp; &quot;world&quot;</p>",
  )
  let _ = reader.read_event() // Start
  // Each entity becomes a separate Text event
  let events : Array[@xml.Event] = []
  while true {
    let event = reader.read_event()
    if event.kind is End(_) {
      break
    }
    events.push(event)
  }
  @debug.debug_inspect(
    events,
    content=(
      #|[
      #|  Text("<"),
      #|  Text("hello"),
      #|  Text(">"),
      #|  Text(" "),
      #|  Text("&"),
      #|  Text(" "),
      #|  Text("\""),
      #|  Text("world"),
      #|  Text("\""),
      #|]
    ),
  )
}

///|
test "parse numeric entities" {
  // Entities are split into separate Text events (lxml behavior)
  let reader = @xml.Reader::from_string("<p>&#65;&#x42;</p>")
  let _ = reader.read_event() // Start
  let event1 = reader.read_event()
  @debug.debug_inspect(event1, content="Text(\"A\")")
  let event2 = reader.read_event()
  @debug.debug_inspect(event2, content="Text(\"B\")")
}

// ============================================================================
// Whitespace Handling
// ============================================================================

///|
test "preserve whitespace in text" {
  let reader = @xml.Reader::from_string("<pre>  hello\n  world  </pre>")
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  @debug.debug_inspect(
    event,
    content=(
      #|Text("  hello\n  world  ")
    ),
  )
}

///|
test "parse with leading whitespace" {
  let reader = @xml.Reader::from_string("  <root/>")
  // Leading whitespace before root element is emitted as Text event
  let whitespace = reader.read_event()
  @debug.debug_inspect(whitespace, content="Text(\"  \")")
  let event = reader.read_event()
  @debug.debug_inspect(
    event,
    content=(
      #|Empty({ name: "root", attributes: [] })
    ),
  )
}

// ============================================================================
// Error Handling
// ============================================================================

///|
test "error on unclosed tag" {
  let reader = @xml.Reader::from_string("<root>")
  let _ = reader.read_event() // Start
  try reader.read_event() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content="InvalidSyntax(\"unclosed element: <root>\")",
      )
  } noraise {
    _ => fail("expected reader.read_event to raise")
  }
}

///|
test "error on mismatched tags" {
  let reader = @xml.Reader::from_string("<root></other>")
  let _ = reader.read_event() // Start
  try reader.read_event() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content=(
          #|InvalidSyntax("end tag mismatch: expected </root>, found </other>")
        ),
      )
  } noraise {
    _ => fail("expected reader.read_event to raise")
  }
}

///|
test "error on invalid syntax" {
  let reader = @xml.Reader::from_string("<root<>")
  try reader.read_event() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content=(
          #|InvalidSyntax("unexpected character in tag: '<'")
        ),
      )
  } noraise {
    _ => fail("expected reader.read_event to raise")
  }
}

///|
test "from_file does not resolve external entities implicitly" {
  let reader = @xml.Reader::from_file("src/testdata/external-entity.xml")
  try reader.read_events_until_eof() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content=(
          #|InvalidEntity("undefined entity reference: &leak;")
        ),
      )
  } noraise {
    _ => fail("expected external entity reference to remain unresolved")
  }
}

///|
test "reject entity expansion over the output budget" {
  let xml =
    #|<!DOCTYPE root [
    #|<!ENTITY a "1234567890">
    #|<!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">
    #|<!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
    #|<!ENTITY d "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
    #|<!ENTITY e "&d;&d;&d;&d;&d;&d;&d;&d;&d;&d;">
    #|<!ENTITY f "&e;&e;&e;&e;&e;&e;&e;&e;&e;&e;">
    #|]><root>&f;</root>

  let reader = @xml.Reader::from_string(xml)
  try reader.read_events_until_eof() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content=(
          #|InvalidEntity("entity expansion limit exceeded")
        ),
      )
  } noraise {
    _ => fail("expected oversized entity expansion to raise")
  }
}

///|
test "apply entity expansion budget before parsing replacement markup" {
  let payload = StringBuilder()
  for i = 0; i < 262_145; i = i + 1 {
    payload.write_char('x')
  }
  let xml = "<!DOCTYPE root [<!ENTITY markup \"<child>" +
    payload.to_string() +
    "</child>\">]><root>&markup;</root>"
  let reader = @xml.Reader::from_string(xml)
  try reader.read_events_until_eof() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content=(
          #|InvalidEntity("entity expansion limit exceeded")
        ),
      )
  } noraise {
    _ => fail("expected replacement markup expansion to raise")
  }
}

///|
test "reject entity expansion over the nesting-depth budget" {
  let xml = StringBuilder()
  xml.write_string("<!DOCTYPE root [<!ENTITY e0 \"ok\">")
  for i = 1; i <= 33; i = i + 1 {
    xml.write_string("<!ENTITY e\{i} \"&e\{i - 1};\">")
  }
  xml.write_string("]><root>&e33;</root>")
  let reader = @xml.Reader::from_string(xml.to_string())
  try reader.read_events_until_eof() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content=(
          #|InvalidEntity("entity expansion depth exceeded")
        ),
      )
  } noraise {
    _ => fail("expected deeply nested entity expansion to raise")
  }
}

///|
test "share the entity expansion budget across the document" {
  let xml =
    #|<!DOCTYPE root [
    #|<!ENTITY a "1234567890">
    #|<!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">
    #|<!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
    #|<!ENTITY d "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
    #|<!ENTITY e "&d;&d;&d;&d;&d;&d;&d;&d;&d;&d;">
    #|]><root>&e;&e;&e;</root>

  let reader = @xml.Reader::from_string(xml)
  try reader.read_events_until_eof() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content=(
          #|InvalidEntity("entity expansion limit exceeded")
        ),
      )
  } noraise {
    _ => fail("expected document-wide entity expansion budget to raise")
  }
}

///|
test "reject non-XML whitespace in tag grammar" {
  let reader = @xml.Reader::from_string("<root\u{00A0}id=\"1\"/>")
  try reader.read_event() catch {
    At(error=InvalidSyntax(_), span=_) => ()
    _ => fail("expected an invalid-syntax error")
  } noraise {
    _ => fail("expected non-breaking space in tag grammar to raise")
  }
}

///|
test "reject control characters before end-tag close" {
  let reader = @xml.Reader::from_string("<root></root\u{0001}>")
  let _ = reader.read_event()
  try reader.read_event() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content=(
          #|InvalidSyntax("expected '>' after end tag name")
        ),
      )
  } noraise {
    _ => fail("expected control character in end tag to raise")
  }
}

///|
test "accept the four XML grammar whitespace characters" {
  for whitespace in [" ", "\t", "\n", "\r"] {
    let reader = @xml.Reader::from_string("<root" + whitespace + "id=\"1\"/>")
    @debug.debug_inspect(
      reader.read_event(),
      content=(
        #|Empty({ name: "root", attributes: [("id", "1")] })
      ),
    )
  }
}
