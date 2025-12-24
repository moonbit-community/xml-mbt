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
  let chars = input.to_array()
  // Skip BOM (Byte Order Mark, U+FEFF) if present at start
  let start_pos = if chars.length() > 0 && chars[0] == '\u{FEFF}' {
    1
  } else {
    0
  }
  {
    input: chars,
    pos: start_pos,
    line: 1,
    column: 1,
    entities: {},
    base_path: "",
    tag_stack: [],
  }
}

///|
/// Create a new reader from a file path
pub fn Reader::from_file(path : String) -> Reader raise @fs.IOError {
  let content = @fs.read_file_to_string(path)
  let base_path = get_directory(path)
  let chars = content.to_array()
  // Skip BOM if present at start
  let start_pos = if chars.length() > 0 && chars[0] == '\u{FEFF}' {
    1
  } else {
    0
  }
  {
    input: chars,
    pos: start_pos,
    line: 1,
    column: 1,
    entities: {},
    base_path,
    tag_stack: [],
  }
}

///|
/// Get the directory part of a path
fn get_directory(path : String) -> String {
  let chars = path.to_array()
  let mut last_sep = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' || chars[i] == '\\' {
      last_sep = i
    }
  }
  if last_sep >= 0 {
    let buf = StringBuilder::new()
    for i = 0; i <= last_sep; i = i + 1 {
      buf.write_char(chars[i])
    }
    buf.to_string()
  } else {
    ""
  }
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
/// Skip whitespace and control characters (for lenient tag parsing)
fn Reader::skip_ws_and_control(self : Reader) -> Unit {
  while true {
    match self.peek() {
      Some(c) => {
        let code = c.to_int()
        // Skip whitespace or control characters (< 0x20, except we keep meaningful ones)
        if is_whitespace(c) ||
          (code < 0x20 && c != '\t' && c != '\n' && c != '\r') {
          let _ = self.advance()

        } else {
          break
        }
      }
      None => break
    }
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
  // Empty end tag name is invalid
  if name == "" {
    raise InvalidSyntax("empty end tag name")
  }
  // Validate tag matching
  if self.tag_stack.length() == 0 {
    raise InvalidSyntax("unexpected end tag, no matching start tag")
  }
  let expected = self.tag_stack.pop().unwrap()
  if expected != name {
    raise InvalidSyntax(
      "end tag mismatch: expected </" + expected + ">, found </" + name + ">",
    )
  }
  // Skip whitespace and control characters
  self.skip_ws_and_control()
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
  // Skip whitespace and control characters before tag end
  self.skip_ws_and_control()
  match self.peek() {
    Some('/') => {
      let _ = self.advance() // consume '/'
      // No whitespace allowed between / and > per XML spec
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
      // Push tag name onto stack for matching with end tag
      self.tag_stack.push(name)
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
    // Skip everything until we find '[' or '>', properly handling quoted strings
    while self.peek() is Some(c) && c != '[' && c != '>' {
      if c == '"' || c == '\'' {
        // Skip quoted string
        let quote = c
        let _ = self.advance() // consume opening quote
        while self.peek() is Some(qc) && qc != quote {
          let _ = self.advance()

        }
        let _ = self.advance()
         // consume closing quote (if present)
      } else {
        let _ = self.advance()

      }
    }
    // Check for internal subset
    if self.peek() is Some('[') {
      // Parse internal subset [...] and extract entities
      let _ = self.advance() // consume '['
      self.parse_internal_subset()
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
    // Skip exactly one whitespace after target (matches quick-xml behavior)
    match self.peek() {
      Some(c) if is_whitespace(c) => {
        let _ = self.advance()

      }
      _ => ()
    }
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
    // If no attribute name, break (handles malformed XML leniently)
    if attr_name == "" {
      break
    }
    self.skip_whitespace()
    match self.peek() {
      Some('=') => {
        let _ = self.advance()

      }
      _ => break // Skip malformed attribute (lenient like quick-xml)
    }
    self.skip_whitespace()
    // Use raw attribute value (no entity decoding) for XML declaration
    let value = self.read_raw_attr_value()
    match attr_name {
      "version" => version = value
      "encoding" => encoding = Some(value)
      "standalone" => standalone = Some(value)
      _ => () // ignore unknown attributes
    }
    self.skip_whitespace()
  }
  // Skip any remaining characters until ?>
  while not(self.check_string("?>")) && not(self.is_eof()) {
    let _ = self.advance()

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
      Some(c) if is_name_char(c) => {
        let name = self.read_name()
        self.skip_whitespace()
        match self.peek() {
          Some('=') => {
            let _ = self.advance()
            self.skip_whitespace()
            // If value isn't properly quoted, skip this attribute (matches quick-xml)
            match (try? self.read_attr_value()) {
              Ok(value) => {
                // Skip duplicate attributes (keep first occurrence, matches quick-xml)
                let exists = attrs.iter().any(fn(pair) { pair.0 == name })
                if not(exists) {
                  attrs.push((name, value))
                }
              }
              Err(_) => ()
            }
          }
          _ => () // Skip attribute without value (matches quick-xml)
        }
      }
      // Skip orphaned quoted values (e.g., "value" without name=)
      Some('"') | Some('\'') => {
        let quote = self.advance().unwrap()
        // Skip until closing quote
        while self.peek() is Some(c) && c != quote {
          let _ = self.advance()

        }
        if self.peek() is Some(_) {
          let _ = self.advance()
           // consume closing quote
        }
      }
      _ => break
    }
  }
  attrs
}

///|
/// Read raw attribute value (quoted) without entity decoding
/// Used for XML declaration attributes where entities should be kept as-is
fn Reader::read_raw_attr_value(self : Reader) -> String raise XmlError {
  let quote = match self.peek() {
    Some('"') => '"'
    Some('\'') => '\''
    _ => raise InvalidSyntax("expected quoted attribute value")
  }
  let _ = self.advance() // consume opening quote
  let buf = StringBuilder::new()
  while not(self.is_eof()) {
    match self.peek() {
      Some(c) if c == quote => {
        let _ = self.advance()
        break
      }
      Some(c) => {
        buf.write_char(c)
        let _ = self.advance()

      }
      None => break
    }
  }
  buf.to_string()
}

///|
/// Read attribute value (quoted) and decode entities
/// If any entity is unknown, returns empty string (matching quick-xml behavior)
fn Reader::read_attr_value(self : Reader) -> String raise XmlError {
  let quote = match self.peek() {
    Some('"') => '"'
    Some('\'') => '\''
    _ => raise InvalidSyntax("expected quoted attribute value")
  }
  let _ = self.advance() // consume opening quote
  let buf = StringBuilder::new()
  let mut has_unknown_entity = false
  while not(self.is_eof()) {
    match self.peek() {
      Some(c) if c == quote => {
        let _ = self.advance()
        break
      }
      Some('&') => {
        let _ = self.advance()
        // Stop at ';' or quote (don't consume past attribute value)
        let entity_name = self.read_while(fn(c) { c != ';' && c != quote })
        match self.peek() {
          Some(';') => {
            let _ = self.advance()
            let entity = "&" + entity_name + ";"
            match (try? unescape(entity)) {
              Ok(decoded) => buf.write_string(decoded)
              Err(_) => has_unknown_entity = true
            }
          }
          _ => {
            // Not a valid entity reference
            has_unknown_entity = true
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
  // If any entity was unknown/malformed, return empty (matching quick-xml)
  if has_unknown_entity {
    ""
  } else {
    buf.to_string()
  }
}

///|
/// Read text content
/// If any entity is unknown, returns empty string (matching quick-xml behavior)
fn Reader::read_text(self : Reader) -> Event raise XmlError {
  let buf = StringBuilder::new()
  let mut has_unknown_entity = false
  while not(self.is_eof()) {
    match self.peek() {
      Some('<') => break
      Some('&') => {
        // Read entity
        let _ = self.advance() // consume '&'
        // Stop at ';' or '<' (don't consume into next tag)
        let entity_name = self.read_while(fn(c) { c != ';' && c != '<' })
        match self.peek() {
          Some(';') => {
            let _ = self.advance()
            let entity = "&" + entity_name + ";"
            match (try? unescape(entity)) {
              Ok(decoded) => buf.write_string(decoded)
              Err(_) => has_unknown_entity = true
            }
          }
          _ => {
            // Not a valid entity reference, treat as text
            // Mark as unknown so we return empty (matching quick-xml)
            has_unknown_entity = true
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
  // If any entity was unknown/malformed, return empty (matching quick-xml)
  if has_unknown_entity {
    Text("")
  } else {
    Text(buf.to_string())
  }
}

///|
/// Parse DTD internal subset content until ]
/// Extracts entity declarations and stores them
fn Reader::parse_internal_subset(self : Reader) -> Unit {
  while not(self.is_eof()) {
    self.skip_whitespace()
    match self.peek() {
      Some(']') => {
        let _ = self.advance()
        return
      }
      Some('<') => {
        let _ = self.advance()
        if self.peek() is Some('!') {
          let _ = self.advance()
          if self.check_string("ENTITY") {
            // Parse entity declaration
            let _ = self.skip_string("ENTITY")
            self.skip_whitespace()
            // Check for parameter entity (skip those)
            if self.peek() is Some('%') {
              // Parameter entity - skip to >
              while self.peek() is Some(c) && c != '>' {
                let _ = self.advance()

              }
              let _ = self.advance()

            } else {
              // General entity
              let name = self.read_name()
              self.skip_whitespace()
              // Check if it's an internal entity (quoted value) or external
              match self.peek() {
                Some('"') => {
                  let _ = self.advance()
                  let raw_value = self.read_entity_value('"')
                  let _ = self.advance() // closing quote
                  // Decode entities in value
                  let value = unescape(raw_value) catch { _ => raw_value }
                  self.entities.set(name, value)
                  // Skip to >
                  while self.peek() is Some(c) && c != '>' {
                    let _ = self.advance()

                  }
                  let _ = self.advance()

                }
                Some('\'') => {
                  let _ = self.advance()
                  let raw_value = self.read_entity_value('\'')
                  let _ = self.advance() // closing quote
                  // Decode entities in value
                  let value = unescape(raw_value) catch { _ => raw_value }
                  self.entities.set(name, value)
                  // Skip to >
                  while self.peek() is Some(c) && c != '>' {
                    let _ = self.advance()

                  }
                  let _ = self.advance()

                }
                _ => {
                  // External entity (SYSTEM/PUBLIC)
                  // Try to read SYSTEM "path" or PUBLIC "..." "path"
                  let keyword = self.read_name()
                  self.skip_whitespace()
                  if keyword == "SYSTEM" {
                    // SYSTEM "path"
                    match self.peek() {
                      Some('"') => {
                        let _ = self.advance()
                        let path = self.read_entity_value('"')
                        let _ = self.advance()
                        // Try to read the external entity file
                        if self.base_path.length() > 0 {
                          let full_path = self.base_path + path
                          let content = @fs.read_file_to_string(full_path) catch {
                            _ => ""
                          }
                          if content.length() > 0 {
                            self.entities.set(name, content)
                          }
                        }
                      }
                      Some('\'') => {
                        let _ = self.advance()
                        let path = self.read_entity_value('\'')
                        let _ = self.advance()
                        if self.base_path.length() > 0 {
                          let full_path = self.base_path + path
                          let content = @fs.read_file_to_string(full_path) catch {
                            _ => ""
                          }
                          if content.length() > 0 {
                            self.entities.set(name, content)
                          }
                        }
                      }
                      _ => ()
                    }
                  }
                  // Skip rest to >
                  while self.peek() is Some(c) && c != '>' {
                    let _ = self.advance()

                  }
                  let _ = self.advance()

                }
              }
            }
          } else {
            // Other declarations (ELEMENT, ATTLIST, etc.) - skip to >
            while self.peek() is Some(c) && c != '>' {
              // Handle quoted strings
              if c == '"' {
                let _ = self.advance()
                while self.peek() is Some(c2) && c2 != '"' {
                  let _ = self.advance()

                }
                let _ = self.advance()

              } else if c == '\'' {
                let _ = self.advance()
                while self.peek() is Some(c2) && c2 != '\'' {
                  let _ = self.advance()

                }
                let _ = self.advance()

              } else {
                let _ = self.advance()

              }
            }
            let _ = self.advance()

          }
        } else if self.peek() is Some('?') {
          // Processing instruction in DTD - skip to ?>
          while not(self.is_eof()) {
            if self.check_string("?>") {
              let _ = self.skip_string("?>")
              break
            }
            let _ = self.advance()

          }
        } else {
          // Unknown - skip
          let _ = self.advance()

        }
      }
      Some('%') => {
        // Parameter entity reference - skip
        let _ = self.advance()
        while self.peek() is Some(c) && c != ';' {
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
/// Read entity value (handles nested entity references)
fn Reader::read_entity_value(self : Reader, quote : Char) -> String {
  let buf = StringBuilder::new()
  while self.peek() is Some(c) && c != quote {
    buf.write_char(c)
    let _ = self.advance()

  }
  buf.to_string()
}

///|
fn is_whitespace(c : Char) -> Bool {
  if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
    return true
  }
  let code = c.to_int()
  // U+00A0 (NBSP - non-breaking space)
  if code == 0xA0 {
    return true
  }
  // Unicode whitespace: U+2000-U+200A (various spaces), U+3000 (ideographic space)
  // Note: U+200B (ZWSP) is kept in names per quick-xml behavior
  (code >= 0x2000 && code <= 0x200A) || code == 0x3000
}

///|
/// Lenient name character check - accepts any non-special character
/// This matches quick-xml's lenient behavior for better compatibility
fn is_name_char(c : Char) -> Bool {
  // Reject NUL character
  if c == '\u0000' {
    return false
  }
  // Reject ASCII whitespace (space, tab, newline, carriage return)
  if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
    return false
  }
  // Reject XML syntax characters
  if c == '<' ||
    c == '>' ||
    c == '/' ||
    c == '=' ||
    c == '&' ||
    c == '?' ||
    c == '!' {
    return false
  }
  // Reject quotes
  if c == '"' || c == '\'' {
    return false
  }
  // Reject semicolon (entity terminator) and brackets
  if c == ';' || c == '[' || c == ']' {
    return false
  }
  true
}
