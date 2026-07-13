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
/// XML Parser Specification
/// Inspired by quick-xml (https://github.com/tafia/quick-xml)
///
/// This module provides a streaming XML parser using a pull-parser model.
/// Users read events one at a time, similar to StAX in Java.

// ============================================================================
// Reader API (Pull Parser)
// ============================================================================

///|
/// A position in the original XML source.
/// `offset` is a zero-indexed UTF-16 code-unit offset suitable for slicing the
/// original MoonBit `String`; `line` and `column` are one-indexed and count
/// Unicode characters.
pub struct SourcePosition {
  offset : Int
  line : Int
  column : Int
} derive(Debug, Eq)

///|
/// A half-open range `[start, end)` in the original XML source.
pub struct SourceSpan {
  start : SourcePosition
  end : SourcePosition
} derive(Debug, Eq)

///|
/// A parsed attribute together with its authored source ranges.
/// `value_span` excludes the surrounding quote characters.
pub struct XmlAttribute {
  name : String
  value : String
  span : SourceSpan
  name_span : SourceSpan
  value_span : SourceSpan
} derive(Debug, Eq)

///|
/// An XML event together with its authored source range.
pub struct Event {
  kind : EventKind
  span : SourceSpan
} derive(Eq)

///|
/// An XML parsing error paired with the position where it was detected.
pub(all) suberror XmlError {
  At(error~ : XmlErrorKind, position~ : SourcePosition)
} derive(Debug, Eq)

///|
/// A streaming XML reader
pub struct Reader {
  input : Array[Char]
  mut pos : Int
  mut offset : Int
  mut line : Int
  mut column : Int
  entities : Map[String, String] // Custom entities from DTD
  attr_types : Map[String, String] // Attribute types from ATTLIST (key: "elem:attr", value: type)
  base_path : String // Base path for resolving external entities
  tag_stack : Array[String] // Stack of open element names for validation
  mut seen_root : Bool // Whether we've seen the root element
  mut root_closed : Bool // Whether the root element has been closed
  mut seen_content : Bool // Whether any content has been parsed (for XML decl position check)
  mut just_saw_decl : Bool // Skip whitespace after XML declaration (lxml behavior)
  pending_events : Array[Event] // Queue of events to return (for text splitting)
  internal_subset_events : Array[Event] // PIs/comments from internal subset (emit after prolog whitespace)
  mut just_saw_doctype : Bool // Track if we just returned DocType to handle internal subset events
  had_bom : Bool // Whether input started with BOM (affects Decl emission)
}

///|
/// Create a new reader from a string
#declaration_only
pub fn Reader::from_string(input : String) -> Reader {
  ...
}

///|
/// Create a new reader from a file path
#declaration_only
pub fn Reader::from_file(path : String) -> Reader raise @fs.IOError {
  ...
}

///|
/// Read the next XML event
#declaration_only
pub fn Reader::read_event(self : Reader) -> Event raise XmlError {
  ...
}

///|
/// Check if the reader has reached the end
#declaration_only
pub fn Reader::is_eof(self : Reader) -> Bool {
  ...
}

///|
/// Get current line number (1-indexed)
#declaration_only
pub fn Reader::line(self : Reader) -> Int {
  ...
}

///|
/// Get current column number (1-indexed)
#declaration_only
pub fn Reader::column(self : Reader) -> Int {
  ...
}

///|
/// Read all events until EOF (inclusive) as an Array.
/// Includes the final Eof event in the result.
/// Raises XmlError if parsing fails.
#declaration_only
pub fn Reader::read_events_until_eof(
  self : Reader,
) -> Array[Event] raise XmlError {
  ...
}

// ============================================================================
// Namespace-aware Reader API
// ============================================================================

///|
/// An XML qualified name resolved against the namespace declarations in scope.
pub struct XmlName {
  qualified_name : String
  prefix : String?
  local_name : String
  namespace_uri : String?
} derive(Debug, Eq)

///|
/// A namespace declaration from an element start tag.
/// `None` denotes the default namespace declaration.
pub struct NamespaceDeclaration {
  prefix : String?
  namespace_uri : String
  span : SourceSpan
  name_span : SourceSpan
  value_span : SourceSpan
} derive(Debug, Eq)

///|
/// An XML attribute with a namespace-resolved name.
pub struct NamespaceAttribute {
  name : XmlName
  value : String
  span : SourceSpan
  name_span : SourceSpan
  value_span : SourceSpan
} derive(Debug, Eq)

///|
/// An XML element with namespace-resolved element and attribute names.
/// Namespace declarations are exposed separately and are not normal attributes.
pub struct NamespaceElement {
  name : XmlName
  attributes : Array[NamespaceAttribute]
  namespace_declarations : Array[NamespaceDeclaration]
} derive(Debug, Eq)

///|
/// The semantic kind of a namespace-aware XML event.
pub(all) enum NamespaceEventKind {
  Start(NamespaceElement)
  End(XmlName)
  Empty(NamespaceElement)
  Text(String)
  CData(String)
  Comment(String)
  PI(target~ : String, data~ : String)
  Decl(version~ : String, encoding~ : String?, standalone~ : String?)
  DocType(String)
  Eof
} derive(Debug, Eq)

///|
/// A namespace-aware XML event with its authored source range.
pub struct NamespaceEvent {
  kind : NamespaceEventKind
  span : SourceSpan
} derive(Debug, Eq)

///|
/// A namespace-aware adapter over the raw XML `Reader` event stream.
pub struct NamespaceReader {
  reader : Reader
  scopes : Array[Map[String, String]]
}

///|
/// Create a namespace-aware reader from a string.
#declaration_only
pub fn NamespaceReader::from_string(input : String) -> NamespaceReader {
  ...
}

///|
/// Create a namespace-aware reader from a file path.
#declaration_only
pub fn NamespaceReader::from_file(
  path : String,
) -> NamespaceReader raise @fs.IOError {
  ...
}

///|
/// Check whether the underlying reader has consumed its input.
#declaration_only
pub fn NamespaceReader::is_eof(self : NamespaceReader) -> Bool {
  ...
}

///|
/// Get the current one-indexed line number.
#declaration_only
pub fn NamespaceReader::line(self : NamespaceReader) -> Int {
  ...
}

///|
/// Get the current one-indexed column number.
#declaration_only
pub fn NamespaceReader::column(self : NamespaceReader) -> Int {
  ...
}

///|
/// Read the next namespace-aware XML event.
#declaration_only
pub fn NamespaceReader::read_event(
  self : NamespaceReader,
) -> NamespaceEvent raise XmlError {
  ...
}

///|
/// Read all namespace-aware events through the final `Eof` event.
#declaration_only
pub fn NamespaceReader::read_events_until_eof(
  self : NamespaceReader,
) -> Array[NamespaceEvent] raise XmlError {
  ...
}

// ============================================================================
// Writer API
// ============================================================================

///|
/// An XML writer for generating XML output
pub struct Writer {
  buffer : StringBuilder
  indent_level : Int
  pretty : Bool
}

///|
/// Create a new writer
#declaration_only
pub fn Writer::new() -> Writer {
  ...
}

///|
/// Write an XML event
#declaration_only
pub fn Writer::write_event(self : Writer, event : Event) -> Unit {
  ...
}

///|
/// Write a start element
#declaration_only
pub fn Writer::start_element(
  self : Writer,
  name : String,
  attributes : Array[(String, String)],
) -> Unit {
  ...
}

///|
/// Write an end element
#declaration_only
pub fn Writer::end_element(self : Writer, name : String) -> Unit {
  ...
}

///|
/// Write a self-closing element
#declaration_only
pub fn Writer::empty_element(
  self : Writer,
  name : String,
  attributes : Array[(String, String)],
) -> Unit {
  ...
}

///|
/// Write text content (escaped)
#declaration_only
pub fn Writer::text(self : Writer, content : String) -> Unit {
  ...
}

///|
/// Write CDATA section
#declaration_only
pub fn Writer::cdata(self : Writer, content : String) -> Unit {
  ...
}

///|
/// Write a comment
#declaration_only
pub fn Writer::comment(self : Writer, content : String) -> Unit {
  ...
}

///|
/// Get the generated XML string
#declaration_only
pub fn Writer::to_string(self : Writer) -> String {
  ...
}

// ============================================================================
// Convenience Functions
// ============================================================================

///|
/// Escape special XML characters in text
#declaration_only
pub fn escape(text : String) -> String {
  ...
}

///|
/// Unescape XML entities (&lt; &gt; &amp; &quot; &apos;)
#declaration_only
pub fn unescape(text : String) -> String raise XmlErrorKind {
  ...
}
