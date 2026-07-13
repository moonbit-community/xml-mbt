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
test "event spans use UTF-16 offsets and character-based columns" {
  let input = "<root>😀</root>"
  let reader = Reader::from_string(input)
  let start = reader.read_event()
  assert_eq(input[start.span.start.offset:start.span.end.offset], "<root>")
  assert_eq(start.span.start.line, 1)
  assert_eq(start.span.start.column, 1)
  assert_eq(start.span.end.column, 7)
  let text = reader.read_event()
  assert_eq(text.kind, Text("😀"))
  assert_eq(text.span.start.offset, 6)
  assert_eq(text.span.end.offset, 8)
  assert_eq(text.span.start.column, 7)
  assert_eq(text.span.end.column, 8)
  assert_eq(input[text.span.start.offset:text.span.end.offset], "😀")
}

///|
test "start events expose whole, name, and value attribute spans" {
  let input = "<root id='a&amp;b'/>"
  let reader = Reader::from_string(input)
  let event = reader.read_event()
  guard event.kind is Empty(element) else { fail("expected empty element") }
  assert_eq(element.attributes.length(), 1)
  let attribute = element.attributes[0]
  assert_eq(attribute.name, "id")
  assert_eq(attribute.value, "a&b")
  assert_eq(
    input[attribute.span.start.offset:attribute.span.end.offset],
    "id='a&amp;b'",
  )
  assert_eq(
    input[attribute.name_span.start.offset:attribute.name_span.end.offset],
    "id",
  )
  assert_eq(
    input[attribute.value_span.start.offset:attribute.value_span.end.offset],
    "a&amp;b",
  )
}

///|
test "split text events retain their authored source ranges" {
  let reader = Reader::from_string("<root>a&amp;b</root>")
  let _ = reader.read_event()
  let before = reader.read_event()
  let entity = reader.read_event()
  let after = reader.read_event()
  assert_eq(before.kind, Text("a"))
  assert_eq((before.span.start.offset, before.span.end.offset), (6, 7))
  assert_eq(entity.kind, Text("&"))
  assert_eq((entity.span.start.offset, entity.span.end.offset), (7, 12))
  assert_eq(after.kind, Text("b"))
  assert_eq((after.span.start.offset, after.span.end.offset), (12, 13))
}

///|
test "parsing reports the source span of errors" {
  let reader = Reader::from_string("<root id=>")
  try reader.read_event() catch {
    At(error~, span~) => {
      assert_eq(error, InvalidSyntax("expected quoted attribute value"))
      assert_eq((span.start.offset, span.end.offset), (0, 9))
      assert_eq((span.start.line, span.start.column), (1, 1))
      assert_eq((span.end.line, span.end.column), (1, 10))
    }
  } noraise {
    _ => fail("expected parsing to raise")
  }
}

///|
test "unclosed element errors point to the opening tag" {
  let reader = Reader::from_string("<root>")
  let _ = reader.read_event()
  try reader.read_event() catch {
    At(error~, span~) => {
      assert_eq(error, InvalidSyntax("unclosed element: <root>"))
      assert_eq((span.start.offset, span.end.offset), (0, 6))
      assert_eq((span.start.line, span.start.column), (1, 1))
      assert_eq((span.end.line, span.end.column), (1, 7))
    }
  } noraise {
    _ => fail("expected unclosed element to raise")
  }
}

///|
test "nested unclosed element errors point to the innermost opening tag" {
  let reader = Reader::from_string("<root>\n  <child>")
  let _ = reader.read_event()
  let _ = reader.read_event()
  let _ = reader.read_event()
  try reader.read_event() catch {
    At(error~, span~) => {
      assert_eq(error, InvalidSyntax("unclosed element: <child>"))
      assert_eq((span.start.offset, span.end.offset), (9, 16))
      assert_eq((span.start.line, span.start.column), (2, 3))
      assert_eq((span.end.line, span.end.column), (2, 10))
    }
  } noraise {
    _ => fail("expected nested unclosed element to raise")
  }
}

///|
test "error spans treat a carriage return as a source line break" {
  let reader = Reader::from_string("<root>\r<child id=>")
  let _ = reader.read_event()
  let _ = reader.read_event()
  try reader.read_event() catch {
    At(error=_, span~) => {
      assert_eq((span.start.offset, span.end.offset), (7, 17))
      assert_eq((span.start.line, span.start.column), (2, 1))
      assert_eq((span.end.line, span.end.column), (2, 11))
    }
  } noraise {
    _ => fail("expected parsing to raise")
  }
}

///|
test "queued internal subset events retain their authored ranges" {
  let input = "<!DOCTYPE root [<!--inside--><?pi data?>]>\n<root/>"
  let reader = Reader::from_string(input)
  let _ = reader.read_event()
  let _ = reader.read_event()
  let comment = reader.read_event()
  assert_eq(comment.kind, Comment("inside"))
  assert_eq(
    input[comment.span.start.offset:comment.span.end.offset],
    "<!--inside-->",
  )
  let pi = reader.read_event()
  assert_eq(pi.kind, PI(target="pi", data="data"))
  assert_eq(input[pi.span.start.offset:pi.span.end.offset], "<?pi data?>")
}

///|
test "markup expanded from an entity maps back to the entity reference" {
  let input = "<!DOCTYPE root [<!ENTITY child \"<child id='1'/>\">]><root>&child;</root>"
  let reader = Reader::from_string(input)
  let _ = reader.read_event()
  let _ = reader.read_event()
  let child = reader.read_event()
  guard child.kind is Empty(element) else {
    fail("expected expanded child element")
  }
  assert_eq(element.name, "child")
  assert_eq(input[child.span.start.offset:child.span.end.offset], "&child;")
  assert_eq(element.attributes.length(), 1)
  assert_eq(element.attributes[0].span, child.span)
}
