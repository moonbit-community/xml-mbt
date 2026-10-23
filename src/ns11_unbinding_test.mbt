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
/// Namespaces in XML 1.1 §2.2: xmlns:p="" undoes the prefix binding.
/// XML 1.0 keeps rejecting it. The default-namespace branch already
/// implemented the 1.1 behavior; the prefixed branch now matches it.
/// Regression for W3C XML conformance suite eduni/namespaces/1.1/003.xml
/// and 004.xml.

///|
test "ns11/1.1 prefix unbinding is accepted" {
  // eduni/namespaces/1.1/003.xml (W3C XML conformance suite, verbatim).
  let input = "<?xml version=\"1.1\"?><!DOCTYPE foo [<!ELEMENT foo (bar)><!ATTLIST foo xmlns:a CDATA #IMPLIED><!ELEMENT bar EMPTY><!ATTLIST bar xmlns:a CDATA #IMPLIED>]><foo xmlns:a=\"http://example.org/namespace\"><bar xmlns:a=\"\"/></foo>"
  let _ = @xml.NamespaceReader::from_string(input).read_events_until_eof()
}

///|
test "ns11/1.1 prefix unbinding and rebinding is accepted" {
  // eduni/namespaces/1.1/004.xml (W3C XML conformance suite, verbatim).
  let input = "<?xml version=\"1.1\"?><!DOCTYPE foo [<!ELEMENT foo (bar?)><!ATTLIST foo xmlns:a CDATA #IMPLIED a:attr CDATA #IMPLIED><!ELEMENT bar (foo)><!ATTLIST bar xmlns:a CDATA #IMPLIED>]><foo xmlns:a=\"http://example.org/namespace\"><bar xmlns:a=\"\"><foo xmlns:a=\"http://example.org/other-namespace\" a:attr=\"1\"/></bar></foo>"
  let events = @xml.NamespaceReader::from_string(input).read_events_until_eof()
  // a:attr inside the rebound scope resolves to the new namespace URI.
  let mut rebound_uri = ""
  for event in events {
    if event.kind is Empty(element) {
      for attribute in element.attributes {
        if attribute.name.qualified_name == "a:attr" {
          rebound_uri = attribute.name.namespace_uri.unwrap_or("")
        }
      }
    }
  }
  assert_eq(rebound_uri, "http://example.org/other-namespace")
}

///|
/// Namespace validation lives in the namespace-aware reader; the raw reader
/// treats xmlns attributes as plain attributes.
fn assert_rejected_namespace_document(input : String) -> Unit raise {
  try @xml.NamespaceReader::from_string(input).read_events_until_eof() catch {
    At(_) => ()
  } noraise {
    _ => fail("expected malformed XML to be rejected: " + input)
  }
}

///|
test "ns11/1.0 prefix unbinding stays rejected" {
  assert_rejected_namespace_document(
    "<?xml version=\"1.0\"?><foo xmlns:a=\"u\"><bar xmlns:a=\"\"/></foo>",
  )
  // Without a declaration the document is not 1.1; unbinding stays rejected.
  assert_rejected_namespace_document(
    "<foo xmlns:a=\"u\"><bar xmlns:a=\"\"/></foo>",
  )
}
