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
/// An XML element with tag name and attributes
pub struct XmlElement {
  name : String
  attributes : Array[(String, String)]
} derive(Show, Eq)

///|
/// Transform attributes to match lxml behavior:
/// - Filter out xmlns namespace declarations
/// - Strip namespace prefixes (a:attr -> attr)
fn transform_attrs_for_libxml(
  attrs : Array[(String, String)],
) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  for attr in attrs {
    let name = attr.0
    if name == "xmlns" || name.has_prefix("xmlns:") {
      // Skip namespace declarations
      continue
    }
    // Strip namespace prefix (a:attr -> attr, xml:lang -> lang)
    let final_name = match name.find(":") {
      Some(idx) => (try! name[idx + 1:]).to_string()
      None => name
    }
    // Attribute value is already normalized by the parser
    result.push((final_name, attr.1))
  }
  result
}

///|
/// Strip namespace prefix from element name (a:foo -> foo)
fn strip_ns_prefix(name : String) -> String {
  match name.find(":") {
    Some(idx) => (try! name[idx + 1:]).to_string()
    None => name
  }
}

///|
pub fn XmlElement::new(name : String) -> XmlElement {
  { name, attributes: [] }
}

///|
pub fn XmlElement::with_attrs(
  name : String,
  attributes : Array[(String, String)],
) -> XmlElement {
  { name, attributes }
}

///|
/// Get an attribute value by name
pub fn XmlElement::get(self : XmlElement, attr_name : String) -> String? {
  for pair in self.attributes {
    if pair.0 == attr_name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// An XML event returned by the parser
pub(all) enum Event {
  /// Start of an XML element: <tag attr="value">
  Start(XmlElement)
  /// End of an XML element: </tag>
  End(String)
  /// Self-closing element: <tag/>
  Empty(XmlElement)
  /// Text content between elements
  Text(String)
  /// CDATA section: <![CDATA[...]]>
  CData(String)
  /// XML comment: <!-- ... -->
  Comment(String)
  /// Processing instruction: <?target data?>
  PI(target~ : String, data~ : String)
  /// XML declaration: <?xml version="1.0"?>
  Decl(version~ : String, encoding~ : String?, standalone~ : String?)
  /// DOCTYPE declaration
  DocType(String)
  /// End of file
  Eof
} derive(Show, Eq)

///|
/// XML parsing error
pub(all) suberror XmlError {
  UnexpectedEof
  InvalidSyntax(String)
  UnmatchedTag(expected~ : String, found~ : String)
  InvalidAttribute(String)
  InvalidEntity(String)
} derive(Show, Eq)

///|
/// Convert events to libxml2/lxml format for conformance testing.
///
/// Handles known differences between our parser and lxml:
/// - Removes prolog whitespace (Text events before first element)
/// - Converts Start+End pairs (no content) to Empty
/// - Fills in default encoding (UTF-8) and standalone (no) for XML declaration
/// - Reorders prolog: Decl first, then DocType, then Comments/PIs
pub fn to_libxml_format(events : Array[Event]) -> Array[Event] {
  let result : Array[Event] = []
  // First pass: collect prolog events and find first element
  let mut first_element_idx = 0
  for i, event in events {
    match event {
      Start(_) | Empty(_) => {
        first_element_idx = i
        break
      }
      _ => ()
    }
  }
  // Process prolog: reorder Decl -> DocType -> others
  let mut decl_event : Event? = None
  let mut doctype_event : Event? = None
  let prolog_others : Array[Event] = []
  for i = 0; i < first_element_idx; i = i + 1 {
    match events[i] {
      Decl(version~, encoding~, standalone~) => {
        // lxml fills in defaults
        let enc = match encoding {
          Some(e) => Some(e)
          None => Some("UTF-8")
        }
        let std = match standalone {
          Some(s) => Some(s)
          None => Some("no")
        }
        decl_event = Some(Decl(version~, encoding=enc, standalone=std))
      }
      DocType(name) => doctype_event = Some(DocType(strip_ns_prefix(name)))
      Text(_) => () // Skip prolog whitespace
      PI(target~, data~) =>
        // lxml trims leading whitespace from PI data
        prolog_others.push(PI(target~, data=data.trim_start().to_string()))
      other => prolog_others.push(other)
    }
  }
  // Emit prolog in lxml order
  match decl_event {
    Some(e) => result.push(e)
    None => ()
  }
  match doctype_event {
    Some(e) => result.push(e)
    None => ()
  }
  for e in prolog_others {
    result.push(e)
  }
  // Process remaining events (from first element onward)
  let len = events.length()
  let mut i = first_element_idx
  while i < len {
    let event = events[i]
    match event {
      Start(elem) => {
        // Transform element name and attributes for lxml compatibility
        let elem_name = strip_ns_prefix(elem.name)
        let filtered_elem = XmlElement::with_attrs(
          elem_name,
          transform_attrs_for_libxml(elem.attributes),
        )
        // Check if next event is matching End (empty element)
        if i + 1 < len {
          match events[i + 1] {
            End(name) =>
              if name == elem.name {
                // Convert Start+End to Empty
                result.push(Empty(filtered_elem))
                i += 2
                continue
              }
            _ => ()
          }
        }
        result.push(Start(filtered_elem))
      }
      Empty(elem) => {
        // Transform element name and attributes for lxml compatibility
        let elem_name = strip_ns_prefix(elem.name)
        let filtered_elem = XmlElement::with_attrs(
          elem_name,
          transform_attrs_for_libxml(elem.attributes),
        )
        result.push(Empty(filtered_elem))
      }
      End(name) =>
        // Strip namespace prefix from end tag
        result.push(End(strip_ns_prefix(name)))
      DocType(name) =>
        // Strip namespace prefix from doctype name
        result.push(DocType(strip_ns_prefix(name)))
      PI(target~, data~) =>
        // lxml trims leading whitespace from PI data
        result.push(PI(target~, data=data.trim_start().to_string()))
      _ => result.push(event)
    }
    i += 1
  }
  result
}
