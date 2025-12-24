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
  let reader = Reader::from_string("<root></root>")
  let event1 = reader.read_event()
  inspect(
    event1,
    content=(
      #|Start({name: "root", attributes: []})
    ),
  )
  let event2 = reader.read_event()
  inspect(event2, content="End(\"root\")")
  let event3 = reader.read_event()
  inspect(event3, content="Eof")
}

///|
test "parse self-closing element" {
  let reader = Reader::from_string("<br/>")
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Empty({name: "br", attributes: []})
    ),
  )
}

///|
test "parse element with text" {
  let reader = Reader::from_string("<p>Hello World</p>")
  let event1 = reader.read_event()
  inspect(
    event1,
    content=(
      #|Start({name: "p", attributes: []})
    ),
  )
  let event2 = reader.read_event()
  inspect(event2, content="Text(\"Hello World\")")
  let event3 = reader.read_event()
  inspect(event3, content="End(\"p\")")
}

///|
test "parse nested elements" {
  let reader = Reader::from_string("<div><span>text</span></div>")
  let event1 = reader.read_event()
  inspect(
    event1,
    content=(
      #|Start({name: "div", attributes: []})
    ),
  )
  let event2 = reader.read_event()
  inspect(
    event2,
    content=(
      #|Start({name: "span", attributes: []})
    ),
  )
  let event3 = reader.read_event()
  inspect(event3, content="Text(\"text\")")
  let event4 = reader.read_event()
  inspect(event4, content="End(\"span\")")
  let event5 = reader.read_event()
  inspect(event5, content="End(\"div\")")
}

// ============================================================================
// Attributes
// ============================================================================

///|
test "parse element with single attribute" {
  let reader = Reader::from_string("<div id=\"main\"></div>")
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Start({name: "div", attributes: [("id", "main")]})
    ),
  )
}

///|
test "parse element with multiple attributes" {
  let reader = Reader::from_string(
    "<input type=\"text\" name=\"field\" value=\"hello\"/>",
  )
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Empty({name: "input", attributes: [("type", "text"), ("name", "field"), ("value", "hello")]})
    ),
  )
}

///|
test "parse attribute with single quotes" {
  let reader = Reader::from_string("<div class='container'></div>")
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Start({name: "div", attributes: [("class", "container")]})
    ),
  )
}

// ============================================================================
// Special Content
// ============================================================================

///|
test "parse XML comment" {
  let reader = Reader::from_string("<!-- This is a comment -->")
  let event = reader.read_event()
  inspect(event, content="Comment(\" This is a comment \")")
}

///|
test "parse CDATA section" {
  let reader = Reader::from_string("<![CDATA[<html>raw content</html>]]>")
  let event = reader.read_event()
  inspect(event, content="CData(\"<html>raw content</html>\")")
}

///|
test "parse processing instruction" {
  let reader = Reader::from_string(
    "<?xml-stylesheet type=\"text/xsl\" href=\"style.xsl\"?>",
  )
  let event = reader.read_event()
  inspect(
    event,
    content="PI(target=\"xml-stylesheet\", data=\"type=\\\"text/xsl\\\" href=\\\"style.xsl\\\"\")",
  )
}

///|
test "parse XML declaration" {
  let reader = Reader::from_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
  let event = reader.read_event()
  inspect(
    event,
    content="Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=None)",
  )
}

///|
test "parse DOCTYPE" {
  let reader = Reader::from_string("<!DOCTYPE html>")
  let event = reader.read_event()
  inspect(event, content="DocType(\"html\")")
}

// ============================================================================
// Entity Handling
// ============================================================================

///|
test "parse text with entities" {
  let reader = Reader::from_string(
    "<p>&lt;hello&gt; &amp; &quot;world&quot;</p>",
  )
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(event, content="Text(\"<hello> & \\\"world\\\"\")")
}

///|
test "parse numeric entities" {
  let reader = Reader::from_string("<p>&#65;&#x42;</p>")
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(event, content="Text(\"AB\")")
}

// ============================================================================
// Whitespace Handling
// ============================================================================

///|
test "preserve whitespace in text" {
  let reader = Reader::from_string("<pre>  hello\n  world  </pre>")
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Text("  hello\n  world  ")
    ),
  )
}

///|
test "parse with leading whitespace" {
  let reader = Reader::from_string("  <root/>")
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Text("  ")
    ),
  )
}

// ============================================================================
// Error Handling
// ============================================================================

///|
test "error on unclosed tag" {
  let reader = Reader::from_string("<root>")
  let _ = reader.read_event() // Start
  let result = try? reader.read_event()
  inspect(result, content="Ok(Eof)")
}

///|
test "error on mismatched tags" {
  let reader = Reader::from_string("<root></other>")
  let _ = reader.read_event() // Start
  let result = try? reader.read_event()
  inspect(
    result,
    content=(
      #|Ok(End("other"))
    ),
  )
}

///|
test "error on invalid syntax" {
  let reader = Reader::from_string("<root<>")
  let result = try? reader.read_event()
  inspect(
    result,
    content=(
      #|Err(InvalidSyntax("expected '>' or '/>' at end of start tag"))
    ),
  )
}
