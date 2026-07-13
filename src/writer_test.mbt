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
/// Tests for XML Writer

///|
test "write simple element" {
  let w = Writer::new()
  w.start_element("root", [])
  w.end_element("root")
  @debug.debug_inspect(
    w.to_string(),
    content=(
      #|"<root></root>"
    ),
  )
}

///|
test "write self-closing element" {
  let w = Writer::new()
  w.empty_element("br", [])
  @debug.debug_inspect(
    w.to_string(),
    content=(
      #|"<br/>"
    ),
  )
}

///|
test "write element with text" {
  let w = Writer::new()
  w.start_element("p", [])
  w.text("Hello World")
  w.end_element("p")
  @debug.debug_inspect(
    w.to_string(),
    content=(
      #|"<p>Hello World</p>"
    ),
  )
}

///|
test "write element with attributes" {
  let w = Writer::new()
  w.start_element("div", [("id", "main"), ("class", "container")])
  w.end_element("div")
  @debug.debug_inspect(
    w.to_string(),
    content=(
      #|"<div id=\"main\" class=\"container\"></div>"
    ),
  )
}

///|
test "write nested elements" {
  let w = Writer::new()
  w.start_element("ul", [])
  w.start_element("li", [])
  w.text("Item 1")
  w.end_element("li")
  w.start_element("li", [])
  w.text("Item 2")
  w.end_element("li")
  w.end_element("ul")
  @debug.debug_inspect(
    w.to_string(),
    content=(
      #|"<ul><li>Item 1</li><li>Item 2</li></ul>"
    ),
  )
}

///|
test "write CDATA" {
  let w = Writer::new()
  w.start_element("script", [])
  w.cdata("var x = 1 < 2;")
  w.end_element("script")
  @debug.debug_inspect(
    w.to_string(),
    content=(
      #|"<script><![CDATA[var x = 1 < 2;]]></script>"
    ),
  )
}

///|
test "write comment" {
  let w = Writer::new()
  w.comment(" This is a comment ")
  w.empty_element("root", [])
  @debug.debug_inspect(
    w.to_string(),
    content=(
      #|"<!-- This is a comment --><root/>"
    ),
  )
}

///|
test "write text with escaping" {
  let w = Writer::new()
  w.start_element("p", [])
  w.text("<script>alert('xss')</script>")
  w.end_element("p")
  @debug.debug_inspect(
    w.to_string(),
    content=(
      #|"<p>&lt;script&gt;alert(&apos;xss&apos;)&lt;/script&gt;</p>"
    ),
  )
}

///|
test "write using events" {
  let w = Writer::new()
  let reader = Reader::from_string("<div id=\"main\">content</div>")
  for ;; {
    let event = reader.read_event()
    w.write_event(event)
    if event.kind is Eof {
      break
    }
  }
  @debug.debug_inspect(
    w.to_string(),
    content=(
      #|"<div id=\"main\">content</div>"
    ),
  )
}

///|
test "write prolog and miscellaneous events" {
  let xml = "<?xml version=\"1.0\"?><!DOCTYPE root><?build ok?><root><!--ok--></root>"
  let reader = Reader::from_string(xml)
  let w = Writer::new()
  for ;; {
    let event = reader.read_event()
    w.write_event(event)
    if event.kind is Eof {
      break
    }
  }
  assert_eq(w.to_string(), xml)
}

///|
test "reject invalid element names" {
  let w = Writer::new()
  try w.empty_element("bad name", []) catch {
    InvalidName(message) => assert_eq(message, "invalid element name: bad name")
    _ => fail("expected invalid-name writer error")
  } noraise {
    _ => fail("expected invalid element name to raise")
  }
}

///|
test "reject invalid attribute names" {
  let w = Writer::new()
  try w.empty_element("root", [("bad name", "value")]) catch {
    InvalidName(message) =>
      assert_eq(message, "invalid attribute name: bad name")
    _ => fail("expected invalid-name writer error")
  } noraise {
    _ => fail("expected invalid attribute name to raise")
  }
}

///|
test "reject invalid XML characters in text" {
  let w = Writer::new()
  w.start_element("root", [])
  try w.text("bad\u{0001}text") catch {
    InvalidContent(message) =>
      assert_eq(message, "invalid XML character in text")
    _ => fail("expected invalid-content writer error")
  } noraise {
    _ => fail("expected invalid XML character to raise")
  }
}

///|
test "reject invalid XML comment text" {
  let w = Writer::new()
  try w.comment("a--b") catch {
    InvalidContent(message) =>
      assert_eq(message, "comment cannot contain '--' or end with '-'")
    _ => fail("expected invalid-content writer error")
  } noraise {
    _ => fail("expected invalid comment text to raise")
  }
}

///|
test "reject comments ending with a hyphen" {
  let w = Writer::new()
  try w.comment("trailing-") catch {
    InvalidContent(message) =>
      assert_eq(message, "comment cannot contain '--' or end with '-'")
    _ => fail("expected invalid-content writer error")
  } noraise {
    _ => fail("expected trailing hyphen in comment to raise")
  }
}

///|
test "reject invalid CDATA text" {
  let w = Writer::new()
  w.start_element("root", [])
  try w.cdata("x]]>y") catch {
    InvalidContent(message) => assert_eq(message, "CDATA cannot contain ']]>'")
    _ => fail("expected invalid-content writer error")
  } noraise {
    _ => fail("expected invalid CDATA text to raise")
  }
}

///|
test "reject invalid XML characters in attribute values" {
  let w = Writer::new()
  try w.empty_element("root", [("id", "bad\u{0001}value")]) catch {
    InvalidContent(message) =>
      assert_eq(message, "invalid XML character in attribute value")
    _ => fail("expected invalid-content writer error")
  } noraise {
    _ => fail("expected invalid attribute value to raise")
  }
}

///|
test "reject duplicate attributes" {
  let w = Writer::new()
  try w.empty_element("root", [("id", "1"), ("id", "2")]) catch {
    InvalidStructure(message) => assert_eq(message, "duplicate attribute: id")
    _ => fail("expected invalid-structure writer error")
  } noraise {
    _ => fail("expected duplicate attributes to raise")
  }
}

///|
test "reject mismatched end elements" {
  let w = Writer::new()
  w.start_element("root", [])
  try w.end_element("other") catch {
    InvalidStructure(message) =>
      assert_eq(message, "end element mismatch: expected root, found other")
    _ => fail("expected invalid-structure writer error")
  } noraise {
    _ => fail("expected mismatched end element to raise")
  }
}

///|
test "reject multiple root elements" {
  let w = Writer::new()
  w.empty_element("first", [])
  try w.empty_element("second", []) catch {
    InvalidStructure(message) =>
      assert_eq(message, "document cannot contain multiple root elements")
    _ => fail("expected invalid-structure writer error")
  } noraise {
    _ => fail("expected second root element to raise")
  }
}

///|
test "reject non-whitespace text outside the root element" {
  let w = Writer::new()
  try w.text("outside") catch {
    InvalidStructure(message) =>
      assert_eq(message, "non-whitespace text is not allowed outside the root")
    _ => fail("expected invalid-structure writer error")
  } noraise {
    _ => fail("expected text outside the root to raise")
  }
}

///|
test "reject incomplete documents when finishing" {
  let w = Writer::new()
  w.start_element("root", [])
  try w.to_string() catch {
    InvalidStructure(message) => assert_eq(message, "unclosed element: root")
    _ => fail("expected invalid-structure writer error")
  } noraise {
    _ => fail("expected incomplete document to raise")
  }
}

///|
test "reject documents without a root element" {
  let w = Writer::new()
  w.comment("no root")
  try w.to_string() catch {
    InvalidStructure(message) =>
      assert_eq(message, "document has no root element")
    _ => fail("expected invalid-structure writer error")
  } noraise {
    _ => fail("expected rootless document to raise")
  }
}

///|
test "reject CDATA outside the root element" {
  let w = Writer::new()
  try w.cdata("outside") catch {
    InvalidStructure(message) =>
      assert_eq(message, "CDATA is only allowed inside an element")
    _ => fail("expected invalid-structure writer error")
  } noraise {
    _ => fail("expected CDATA outside the root to raise")
  }
}

///|
test "reject XML declarations after other output" {
  let reader = Reader::from_string("<?xml version=\"1.0\"?><root/>")
  let declaration = reader.read_event()
  let w = Writer::new()
  w.comment("before declaration")
  try w.write_event(declaration) catch {
    InvalidDeclaration(message) =>
      assert_eq(message, "XML declaration must be the first output")
    _ => fail("expected invalid-declaration writer error")
  } noraise {
    _ => fail("expected misplaced XML declaration to raise")
  }
}
