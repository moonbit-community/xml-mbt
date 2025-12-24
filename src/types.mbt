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
/// An XML element with tag name and attributes
pub struct XmlElement {
  name : String
  attributes : Array[(String, String)]
} derive(Show, Eq)

///|
pub fn XmlElement::new(name : String) -> XmlElement {
  { name, attributes: [] }
}

///|
pub fn XmlElement::with_attrs(
  name : String,
  attributes : Array[(String, String)],
) -> XmlElement {
  { name, attributes }
}

///|
/// Get an attribute value by name
pub fn XmlElement::get(self : XmlElement, attr_name : String) -> String? {
  for pair in self.attributes {
    if pair.0 == attr_name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// An XML event returned by the parser
pub(all) enum Event {
  /// Start of an XML element: <tag attr="value">
  Start(XmlElement)
  /// End of an XML element: </tag>
  End(String)
  /// Self-closing element: <tag/>
  Empty(XmlElement)
  /// Text content between elements
  Text(String)
  /// CDATA section: <![CDATA[...]]>
  CData(String)
  /// XML comment: <!-- ... -->
  Comment(String)
  /// Processing instruction: <?target data?>
  PI(target~ : String, data~ : String)
  /// XML declaration: <?xml version="1.0"?>
  Decl(version~ : String, encoding~ : String?, standalone~ : String?)
  /// DOCTYPE declaration
  DocType(String)
  /// End of file
  Eof
} derive(Show, Eq)

///|
/// XML parsing error
pub(all) suberror XmlError {
  UnexpectedEof
  InvalidSyntax(String)
  UnmatchedTag(expected~ : String, found~ : String)
  InvalidAttribute(String)
  InvalidEntity(String)
} derive(Show, Eq)
