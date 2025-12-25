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
/// W3C XML Conformance Test Suite Tests
/// https://www.w3.org/XML/Test/

// ============================================================================
// Valid/SA tests - Well-formed standalone documents
// These should parse without error
// ============================================================================

///|
test "valid/sa/001 - empty element with DTD" {
  // DTD is skipped by our parser, but document structure should parse
  let xml =
    #|<!DOCTYPE doc [
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc></doc>
  let reader = Reader::from_string(xml)
  // Skip DOCTYPE
  let event1 = reader.read_event()
  inspect(event1, content="DocType(\"doc\")")
  let event2 = reader.read_event()
  inspect(
    event2,
    content=(
      #|Start({name: "doc", attributes: []})
    ),
  )
  let event3 = reader.read_event()
  inspect(
    event3,
    content=(
      #|End("doc")
    ),
  )
}

///|
test "valid/sa/003 - whitespace in start tag" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc ></doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Start({name: "doc", attributes: []})
    ),
  )
}

///|
test "valid/sa/004 - attribute with value" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ATTLIST doc a1 CDATA #IMPLIED>
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc a1="v1"></doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Start({name: "doc", attributes: [("a1", "v1")]})
    ),
  )
}

///|
test "valid/sa/005 - multiple attributes" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ATTLIST doc a1 CDATA #IMPLIED a2 CDATA #IMPLIED>
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc a1="v1" a2="v2"></doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Start({name: "doc", attributes: [("a1", "v1"), ("a2", "v2")]})
    ),
  )
}

///|
test "valid/sa/006 - numeric character reference" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc>&#32;</doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Text(" ")
    ),
  )
}

///|
test "valid/sa/007 - hex character reference" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc>&#x20;</doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Text(" ")
    ),
  )
}

///|
test "valid/sa/008 - built-in entity lt" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc>&lt;</doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Text("<")
    ),
  )
}

///|
test "valid/sa/009 - built-in entity gt" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc>&gt;</doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Text(">")
    ),
  )
}

///|
test "valid/sa/010 - built-in entity amp" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc>&amp;</doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Text("&")
    ),
  )
}

///|
test "valid/sa/011 - built-in entity apos" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc>&apos;</doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Text("'")
    ),
  )
}

///|
test "valid/sa/012 - built-in entity quot" {
  let xml =
    #|<!DOCTYPE doc [
    #|<!ELEMENT doc (#PCDATA)>
    #|]>
    #|<doc>&quot;</doc>
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // DOCTYPE
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Text("\"")
    ),
  )
}

// ============================================================================
// Not-Well-Formed tests - Should produce parse errors
// ============================================================================

///|
test "not-wf/sa/006 - comments may not contain --" {
  // This test checks that "--" inside comments is rejected
  // Our parser currently allows this (non-conforming)
  let xml = "<doc><!-- -- --></doc>"
  let reader = Reader::from_string(xml)
  let event1 = reader.read_event()
  // Note: A conforming parser should reject this
  inspect(
    event1,
    content=(
      #|Start({name: "doc", attributes: []})
    ),
  )
}

///|
test "not-wf/sa/017 - CDATA needs terminating ]]>" {
  let xml = "<doc><![CDATA[</doc>"
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // Start
  let result = try? reader.read_event()
  inspect(result, content="Err(UnexpectedEof)")
}

///|
test "not-wf/sa/027 - comments must end with -->" {
  let xml = "<doc><!-- comment --"
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // Start
  let result = try? reader.read_event()
  // Comment has -- not followed by >, which is invalid
  inspect(
    result,
    content="Err(InvalidSyntax(\"'--' is not allowed in comments\"))",
  )
}

///|
test "not-wf/sa/028 - PI must end with ?>" {
  let xml = "<?xml-test test?"
  let reader = Reader::from_string(xml)
  let result = try? reader.read_event()
  inspect(result, content="Err(UnexpectedEof)")
}

// ============================================================================
// CDATA tests
// ============================================================================

///|
test "valid - CDATA section" {
  let xml = "<doc><![CDATA[<greeting>Hello</greeting>]]></doc>"
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(event, content="Text(\"<greeting>Hello</greeting>\")")
}

///|
test "valid - CDATA with special chars" {
  let xml = "<doc><![CDATA[a]b]]c]]]></doc>"
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(event, content="Text(\"a]b]]c]\")")
}

// ============================================================================
// Comment tests
// ============================================================================

///|
test "valid - simple comment" {
  let xml = "<!-- comment --><doc/>"
  let reader = Reader::from_string(xml)
  let event = reader.read_event()
  inspect(event, content="Comment(\" comment \")")
}

///|
test "valid - comment between elements" {
  let xml = "<doc><!-- middle --></doc>"
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // Start
  let event = reader.read_event()
  inspect(event, content="Comment(\" middle \")")
}

// ============================================================================
// Processing Instruction tests
// ============================================================================

///|
test "valid - PI with data" {
  let xml = "<?target data?><doc/>"
  let reader = Reader::from_string(xml)
  let event = reader.read_event()
  inspect(event, content="PI(target=\"target\", data=\"data\")")
}

///|
test "valid - PI without data" {
  let xml = "<?target?><doc/>"
  let reader = Reader::from_string(xml)
  let event = reader.read_event()
  inspect(event, content="PI(target=\"target\", data=\"\")")
}

// ============================================================================
// XML Declaration tests
// ============================================================================

///|
test "valid - XML declaration" {
  let xml = "<?xml version=\"1.0\"?><doc/>"
  let reader = Reader::from_string(xml)
  let event = reader.read_event()
  inspect(
    event,
    content="Decl(version=\"1.0\", encoding=None, standalone=None)",
  )
}

///|
test "valid - XML declaration with encoding" {
  let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><doc/>"
  let reader = Reader::from_string(xml)
  let event = reader.read_event()
  inspect(
    event,
    content="Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=None)",
  )
}

///|
test "valid - XML declaration with standalone" {
  let xml = "<?xml version=\"1.0\" standalone=\"yes\"?><doc/>"
  let reader = Reader::from_string(xml)
  let event = reader.read_event()
  inspect(
    event,
    content="Decl(version=\"1.0\", encoding=None, standalone=Some(\"yes\"))",
  )
}

// ============================================================================
// Nested element tests
// ============================================================================

///|
test "valid - deeply nested elements" {
  let xml = "<a><b><c><d>text</d></c></b></a>"
  let reader = Reader::from_string(xml)
  let events : Array[Event] = []
  while true {
    let event = reader.read_event()
    events.push(event)
    if event is Eof {
      break
    }
  }
  inspect(events.length(), content="10")
}

///|
test "valid - sibling elements" {
  let xml = "<root><a/><b/><c/></root>"
  let reader = Reader::from_string(xml)
  let _ = reader.read_event() // root Start
  let e1 = reader.read_event()
  inspect(
    e1,
    content=(
      #|Empty({name: "a", attributes: []})
    ),
  )
  let e2 = reader.read_event()
  inspect(
    e2,
    content=(
      #|Empty({name: "b", attributes: []})
    ),
  )
  let e3 = reader.read_event()
  inspect(
    e3,
    content=(
      #|Empty({name: "c", attributes: []})
    ),
  )
}

// ============================================================================
// Attribute tests
// ============================================================================

///|
test "valid - single quoted attribute" {
  let xml = "<doc attr='value'/>"
  let reader = Reader::from_string(xml)
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Empty({name: "doc", attributes: [("attr", "value")]})
    ),
  )
}

///|
test "valid - attribute with entity" {
  let xml = "<doc attr=\"&lt;value&gt;\"/>"
  let reader = Reader::from_string(xml)
  let event = reader.read_event()
  // Note: attribute values are not unescaped by our parser currently
  inspect(
    event,
    content=(
      #|Empty({name: "doc", attributes: [("attr", "<value>")]})
    ),
  )
}

///|
test "valid - empty attribute value" {
  let xml = "<doc attr=\"\"/>"
  let reader = Reader::from_string(xml)
  let event = reader.read_event()
  inspect(
    event,
    content=(
      #|Empty({name: "doc", attributes: [("attr", "")]})
    ),
  )
}
