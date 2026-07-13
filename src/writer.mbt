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
/// Create a new writer
pub fn Writer::new() -> Writer {
  {
    buffer: StringBuilder::new(),
    element_stack: [],
    seen_root: false,
    wrote_anything: false,
    wrote_doctype: false,
  }
}

///|
/// Write an XML event
pub fn Writer::write_event(
  self : Writer,
  event : Event,
) -> Unit raise WriterError {
  match event.kind {
    Start(elem) =>
      self.start_element(
        elem.name,
        elem.attributes.map(fn(attribute) { (attribute.name, attribute.value) }),
      )
    End(name) => self.end_element(name)
    Empty(elem) =>
      self.empty_element(
        elem.name,
        elem.attributes.map(fn(attribute) { (attribute.name, attribute.value) }),
      )
    Text(content) => self.text(content)
    CData(content) => self.cdata(content)
    Comment(content) => self.comment(content)
    PI(target~, data~) => self.write_processing_instruction(target, data)
    Decl(version~, encoding~, standalone~) =>
      self.write_declaration(version, encoding, standalone)
    DocType(name) => self.write_doctype(name)
    Eof => self.validate_complete()
  }
}

///|
/// Write a start element
pub fn Writer::start_element(
  self : Writer,
  name : String,
  attributes : Array[(String, String)],
) -> Unit raise WriterError {
  validate_writer_name(name, "element")
  validate_writer_attributes(attributes)
  self.begin_element()
  self.buffer.write_string("<")
  self.buffer.write_string(name)
  for attr in attributes {
    self.buffer.write_string(" ")
    self.buffer.write_string(attr.0)
    self.buffer.write_string("=\"")
    self.buffer.write_string(escape_attr(attr.1))
    self.buffer.write_string("\"")
  }
  self.buffer.write_string(">")
  self.element_stack.push(name)
  self.wrote_anything = true
}

///|
/// Write an end element
pub fn Writer::end_element(
  self : Writer,
  name : String,
) -> Unit raise WriterError {
  validate_writer_name(name, "element")
  if self.element_stack.length() == 0 {
    raise InvalidStructure("end element without a matching start: " + name)
  }
  let expected = self.element_stack[self.element_stack.length() - 1]
  if expected != name {
    raise InvalidStructure(
      "end element mismatch: expected " + expected + ", found " + name,
    )
  }
  self.buffer.write_string("</")
  self.buffer.write_string(name)
  self.buffer.write_string(">")
  let _ = self.element_stack.pop()
  self.wrote_anything = true
}

///|
/// Write a self-closing element
pub fn Writer::empty_element(
  self : Writer,
  name : String,
  attributes : Array[(String, String)],
) -> Unit raise WriterError {
  validate_writer_name(name, "element")
  validate_writer_attributes(attributes)
  self.begin_element()
  self.buffer.write_string("<")
  self.buffer.write_string(name)
  for attr in attributes {
    self.buffer.write_string(" ")
    self.buffer.write_string(attr.0)
    self.buffer.write_string("=\"")
    self.buffer.write_string(escape_attr(attr.1))
    self.buffer.write_string("\"")
  }
  self.buffer.write_string("/>")
  self.wrote_anything = true
}

///|
/// Write text content (escaped)
pub fn Writer::text(self : Writer, content : String) -> Unit raise WriterError {
  validate_writer_content(content, "text")
  if self.element_stack.length() == 0 {
    for c in content {
      if !is_whitespace(c) {
        raise InvalidStructure(
          "non-whitespace text is not allowed outside the root",
        )
      }
    }
  }
  self.buffer.write_string(escape(content))
  if content.length() > 0 {
    self.wrote_anything = true
  }
}

///|
/// Write CDATA section
pub fn Writer::cdata(self : Writer, content : String) -> Unit raise WriterError {
  validate_writer_content(content, "CDATA")
  if content.find("]]>") is Some(_) {
    raise InvalidContent("CDATA cannot contain ']]>'")
  }
  if self.element_stack.length() == 0 {
    raise InvalidStructure("CDATA is only allowed inside an element")
  }
  self.buffer.write_string("<![CDATA[")
  self.buffer.write_string(content)
  self.buffer.write_string("]]>")
  self.wrote_anything = true
}

///|
/// Write a comment
pub fn Writer::comment(
  self : Writer,
  content : String,
) -> Unit raise WriterError {
  validate_writer_content(content, "comment")
  if content.find("--") is Some(_) || content.has_suffix("-") {
    raise InvalidContent("comment cannot contain '--' or end with '-'")
  }
  self.buffer.write_string("<!--")
  self.buffer.write_string(content)
  self.buffer.write_string("-->")
  self.wrote_anything = true
}

///|
/// Get the generated XML string
pub fn Writer::to_string(self : Writer) -> String raise WriterError {
  self.validate_complete()
  self.buffer.to_string()
}

///|
/// Escape attribute value (escapes < > & " ')
fn escape_attr(text : String) -> String {
  escape(text)
}

///|
fn validate_writer_name(name : String, kind : String) -> Unit raise WriterError {
  let chars = name.to_array()
  if chars.length() == 0 || !is_name_start_char(chars[0]) {
    raise InvalidName("invalid " + kind + " name: " + name)
  }
  for i = 1; i < chars.length(); i = i + 1 {
    if !is_name_char(chars[i]) {
      raise InvalidName("invalid " + kind + " name: " + name)
    }
  }
}

///|
fn validate_writer_attributes(
  attributes : Array[(String, String)],
) -> Unit raise WriterError {
  let seen : Map[String, Bool] = Map([])
  for attribute in attributes {
    validate_writer_name(attribute.0, "attribute")
    validate_writer_content(attribute.1, "attribute value")
    if seen.contains(attribute.0) {
      raise InvalidStructure("duplicate attribute: " + attribute.0)
    }
    seen.set(attribute.0, true)
  }
}

///|
fn validate_writer_content(
  content : String,
  kind : String,
) -> Unit raise WriterError {
  for c in content {
    if !is_valid_xml_content_char(c.to_int()) {
      raise InvalidContent("invalid XML character in " + kind)
    }
  }
}

///|
fn Writer::begin_element(self : Writer) -> Unit raise WriterError {
  if self.element_stack.length() == 0 {
    if self.seen_root {
      raise InvalidStructure("document cannot contain multiple root elements")
    }
    self.seen_root = true
  }
}

///|
fn Writer::validate_complete(self : Writer) -> Unit raise WriterError {
  if self.element_stack.length() > 0 {
    let name = self.element_stack[self.element_stack.length() - 1]
    raise InvalidStructure("unclosed element: " + name)
  }
  if !self.seen_root {
    raise InvalidStructure("document has no root element")
  }
}

///|
fn Writer::write_declaration(
  self : Writer,
  version : String,
  encoding : String?,
  standalone : String?,
) -> Unit raise WriterError {
  if self.wrote_anything {
    raise InvalidDeclaration("XML declaration must be the first output")
  }
  if !is_valid_version(version) {
    raise InvalidDeclaration("invalid XML version: " + version)
  }
  match encoding {
    Some(value) if !is_valid_encoding_name(value) =>
      raise InvalidDeclaration("invalid encoding name: " + value)
    _ => ()
  }
  match standalone {
    Some(value) if value != "yes" && value != "no" =>
      raise InvalidDeclaration("standalone must be 'yes' or 'no'")
    _ => ()
  }
  self.buffer.write_string("<?xml version=\"")
  self.buffer.write_string(version)
  self.buffer.write_string("\"")
  match encoding {
    Some(value) => {
      self.buffer.write_string(" encoding=\"")
      self.buffer.write_string(value)
      self.buffer.write_string("\"")
    }
    None => ()
  }
  match standalone {
    Some(value) => {
      self.buffer.write_string(" standalone=\"")
      self.buffer.write_string(value)
      self.buffer.write_string("\"")
    }
    None => ()
  }
  self.buffer.write_string("?>")
  self.wrote_anything = true
}

///|
fn Writer::write_processing_instruction(
  self : Writer,
  target : String,
  data : String,
) -> Unit raise WriterError {
  validate_writer_name(target, "processing instruction target")
  if target.to_lower() == "xml" {
    raise InvalidName("processing instruction target cannot be XML")
  }
  validate_writer_content(data, "processing instruction data")
  if data.find("?>") is Some(_) {
    raise InvalidContent("processing instruction data cannot contain '?>'")
  }
  self.buffer.write_string("<?")
  self.buffer.write_string(target)
  if data.length() > 0 {
    self.buffer.write_string(" ")
    self.buffer.write_string(data)
  }
  self.buffer.write_string("?>")
  self.wrote_anything = true
}

///|
fn Writer::write_doctype(
  self : Writer,
  content : String,
) -> Unit raise WriterError {
  if self.seen_root || self.element_stack.length() > 0 {
    raise InvalidStructure("DOCTYPE must appear before the root element")
  }
  if self.wrote_doctype {
    raise InvalidStructure(
      "document cannot contain multiple DOCTYPE declarations",
    )
  }
  let validator = Reader::from_string("<!DOCTYPE " + content + "><root/>")
  let _ = validator.read_events_until_eof() catch {
    _ => raise InvalidContent("invalid DOCTYPE declaration")
  }
  self.buffer.write_string("<!DOCTYPE ")
  self.buffer.write_string(content)
  self.buffer.write_string(">")
  self.wrote_anything = true
  self.wrote_doctype = true
}
