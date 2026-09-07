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
  attributes : Array[XmlAttribute]
} derive(Eq)

///|
priv struct DebugXmlElement {
  name : String
  attributes : Array[(String, String)]
} derive(Debug)

///|
/// Get an attribute value by name
pub fn XmlElement::get(self : XmlElement, attr_name : String) -> String? {
  for pair in self.attributes {
    if pair.name == attr_name {
      return Some(pair.value)
    }
  }
  None
}

///|
/// An XML event returned by the parser
pub(all) enum EventKind {
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
} derive(Debug, Eq)

///|
/// XML parsing error
pub(all) suberror XmlErrorKind {
  UnexpectedEof
  InvalidSyntax(String)
  UnmatchedTag(expected~ : String, found~ : String)
  InvalidAttribute(String)
  InvalidEntity(String)
} derive(Debug, Eq)

///|
pub impl Show for XmlElement with fn output(self, logger) {
  logger.write_string("{name: ")
  logger.write_object(self.name)
  logger.write_string(", attributes: ")
  logger.write_object(
    Repr(
      self.attributes.map(fn(attribute) { (attribute.name, attribute.value) }),
    ),
  )
  logger.write_string("}")
}

///|
pub impl Debug for XmlElement with fn to_repr(self) {
  let debug : DebugXmlElement = {
    name: self.name,
    attributes: self.attributes.map(fn(attribute) {
      (attribute.name, attribute.value)
    }),
  }
  Repr(debug)
}

///|
pub impl Debug for Event with fn to_repr(self) {
  Repr(self.kind)
}

///|
pub impl Show for Event with fn output(self, logger) {
  logger.write_object(self.kind)
}

///|
pub impl Show for EventKind with fn output(self, logger) {
  match self {
    Start(elem) => {
      logger.write_string("Start(")
      logger.write_object(elem)
      logger.write_string(")")
    }
    End(name) => {
      logger.write_string("End(")
      logger.write_object(name)
      logger.write_string(")")
    }
    Empty(elem) => {
      logger.write_string("Empty(")
      logger.write_object(elem)
      logger.write_string(")")
    }
    Text(content) => {
      logger.write_string("Text(")
      logger.write_object(content)
      logger.write_string(")")
    }
    CData(content) => {
      logger.write_string("CData(")
      logger.write_object(content)
      logger.write_string(")")
    }
    Comment(content) => {
      logger.write_string("Comment(")
      logger.write_object(content)
      logger.write_string(")")
    }
    PI(target~, data~) => {
      logger.write_string("PI(target=")
      logger.write_object(target)
      logger.write_string(", data=")
      logger.write_object(data)
      logger.write_string(")")
    }
    Decl(version~, encoding~, standalone~) => {
      logger.write_string("Decl(version=")
      logger.write_object(version)
      logger.write_string(", encoding=")
      logger.write_object(Repr(encoding))
      logger.write_string(", standalone=")
      logger.write_object(Repr(standalone))
      logger.write_string(")")
    }
    DocType(name) => {
      logger.write_string("DocType(")
      logger.write_object(name)
      logger.write_string(")")
    }
    Eof => logger.write_string("Eof")
  }
}

///|
pub impl Show for XmlErrorKind with fn output(self, logger) {
  match self {
    UnexpectedEof => logger.write_string("UnexpectedEof")
    InvalidSyntax(message) => {
      logger.write_string("InvalidSyntax(")
      logger.write_object(message)
      logger.write_string(")")
    }
    UnmatchedTag(expected~, found~) => {
      logger.write_string("UnmatchedTag(expected=")
      logger.write_object(expected)
      logger.write_string(", found=")
      logger.write_object(found)
      logger.write_string(")")
    }
    InvalidAttribute(message) => {
      logger.write_string("InvalidAttribute(")
      logger.write_object(message)
      logger.write_string(")")
    }
    InvalidEntity(message) => {
      logger.write_string("InvalidEntity(")
      logger.write_object(message)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for XmlError with fn output(self, logger) {
  match self {
    At(error~, span~) => {
      logger.write_object(error)
      logger.write_string(" at ")
      logger.write_object(span.start.line)
      logger.write_string(":")
      logger.write_object(span.start.column)
      logger.write_string("-")
      logger.write_object(span.end.line)
      logger.write_string(":")
      logger.write_object(span.end.column)
    }
  }
}

///|
pub extend Event with Debug::{to_repr}

///|
pub extend Event with Show::{to_string, output}

///|
pub extend EventKind with Debug::{to_repr}

///|
pub extend EventKind with Eq::{not_equal, equal}

///|
pub extend EventKind with Show::{to_string, output}

///|
pub extend XmlElement with Debug::{to_repr}

///|
pub extend XmlElement with Eq::{not_equal, equal}

///|
pub extend XmlElement with Show::{to_string, output}

///|
pub extend XmlError with Show::{to_string, output}

///|
pub extend XmlErrorKind with Debug::{to_repr}

///|
pub extend XmlErrorKind with Eq::{not_equal, equal}

///|
pub extend XmlErrorKind with Show::{to_string, output}
