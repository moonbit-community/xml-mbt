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
  { buffer: StringBuilder::new(), indent_level: 0, pretty: false }
}

///|
/// Write an XML event
pub fn Writer::write_event(self : Writer, event : Event) -> Unit {
  match event {
    Start(elem) => self.start_element(elem.name, elem.attributes)
    End(name) => self.end_element(name)
    Empty(elem) => self.empty_element(elem.name, elem.attributes)
    Text(content) => self.text(content)
    CData(content) => self.cdata(content)
    Comment(content) => self.comment(content)
    PI(target~, data~) => {
      self.buffer.write_string("<?")
      self.buffer.write_string(target)
      if data.length() > 0 {
        self.buffer.write_string(" ")
        self.buffer.write_string(data)
      }
      self.buffer.write_string("?>")
    }
    Decl(version~, encoding~, standalone~) => {
      self.buffer.write_string("<?xml version=\"")
      self.buffer.write_string(version)
      self.buffer.write_string("\"")
      match encoding {
        Some(enc) => {
          self.buffer.write_string(" encoding=\"")
          self.buffer.write_string(enc)
          self.buffer.write_string("\"")
        }
        None => ()
      }
      match standalone {
        Some(s) => {
          self.buffer.write_string(" standalone=\"")
          self.buffer.write_string(s)
          self.buffer.write_string("\"")
        }
        None => ()
      }
      self.buffer.write_string("?>")
    }
    DocType(name) => {
      self.buffer.write_string("<!DOCTYPE ")
      self.buffer.write_string(name)
      self.buffer.write_string(">")
    }
    Eof => ()
  }
}

///|
/// Write a start element
pub fn Writer::start_element(
  self : Writer,
  name : String,
  attributes : Array[(String, String)],
) -> Unit {
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
}

///|
/// Write an end element
pub fn Writer::end_element(self : Writer, name : String) -> Unit {
  self.buffer.write_string("</")
  self.buffer.write_string(name)
  self.buffer.write_string(">")
}

///|
/// Write a self-closing element
pub fn Writer::empty_element(
  self : Writer,
  name : String,
  attributes : Array[(String, String)],
) -> Unit {
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
}

///|
/// Write text content (escaped)
pub fn Writer::text(self : Writer, content : String) -> Unit {
  self.buffer.write_string(escape(content))
}

///|
/// Write CDATA section
pub fn Writer::cdata(self : Writer, content : String) -> Unit {
  self.buffer.write_string("<![CDATA[")
  self.buffer.write_string(content)
  self.buffer.write_string("]]>")
}

///|
/// Write a comment
pub fn Writer::comment(self : Writer, content : String) -> Unit {
  self.buffer.write_string("<!--")
  self.buffer.write_string(content)
  self.buffer.write_string("-->")
}

///|
/// Get the generated XML string
pub fn Writer::to_string(self : Writer) -> String {
  self.buffer.to_string()
}

///|
/// Escape attribute value (escapes < > & " ')
fn escape_attr(text : String) -> String {
  escape(text)
}
