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
/// Escape special XML characters in text
/// Replaces: < > & " '
pub fn escape(text : String) -> String {
  let buf = StringBuilder::new()
  for c in text {
    match c {
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '&' => buf.write_string("&amp;")
      '"' => buf.write_string("&quot;")
      '\'' => buf.write_string("&apos;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Unescape XML entities
/// Handles: &lt; &gt; &amp; &quot; &apos; &#NN; &#xHH;
pub fn unescape(text : String) -> String raise XmlError {
  let buf = StringBuilder::new()
  let chars = text.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    if chars[i] == '&' {
      // Find the end of the entity
      let start = i
      i += 1
      while i < len && chars[i] != ';' {
        i += 1
      }
      if i >= len {
        raise InvalidEntity(substring_chars(chars, start, len))
      }
      let entity = substring_chars(chars, start, i + 1)
      let decoded = decode_entity(entity)
      buf.write_string(decoded)
      i += 1
    } else {
      buf.write_char(chars[i])
      i += 1
    }
  }
  buf.to_string()
}

///|
fn substring_chars(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn decode_entity(entity : String) -> String raise XmlError {
  match entity {
    "&lt;" => "<"
    "&gt;" => ">"
    "&amp;" => "&"
    "&quot;" => "\""
    "&apos;" => "'"
    _ =>
      // Check for numeric entity: &#NN; or &#xHH;
      if entity.has_prefix("&#") && entity.has_suffix(";") {
        let chars = entity.to_array()
        let inner_start = 2
        let inner_end = chars.length() - 1
        let first_inner = chars[inner_start]
        let code_point = if first_inner == 'x' || first_inner == 'X' {
          // Hexadecimal: skip the 'x'
          parse_hex_chars(chars, inner_start + 1, inner_end)
        } else {
          // Decimal
          parse_decimal_chars(chars, inner_start, inner_end)
        }
        // Be lenient: output any valid Unicode code point (even if not valid XML)
        // Only reject code points that can't be represented in Unicode
        if is_valid_unicode_code_point(code_point) {
          Int::unsafe_to_char(code_point).to_string()
        } else {
          raise InvalidEntity(entity)
        }
      } else {
        raise InvalidEntity(entity)
      }
  }
}

///|
fn is_valid_unicode_code_point(code : Int) -> Bool {
  // Accept any Unicode code point in the valid range (0x1 to 0x10FFFF)
  // excluding NUL (0x00) and surrogate pairs (0xD800-0xDFFF)
  code >= 1 && code <= 0x10FFFF && not(code >= 0xD800 && code <= 0xDFFF)
}

///|
fn is_valid_xml_char(code : Int) -> Bool {
  code == 0x9 ||
  code == 0xA ||
  code == 0xD ||
  (code >= 0x20 && code <= 0xD7FF) ||
  (code >= 0xE000 && code <= 0xFFFD) ||
  (code >= 0x10000 && code <= 0x10FFFF)
}

///|
fn parse_hex_chars(
  chars : Array[Char],
  start : Int,
  end : Int,
) -> Int raise XmlError {
  let mut result = 0
  // Maximum valid Unicode code point is 0x10FFFF
  let max_code_point = 0x10FFFF
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
      _ => raise InvalidEntity(substring_chars(chars, 0, chars.length()))
    }
    result = result * 16 + digit
    // Check for overflow - if result exceeds max code point, it's invalid
    if result > max_code_point {
      raise InvalidEntity(substring_chars(chars, 0, chars.length()))
    }
  }
  result
}

///|
fn parse_decimal_chars(
  chars : Array[Char],
  start : Int,
  end : Int,
) -> Int raise XmlError {
  let mut result = 0
  // Maximum valid Unicode code point is 0x10FFFF (1114111 decimal)
  let max_code_point = 0x10FFFF
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
      _ => raise InvalidEntity(substring_chars(chars, 0, chars.length()))
    }
    result = result * 10 + digit
    // Check for overflow - if result exceeds max code point, it's invalid
    if result > max_code_point {
      raise InvalidEntity(substring_chars(chars, 0, chars.length()))
    }
  }
  result
}
