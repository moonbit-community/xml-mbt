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
/// The reader consumes already-transcoded text: the decoder consumed the
/// BOM and UTF-16 null bytes are gone, so a null-byte heuristic over
/// decoded input cannot detect anything and only rejected well-formed
/// documents. Regression for W3C XML conformance suite
/// sun/invalid/utf16b.xml and utf16l.xml (well-formed, misclassified).

///|
test "utf16/declared UTF-16 with ASCII replacement text is accepted" {
  // Decoded shape of sun/invalid/utf16b.xml (UTF-16BE + BOM on the wire).
  let input = "<?xml version='1.0' encoding='UTF-16'?>\n<root/>\n"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  let mut saw_root = false
  for event in events {
    if event.kind is Start(_) {
      saw_root = true
    }
    if event.kind is Empty(_) {
      saw_root = true
    }
  }
  assert_true(saw_root)
}

///|
test "utf16/BOM-prefixed declared UTF-16 stays accepted" {
  let input = "\u{FEFF}<?xml version='1.0' encoding='UTF-16'?><root/>"
  let _ = @xml.Reader::from_string(input).read_events_until_eof()
}

///|
test "utf16/UTF-16LE and UTF-16BE declarations accepted" {
  let _ = @xml.Reader::from_string(
    "<?xml version='1.0' encoding='UTF-16LE'?><root/>",
  ).read_events_until_eof()
  let _ = @xml.Reader::from_string(
    "<?xml version='1.0' encoding='UTF-16BE'?><root/>",
  ).read_events_until_eof()
}
