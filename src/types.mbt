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
  attributes : Array[XmlAttribute]
} derive(Eq)

///|
priv struct DebugXmlElement {
  name : String
  attributes : Array[(String, String)]
} derive(Debug)

///|
/// Transform attributes to match lxml behavior:
/// - Filter out xmlns namespace declarations
/// - Strip namespace prefixes (a:attr -> attr)
fn transform_attrs_for_libxml(
  attrs : Array[XmlAttribute],
) -> Array[XmlAttribute] {
  let result : Array[XmlAttribute] = []
  for attr in attrs {
    let name = attr.name
    if name == "xmlns" || name.has_prefix("xmlns:") {
      // Skip namespace declarations
      continue
    }
    // Strip namespace prefix (a:attr -> attr, xml:lang -> lang)
    let final_name = match name.find(":") {
      Some(idx) => name[idx + 1:].to_owned()
      None => name
    }
    // Attribute value is already normalized by the parser
    result.push({
      name: final_name,
      value: attr.value,
      span: attr.span,
      name_span: attr.name_span,
      value_span: attr.value_span,
    })
  }
  result
}

///|
/// Strip namespace prefix from element name (a:foo -> foo)
fn strip_ns_prefix(name : String) -> String {
  match name.find(":") {
    Some(idx) => name[idx + 1:].to_owned()
    None => name
  }
}

///|
/// Get an attribute value by name
pub fn XmlElement::get(self : XmlElement, attr_name : String) -> String? {
  for pair in self.attributes {
    if pair.name == attr_name {
      return Some(pair.value)
    }
  }
  None
}

///|
/// An XML event returned by the parser
pub(all) enum EventKind {
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
} derive(Debug, Eq)

///|
/// XML parsing error
pub(all) suberror XmlErrorKind {
  UnexpectedEof
  InvalidSyntax(String)
  UnmatchedTag(expected~ : String, found~ : String)
  InvalidAttribute(String)
  InvalidEntity(String)
} derive(Debug, Eq)

///|
pub impl Show for XmlElement with fn output(self, logger) {
  logger.write_string("{name: ")
  logger.write_object(self.name)
  logger.write_string(", attributes: ")
  logger.write_object(
    to_repr(
      self.attributes.map(fn(attribute) { (attribute.name, attribute.value) }),
    ),
  )
  logger.write_string("}")
}

///|
pub impl Debug for XmlElement with fn to_repr(self) {
  let debug : DebugXmlElement = {
    name: self.name,
    attributes: self.attributes.map(fn(attribute) {
      (attribute.name, attribute.value)
    }),
  }
  to_repr(debug)
}

///|
pub impl Debug for Event with fn to_repr(self) {
  to_repr(self.kind)
}

///|
pub impl Show for Event with fn output(self, logger) {
  logger.write_object(self.kind)
}

///|
pub impl Show for EventKind with fn output(self, logger) {
  match self {
    Start(elem) => {
      logger.write_string("Start(")
      logger.write_object(elem)
      logger.write_string(")")
    }
    End(name) => {
      logger.write_string("End(")
      logger.write_object(name)
      logger.write_string(")")
    }
    Empty(elem) => {
      logger.write_string("Empty(")
      logger.write_object(elem)
      logger.write_string(")")
    }
    Text(content) => {
      logger.write_string("Text(")
      logger.write_object(content)
      logger.write_string(")")
    }
    CData(content) => {
      logger.write_string("CData(")
      logger.write_object(content)
      logger.write_string(")")
    }
    Comment(content) => {
      logger.write_string("Comment(")
      logger.write_object(content)
      logger.write_string(")")
    }
    PI(target~, data~) => {
      logger.write_string("PI(target=")
      logger.write_object(target)
      logger.write_string(", data=")
      logger.write_object(data)
      logger.write_string(")")
    }
    Decl(version~, encoding~, standalone~) => {
      logger.write_string("Decl(version=")
      logger.write_object(version)
      logger.write_string(", encoding=")
      logger.write_object(to_repr(encoding))
      logger.write_string(", standalone=")
      logger.write_object(to_repr(standalone))
      logger.write_string(")")
    }
    DocType(name) => {
      logger.write_string("DocType(")
      logger.write_object(name)
      logger.write_string(")")
    }
    Eof => logger.write_string("Eof")
  }
}

///|
pub impl Show for XmlErrorKind with fn output(self, logger) {
  match self {
    UnexpectedEof => logger.write_string("UnexpectedEof")
    InvalidSyntax(message) => {
      logger.write_string("InvalidSyntax(")
      logger.write_object(message)
      logger.write_string(")")
    }
    UnmatchedTag(expected~, found~) => {
      logger.write_string("UnmatchedTag(expected=")
      logger.write_object(expected)
      logger.write_string(", found=")
      logger.write_object(found)
      logger.write_string(")")
    }
    InvalidAttribute(message) => {
      logger.write_string("InvalidAttribute(")
      logger.write_object(message)
      logger.write_string(")")
    }
    InvalidEntity(message) => {
      logger.write_string("InvalidEntity(")
      logger.write_object(message)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for XmlError with fn output(self, logger) {
  match self {
    At(error~, span~) => {
      logger.write_object(error)
      logger.write_string(" at ")
      logger.write_object(span.start.line)
      logger.write_string(":")
      logger.write_object(span.start.column)
      logger.write_string("-")
      logger.write_object(span.end.line)
      logger.write_string(":")
      logger.write_object(span.end.column)
    }
  }
}

///|
/// Push an event into `result`, coalescing adjacent `Text(...)` events.
///
/// lxml (and many streaming parsers) may split text into multiple adjacent
/// chunks; for conformance testing we treat adjacent text events as equivalent
/// by concatenating them.
fn push_coalesced(result : Array[EventKind], event : EventKind) -> Unit {
  match event {
    Text(s) => {
      let n = result.length()
      if n > 0 {
        match result[n - 1] {
          Text(prev) => {
            result[n - 1] = Text(prev + s)
            return
          }
          _ => ()
        }
      }
      result.push(Text(s))
    }
    _ => result.push(event)
  }
}

///|
/// Convert events to libxml2/lxml format for conformance testing.
///
/// Handles known differences between our parser and lxml:
/// - Removes prolog whitespace (Text events before first element)
/// - Converts Start+End pairs (no content) to Empty
/// - Converts CDATA to Text and coalesces adjacent text content
/// - Fills in default encoding (UTF-8) and standalone (no) for XML declaration
/// - Reorders prolog: Decl first, then DocType, then Comments/PIs
pub fn to_libxml_format(events : Array[Event]) -> Array[EventKind] {
  let result : Array[EventKind] = []
  // First pass: collect prolog events and find first element
  let mut first_element_idx = 0
  for i, event in events {
    match event.kind {
      Start(_) | Empty(_) => {
        first_element_idx = i
        break
      }
      _ => ()
    }
  }
  // Process prolog: reorder Decl -> DocType -> others
  let mut decl_event : EventKind? = None
  let mut doctype_event : EventKind? = None
  let prolog_others : Array[EventKind] = []
  for i = 0; i < first_element_idx; i = i + 1 {
    match events[i].kind {
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
        prolog_others.push(PI(target~, data=data.trim_start().to_owned()))
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
    let event = events[i].kind
    match event {
      Start(elem) => {
        // Transform element name and attributes for lxml compatibility
        let elem_name = strip_ns_prefix(elem.name)
        let filtered_elem : XmlElement = {
          name: elem_name,
          attributes: transform_attrs_for_libxml(elem.attributes),
        }
        // Check if next event is matching End (empty element)
        if i + 1 < len {
          match events[i + 1].kind {
            End(name) =>
              if name == elem.name {
                // Convert Start+End to Empty
                push_coalesced(result, Empty(filtered_elem))
                i += 2
                continue
              }
            _ => ()
          }
        }
        push_coalesced(result, Start(filtered_elem))
      }
      Empty(elem) => {
        // Transform element name and attributes for lxml compatibility
        let elem_name = strip_ns_prefix(elem.name)
        let filtered_elem : XmlElement = {
          name: elem_name,
          attributes: transform_attrs_for_libxml(elem.attributes),
        }
        push_coalesced(result, Empty(filtered_elem))
      }
      End(name) =>
        // Strip namespace prefix from end tag
        push_coalesced(result, End(strip_ns_prefix(name)))
      DocType(name) =>
        // Strip namespace prefix from doctype name
        push_coalesced(result, DocType(strip_ns_prefix(name)))
      PI(target~, data~) =>
        // lxml trims leading whitespace from PI data
        push_coalesced(result, PI(target~, data=data.trim_start().to_owned()))
      CData(content) => push_coalesced(result, Text(content))
      _ => push_coalesced(result, event)
    }
    i += 1
  }
  result
}
