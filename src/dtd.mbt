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
/// Validate entity replacement text for well-formedness
/// Checks that entity values don't contain bare & not followed by valid reference
/// Also validates character references when expanded
pub fn validate_entity_value(value : String) -> Unit raise XmlError {
  let chars = value.to_array()
  let len = chars.length()
  let mut i = 0

  // Check for text declaration (<?xml) - not allowed in internal parsed entities
  if len >= 5 && chars[0] == '<' && chars[1] == '?' && chars[2] == 'x' && chars[3] == 'm' && chars[4] == 'l' {
    raise InvalidEntity("text declaration not allowed in internal parsed entity")
  }

  while i < len {
    // Check for parameter entity reference - not allowed in entity values in internal subset
    if chars[i] == '%' {
      // Check if it looks like a PE reference
      let j = i + 1
      if j < len && is_name_start_char(chars[j]) {
        raise InvalidEntity("parameter entity reference not allowed in entity value")
      }
    }
    if chars[i] == '&' {
      // Must be followed by valid reference
      i += 1
      if i >= len {
        // Bare & at end
        raise InvalidEntity("bare '&' in entity value")
      }
      // Check for character reference or entity reference
      if chars[i] == '#' {
        // Character reference: &#NN; or &#xHH;
        i += 1
        if i >= len {
          raise InvalidEntity("incomplete character reference in entity value")
        }
        let is_hex = chars[i] == 'x'
        if is_hex {
          i += 1
          if i >= len {
            raise InvalidEntity(
              "incomplete hex character reference in entity value",
            )
          }
        }
        // Must have at least one digit
        let digit_start = i
        while i < len && chars[i] != ';' {
          let c = chars[i]
          let valid = if is_hex {
            (c >= '0' && c <= '9') ||
            (c >= 'a' && c <= 'f') ||
            (c >= 'A' && c <= 'F')
          } else {
            c >= '0' && c <= '9'
          }
          if not(valid) {
            raise InvalidEntity(
              "invalid character in character reference in entity value",
            )
          }
          i += 1
        }
        if i >= len {
          raise InvalidEntity(
            "unterminated character reference in entity value",
          )
        }
        if i == digit_start {
          raise InvalidEntity(
            "empty character reference in entity value",
          )
        }
        // Validate the character reference value itself
        let code_point = if is_hex {
          parse_hex_code(chars, digit_start, i)
        } else {
          parse_decimal_code(chars, digit_start, i)
        }
        // Check for valid XML character
        if not(is_valid_xml_char(code_point)) {
          raise InvalidEntity("invalid character reference in entity value")
        }
        // After expanding, check if it produces a bare &
        if code_point == 38 {
          // &#38; decodes to '&', check what follows in the raw text
          // The decoded & must itself be followed by valid reference syntax
          // in the entity replacement text
          let after_semi = i + 1
          if after_semi >= len {
            // & at end of entity value
            raise InvalidEntity("character reference &#38; produces bare '&' at end of entity value")
          }
          let next = chars[after_semi]
          // Must be followed by entity ref name or # for char ref
          if next == '#' {
            // Check for valid character reference format: must have ; before end
            let mut j = after_semi + 1
            // Skip x for hex
            if j < len && chars[j] == 'x' {
              j += 1
            }
            // Skip digits
            while j < len && ((chars[j] >= '0' && chars[j] <= '9') || (chars[j] >= 'a' && chars[j] <= 'f') || (chars[j] >= 'A' && chars[j] <= 'F')) {
              j += 1
            }
            // Must end with ;
            if j >= len || chars[j] != ';' {
              raise InvalidEntity("character reference &#38; produces incomplete character reference")
            }
          } else if not(is_name_start_char(next)) {
            raise InvalidEntity("character reference &#38; produces bare '&' not followed by valid reference")
          } else {
            // Entity reference - must end with ;
            let mut j = after_semi
            while j < len && is_name_char(chars[j]) {
              j += 1
            }
            if j >= len || chars[j] != ';' {
              raise InvalidEntity("character reference &#38; produces incomplete entity reference")
            }
          }
        }
        i += 1 // skip ';'
      } else {
        // Entity reference: &name;
        // Must start with letter or underscore
        if not(is_name_start_char(chars[i])) {
          raise InvalidEntity("bare '&' not followed by valid reference")
        }
        while i < len && chars[i] != ';' {
          if not(is_name_char(chars[i])) {
            raise InvalidEntity("invalid character in entity reference")
          }
          i += 1
        }
        if i >= len {
          raise InvalidEntity("unterminated entity reference in entity value")
        }
        i += 1 // skip ';'
      }
    } else {
      i += 1
    }
  }
}

///|
/// Validate that all entity references in a value are defined
/// Checks against the reader's entities map plus predefined entities
pub fn validate_entity_refs(
  value : String,
  entities : Map[String, String]
) -> Unit raise XmlError {
  let chars = value.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    if chars[i] == '&' {
      i += 1
      if i >= len {
        return // syntax error handled elsewhere
      }
      if chars[i] == '#' {
        // Character reference - skip to ;
        while i < len && chars[i] != ';' {
          i += 1
        }
        if i < len {
          i += 1 // skip ;
        }
      } else {
        // Entity reference - extract name and check if defined
        let name_start = i
        while i < len && chars[i] != ';' && is_name_char(chars[i]) {
          i += 1
        }
        if i < len && chars[i] == ';' {
          let name = substring_from_chars(chars, name_start, i)
          // Check if entity is defined (including predefined entities)
          if not(is_predefined_entity(name)) && not(entities.contains(name)) {
            raise InvalidEntity("undefined entity reference: &" + name + ";")
          }
          i += 1 // skip ;
        }
      }
    } else {
      i += 1
    }
  }
}

///|
fn substring_from_chars(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn is_predefined_entity(name : String) -> Bool {
  name == "lt" || name == "gt" || name == "amp" || name == "quot" || name == "apos"
}

///|
/// Expand entity value recursively, validating all nested entity refs
/// Returns the fully expanded string
/// Raises error for undefined entities or recursive references
pub fn expand_entity_value(
  value : String,
  entities : Map[String, String],
  seen : Map[String, Bool],
) -> String raise XmlError {
  let buf = StringBuilder::new()
  let chars = value.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    // Check for CDATA section - copy everything inside literally
    if i + 8 < len && chars[i] == '<' && chars[i + 1] == '!' && chars[i + 2] == '[' && chars[i + 3] == 'C' && chars[i + 4] == 'D' && chars[i + 5] == 'A' && chars[i + 6] == 'T' && chars[i + 7] == 'A' && chars[i + 8] == '[' {
      // Found <![CDATA[ - copy until ]]>
      buf.write_string("<![CDATA[")
      i += 9
      while i < len {
        if i + 2 < len && chars[i] == ']' && chars[i + 1] == ']' && chars[i + 2] == '>' {
          buf.write_string("]]>")
          i += 3
          break
        }
        buf.write_char(chars[i])
        i += 1
      }
      continue
    }
    if chars[i] == '&' {
      i += 1
      if i >= len {
        buf.write_char('&')
        continue
      }
      if chars[i] == '#' {
        // Character reference - collect and decode
        let ref_start = i - 1 // include &
        i += 1
        while i < len && chars[i] != ';' {
          i += 1
        }
        if i < len {
          i += 1 // include ;
          let char_ref = substring_from_chars(chars, ref_start, i)
          let decoded = unescape(char_ref)
          buf.write_string(decoded)
        }
      } else {
        // Entity reference - extract name
        let name_start = i
        while i < len && chars[i] != ';' && is_name_char(chars[i]) {
          i += 1
        }
        if i < len && chars[i] == ';' {
          let name = substring_from_chars(chars, name_start, i)
          i += 1 // skip ;

          if is_predefined_entity(name) {
            // Predefined entities - decode to actual character
            let entity = "&" + name + ";"
            let decoded = unescape(entity)
            buf.write_string(decoded)
          } else {
            // Check if entity is defined
            match entities.get(name) {
              None => raise InvalidEntity("undefined entity reference: &" + name + ";")
              Some(entity_value) => {
                // Check for recursion
                if seen.contains(name) {
                  raise InvalidEntity("recursive entity reference: &" + name + ";")
                }
                // Mark as seen and expand recursively
                seen.set(name, true)
                let expanded = expand_entity_value(entity_value, entities, seen)
                buf.write_string(expanded)
                // Unmark after expansion (allow same entity in different branches)
                seen.remove(name)
              }
            }
          }
        } else {
          // Malformed entity ref - just write it
          buf.write_char('&')
          for j = name_start; j < i; j = j + 1 {
            buf.write_char(chars[j])
          }
        }
      }
    } else {
      buf.write_char(chars[i])
      i += 1
    }
  }
  buf.to_string()
}

///|
/// Parse ATTLIST declaration with validation
/// ATTLIST format: <!ATTLIST element_name attr_name type default>
pub fn parse_attlist(reader : Reader) -> Unit raise XmlError {
  // Skip whitespace after ATTLIST
  skip_ws(reader)

  // Read element name
  if not(peek_is_name_start(reader)) {
    raise InvalidSyntax("expected element name in ATTLIST")
  }
  skip_name(reader)

  // Parse attribute definitions until >
  while not(reader.is_eof()) {
    skip_ws(reader)
    match reader.peek() {
      Some('>') => {
        let _ = reader.advance()
        return
      }
      Some(c) if is_name_start_char(c) => {
        // Parse one attribute definition
        parse_attdef(reader)
      }
      _ => raise InvalidSyntax("expected attribute name or '>' in ATTLIST")
    }
  }
  raise InvalidSyntax("unterminated ATTLIST declaration")
}

///|
fn parse_attdef(reader : Reader) -> Unit raise XmlError {
  // Read attribute name
  skip_name(reader)

  // Require whitespace between name and type
  if not(peek_is_whitespace(reader)) {
    raise InvalidSyntax("whitespace required between attribute name and type")
  }
  skip_ws(reader)

  // Parse attribute type
  match reader.peek() {
    Some('(') => {
      // Enumeration
      parse_enumeration(reader)
    }
    Some(c) if is_name_start_char(c) => {
      // Keyword type: CDATA, ID, IDREF, etc.
      let type_name = read_name(reader)
      match type_name {
        "CDATA" | "ID" | "IDREF" | "IDREFS" | "ENTITY" | "ENTITIES" | "NMTOKEN" | "NMTOKENS" => ()
        "NOTATION" => {
          // NOTATION requires whitespace then (name|name...)
          if not(peek_is_whitespace(reader)) {
            raise InvalidSyntax("whitespace required after NOTATION keyword")
          }
          skip_ws(reader)
          if reader.peek() != Some('(') {
            raise InvalidSyntax("expected '(' after NOTATION")
          }
          parse_enumeration(reader)
        }
        _ => raise InvalidSyntax("invalid attribute type: " + type_name)
      }
    }
    _ => raise InvalidSyntax("expected attribute type")
  }

  // Require whitespace between type and default
  if not(peek_is_whitespace(reader)) {
    match reader.peek() {
      Some('"') | Some('\'') | Some('#') | Some('>') =>
        raise InvalidSyntax("whitespace required between attribute type and default")
      _ => ()
    }
  }
  skip_ws(reader)

  // Parse default
  match reader.peek() {
    Some('#') => {
      let _ = reader.advance()
      let keyword = read_name(reader)
      match keyword {
        "REQUIRED" | "IMPLIED" => ()
        "FIXED" => {
          skip_ws(reader)
          let value = read_quoted_value(reader)
          // Expand entity references to validate them (detects undefined and recursive refs)
          let seen : Map[String, Bool] = {}
          let _ = expand_entity_value(value, reader.entities, seen)
        }
        _ => raise InvalidSyntax("invalid attribute default keyword: #" + keyword)
      }
    }
    Some('"') | Some('\'') => {
      let value = read_quoted_value(reader)
      // Expand entity references to validate them (detects undefined and recursive refs)
      let seen : Map[String, Bool] = {}
      let _ = expand_entity_value(value, reader.entities, seen)
    }
    _ => raise InvalidSyntax("expected attribute default value or keyword")
  }
}

///|
fn parse_enumeration(reader : Reader) -> Unit raise XmlError {
  // Skip opening (
  let _ = reader.advance()
  skip_ws(reader)

  // Read first value - enumeration values are NMTOKENs (can start with digits)
  if not(peek_is_nmtoken_char(reader)) {
    raise InvalidSyntax("expected name in enumeration")
  }
  skip_nmtoken(reader)

  // Read remaining values
  for {
    skip_ws(reader)
    match reader.peek() {
      Some(')') => {
        let _ = reader.advance()
        break
      }
      Some('|') => {
        let _ = reader.advance()
        skip_ws(reader)
        if not(peek_is_nmtoken_char(reader)) {
          raise InvalidSyntax("expected name after '|' in enumeration")
        }
        skip_nmtoken(reader)
      }
      Some(',') => {
        raise InvalidSyntax("enumeration uses '|' separator, not ','")
      }
      _ => raise InvalidSyntax("expected '|' or ')' in enumeration")
    }
  }
}

///|
fn read_quoted_value(reader : Reader) -> String raise XmlError {
  let quote = match reader.peek() {
    Some('"') => '"'
    Some('\'') => '\''
    _ => raise InvalidSyntax("expected quoted value")
  }
  let _ = reader.advance()
  let buf = StringBuilder::new()
  while reader.peek() is Some(c) && c != quote {
    buf.write_char(c)
    let _ = reader.advance()
  }
  if reader.peek() != Some(quote) {
    raise InvalidSyntax("unterminated quoted value")
  }
  let _ = reader.advance()
  buf.to_string()
}

///|
fn skip_ws(reader : Reader) -> Unit {
  while reader.peek() is Some(c) && (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
    let _ = reader.advance()
  }
}

///|
fn skip_name(reader : Reader) -> Unit {
  while reader.peek() is Some(c) && is_name_char(c) {
    let _ = reader.advance()
  }
}

///|
fn read_name(reader : Reader) -> String {
  let buf = StringBuilder::new()
  while reader.peek() is Some(c) && is_name_char(c) {
    buf.write_char(c)
    let _ = reader.advance()
  }
  buf.to_string()
}

///|
fn peek_is_whitespace(reader : Reader) -> Bool {
  match reader.peek() {
    Some(' ') | Some('\t') | Some('\n') | Some('\r') => true
    _ => false
  }
}

///|
fn peek_is_name_start(reader : Reader) -> Bool {
  match reader.peek() {
    Some(c) => is_name_start_char(c)
    None => false
  }
}

///|
fn peek_is_nmtoken_char(reader : Reader) -> Bool {
  match reader.peek() {
    Some(c) => is_name_char(c)
    None => false
  }
}

///|
fn skip_nmtoken(reader : Reader) -> Unit {
  while reader.peek() is Some(c) && is_name_char(c) {
    let _ = reader.advance()
  }
}

///|
fn parse_hex_code(chars : Array[Char], start : Int, end : Int) -> Int {
  let mut result = 0
  for i = start; i < end; i = i + 1 {
    let c = chars[i]
    let digit = match c {
      '0' => 0
      '1' => 1
      '2' => 2
      '3' => 3
      '4' => 4
      '5' => 5
      '6' => 6
      '7' => 7
      '8' => 8
      '9' => 9
      'a' | 'A' => 10
      'b' | 'B' => 11
      'c' | 'C' => 12
      'd' | 'D' => 13
      'e' | 'E' => 14
      'f' | 'F' => 15
      _ => 0
    }
    result = result * 16 + digit
  }
  result
}

///|
fn parse_decimal_code(chars : Array[Char], start : Int, end : Int) -> Int {
  let mut result = 0
  for i = start; i < end; i = i + 1 {
    let c = chars[i]
    let digit = match c {
      '0' => 0
      '1' => 1
      '2' => 2
      '3' => 3
      '4' => 4
      '5' => 5
      '6' => 6
      '7' => 7
      '8' => 8
      '9' => 9
      _ => 0
    }
    result = result * 10 + digit
  }
  result
}

///|
/// Parse ELEMENT declaration with validation
/// ELEMENT format: <!ELEMENT name content-model>
pub fn parse_element_decl(reader : Reader) -> Unit raise XmlError {
  // Skip whitespace after ELEMENT
  skip_ws(reader)

  // Read element name
  if not(peek_is_name_start(reader)) {
    raise InvalidSyntax("expected element name in ELEMENT declaration")
  }
  skip_name(reader)

  // Require whitespace between name and content model
  if not(peek_is_whitespace(reader)) {
    raise InvalidSyntax("whitespace required between element name and content model")
  }
  skip_ws(reader)

  // Parse content model
  match reader.peek() {
    Some('(') => {
      parse_content_spec(reader, 0)
    }
    Some(c) if is_name_start_char(c) => {
      // Keyword: EMPTY or ANY
      let keyword = read_name(reader)
      match keyword {
        "EMPTY" | "ANY" => ()
        "CDATA" | "RCDATA" =>
          raise InvalidSyntax("CDATA/RCDATA content model is SGML only, not valid in XML")
        _ => raise InvalidSyntax("invalid content model keyword: " + keyword)
      }
    }
    _ => raise InvalidSyntax("expected content model")
  }

  skip_ws(reader)
  if reader.peek() != Some('>') {
    raise InvalidSyntax("expected '>' at end of ELEMENT declaration")
  }
  let _ = reader.advance()
}

///|
fn parse_content_spec(reader : Reader, _depth : Int) -> Unit raise XmlError {
  // Skip opening (
  let _ = reader.advance()
  skip_ws(reader)

  // Check for empty content model ()
  if reader.peek() == Some(')') {
    raise InvalidSyntax("empty content model () is not allowed")
  }

  // Check for #PCDATA (mixed content)
  if reader.peek() == Some('#') {
    let _ = reader.advance()
    let keyword = read_name(reader)
    if keyword != "PCDATA" {
      raise InvalidSyntax("expected PCDATA after #")
    }
    skip_ws(reader)
    // Mixed content: (#PCDATA) or (#PCDATA | name | name)*
    match reader.peek() {
      Some(')') => {
        let _ = reader.advance()
        // (#PCDATA) alone can only have * or nothing, not + or ?
        match reader.peek() {
          Some('*') => { let _ = reader.advance() }
          Some('+') => raise InvalidSyntax("(#PCDATA) cannot use '+', only '*' is allowed")
          Some('?') => raise InvalidSyntax("(#PCDATA) cannot use '?', only '*' is allowed")
          _ => () // no occurrence indicator is fine
        }
      }
      Some('|') => {
        // Mixed content with names
        while reader.peek() == Some('|') {
          let _ = reader.advance()
          skip_ws(reader)
          if reader.peek() == Some('#') {
            raise InvalidSyntax("#PCDATA must come first in mixed content")
          }
          if not(peek_is_name_start(reader)) {
            raise InvalidSyntax("expected name in mixed content")
          }
          skip_name(reader)
          skip_ws(reader)
        }
        if reader.peek() != Some(')') {
          raise InvalidSyntax("expected ')' to close mixed content")
        }
        let _ = reader.advance()
        // Mixed content must have * occurrence
        match reader.peek() {
          Some('*') => { let _ = reader.advance() }
          Some('+') => raise InvalidSyntax("mixed content must use '*', not '+'")
          Some('?') => raise InvalidSyntax("mixed content must use '*', not '?'")
          _ => raise InvalidSyntax("mixed content with alternatives must have '*' occurrence")
        }
      }
      _ => raise InvalidSyntax("expected ')' or '|' in mixed content")
    }
    return
  }

  // Check for extra parentheses around #PCDATA
  if reader.peek() == Some('(') {
    let saved_pos = reader.pos
    let _ = reader.advance()
    skip_ws(reader)
    if reader.peek() == Some('#') {
      raise InvalidSyntax("extra parentheses around #PCDATA not allowed")
    }
    // Reset and parse normally
    reader.pos = saved_pos
  }

  // Parse children content model
  // First, check for element name or nested group
  let mut need_connector = false // true if we need a connector before next element
  let mut connector : Char = ' ' // ' ' means not set yet
  let mut paren_depth = 1

  while paren_depth > 0 && not(reader.is_eof()) {
    skip_ws(reader)
    match reader.peek() {
      Some(')') => {
        let _ = reader.advance()
        paren_depth -= 1
        if paren_depth == 0 {
          // After closing paren, check for occurrence indicator
          skip_occurrence(reader)
        }
        need_connector = true
      }
      Some('(') => {
        if need_connector {
          raise InvalidSyntax("expected connector (',' or '|') before '('")
        }
        let _ = reader.advance()
        paren_depth += 1
        need_connector = false
      }
      Some('|') | Some(',') => {
        let c = reader.peek().unwrap()
        let _ = reader.advance()
        if connector == ' ' {
          connector = c
        } else if connector != c {
          raise InvalidSyntax("cannot mix ',' and '|' in content model at same level")
        }
        need_connector = false
      }
      Some(c) if is_name_start_char(c) => {
        if need_connector {
          raise InvalidSyntax("expected connector (',' or '|') between elements")
        }
        skip_name(reader)
        skip_occurrence(reader)
        need_connector = true
      }
      _ => {
        // Check for mismatched parentheses
        if paren_depth > 0 {
          raise InvalidSyntax("unexpected character in content model")
        }
      }
    }
  }

  if paren_depth > 0 {
    raise InvalidSyntax("mismatched parentheses in content model")
  }
}

///|
fn skip_occurrence(reader : Reader) -> Unit {
  match reader.peek() {
    Some('?') | Some('*') | Some('+') => { let _ = reader.advance() }
    _ => ()
  }
}

