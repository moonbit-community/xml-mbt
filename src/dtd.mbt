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
/// Validate entity-value reference syntax at declaration time.
/// Replacement markup is checked by the reader when the entity is used, so
/// comments, PIs and unused replacement text keep their XML-defined semantics.
fn validate_entity_value(value : String) -> Unit raise XmlErrorKind {
  let chars = value.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    // Parameter references cannot occur inside internal-subset declarations.
    if chars[i] == '%' {
      raise InvalidEntity("'%' is not allowed in an internal entity value")
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
          if !valid {
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
        if !is_valid_xml_char(code_point) {
          raise InvalidEntity("invalid character reference in entity value")
        }
        i += 1 // skip ';'
      } else {
        // Entity reference: &name;
        // Must start with letter or underscore
        if !is_name_start_char(chars[i]) {
          raise InvalidEntity("bare '&' not followed by valid reference")
        }
        while i < len && chars[i] != ';' {
          if !is_name_char(chars[i]) {
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
fn substring_from_chars(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder()
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
const MAX_ENTITY_EXPANSION_CHARS : Int = 262_144

///|
const MAX_ENTITY_EXPANSION_DEPTH : Int = 32

///|
priv struct EntityExpansionBudget {
  mut remaining : Int
}

///|
fn EntityExpansionBudget::consume(
  self : EntityExpansionBudget,
  amount : Int,
) -> Unit raise XmlErrorKind {
  if amount > self.remaining {
    raise InvalidEntity("entity expansion limit exceeded")
  }
  self.remaining -= amount
}

///|
/// Expand entity value recursively, validating all nested entity refs
/// Returns the fully expanded string
/// Raises error for undefined entities or recursive references
fn expand_entity_value_with_remaining(
  value : String,
  entities : Map[String, String],
  seen : Map[String, Bool],
  remaining : Int,
  attribute_context : Bool,
) -> (String, Int) raise XmlErrorKind {
  let budget : EntityExpansionBudget = { remaining, }
  let expanded = expand_entity_value_with_budget(
    value, entities, seen, budget, 0, attribute_context,
  )
  (expanded, budget.remaining)
}

///|
fn expand_entity_value_with_budget(
  value : String,
  entities : Map[String, String],
  seen : Map[String, Bool],
  budget : EntityExpansionBudget,
  depth : Int,
  attribute_context : Bool,
) -> String raise XmlErrorKind {
  if depth > MAX_ENTITY_EXPANSION_DEPTH {
    raise InvalidEntity("entity expansion depth exceeded")
  }
  let buf = StringBuilder()
  let chars = value.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    // References inside replacement comments and PIs are literal content.
    let literal_end : Array[Char]? = if !attribute_context && chars[i] == '<' {
      if matches_chars_at(chars, i, ['<', '!', '-', '-']) {
        Some(['-', '-', '>'])
      } else if matches_chars_at(chars, i, ['<', '?']) {
        Some(['?', '>'])
      } else {
        None
      }
    } else {
      None
    }
    if literal_end is Some(end) {
      while i < len {
        if matches_chars_at(chars, i, end) {
          for c in end {
            budget.consume(1)
            buf.write_char(c)
          }
          i += end.length()
          break
        }
        budget.consume(1)
        buf.write_char(chars[i])
        i += 1
      }
      continue
    }
    // Check for CDATA section - copy everything inside literally
    if !attribute_context &&
      i + 8 < len &&
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
      budget.consume(9)
      buf.write_string("<![CDATA[")
      i += 9
      while i < len {
        if i + 2 < len &&
          chars[i] == ']' &&
          chars[i + 1] == ']' &&
          chars[i + 2] == '>' {
          budget.consume(3)
          buf.write_string("]]>")
          i += 3
          break
        }
        budget.consume(1)
        buf.write_char(chars[i])
        i += 1
      }
      continue
    }
    if chars[i] == '&' {
      i += 1
      if i >= len {
        raise InvalidEntity("bare '&' in entity replacement text")
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
          budget.consume(decoded.length())
          buf.write_string(decoded)
        } else {
          raise InvalidEntity(
            "unterminated character reference in entity replacement text",
          )
        }
      } else {
        // Entity reference - extract name
        if !is_name_start_char(chars[i]) {
          raise InvalidEntity("invalid entity reference in replacement text")
        }
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
            budget.consume(decoded.length())
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
                let expanded = expand_entity_value_with_budget(
                  entity_value,
                  entities,
                  seen,
                  budget,
                  depth + 1,
                  attribute_context,
                )
                buf.write_string(expanded)
                // Unmark after expansion (allow same entity in different branches)
                seen.remove(name)
              }
            }
          }
        } else {
          raise InvalidEntity(
            "unterminated entity reference in replacement text",
          )
        }
      }
    } else {
      if attribute_context && chars[i] == '<' {
        raise InvalidEntity(
          "'<' in entity replacement text is not allowed in attribute values",
        )
      }
      budget.consume(1)
      if attribute_context && is_whitespace(chars[i]) {
        buf.write_char(' ')
      } else {
        buf.write_char(chars[i])
      }
      i += 1
    }
  }
  buf.to_string()
}

///|
fn matches_chars_at(
  chars : Array[Char],
  start : Int,
  expected : Array[Char],
) -> Bool {
  if start + expected.length() > chars.length() {
    return false
  }
  for i, c in expected {
    if chars[start + i] != c {
      return false
    }
  }
  true
}

///|
/// Parse ATTLIST declaration with validation
/// ATTLIST format: <!ATTLIST element_name attr_name type default>
fn parse_attlist(reader : Reader) -> Unit raise XmlErrorKind {
  // Skip whitespace after ATTLIST
  if reader.skip_whitespace_count() == 0 {
    raise InvalidSyntax("whitespace required after ATTLIST")
  }

  // Read element name
  if !peek_is_name_start(reader) {
    raise InvalidSyntax("expected element name in ATTLIST")
  }
  let elem_name = read_name(reader)

  // Parse attribute definitions until >
  while !reader.is_eof() {
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
fn parse_attdef(reader : Reader, elem_name : String) -> Unit raise XmlErrorKind {
  let attribute_start = reader.source_position()
  // Read attribute name
  let attr_name = read_name(reader)
  let name_span = source_span(attribute_start, reader.source_position())

  // Require whitespace between name and type
  if !peek_is_whitespace(reader) {
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
          if !peek_is_whitespace(reader) {
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
  let first_definition = !reader.attr_types.contains(key)
  if first_definition {
    reader.attr_types.set(key, attr_type)
  }

  // Require whitespace between type and default
  if !peek_is_whitespace(reader) {
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
  let default_value = match reader.peek() {
    Some('#') => {
      let _ = reader.advance()
      let keyword = read_name(reader)
      match keyword {
        "REQUIRED" | "IMPLIED" => None
        "FIXED" => {
          if reader.skip_whitespace_count() == 0 {
            raise InvalidSyntax("whitespace required after #FIXED")
          }
          Some(reader.read_attr_value())
        }
        _ =>
          raise InvalidSyntax("invalid attribute default keyword: #" + keyword)
      }
    }
    Some('"') | Some('\'') => Some(reader.read_attr_value())
    _ => raise InvalidSyntax("expected attribute default value or keyword")
  }
  if first_definition && default_value is Some((value, value_span)) {
    let attribute : XmlAttribute = {
      name: attr_name,
      value,
      span: source_span(attribute_start, reader.source_position()),
      name_span,
      value_span,
    }
    match reader.default_attributes.get(elem_name) {
      Some(defaults) => defaults.push(attribute)
      None => reader.default_attributes.set(elem_name, [attribute])
    }
  }
}

///|
fn parse_enumeration(reader : Reader) -> Unit raise XmlErrorKind {
  // Skip opening (
  let _ = reader.advance()
  skip_ws(reader)

  // Read first value - enumeration values are NMTOKENs (can start with digits)
  if !peek_is_nmtoken_char(reader) {
    raise InvalidSyntax("expected name in enumeration")
  }
  skip_nmtoken(reader)

  // Read remaining values
  for ;; {
    skip_ws(reader)
    match reader.peek() {
      Some(')') => {
        let _ = reader.advance()
        break
      }
      Some('|') => {
        let _ = reader.advance()
        skip_ws(reader)
        if !peek_is_nmtoken_char(reader) {
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
  let buf = StringBuilder()
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
fn parse_element_decl(reader : Reader) -> Unit raise XmlErrorKind {
  // Skip whitespace after ELEMENT
  if reader.skip_whitespace_count() == 0 {
    raise InvalidSyntax("whitespace required after ELEMENT")
  }

  // Read element name
  if !peek_is_name_start(reader) {
    raise InvalidSyntax("expected element name in ELEMENT declaration")
  }
  skip_name(reader)

  // Require whitespace between name and content model
  if !peek_is_whitespace(reader) {
    raise InvalidSyntax(
      "whitespace required between element name and content model",
    )
  }
  skip_ws(reader)

  // Parse content model
  match reader.peek() {
    Some('(') => parse_content_spec(reader)
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
fn parse_content_spec(reader : Reader) -> Unit raise XmlErrorKind {
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
          if !peek_is_name_start(reader) {
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

  // Each group has its own connector and operand state. Keep the stack explicit
  // so deeply nested content models do not consume the call stack.
  let groups : Array[(Char, Bool)] = [(' ', true)]
  while groups.length() > 0 && !reader.is_eof() {
    skip_ws(reader)
    let index = groups.length() - 1
    let (connector, expect_operand) = groups[index]
    match reader.peek() {
      Some(')') if !expect_operand => {
        let _ = reader.advance()
        let _ = groups.pop()
        skip_occurrence(reader)
        if groups.length() > 0 {
          let parent = groups.length() - 1
          groups[parent] = (groups[parent].0, false)
        }
      }
      Some('(') if expect_operand => {
        let _ = reader.advance()
        groups.push((' ', true))
      }
      Some('|' | ',') if !expect_operand => {
        let c = reader.peek().unwrap()
        let _ = reader.advance()
        if connector != ' ' && connector != c {
          raise InvalidSyntax(
            "cannot mix ',' and '|' in content model at same level",
          )
        }
        groups[index] = (c, true)
      }
      Some(c) if expect_operand && is_name_start_char(c) => {
        skip_name(reader)
        skip_occurrence(reader)
        groups[index] = (connector, false)
      }
      _ => raise InvalidSyntax("unexpected character in content model")
    }
  }
  if groups.length() > 0 {
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
