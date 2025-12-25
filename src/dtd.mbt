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
/// Validate parameter entity value (less strict than general entity)
/// Checks for PE references, invalid characters, and bare &
pub fn validate_pe_value(value : String) -> Unit raise XmlError {
  let chars = value.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    let c = chars[i]
    // Check for invalid XML characters
    let code = c.to_int()
    if not(is_valid_xml_char(code)) {
      raise InvalidEntity("invalid character in parameter entity value")
    }
    // Check for PE reference
    if c == '%' {
      let j = i + 1
      if j < len && is_name_start_char(chars[j]) {
        raise InvalidEntity(
          "parameter entity reference not allowed in entity value",
        )
      }
    }
    // Check for bare &
    if c == '&' {
      i += 1
      if i >= len {
        raise InvalidEntity("bare '&' in parameter entity value")
      }
      // Must be followed by # for char ref or name start for entity ref
      let next = chars[i]
      if next == '#' {
        // Character reference - skip to ;
        while i < len && chars[i] != ';' {
          i += 1
        }
        if i >= len {
          raise InvalidEntity(
            "unterminated character reference in parameter entity value",
          )
        }
      } else if is_name_start_char(next) {
        // Entity reference - skip to ;
        while i < len && chars[i] != ';' {
          i += 1
        }
        if i >= len {
          raise InvalidEntity(
            "unterminated entity reference in parameter entity value",
          )
        }
      } else {
        raise InvalidEntity("bare '&' in parameter entity value")
      }
    }
    i += 1
  }
}

///|
/// Validate entity replacement text for well-formedness
/// Checks that entity values don't contain bare & not followed by valid reference
/// Also validates character references when expanded
pub fn validate_entity_value(value : String) -> Unit raise XmlError {
  let chars = value.to_array()
  let len = chars.length()
  let mut i = 0

  // Check for text declaration (<?xml) - not allowed in internal parsed entities
  if len >= 5 &&
    chars[0] == '<' &&
    chars[1] == '?' &&
    chars[2] == 'x' &&
    chars[3] == 'm' &&
    chars[4] == 'l' {
    raise InvalidEntity(
      "text declaration not allowed in internal parsed entity",
    )
  }
  while i < len {
    // Check for parameter entity reference - not allowed in entity values in internal subset
    if chars[i] == '%' {
      // Check if it looks like a PE reference
      let j = i + 1
      if j < len && is_name_start_char(chars[j]) {
        raise InvalidEntity(
          "parameter entity reference not allowed in entity value",
        )
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
          raise InvalidEntity("empty character reference in entity value")
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
            raise InvalidEntity(
              "character reference &#38; produces bare '&' at end of entity value",
            )
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
            while j < len &&
                  (
                    (chars[j] >= '0' && chars[j] <= '9') ||
                    (chars[j] >= 'a' && chars[j] <= 'f') ||
                    (chars[j] >= 'A' && chars[j] <= 'F')
                  ) {
              j += 1
            }
            // Must end with ;
            if j >= len || chars[j] != ';' {
              raise InvalidEntity(
                "character reference &#38; produces incomplete character reference",
              )
            }
          } else if not(is_name_start_char(next)) {
            raise InvalidEntity(
              "character reference &#38; produces bare '&' not followed by valid reference",
            )
          } else {
            // Entity reference - must end with ;
            let mut j = after_semi
            while j < len && is_name_char(chars[j]) {
              j += 1
            }
            if j >= len || chars[j] != ';' {
              raise InvalidEntity(
                "character reference &#38; produces incomplete entity reference",
              )
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

  // Additional check: detect < (via &#60; or &#x3c;) inside attribute value contexts
  // This is invalid as < cannot appear literally in attribute values
  validate_no_lt_in_attr_context(chars, len)

  // Check for incomplete markup from character references
  validate_no_incomplete_markup(chars, len)

  // Check for unbalanced literal markup (e.g., </foo><foo>)
  validate_literal_markup(chars, len)
}

///|
/// Check if entity value contains < in an attribute value context
/// Scans for patterns like: a='&#60;' or a="&#x3C;"
fn validate_no_lt_in_attr_context(
  chars : Array[Char],
  len : Int,
) -> Unit raise XmlError {
  let mut i = 0
  while i < len {
    // Look for = followed by quote (attribute value start)
    if chars[i] == '=' {
      i += 1
      // Skip whitespace
      while i < len &&
            (
              chars[i] == ' ' ||
              chars[i] == '\t' ||
              chars[i] == '\n' ||
              chars[i] == '\r'
            ) {
        i += 1
      }
      if i < len && (chars[i] == '\'' || chars[i] == '"') {
        let quote = chars[i]
        i += 1
        // Inside attribute value - check for &#60; or &#x3c;/&#x3C;
        while i < len && chars[i] != quote {
          if chars[i] == '&' && i + 1 < len && chars[i + 1] == '#' {
            // Character reference - check if it's < (code point 60 or 0x3c)
            let ref_start = i
            i += 2 // skip &#
            if i < len {
              if chars[i] == 'x' || chars[i] == 'X' {
                // Hex: check for 3c or 3C
                i += 1
                if i + 1 < len &&
                  chars[i] == '3' &&
                  (chars[i + 1] == 'c' || chars[i + 1] == 'C') {
                  // Found &#x3c; or &#x3C; in attribute value
                  raise InvalidEntity(
                    "'<' not allowed in attribute value (via character reference)",
                  )
                }
              } else if chars[i] == '6' && i + 1 < len && chars[i + 1] == '0' {
                // Decimal: check for 60
                // Make sure it's exactly 60 and followed by ;
                if i + 2 < len && chars[i + 2] == ';' {
                  raise InvalidEntity(
                    "'<' not allowed in attribute value (via character reference)",
                  )
                }
              }
            }
            i = ref_start + 1 // continue scanning from after &
          } else {
            i += 1
          }
        }
        if i < len {
          i += 1 // skip closing quote
        }
      }
    } else {
      i += 1
    }
  }
}

///|
/// Check if entity value contains &#60; that creates incomplete markup
/// Entity values must be self-contained well-formed content
fn validate_no_incomplete_markup(
  chars : Array[Char],
  len : Int,
) -> Unit raise XmlError {
  let mut i = 0
  while i < len {
    // Look for &#60; or &#x3c; (expands to <)
    if chars[i] == '&' && i + 1 < len && chars[i + 1] == '#' {
      let ref_start = i
      i += 2
      let mut is_lt = false
      if i < len {
        if chars[i] == 'x' || chars[i] == 'X' {
          // Hex reference
          i += 1
          if i + 2 < len &&
            chars[i] == '3' &&
            (chars[i + 1] == 'c' || chars[i + 1] == 'C') &&
            chars[i + 2] == ';' {
            is_lt = true
            i += 3
          }
        } else if i + 2 < len &&
          chars[i] == '6' &&
          chars[i + 1] == '0' &&
          chars[i + 2] == ';' {
          // Decimal &#60;
          is_lt = true
          i += 3
        }
      }
      if is_lt {
        // Found < via char ref - check what follows
        if i < len {
          let next = chars[i]
          if next == '!' {
            // Could be <!-- or <!ENTITY etc - check for incomplete comment
            if i + 1 < len &&
              chars[i + 1] == '-' &&
              i + 2 < len &&
              chars[i + 2] == '-' {
              // Comment start - must have --> in entity value
              let mut found_end = false
              let mut j = i + 3
              while j + 2 < len {
                if chars[j] == '-' && chars[j + 1] == '-' && chars[j + 2] == '>' {
                  found_end = true
                  break
                }
                j += 1
              }
              if not(found_end) {
                raise InvalidEntity(
                  "incomplete comment in entity value (missing -->)",
                )
              }
            }
          } else if is_name_start_char(next) {
            // Element start - must have matching end tag or be empty
            // Collect element name
            let name_start = i
            while i < len && is_name_char(chars[i]) {
              i += 1
            }
            let name_end = i
            // Skip to > (simplified - doesn't handle attributes properly)
            while i < len && chars[i] != '>' {
              if chars[i] == '/' && i + 1 < len && chars[i + 1] == '>' {
                // Empty element - OK
                i = len // exit loop
                break
              }
              i += 1
            }
            if i < len && chars[i] == '>' {
              i += 1
              // Now we need to find </name> in the rest of entity value
              let mut found_end = false
              while i + 3 < len {
                if chars[i] == '<' && chars[i + 1] == '/' {
                  // Check name matches
                  let mut j = i + 2
                  let mut k = name_start
                  let mut matches = true
                  while k < name_end && j < len {
                    if chars[j] != chars[k] {
                      matches = false
                      break
                    }
                    j += 1
                    k += 1
                  }
                  if matches && k == name_end && j < len && chars[j] == '>' {
                    found_end = true
                    break
                  }
                }
                i += 1
              }
              if not(found_end) {
                raise InvalidEntity("unclosed element in entity value")
              }
            }
          }
        }
      } else {
        i = ref_start + 1
      }
    } else {
      i += 1
    }
  }
}

///|
/// Check for unbalanced markup in entity values after expanding char refs
/// e.g., "</foo><foo>" has an end tag without matching start
fn validate_literal_markup(
  chars : Array[Char],
  len : Int,
) -> Unit raise XmlError {
  // First expand character references to get actual markup
  let expanded = expand_char_refs(chars, len)
  let exp_chars = expanded.to_array()
  let exp_len = exp_chars.length()

  // Track open elements
  let stack : Array[String] = []
  let mut i = 0
  while i < exp_len {
    if exp_chars[i] == '<' {
      i += 1
      if i >= exp_len {
        continue
      }
      if exp_chars[i] == '/' {
        // End tag
        i += 1
        let name_start = i
        while i < exp_len && is_name_char(exp_chars[i]) {
          i += 1
        }
        let name = substring_from_chars(exp_chars, name_start, i)
        // Check stack
        if stack.length() == 0 || stack.last() != Some(name) {
          raise InvalidEntity(
            "unbalanced end tag </" + name + "> in entity value",
          )
        }
        let _ = stack.pop()
        // Skip to >
        while i < exp_len && exp_chars[i] != '>' {
          i += 1
        }
      } else if exp_chars[i] == '!' || exp_chars[i] == '?' {
        // Comment, CDATA, PI - skip to end
        while i < exp_len && exp_chars[i] != '>' {
          i += 1
        }
      } else if is_name_start_char(exp_chars[i]) {
        // Start tag
        let name_start = i
        while i < exp_len && is_name_char(exp_chars[i]) {
          i += 1
        }
        let name = substring_from_chars(exp_chars, name_start, i)
        // Skip attributes until > or />
        let mut is_empty = false
        while i < exp_len && exp_chars[i] != '>' {
          if exp_chars[i] == '/' && i + 1 < exp_len && exp_chars[i + 1] == '>' {
            is_empty = true
            break
          }
          i += 1
        }
        if not(is_empty) {
          stack.push(name)
        }
      }
    }
    i += 1
  }
  // Check for unclosed elements
  if stack.length() > 0 {
    let name = stack.last().unwrap()
    raise InvalidEntity("unclosed element <" + name + "> in entity value")
  }
}

///|
/// Expand only character references in a string (not entity refs)
fn expand_char_refs(chars : Array[Char], len : Int) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < len {
    if chars[i] == '&' && i + 1 < len && chars[i + 1] == '#' {
      // Character reference
      i += 2
      let is_hex = i < len && (chars[i] == 'x' || chars[i] == 'X')
      if is_hex {
        i += 1
      }
      let digit_start = i
      while i < len && chars[i] != ';' {
        i += 1
      }
      if i < len {
        let code = if is_hex {
          parse_hex_code(chars, digit_start, i)
        } else {
          parse_decimal_code(chars, digit_start, i)
        }
        if code > 0 && code <= 0x10FFFF {
          buf.write_char(Int::unsafe_to_char(code))
        }
        i += 1 // skip ;
      }
    } else {
      buf.write_char(chars[i])
      i += 1
    }
  }
  buf.to_string()
}

///|
/// Validate that all entity references in a value are defined
/// Checks against the reader's entities map plus predefined entities
pub fn validate_entity_refs(
  value : String,
  entities : Map[String, String],
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
  name == "lt" ||
  name == "gt" ||
  name == "amp" ||
  name == "quot" ||
  name == "apos"
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
    if i + 8 < len &&
      chars[i] == '<' &&
      chars[i + 1] == '!' &&
      chars[i + 2] == '[' &&
      chars[i + 3] == 'C' &&
      chars[i + 4] == 'D' &&
      chars[i + 5] == 'A' &&
      chars[i + 6] == 'T' &&
      chars[i + 7] == 'A' &&
      chars[i + 8] == '[' {
      // Found <![CDATA[ - copy until ]]>
      buf.write_string("<![CDATA[")
      i += 9
      while i < len {
        if i + 2 < len &&
          chars[i] == ']' &&
          chars[i + 1] == ']' &&
          chars[i + 2] == '>' {
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
              None =>
                raise InvalidEntity(
                  "undefined entity reference: &" + name + ";",
                )
              Some(entity_value) => {
                // Check for recursion
                if seen.contains(name) {
                  raise InvalidEntity(
                    "recursive entity reference: &" + name + ";",
                  )
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
  let elem_name = read_name(reader)

  // Parse attribute definitions until >
  while not(reader.is_eof()) {
    skip_ws(reader)
    match reader.peek() {
      Some('>') => {
        let _ = reader.advance()
        return
      }
      Some(c) if is_name_start_char(c) =>
        // Parse one attribute definition
        parse_attdef(reader, elem_name)
      _ => raise InvalidSyntax("expected attribute name or '>' in ATTLIST")
    }
  }
  raise InvalidSyntax("unterminated ATTLIST declaration")
}

///|
fn parse_attdef(reader : Reader, elem_name : String) -> Unit raise XmlError {
  // Read attribute name
  let attr_name = read_name(reader)

  // Require whitespace between name and type
  if not(peek_is_whitespace(reader)) {
    raise InvalidSyntax("whitespace required between attribute name and type")
  }
  skip_ws(reader)

  // Parse attribute type
  let attr_type = match reader.peek() {
    Some('(') => {
      // Enumeration - treated like NMTOKEN for normalization
      parse_enumeration(reader)
      "ENUMERATION"
    }
    Some(c) if is_name_start_char(c) => {
      // Keyword type: CDATA, ID, IDREF, etc.
      let type_name = read_name(reader)
      match type_name {
        "CDATA"
        | "ID"
        | "IDREF"
        | "IDREFS"
        | "ENTITY"
        | "ENTITIES"
        | "NMTOKEN"
        | "NMTOKENS" => type_name
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
          "NOTATION"
        }
        _ => raise InvalidSyntax("invalid attribute type: " + type_name)
      }
    }
    _ => raise InvalidSyntax("expected attribute type")
  }

  // Store attribute type (first declaration wins per XML spec)
  let key = elem_name + ":" + attr_name
  if not(reader.attr_types.contains(key)) {
    reader.attr_types.set(key, attr_type)
  }

  // Require whitespace between type and default
  if not(peek_is_whitespace(reader)) {
    match reader.peek() {
      Some('"') | Some('\'') | Some('#') | Some('>') =>
        raise InvalidSyntax(
          "whitespace required between attribute type and default",
        )
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
        _ =>
          raise InvalidSyntax("invalid attribute default keyword: #" + keyword)
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
      Some(',') =>
        raise InvalidSyntax("enumeration uses '|' separator, not ','")
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
  while reader.peek() is Some(c) &&
        (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
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
    raise InvalidSyntax(
      "whitespace required between element name and content model",
    )
  }
  skip_ws(reader)

  // Parse content model
  match reader.peek() {
    Some('(') => parse_content_spec(reader, 0)
    Some(c) if is_name_start_char(c) => {
      // Keyword: EMPTY or ANY
      let keyword = read_name(reader)
      match keyword {
        "EMPTY" | "ANY" => ()
        "CDATA" | "RCDATA" =>
          raise InvalidSyntax(
            "CDATA/RCDATA content model is SGML only, not valid in XML",
          )
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
          Some('*') => {
            let _ = reader.advance()

          }
          Some('+') =>
            raise InvalidSyntax("(#PCDATA) cannot use '+', only '*' is allowed")
          Some('?') =>
            raise InvalidSyntax("(#PCDATA) cannot use '?', only '*' is allowed")
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
          Some('*') => {
            let _ = reader.advance()

          }
          Some('+') =>
            raise InvalidSyntax("mixed content must use '*', not '+'")
          Some('?') =>
            raise InvalidSyntax("mixed content must use '*', not '?'")
          _ =>
            raise InvalidSyntax(
              "mixed content with alternatives must have '*' occurrence",
            )
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
          raise InvalidSyntax(
            "cannot mix ',' and '|' in content model at same level",
          )
        }
        need_connector = false
      }
      Some(c) if is_name_start_char(c) => {
        if need_connector {
          raise InvalidSyntax(
            "expected connector (',' or '|') between elements",
          )
        }
        skip_name(reader)
        skip_occurrence(reader)
        need_connector = true
      }
      _ =>
        // Check for mismatched parentheses
        if paren_depth > 0 {
          raise InvalidSyntax("unexpected character in content model")
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
    Some('?') | Some('*') | Some('+') => {
      let _ = reader.advance()

    }
    _ => ()
  }
}
