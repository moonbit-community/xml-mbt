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
    attr_types: {},
    base_path: "",
    tag_stack: [],
    seen_root: false,
    root_closed: false,
    seen_content: false,
    just_saw_decl: false,
    pending_events: [],
    internal_subset_events: [],
    just_saw_doctype: false,
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
    attr_types: {},
    base_path,
    tag_stack: [],
    seen_root: false,
    root_closed: false,
    seen_content: false,
    just_saw_decl: false,
    pending_events: [],
    internal_subset_events: [],
    just_saw_doctype: false,
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
/// Skip whitespace characters and return count of characters skipped
fn Reader::skip_whitespace_count(self : Reader) -> Int {
  let mut count = 0
  while self.peek() is Some(c) && is_whitespace(c) {
    let _ = self.advance()
    count += 1
  }
  count
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
      Some(c) => {
        // Validate character is allowed in XML content
        let code = c.to_int()
        if not(is_valid_xml_content_char(code)) {
          raise InvalidSyntax("invalid character in content")
        }
        buf.write_char(c)
      }
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
  // Return pending events first (from split text)
  if self.pending_events.length() > 0 {
    let event = self.pending_events.remove(0)
    // Skip empty Text events
    match event {
      Text(s) if s == "" => return self.read_event()
      _ => {
        self.seen_content = true
        return event
      }
    }
  }
  if self.is_eof() {
    // Check for unclosed tags
    if self.tag_stack.length() > 0 {
      let unclosed = self.tag_stack.pop().unwrap()
      raise InvalidSyntax("unclosed element: <" + unclosed + ">")
    }
    // Empty document is not valid
    if not(self.seen_root) {
      raise InvalidSyntax("empty document - no root element")
    }
    return Eof
  }
  match self.peek() {
    Some('<') => {
      let event = self.read_tag()
      // Track root element state
      match event {
        Start(_) => {
          self.seen_content = true
          if self.root_closed {
            raise InvalidSyntax("content after root element")
          } else if self.tag_stack.length() == 1 {
            // Just pushed the root element
            self.seen_root = true
          }
        }
        Empty(_) => {
          self.seen_content = true
          // Empty element: if no root seen yet, this is the root and it's now closed
          if self.root_closed {
            raise InvalidSyntax("content after root element")
          } else if not(self.seen_root) {
            self.seen_root = true
            self.root_closed = true
          }
        }
        End(_) => {
          self.seen_content = true
          if self.tag_stack.length() == 0 && self.seen_root {
            // Root element just closed
            self.root_closed = true
          }
        }
        CData(_) => {
          self.seen_content = true
          // CDATA only allowed inside elements
          if self.root_closed {
            raise InvalidSyntax("CDATA section after root element")
          }
          if not(self.seen_root) || self.tag_stack.length() == 0 {
            raise InvalidSyntax("CDATA section not allowed in prolog")
          }
        }
        Text(_) => {
          self.seen_content = true
          self.just_saw_decl = false
        }
        Comment(_) => {
          self.seen_content = true
          self.just_saw_decl = false
        }
        DocType(_) => {
          self.seen_content = true
          self.just_saw_decl = false
          self.just_saw_doctype = true // Track for internal subset event ordering
        }
        PI(_) => {
          self.seen_content = true
          self.just_saw_decl = false
        }
        Decl(_) => self.just_saw_decl = true // Skip next whitespace
        Eof => ()
      }
      event
    }
    Some(_) =>
      // Check for non-whitespace content in prolog or after root
      if self.root_closed {
        // After root closes: skip whitespace (lxml doesn't emit trailing whitespace)
        // and return Eof, or error on non-whitespace
        while self.peek() is Some(c) {
          if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
            let _ = self.advance()

          } else if c == '<' {
            // There's more content - could be comment or PI
            break
          } else if c == '&' {
            raise InvalidSyntax("character reference after root element")
          } else {
            raise InvalidSyntax("content after root element")
          }
        }
        // After skipping whitespace, try to read the next event
        return self.read_event()
      } else if not(self.seen_root) {
        // Before root element: only literal whitespace is allowed
        if self.just_saw_decl {
          // Skip whitespace after XML declaration (lxml behavior)
          while self.peek() is Some(c) {
            if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
              let _ = self.advance()

            } else if c == '<' {
              break
            } else if c == '&' {
              raise InvalidSyntax("character reference before root element")
            } else {
              raise InvalidSyntax("content before root element")
            }
          }
          self.just_saw_decl = false
          return self.read_event()
        }
        // Read prolog whitespace
        let text_event = self.read_whitespace_only()
        // Mark that we've seen content
        self.seen_content = true
        // Move internal subset events to pending queue
        if self.just_saw_doctype {
          self.just_saw_doctype = false
          for event in self.internal_subset_events {
            self.pending_events.push(event)
          }
          self.internal_subset_events.clear()
        }
        text_event
      } else {
        let text_event = self.read_text()
        // Skip empty Text events (lxml doesn't emit them)
        match text_event {
          Text(s) if s == "" => return self.read_event()
          _ => {
            // Mark that we've seen content (affects XML declaration placement check)
            self.seen_content = true
            text_event
          }
        }
      }
    None => {
      // Check for unclosed tags at EOF
      if self.tag_stack.length() > 0 {
        let unclosed = self.tag_stack.pop().unwrap()
        raise InvalidSyntax("unclosed element: <" + unclosed + ">")
      }
      // Empty document is not valid
      if not(self.seen_root) {
        raise InvalidSyntax("empty document - no root element")
      }
      Eof
    }
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
  let attributes = self.read_attributes(name)
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
      // Check for immediately following end tag (empty element like <foo></foo>)
      // lxml reports non-root empty elements as Empty, but root element as Start+End
      let end_tag = "</" + name + ">"
      if self.tag_stack.length() > 0 && self.check_string(end_tag) {
        let _ = self.skip_string(end_tag)
        Empty(XmlElement::with_attrs(name, attributes))
      } else {
        // Push tag name onto stack for matching with end tag
        self.tag_stack.push(name)
        Start(XmlElement::with_attrs(name, attributes))
      }
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
    let content = self.read_comment_content()
    Comment(content)
  } else if self.check_string("[CDATA[") {
    // CDATA - validate position before parsing
    if self.root_closed {
      raise InvalidSyntax("CDATA section after root element")
    }
    if not(self.seen_root) || self.tag_stack.length() == 0 {
      raise InvalidSyntax("CDATA section not allowed in prolog")
    }
    // Report as Text to match lxml behavior
    let _ = self.skip_string("[CDATA[")
    let content = self.read_until("]]>")
    let _ = self.skip_string("]]>")
    Text(content)
  } else if self.check_string("DOCTYPE") {
    // DOCTYPE
    let _ = self.skip_string("DOCTYPE")
    self.skip_whitespace()
    let name = self.read_while(fn(c) {
      c != '>' && c != '[' && not(is_whitespace(c))
    })
    // Parse external ID if present (SYSTEM or PUBLIC)
    self.skip_whitespace()
    if self.check_string("SYSTEM") {
      let _ = self.skip_string("SYSTEM")
      self.skip_whitespace()
      // Skip system literal
      self.skip_quoted_string()
    } else if self.check_string("PUBLIC") {
      let _ = self.skip_string("PUBLIC")
      self.skip_whitespace()
      // Validate and skip public ID literal
      self.read_and_validate_public_id()
      self.skip_whitespace()
      // Skip system literal
      self.skip_quoted_string()
    }
    // Skip everything else until we find '[' or '>'
    while self.peek() is Some(c) && c != '[' && c != '>' {
      if c == '-' && self.check_string("--") {
        // SGML-style comments are not allowed in XML
        raise InvalidSyntax(
          "SGML-style comments (--) not allowed in XML declarations",
        )
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
    // Skip rest until >, but reject PE references (not allowed outside internal subset)
    while self.peek() is Some(c) && c != '>' {
      if c == '%' {
        raise InvalidSyntax(
          "parameter entity reference not allowed outside internal subset",
        )
      }
      let _ = self.advance()

    }
    let _ = self.advance() // consume '>'
    DocType(name)
  } else {
    raise InvalidSyntax("invalid special tag after '<!'")
  }
}

///|
/// Read comment content, validating that it doesn't contain "--" and ends with ">"
fn Reader::read_comment_content(self : Reader) -> String raise XmlError {
  let buf = StringBuilder::new()
  while not(self.is_eof()) {
    // Check for "--"
    if self.check_string("--") {
      let _ = self.skip_string("--")
      // Must be followed by ">" to be valid comment end
      match self.peek() {
        Some('>') => {
          let _ = self.advance()
          return buf.to_string()
        }
        _ => raise InvalidSyntax("'--' is not allowed in comments")
      }
    }
    match self.advance() {
      Some(c) => {
        let code = c.to_int()
        if not(is_valid_xml_content_char(code)) {
          raise InvalidSyntax("invalid character in comment")
        }
        buf.write_char(c)
      }
      None => raise UnexpectedEof
    }
  }
  raise UnexpectedEof
}

///|
/// Read processing instruction: <?target data?>
fn Reader::read_pi(self : Reader) -> Event raise XmlError {
  let _ = self.advance() // consume '?'
  let target = self.read_name()
  // PI target is required
  if target == "" {
    raise InvalidSyntax("processing instruction target is required")
  }
  // Check for "xml" in any case - case-insensitive match for reserved target
  let target_lower = target.to_lower()
  if target_lower == "xml" {
    if target != "xml" {
      // "XML", "Xml", etc. are not valid - only lowercase "xml" is allowed
      raise InvalidSyntax("PI target 'xml' is reserved (case-insensitive)")
    }
    // XML declaration
    self.read_xml_decl()
  } else {
    // After target, must have whitespace before data, or ?> to end
    match self.peek() {
      Some(c) if is_whitespace(c) => {
        // Skip whitespace before data
        let _ = self.advance()
        let data = self.read_pi_data()
        let _ = self.skip_string("?>")
        PI(target~, data~)
      }
      Some('?') =>
        // Check for ?>
        if self.check_string("?>") {
          let _ = self.skip_string("?>")
          PI(target~, data="")
        } else {
          raise InvalidSyntax("expected whitespace or '?>' after PI target")
        }
      _ => raise InvalidSyntax("expected whitespace or '?>' after PI target")
    }
  }
}

///|
/// Read PI data, validating characters
fn Reader::read_pi_data(self : Reader) -> String raise XmlError {
  let buf = StringBuilder::new()
  while not(self.is_eof()) {
    // Check if we're at the end marker ?>
    if self.check_string("?>") {
      return buf.to_string()
    }
    match self.advance() {
      Some(c) => {
        let code = c.to_int()
        if not(is_valid_xml_content_char(code)) {
          raise InvalidSyntax("invalid character in processing instruction")
        }
        buf.write_char(c)
      }
      None => raise UnexpectedEof
    }
  }
  raise UnexpectedEof
}

///|
/// Read XML declaration: <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
/// Strict validation per XML 1.0 spec:
/// - Pseudo-attributes must be lowercase (version, encoding, standalone)
/// - Order: version (required), encoding (optional), standalone (optional)
/// - No duplicates allowed
/// - standalone must be "yes" or "no"
/// - Whitespace required between pseudo-attributes
fn Reader::read_xml_decl(self : Reader) -> Event raise XmlError {
  // XML declaration must appear at the very beginning of the document
  // Check if any content has been seen (elements, text, DOCTYPE, etc.)
  if self.seen_content {
    raise InvalidSyntax("XML declaration must be at the start of the document")
  }
  // Check if inside element (tag_stack not empty)
  if self.tag_stack.length() > 0 {
    raise InvalidSyntax("XML declaration cannot appear inside an element")
  }
  let mut version = ""
  let mut encoding : String? = None
  let mut standalone : String? = None
  let mut seen_version = false
  let mut seen_encoding = false
  let mut seen_standalone = false
  let mut need_whitespace = false
  self.skip_whitespace()
  while not(self.check_string("?>")) {
    // Check for required whitespace between pseudo-attributes
    let had_whitespace = self.skip_whitespace_count() > 0
    if self.check_string("?>") {
      break
    }
    if need_whitespace && not(had_whitespace) {
      raise InvalidSyntax(
        "whitespace required between XML declaration pseudo-attributes",
      )
    }
    let attr_name = self.read_name()
    if attr_name == "" {
      break
    }
    self.skip_whitespace()
    match self.peek() {
      Some('=') => {
        let _ = self.advance()

      }
      _ => raise InvalidSyntax("expected '=' in XML declaration")
    }
    self.skip_whitespace()
    // Use raw attribute value (no entity decoding) for XML declaration
    let value = self.read_raw_attr_value()
    match attr_name {
      "version" => {
        if seen_version {
          raise InvalidSyntax("duplicate 'version' in XML declaration")
        }
        if seen_encoding || seen_standalone {
          raise InvalidSyntax("'version' must come first in XML declaration")
        }
        // Validate version format: VersionNum ::= '1.' [0-9]+
        if not(is_valid_version(value)) {
          raise InvalidSyntax("invalid version: " + value)
        }
        seen_version = true
        version = value
      }
      "encoding" => {
        if seen_encoding {
          raise InvalidSyntax("duplicate 'encoding' in XML declaration")
        }
        if not(seen_version) {
          raise InvalidSyntax("'version' must come before 'encoding'")
        }
        if seen_standalone {
          raise InvalidSyntax("'encoding' must come before 'standalone'")
        }
        // Validate encoding name: [A-Za-z]([A-Za-z0-9._-])*
        if not(is_valid_encoding_name(value)) {
          raise InvalidSyntax("invalid encoding name: " + value)
        }
        seen_encoding = true
        encoding = Some(value)
      }
      "standalone" => {
        if seen_standalone {
          raise InvalidSyntax("duplicate 'standalone' in XML declaration")
        }
        if not(seen_version) {
          raise InvalidSyntax("'version' must come before 'standalone'")
        }
        // standalone must be exactly "yes" or "no" (case-sensitive)
        if value != "yes" && value != "no" {
          raise InvalidSyntax(
            "'standalone' must be 'yes' or 'no', got: " + value,
          )
        }
        seen_standalone = true
        standalone = Some(value)
      }
      _ => {
        // Reject uppercase variants and unknown attributes
        if attr_name == "VERSION" ||
          attr_name == "Version" ||
          (attr_name.to_lower() == "version" && attr_name != "version") {
          raise InvalidSyntax("'version' must be lowercase in XML declaration")
        }
        if attr_name == "ENCODING" ||
          attr_name == "Encoding" ||
          (attr_name.to_lower() == "encoding" && attr_name != "encoding") {
          raise InvalidSyntax("'encoding' must be lowercase in XML declaration")
        }
        if attr_name == "STANDALONE" ||
          attr_name == "Standalone" ||
          (attr_name.to_lower() == "standalone" && attr_name != "standalone") {
          raise InvalidSyntax(
            "'standalone' must be lowercase in XML declaration",
          )
        }
        raise InvalidSyntax(
          "unknown pseudo-attribute in XML declaration: " + attr_name,
        )
      }
    }
    need_whitespace = true
  }
  let _ = self.skip_string("?>")

  // Validate UTF-16 encoding - must have BOM if declared as UTF-16
  match encoding {
    Some(enc) => {
      let enc_upper = enc.to_upper()
      if enc_upper == "UTF-16" ||
        enc_upper == "UTF-16LE" ||
        enc_upper == "UTF-16BE" {
        // UTF-16 encoded content should have BOM (U+FEFF) at start
        // If input is ASCII/UTF-8 claiming to be UTF-16, it's invalid
        if self.input.length() > 0 && self.input[0] != '\u{FEFF}' {
          // Check if content looks like ASCII (no high bytes)
          // Real UTF-16 would have null bytes in ASCII text
          let all_ascii = self.input.length() < 100 &&
            self.input.iter().all(fn(c) { c.to_int() < 128 })
          if all_ascii {
            raise InvalidSyntax(
              "encoding declared as UTF-16 but content is ASCII/UTF-8",
            )
          }
        }
      }
    }
    None => ()
  }
  Decl(version~, encoding~, standalone~)
}

///|
/// Read element name (validates XML NameStartChar + NameChar)
fn Reader::read_name(self : Reader) -> String raise XmlError {
  // First character must be a NameStartChar
  match self.peek() {
    Some(c) if is_name_start_char(c) => {
      let _ = self.advance()
      let buf = StringBuilder::new()
      buf.write_char(c)
      // Rest can be any NameChar
      while self.peek() is Some(nc) && is_name_char(nc) {
        buf.write_char(nc)
        let _ = self.advance()

      }
      buf.to_string()
    }
    Some(c) if is_name_char(c) =>
      // Character is valid NameChar but not NameStartChar (e.g., '-', '.', digit)
      raise InvalidSyntax("name cannot start with '" + c.to_string() + "'")
    _ => ""
  }
}

///|
/// Read attributes
fn Reader::read_attributes(
  self : Reader,
  elem_name : String,
) -> Array[(String, String)] raise XmlError {
  let attrs : Array[(String, String)] = []
  let mut need_whitespace = false
  while true {
    let had_whitespace = self.skip_whitespace_count() > 0
    match self.peek() {
      Some(c) if is_name_start_char(c) => {
        // Whitespace required between attributes (but not before the first)
        if need_whitespace && not(had_whitespace) {
          raise InvalidSyntax("whitespace required between attributes")
        }
        let attr_name = self.read_name()
        self.skip_whitespace()
        match self.peek() {
          Some('=') => {
            let _ = self.advance()
            self.skip_whitespace()
            let raw_value = self.read_attr_value()
            // Normalize attribute value based on declared type
            let normalized_value = self.normalize_attr_by_type(
              elem_name,
              attr_name,
              raw_value,
            )
            // Reject duplicate attributes
            let exists = attrs.iter().any(fn(pair) { pair.0 == attr_name })
            if exists {
              raise InvalidSyntax("duplicate attribute: " + attr_name)
            }
            attrs.push((attr_name, normalized_value))
            need_whitespace = true
          }
          _ => raise InvalidSyntax("expected '=' after attribute name")
        }
      }
      Some('/') | Some('>') => break
      Some(c) if is_name_char(c) =>
        // Invalid attribute name start (e.g., starts with digit or '-')
        raise InvalidSyntax(
          "attribute name cannot start with '" + c.to_string() + "'",
        )
      Some(c) =>
        raise InvalidSyntax(
          "unexpected character in tag: '" + c.to_string() + "'",
        )
      None => break
    }
  }
  attrs
}

///|
/// Normalize attribute value based on declared type in DTD.
/// CDATA: only replace newlines/tabs with spaces
/// Tokenized types (ID, IDREF, NMTOKEN, etc.): collapse whitespace, trim
fn Reader::normalize_attr_by_type(
  self : Reader,
  elem_name : String,
  attr_name : String,
  value : String,
) -> String {
  let key = elem_name + ":" + attr_name
  let attr_type = self.attr_types.get(key).unwrap_or("CDATA")
  if attr_type == "CDATA" {
    // CDATA: only replace tabs/newlines with spaces
    let buf = StringBuilder::new()
    for c in value {
      if c == '\t' || c == '\n' || c == '\r' {
        buf.write_char(' ')
      } else {
        buf.write_char(c)
      }
    }
    buf.to_string()
  } else {
    // Tokenized types: collapse whitespace and trim
    let buf = StringBuilder::new()
    let mut in_whitespace = true // Start true to skip leading
    let mut need_space = false
    for c in value {
      if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
        if not(in_whitespace) {
          need_space = true
          in_whitespace = true
        }
      } else {
        if need_space {
          buf.write_char(' ')
          need_space = false
        }
        buf.write_char(c)
        in_whitespace = false
      }
    }
    buf.to_string()
  }
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
fn Reader::read_attr_value(self : Reader) -> String raise XmlError {
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
      Some('<') =>
        // < is not allowed in attribute values
        raise InvalidSyntax("'<' not allowed in attribute value")
      Some('&') => {
        let _ = self.advance()
        // Read entity name
        let entity_name = self.read_while(fn(c) {
          c != ';' && c != quote && c != '<'
        })
        match self.peek() {
          Some(';') => {
            let _ = self.advance()
            // First check if it's a character reference
            if entity_name.has_prefix("#") {
              // Character reference - decode directly
              let entity = "&" + entity_name + ";"
              let decoded = unescape(entity)
              buf.write_string(decoded)
            } else {
              // Entity reference - expand with validation
              let entity_ref = "&" + entity_name + ";"
              let seen : Map[String, Bool] = {}
              let expanded = expand_entity_value(
                entity_ref,
                self.entities,
                seen,
              )
              buf.write_string(expanded)
            }
          }
          _ =>
            // Entity reference must end with ';'
            raise InvalidSyntax("entity reference must end with ';'")
        }
      }
      Some(c) => {
        // Check for invalid XML characters
        let code = c.to_int()
        if not(is_valid_xml_content_char(code)) {
          raise InvalidSyntax("invalid character in attribute value")
        }
        // Normalize whitespace: tab, newline, CR -> space
        if c == '\t' || c == '\n' || c == '\r' {
          buf.write_char(' ')
        } else {
          buf.write_char(c)
        }
        let _ = self.advance()

      }
      None => break
    }
  }
  buf.to_string()
}

///|
/// Normalize line endings in a string: \r\n -> \n, \r -> \n
fn normalize_line_endings(s : String) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  let len = chars.length()
  let mut i = 0
  while i < len {
    if chars[i] == '\r' {
      buf.write_char('\n')
      // Skip following \n if present
      if i + 1 < len && chars[i + 1] == '\n' {
        i += 1
      }
    } else {
      buf.write_char(chars[i])
    }
    i += 1
  }
  buf.to_string()
}

///|
/// Check if a string contains actual XML markup (not just escaped chars)
fn has_markup(s : String) -> Bool {
  let chars = s.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    if chars[i] == '<' {
      // Check if followed by name start char (element) or / (end tag)
      // or ! (comment/CDATA) or ? (PI)
      if i + 1 < len {
        let next = chars[i + 1]
        if is_name_start_char(next) || next == '/' || next == '!' || next == '?' {
          return true
        }
      }
    }
    i += 1
  }
  false
}

///|
/// Check if a string forms well-formed XML content (balanced tags).
/// This distinguishes real markup from character-reference `<` in entity values.
fn is_well_formed_content(s : String) -> Bool {
  // Try to parse as XML content - if it fails, it's not well-formed
  let test_reader = Reader::from_string("<root>" + s + "</root>")
  let result = for {
    match (try? test_reader.read_event()) {
      Err(_) => break false
      Ok(Eof) => break true
      Ok(_) => continue
    }
  }
  result
}

///|
/// Parse entity content as XML markup and push events to pending queue
fn Reader::parse_entity_content(self : Reader, content : String) -> Unit {
  // Create a temporary reader to parse the entity content
  let sub_reader = Reader::from_string(content)
  // Copy entity definitions to sub-reader
  for k, v in self.entities {
    sub_reader.entities.set(k, v)
  }
  // Disable root element checking for entity content
  sub_reader.seen_root = true
  // Parse all events from entity content
  while true {
    let event = try? sub_reader.read_event()
    match event {
      Ok(Eof) => break
      Ok(e) => self.pending_events.push(e)
      Err(_) => break // Stop on error in entity content
    }
  }
}

///|
/// Read text content - splits on entities to match lxml behavior
fn Reader::read_text(self : Reader) -> Event raise XmlError {
  let buf = StringBuilder::new()
  while not(self.is_eof()) {
    match self.peek() {
      Some('<') => break
      Some('&') => {
        // Push current buffer as text event before processing entity
        let current_text = buf.to_string()
        if current_text.length() > 0 {
          self.pending_events.push(Text(current_text))
          buf.reset()
        }
        // Read entity
        let _ = self.advance() // consume '&'
        // Check for valid entity name start (# for char ref, or NameStartChar)
        match self.peek() {
          Some('#') => {
            // Character reference
            let entity_name = self.read_while(fn(c) { c != ';' && c != '<' })
            match self.peek() {
              Some(';') => {
                let _ = self.advance()
                let entity = "&" + entity_name + ";"
                let decoded = unescape(entity)
                // Character references preserve literal character (no line ending normalization)
                self.pending_events.push(Text(decoded))
              }
              _ => raise InvalidSyntax("entity reference must end with ';'")
            }
          }
          Some(c) if is_name_start_char(c) => {
            // Entity reference - read name
            let entity_name = self.read_name()
            match self.peek() {
              Some(';') => {
                let _ = self.advance()
                // Expand with validation
                let entity_ref = "&" + entity_name + ";"
                let seen : Map[String, Bool] = {}
                let expanded = expand_entity_value(
                  entity_ref,
                  self.entities,
                  seen,
                )
                // Normalize line endings in expanded value
                let normalized = normalize_line_endings(expanded)
                // Check if expanded value contains actual markup (not just &lt;)
                // Only parse as markup if it forms valid well-formed content
                if has_markup(normalized) && is_well_formed_content(normalized) {
                  // Parse entity content as XML (entity markup expansion)
                  self.parse_entity_content(normalized)
                } else {
                  // Push entity value as separate text event
                  self.pending_events.push(Text(normalized))
                }
              }
              _ => raise InvalidSyntax("entity reference must end with ';'")
            }
          }
          _ => raise InvalidSyntax("invalid entity reference")
        }
      }
      Some(']') => {
        // Check for forbidden ]]> in content
        if self.check_string("]]>") {
          raise InvalidSyntax("']]>' is not allowed in element content")
        }
        buf.write_char(']')
        let _ = self.advance()

      }
      Some(c) => {
        // Check for invalid XML characters
        let code = c.to_int()
        if not(is_valid_xml_content_char(code)) {
          raise InvalidSyntax("invalid character in content")
        }
        // Normalize line endings: \r\n -> \n, \r -> \n
        if c == '\r' {
          let _ = self.advance()
          // Check if followed by \n
          if self.peek() == Some('\n') {
            let _ = self.advance()

          }
          buf.write_char('\n')
        } else {
          buf.write_char(c)
          let _ = self.advance()

        }
      }
      None => break
    }
  }
  // Push any remaining text
  let final_text = buf.to_string()
  if final_text.length() > 0 {
    self.pending_events.push(Text(final_text))
  }
  // Return first pending event, or empty Text if none
  if self.pending_events.length() > 0 {
    self.pending_events.remove(0)
  } else {
    Text("")
  }
}

///|
/// Read whitespace-only content (for prolog and misc after root)
/// Rejects any character references, entity references, or non-whitespace
fn Reader::read_whitespace_only(self : Reader) -> Event raise XmlError {
  let buf = StringBuilder::new()
  while not(self.is_eof()) {
    match self.peek() {
      Some('<') => break
      Some('&') =>
        // Character/entity references not allowed outside root element
        if self.root_closed {
          raise InvalidSyntax("character reference after root element")
        } else {
          raise InvalidSyntax("character reference before root element")
        }
      Some(c) =>
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
          buf.write_char(c)
          let _ = self.advance()
          // Non-whitespace content not allowed outside root element
        } else if self.root_closed {
          raise InvalidSyntax("content after root element")
        } else {
          raise InvalidSyntax("content before root element")
        }
      None => break
    }
  }
  Text(buf.to_string())
}

///|
/// Check if character code is valid in XML content
/// Valid: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
fn is_valid_xml_content_char(code : Int) -> Bool {
  code == 0x9 ||
  code == 0xA ||
  code == 0xD ||
  (code >= 0x20 && code <= 0xD7FF) ||
  (code >= 0xE000 && code <= 0xFFFD) ||
  (code >= 0x10000 && code <= 0x10FFFF)
}

///|
/// Validate version: VersionNum ::= '1.' [0-9]+
fn is_valid_version(version : String) -> Bool {
  let chars = version.to_array()
  // Must be at least "1.0"
  if chars.length() < 3 {
    return false
  }
  // Must start with "1."
  if chars[0] != '1' || chars[1] != '.' {
    return false
  }
  // Must have at least one digit after "1."
  if chars.length() < 3 {
    return false
  }
  // Rest must be digits only
  for i = 2; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
/// Validate encoding name: [A-Za-z]([A-Za-z0-9._-])*
fn is_valid_encoding_name(name : String) -> Bool {
  let chars = name.to_array()
  if chars.length() == 0 {
    return false
  }
  // First character must be a letter
  let first = chars[0]
  if not((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z')) {
    return false
  }
  // Rest must be letters, digits, '.', '_', or '-'
  for i = 1; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if not(
        (c >= 'A' && c <= 'Z') ||
        (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') ||
        c == '.' ||
        c == '_' ||
        c == '-',
      ) {
      return false
    }
  }
  true
}

///|
/// Skip a quoted string (single or double quotes)
fn Reader::skip_quoted_string(self : Reader) -> Unit {
  match self.peek() {
    Some('"') => {
      let _ = self.advance()
      while self.peek() is Some(c) && c != '"' {
        let _ = self.advance()

      }
      if self.peek() == Some('"') {
        let _ = self.advance()

      }
    }
    Some('\'') => {
      let _ = self.advance()
      while self.peek() is Some(c) && c != '\'' {
        let _ = self.advance()

      }
      if self.peek() == Some('\'') {
        let _ = self.advance()

      }
    }
    _ => ()
  }
}

///|
/// Read and validate a Public ID literal
/// PubidChar ::= #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]
fn Reader::read_and_validate_public_id(self : Reader) -> Unit raise XmlError {
  let quote = match self.peek() {
    Some('"') => '"'
    Some('\'') => '\''
    _ => return
  }
  let _ = self.advance() // consume opening quote
  while self.peek() is Some(c) && c != quote {
    if not(is_pubid_char(c)) {
      raise InvalidSyntax(
        "invalid character in public ID: '" + c.to_string() + "'",
      )
    }
    let _ = self.advance()

  }
  if self.peek() == Some(quote) {
    let _ = self.advance()

  }
}

///|
/// Check if a character is valid in a Public ID
fn is_pubid_char(c : Char) -> Bool {
  // PubidChar ::= #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]
  c == ' ' ||
  c == '\r' ||
  c == '\n' ||
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '-' ||
  c == '\'' ||
  c == '(' ||
  c == ')' ||
  c == '+' ||
  c == ',' ||
  c == '.' ||
  c == '/' ||
  c == ':' ||
  c == '=' ||
  c == '?' ||
  c == ';' ||
  c == '!' ||
  c == '*' ||
  c == '#' ||
  c == '@' ||
  c == '$' ||
  c == '_' ||
  c == '%'
}

///|
/// Parse DTD internal subset content until ]
/// Extracts entity declarations and stores them
fn Reader::parse_internal_subset(self : Reader) -> Unit raise XmlError {
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
          // Check for conditional sections and CDATA (not allowed in internal subset)
          if self.check_string("[INCLUDE[") || self.check_string("[IGNORE[") {
            raise InvalidSyntax(
              "conditional sections not allowed in internal DTD subset",
            )
          }
          if self.check_string("[CDATA[") {
            raise InvalidSyntax("CDATA section not allowed in DTD")
          }
          if self.check_string("ENTITY") {
            // Parse entity declaration
            let _ = self.skip_string("ENTITY")
            // Check that whitespace follows ENTITY keyword
            if not(self.peek() is Some(c) && is_whitespace(c)) {
              raise InvalidSyntax("whitespace required after ENTITY")
            }
            self.skip_whitespace()
            // Check for parameter entity
            if self.peek() is Some('%') {
              // Parameter entity - must have whitespace after %
              let _ = self.advance() // skip %
              if not(self.peek() is Some(c) && is_whitespace(c)) {
                raise InvalidSyntax(
                  "whitespace required after % in parameter entity",
                )
              }
              self.skip_whitespace()
              let _ = self.read_name_lenient() // skip name
              self.skip_whitespace()
              // Parse and validate PE value (less strict than general entity)
              match self.peek() {
                Some('"') => {
                  let _ = self.advance()
                  let raw_value = self.read_entity_value('"')
                  let _ = self.advance()
                  validate_pe_value(raw_value)
                  self.skip_to_char_strict('>')
                }
                Some('\'') => {
                  let _ = self.advance()
                  let raw_value = self.read_entity_value('\'')
                  let _ = self.advance()
                  validate_pe_value(raw_value)
                  self.skip_to_char_strict('>')
                }
                _ => self.skip_to_char_strict('>')
              }
            } else {
              // General entity - validate name starts with valid character
              match self.peek() {
                Some(c) if is_name_start_char(c) => ()
                _ =>
                  raise InvalidSyntax(
                    "invalid character at start of entity name",
                  )
              }
              let name = self.read_name_lenient()
              // Require at least one whitespace after entity name
              if not(self.peek() is Some(c) && is_whitespace(c)) {
                raise InvalidSyntax(
                  "whitespace required after entity name in declaration",
                )
              }
              self.skip_whitespace()
              // Check if entity already exists - if so, skip (first wins)
              let is_duplicate = self.entities.contains(name)
              // Check if it's an internal entity (quoted value) or external
              match self.peek() {
                Some('"') => {
                  let _ = self.advance()
                  let raw_value = self.read_entity_value('"')
                  let _ = self.advance() // closing quote
                  // Only validate and store if not duplicate
                  if not(is_duplicate) {
                    validate_entity_value(raw_value)
                    let value = unescape(raw_value) catch { _ => raw_value }
                    self.entities.set(name, value)
                  }
                  self.skip_to_char_strict('>')
                }
                Some('\'') => {
                  let _ = self.advance()
                  let raw_value = self.read_entity_value('\'')
                  let _ = self.advance() // closing quote
                  // Only validate and store if not duplicate
                  if not(is_duplicate) {
                    validate_entity_value(raw_value)
                    let value = unescape(raw_value) catch { _ => raw_value }
                    self.entities.set(name, value)
                  }
                  self.skip_to_char_strict('>')
                }
                _ => {
                  // External entity (SYSTEM/PUBLIC)
                  let keyword = self.read_name_lenient()
                  self.skip_whitespace()
                  if keyword == "SYSTEM" {
                    // SYSTEM "path"
                    match self.peek() {
                      Some('"') => {
                        let _ = self.advance()
                        let path = self.read_entity_value('"')
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
                  self.skip_to_char_strict('>')
                }
              }
            }
          } else if self.check_string("ATTLIST") {
            let _ = self.skip_string("ATTLIST")
            parse_attlist(self)
          } else if self.check_string("ELEMENT") {
            let _ = self.skip_string("ELEMENT")
            parse_element_decl(self)
          } else if self.check_string("--") {
            // Comment in DTD: <!-- ... -->
            let _ = self.skip_string("--")
            let comment_buf = StringBuilder::new()
            while not(self.is_eof()) {
              if self.check_string("--") {
                let _ = self.skip_string("--")
                if self.peek() == Some('>') {
                  let _ = self.advance()
                  break
                } else {
                  // -- not followed by > is invalid in XML comments
                  raise InvalidSyntax("'--' in comment must be followed by '>'")
                }
              }
              match self.advance() {
                Some(c) => comment_buf.write_char(c)
                None => ()
              }
            }
            self.internal_subset_events.push(Comment(comment_buf.to_string()))
          } else if self.check_string("NOTATION") {
            // NOTATION declaration - validate PUBLIC ID if present
            let _ = self.skip_string("NOTATION")
            self.skip_whitespace()
            let _ = self.read_name() // notation name
            self.skip_whitespace()
            if self.check_string("PUBLIC") {
              let _ = self.skip_string("PUBLIC")
              self.skip_whitespace()
              self.read_and_validate_public_id()
              self.skip_whitespace()
              // Optional system literal
              if self.peek() is Some('"') || self.peek() is Some('\'') {
                self.skip_quoted_string()
              }
            } else if self.check_string("SYSTEM") {
              let _ = self.skip_string("SYSTEM")
              self.skip_whitespace()
              self.skip_quoted_string()
            }
            self.skip_to_char_strict('>')
          } else {
            // Other declarations - skip to >
            self.skip_declaration()
          }
        } else if self.peek() is Some('?') {
          // Processing instruction in DTD - emit as event
          let _ = self.advance() // skip ?
          // Read target name
          let target = self.read_name()
          if target == "" {
            raise InvalidSyntax("processing instruction target is required")
          }
          // Check if it's an XML declaration (not allowed in DTD)
          let target_lower = target.to_lower()
          if target_lower == "xml" {
            raise InvalidSyntax("XML declaration not allowed in DTD")
          }
          // After target, must have whitespace before data, or ?>
          match self.peek() {
            Some(c) if is_whitespace(c) => {
              // Skip leading whitespace
              let _ = self.advance()
              // Read PI data
              let data_buf = StringBuilder::new()
              while not(self.is_eof()) {
                if self.check_string("?>") {
                  let _ = self.skip_string("?>")
                  break
                }
                match self.advance() {
                  Some(ch) => data_buf.write_char(ch)
                  None => break
                }
              }
              // Push PI event to internal subset queue (will be emitted after prolog whitespace)
              self.internal_subset_events.push(
                PI(target~, data=data_buf.to_string()),
              )
            }
            Some('?') =>
              // Check for ?>
              if self.check_string("?>") {
                let _ = self.skip_string("?>")
                // Push PI event with empty data to internal subset queue
                self.internal_subset_events.push(PI(target~, data=""))
              } else {
                raise InvalidSyntax(
                  "expected whitespace or '?>' after PI target",
                )
              }
            _ =>
              raise InvalidSyntax("expected whitespace or '?>' after PI target")
          }
        } else {
          // Unknown - skip
          let _ = self.advance()

        }
      }
      Some('%') => {
        // Parameter entity reference - must be %Name; with no whitespace
        let _ = self.advance() // consume %
        // Name must start immediately after %
        match self.peek() {
          Some(c) if is_name_start_char(c) => {
            // Read the name
            let _ = self.read_name()
            // Must be immediately followed by ;
            match self.peek() {
              Some(';') => {
                let _ = self.advance()

              }
              _ =>
                raise InvalidSyntax(
                  "parameter entity reference must end with ';'",
                )
            }
          }
          _ => raise InvalidSyntax("invalid parameter entity reference")
        }
      }
      Some(_) => {
        let _ = self.advance()

      }
      None => return
    }
  }
}

///|
/// Skip to a character, consuming it, and checking for SGML comments
fn Reader::skip_to_char_strict(
  self : Reader,
  target : Char,
) -> Unit raise XmlError {
  while self.peek() is Some(c) && c != target {
    if c == '-' && self.check_string("--") {
      raise InvalidSyntax(
        "SGML-style comments (--) not allowed in XML declarations",
      )
    }
    let _ = self.advance()

  }
  let _ = self.advance()

}

///|
/// Skip a DTD declaration (handles quoted strings)
/// Also checks for SGML-style comments (-- ... --) which are not valid in XML
fn Reader::skip_declaration(self : Reader) -> Unit raise XmlError {
  while self.peek() is Some(c) && c != '>' {
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

    } else if c == '-' && self.check_string("--") {
      // SGML-style comments are not allowed in XML
      raise InvalidSyntax(
        "SGML-style comments (--) not allowed in XML declarations",
      )
    } else {
      let _ = self.advance()

    }
  }
  let _ = self.advance()

}

///|
/// Read name leniently (for DTD parsing where we don't validate strictly)
fn Reader::read_name_lenient(self : Reader) -> String {
  let buf = StringBuilder::new()
  while self.peek() is Some(c) && is_name_char_lenient(c) {
    buf.write_char(c)
    let _ = self.advance()

  }
  buf.to_string()
}

///|
/// Lenient name character check for DTD parsing
fn is_name_char_lenient(c : Char) -> Bool {
  not(
    c == ' ' ||
    c == '\t' ||
    c == '\n' ||
    c == '\r' ||
    c == '<' ||
    c == '>' ||
    c == '"' ||
    c == '\'' ||
    c == '=' ||
    c == '[' ||
    c == ']',
  )
}

///|
/// Read entity value (handles nested entity references)
fn Reader::read_entity_value(
  self : Reader,
  quote : Char,
) -> String raise XmlError {
  let buf = StringBuilder::new()
  while self.peek() is Some(c) && c != quote {
    // Validate character
    let code = c.to_int()
    if not(is_valid_xml_content_char(code)) {
      raise InvalidSyntax("invalid character in entity value")
    }
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
/// Check if character is a valid XML NameStartChar (per XML 1.0 spec)
/// NameStartChar ::= ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] |
///                   [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF] |
///                   [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] |
///                   [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] |
///                   [#x10000-#xEFFFF]
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
/// Check if character is a valid XML NameChar (per XML 1.0 spec)
/// NameChar ::= NameStartChar | "-" | "." | [0-9] | #xB7 |
///              [#x0300-#x036F] | [#x203F-#x2040]
fn is_name_char(c : Char) -> Bool {
  if is_name_start_char(c) {
    return true
  }
  let code = c.to_int()
  c == '-' ||
  c == '.' ||
  (c >= '0' && c <= '9') ||
  code == 0xB7 ||
  (code >= 0x300 && code <= 0x36F) ||
  (code >= 0x203F && code <= 0x2040)
}
