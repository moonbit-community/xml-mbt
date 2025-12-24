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
/// Create a new reader from a string
pub fn Reader::from_string(input : String) -> Reader {
  { input: input.to_array(), pos: 0, line: 1, column: 1 }
}

///|
/// Check if the reader has reached the end
pub fn Reader::is_eof(self : Reader) -> Bool {
  self.pos >= self.input.length()
}

///|
/// Get current line number (1-indexed)
pub fn Reader::line(self : Reader) -> Int {
  self.line
}

///|
/// Get current column number (1-indexed)
pub fn Reader::column(self : Reader) -> Int {
  self.column
}

///|
/// Peek at current character without advancing
fn Reader::peek(self : Reader) -> Char? {
  if self.pos < self.input.length() {
    Some(self.input[self.pos])
  } else {
    None
  }
}

///|
/// Peek at character at offset from current position
fn Reader::peek_at(self : Reader, offset : Int) -> Char? {
  let idx = self.pos + offset
  if idx < self.input.length() {
    Some(self.input[idx])
  } else {
    None
  }
}

///|
/// Advance by one character
fn Reader::advance(self : Reader) -> Char? {
  if self.pos < self.input.length() {
    let c = self.input[self.pos]
    self.pos += 1
    if c == '\n' {
      self.line += 1
      self.column = 1
    } else {
      self.column += 1
    }
    Some(c)
  } else {
    None
  }
}

///|
/// Skip whitespace characters
fn Reader::skip_whitespace(self : Reader) -> Unit {
  while self.peek() is Some(c) && is_whitespace(c) {
    let _ = self.advance()

  }
}

///|
/// Read characters while predicate is true
fn Reader::read_while(self : Reader, pred : (Char) -> Bool) -> String {
  let buf = StringBuilder::new()
  while self.peek() is Some(c) && pred(c) {
    buf.write_char(c)
    let _ = self.advance()

  }
  buf.to_string()
}

///|
/// Read until a specific string is found (exclusive)
fn Reader::read_until(self : Reader, end : String) -> String raise XmlError {
  let buf = StringBuilder::new()
  let end_chars = end.to_array()
  let end_len = end_chars.length()
  while not(self.is_eof()) {
    // Check if we're at the end marker
    let mut found = true
    for i = 0; i < end_len; i = i + 1 {
      match self.peek_at(i) {
        Some(c) if c == end_chars[i] => continue
        _ => {
          found = false
          break
        }
      }
    }
    if found {
      return buf.to_string()
    }
    match self.advance() {
      Some(c) => buf.write_char(c)
      None => raise UnexpectedEof
    }
  }
  raise UnexpectedEof
}

///|
/// Skip a specific string
fn Reader::skip_string(self : Reader, s : String) -> Bool {
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    match self.peek_at(i) {
      Some(c) if c == chars[i] => continue
      _ => return false
    }
  }
  // All matched, advance
  for i = 0; i < chars.length(); i = i + 1 {
    let _ = self.advance()

  }
  true
}

///|
/// Check if next chars match a string (without consuming)
fn Reader::check_string(self : Reader, s : String) -> Bool {
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    match self.peek_at(i) {
      Some(c) if c == chars[i] => continue
      _ => return false
    }
  }
  true
}

///|
/// Read the next XML event
pub fn Reader::read_event(self : Reader) -> Event raise XmlError {
  self.skip_whitespace()
  if self.is_eof() {
    return Eof
  }
  match self.peek() {
    Some('<') => self.read_tag()
    Some(_) => self.read_text()
    None => Eof
  }
}

///|
/// Read a tag (element, comment, CDATA, PI, DOCTYPE, etc.)
fn Reader::read_tag(self : Reader) -> Event raise XmlError {
  let _ = self.advance() // consume '<'
  match self.peek() {
    Some('/') => self.read_end_tag()
    Some('!') => self.read_special()
    Some('?') => self.read_pi()
    Some(_) => self.read_start_tag()
    None => raise UnexpectedEof
  }
}

///|
/// Read an end tag: </name>
fn Reader::read_end_tag(self : Reader) -> Event raise XmlError {
  let _ = self.advance() // consume '/'
  let name = self.read_name()
  self.skip_whitespace()
  match self.peek() {
    Some('>') => {
      let _ = self.advance()
      End(name)
    }
    _ => raise InvalidSyntax("expected '>' after end tag name")
  }
}

///|
/// Read a start tag or empty element: <name ...> or <name .../>
fn Reader::read_start_tag(self : Reader) -> Event raise XmlError {
  let name = self.read_name()
  let attributes = self.read_attributes()
  self.skip_whitespace()
  match self.peek() {
    Some('/') => {
      let _ = self.advance() // consume '/'
      match self.peek() {
        Some('>') => {
          let _ = self.advance()
          Empty(XmlElement::with_attrs(name, attributes))
        }
        _ => raise InvalidSyntax("expected '>' after '/'")
      }
    }
    Some('>') => {
      let _ = self.advance()
      Start(XmlElement::with_attrs(name, attributes))
    }
    _ => raise InvalidSyntax("expected '>' or '/>' at end of start tag")
  }
}

///|
/// Read special tags: <!-- ... -->, <![CDATA[ ... ]]>, <!DOCTYPE ...>
fn Reader::read_special(self : Reader) -> Event raise XmlError {
  let _ = self.advance() // consume '!'
  if self.check_string("--") {
    // Comment
    let _ = self.skip_string("--")
    let content = self.read_until("-->")
    let _ = self.skip_string("-->")
    Comment(content)
  } else if self.check_string("[CDATA[") {
    // CDATA
    let _ = self.skip_string("[CDATA[")
    let content = self.read_until("]]>")
    let _ = self.skip_string("]]>")
    CData(content)
  } else if self.check_string("DOCTYPE") {
    // DOCTYPE
    let _ = self.skip_string("DOCTYPE")
    self.skip_whitespace()
    let name = self.read_while(fn(c) {
      c != '>' && c != '[' && not(is_whitespace(c))
    })
    self.skip_whitespace()
    // Check for internal subset
    if self.peek() is Some('[') {
      // Skip internal subset [...]
      let _ = self.advance() // consume '['
      self.skip_internal_subset()
    }
    // Skip rest until >
    while self.peek() is Some(c) && c != '>' {
      let _ = self.advance()

    }
    let _ = self.advance() // consume '>'
    DocType(name)
  } else {
    raise InvalidSyntax("invalid special tag after '<!'")
  }
}

///|
/// Read processing instruction: <?target data?>
fn Reader::read_pi(self : Reader) -> Event raise XmlError {
  let _ = self.advance() // consume '?'
  let target = self.read_name()
  if target == "xml" {
    // XML declaration
    self.read_xml_decl()
  } else {
    self.skip_whitespace()
    let data = self.read_until("?>")
    let _ = self.skip_string("?>")
    PI(target~, data~)
  }
}

///|
/// Read XML declaration: <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
fn Reader::read_xml_decl(self : Reader) -> Event raise XmlError {
  let mut version = ""
  let mut encoding : String? = None
  let mut standalone : String? = None
  self.skip_whitespace()
  while not(self.check_string("?>")) {
    let attr_name = self.read_name()
    self.skip_whitespace()
    match self.peek() {
      Some('=') => {
        let _ = self.advance()

      }
      _ => raise InvalidSyntax("expected '=' in XML declaration")
    }
    self.skip_whitespace()
    let value = self.read_attr_value()
    match attr_name {
      "version" => version = value
      "encoding" => encoding = Some(value)
      "standalone" => standalone = Some(value)
      _ => () // ignore unknown attributes
    }
    self.skip_whitespace()
  }
  let _ = self.skip_string("?>")
  Decl(version~, encoding~, standalone~)
}

///|
/// Read element name
fn Reader::read_name(self : Reader) -> String {
  self.read_while(fn(c) { is_name_char(c) })
}

///|
/// Read attributes
fn Reader::read_attributes(self : Reader) -> Array[(String, String)] {
  let attrs : Array[(String, String)] = []
  while true {
    self.skip_whitespace()
    match self.peek() {
      Some(c) if is_name_start_char(c) => {
        let name = self.read_name()
        self.skip_whitespace()
        match self.peek() {
          Some('=') => {
            let _ = self.advance()
            self.skip_whitespace()
            let value = self.read_attr_value() catch { _ => "" }
            attrs.push((name, value))
          }
          _ => attrs.push((name, "")) // boolean attribute
        }
      }
      _ => break
    }
  }
  attrs
}

///|
/// Read attribute value (quoted)
fn Reader::read_attr_value(self : Reader) -> String raise XmlError {
  match self.peek() {
    Some('"') => {
      let _ = self.advance()
      let value = self.read_until("\"")
      let _ = self.advance() // consume closing quote
      value
    }
    Some('\'') => {
      let _ = self.advance()
      let value = self.read_until("'")
      let _ = self.advance() // consume closing quote
      value
    }
    _ => raise InvalidSyntax("expected quoted attribute value")
  }
}

///|
/// Read text content
fn Reader::read_text(self : Reader) -> Event raise XmlError {
  let buf = StringBuilder::new()
  while not(self.is_eof()) {
    match self.peek() {
      Some('<') => break
      Some('&') => {
        // Read entity
        let _ = self.advance() // consume '&'
        let entity_name = self.read_while(fn(c) { c != ';' })
        match self.peek() {
          Some(';') => {
            let _ = self.advance()
            let entity = "&" + entity_name + ";"
            let decoded = unescape(entity)
            buf.write_string(decoded)
          }
          _ => {
            // Not a valid entity, treat as text
            buf.write_char('&')
            buf.write_string(entity_name)
          }
        }
      }
      Some(c) => {
        buf.write_char(c)
        let _ = self.advance()

      }
      None => break
    }
  }
  Text(buf.to_string())
}

///|
/// Skip DTD internal subset content until ]
fn Reader::skip_internal_subset(self : Reader) -> Unit {
  let mut depth = 0
  while not(self.is_eof()) {
    match self.peek() {
      Some(']') if depth == 0 => {
        let _ = self.advance()
        return
      }
      Some('<') => {
        let _ = self.advance()
        // Check for nested declarations
        if self.peek() is Some('!') {
          let _ = self.advance()
          if self.peek() is Some('[') {
            depth += 1
          }
        }
      }
      Some(']') => {
        let _ = self.advance()
        if self.peek() is Some(']') {
          let _ = self.advance()
          if self.peek() is Some('>') {
            // End of nested CDATA-like section
            depth -= 1
            let _ = self.advance()

          }
        }
      }
      Some('\'') => {
        // Skip single-quoted string
        let _ = self.advance()
        while self.peek() is Some(c) && c != '\'' {
          let _ = self.advance()

        }
        let _ = self.advance()

      }
      Some('"') => {
        // Skip double-quoted string
        let _ = self.advance()
        while self.peek() is Some(c) && c != '"' {
          let _ = self.advance()

        }
        let _ = self.advance()

      }
      Some(_) => {
        let _ = self.advance()

      }
      None => return
    }
  }
}

///|
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// XML 1.0 NameStartChar production (5th edition)
fn is_name_start_char(c : Char) -> Bool {
  let code = c.to_int()
  c == ':' ||
  c == '_' ||
  (c >= 'A' && c <= 'Z') ||
  (c >= 'a' && c <= 'z') ||
  (code >= 0xC0 && code <= 0xD6) ||
  (code >= 0xD8 && code <= 0xF6) ||
  (code >= 0xF8 && code <= 0x2FF) ||
  (code >= 0x370 && code <= 0x37D) ||
  (code >= 0x37F && code <= 0x1FFF) ||
  (code >= 0x200C && code <= 0x200D) ||
  (code >= 0x2070 && code <= 0x218F) ||
  (code >= 0x2C00 && code <= 0x2FEF) ||
  (code >= 0x3001 && code <= 0xD7FF) ||
  (code >= 0xF900 && code <= 0xFDCF) ||
  (code >= 0xFDF0 && code <= 0xFFFD) ||
  (code >= 0x10000 && code <= 0xEFFFF)
}

///|
/// XML 1.0 NameChar production (5th edition)
fn is_name_char(c : Char) -> Bool {
  let code = c.to_int()
  is_name_start_char(c) ||
  c == '-' ||
  c == '.' ||
  (c >= '0' && c <= '9') ||
  code == 0xB7 ||
  (code >= 0x0300 && code <= 0x036F) ||
  (code >= 0x203F && code <= 0x2040)
}
