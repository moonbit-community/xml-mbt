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
test "resolve default namespace without applying it to attributes" {
  let input = "<root xmlns=\"urn:default\" id=\"1\"/>"
  let reader = @xml.NamespaceReader::from_string(input)
  let event = reader.read_event()
  guard event.kind is Empty(element) else { fail("expected an empty element") }
  assert_eq(input[event.span.start.offset:event.span.end.offset], input)
  assert_eq(element.name.qualified_name, "root")
  assert_eq(element.name.prefix, None)
  assert_eq(element.name.local_name, "root")
  assert_eq(element.name.namespace_uri, Some("urn:default"))
  assert_eq(element.attributes.length(), 1)
  assert_eq(element.attributes[0].name.local_name, "id")
  assert_eq(element.attributes[0].name.namespace_uri, None)
  let attribute = element.attributes[0]
  assert_eq(
    input[attribute.span.start.offset:attribute.span.end.offset],
    "id=\"1\"",
  )
  assert_eq(element.namespace_declarations.length(), 1)
  let declaration = element.namespace_declarations[0]
  assert_eq(declaration.prefix, None)
  assert_eq(
    input[declaration.span.start.offset:declaration.span.end.offset],
    "xmlns=\"urn:default\"",
  )
}

///|
test "resolve prefixed element and attribute names" {
  let reader = @xml.NamespaceReader::from_string(
    "<p:root xmlns:p=\"urn:p\" p:id=\"1\" id=\"2\"/>",
  )
  guard reader.read_event().kind is Empty(element) else {
    fail("expected an empty element")
  }
  assert_eq(element.name.prefix, Some("p"))
  assert_eq(element.name.local_name, "root")
  assert_eq(element.name.namespace_uri, Some("urn:p"))
  assert_eq(element.attributes.length(), 2)
  assert_eq(element.attributes[0].name.prefix, Some("p"))
  assert_eq(element.attributes[0].name.namespace_uri, Some("urn:p"))
  assert_eq(element.attributes[1].name.prefix, None)
  assert_eq(element.attributes[1].name.namespace_uri, None)
}

///|
test "restore parent namespace after nested rebinding" {
  let reader = @xml.NamespaceReader::from_string(
    "<root xmlns=\"urn:outer\"><child xmlns=\"urn:inner\">x</child></root>",
  )
  guard reader.read_event().kind is Start(root) else {
    fail("expected root start")
  }
  assert_eq(root.name.namespace_uri, Some("urn:outer"))
  guard reader.read_event().kind is Start(child) else {
    fail("expected child start")
  }
  assert_eq(child.name.namespace_uri, Some("urn:inner"))
  guard reader.read_event().kind is Text("x") else {
    fail("expected child text")
  }
  guard reader.read_event().kind is End(child_name) else {
    fail("expected child end")
  }
  assert_eq(child_name.namespace_uri, Some("urn:inner"))
  guard reader.read_event().kind is End(root_name) else {
    fail("expected root end")
  }
  assert_eq(root_name.namespace_uri, Some("urn:outer"))
}

///|
test "reject undeclared namespace prefix" {
  let input = "<p:root/>"
  let reader = @xml.NamespaceReader::from_string(input)
  try reader.read_event() catch {
    At(error~, span~) => {
      @debug.debug_inspect(
        error,
        content="InvalidSyntax(\"undeclared namespace prefix: p\")",
      )
      assert_eq(input[span.start.offset:span.end.offset], input)
    }
  } noraise {
    _ => fail("expected namespace resolution to raise")
  }
}

///|
test "reject duplicate expanded attribute names" {
  let reader = @xml.NamespaceReader::from_string(
    "<root xmlns:a=\"urn:x\" xmlns:b=\"urn:x\" a:id=\"1\" b:id=\"2\"/>",
  )
  try reader.read_event() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content="InvalidSyntax(\"duplicate expanded attribute name: {urn:x}id\")",
      )
  } noraise {
    _ => fail("expected namespace resolution to raise")
  }
}

///|
test "reject invalid qualified name" {
  let reader = @xml.NamespaceReader::from_string("<a:b:c/>")
  try reader.read_event() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content="InvalidSyntax(\"invalid qualified name: a:b:c\")",
      )
  } noraise {
    _ => fail("expected namespace resolution to raise")
  }
}

///|
test "enforce reserved xml namespace binding" {
  let reader = @xml.NamespaceReader::from_string(
    "<root xmlns:xml=\"urn:not-xml\"/>",
  )
  try reader.read_event() catch {
    At(error~, span=_) =>
      @debug.debug_inspect(
        error,
        content=(
          #|InvalidSyntax("prefix 'xml' must be bound to http://www.w3.org/XML/1998/namespace")
        ),
      )
  } noraise {
    _ => fail("expected namespace resolution to raise")
  }
}
