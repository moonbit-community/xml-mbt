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
fn xml_namespace_uri() -> String {
  "http://www.w3.org/XML/1998/namespace"
}

///|
fn xmlns_namespace_uri() -> String {
  "http://www.w3.org/2000/xmlns/"
}

///|
fn namespace_reader_from_reader(reader : Reader) -> NamespaceReader {
  let base_scope : Map[String, String] = Map([])
  base_scope.set("xml", xml_namespace_uri())
  { reader, scopes: [base_scope] }
}

///|
/// Create a namespace-aware reader from a string.
pub fn NamespaceReader::from_string(input : String) -> NamespaceReader {
  namespace_reader_from_reader(Reader::from_string(input))
}

///|
/// Create a namespace-aware reader from a file path.
pub fn NamespaceReader::from_file(
  path : String,
) -> NamespaceReader raise @fs.IOError {
  namespace_reader_from_reader(Reader::from_file(path))
}

///|
/// Check whether the underlying reader has consumed its input.
pub fn NamespaceReader::is_eof(self : NamespaceReader) -> Bool {
  self.reader.is_eof()
}

///|
/// Get the current one-indexed line number.
pub fn NamespaceReader::line(self : NamespaceReader) -> Int {
  self.reader.line()
}

///|
/// Get the current one-indexed column number.
pub fn NamespaceReader::column(self : NamespaceReader) -> Int {
  self.reader.column()
}

///|
fn split_qualified_name(name : String) -> (String?, String) raise XmlErrorKind {
  if name == "" {
    raise InvalidSyntax("invalid qualified name: " + name)
  }
  match name.find(":") {
    None => (None, name)
    Some(index) => {
      if index == 0 || index + 1 >= name.length() {
        raise InvalidSyntax("invalid qualified name: " + name)
      }
      let prefix = name[:index].to_owned()
      let local_name = name[index + 1:].to_owned()
      if local_name.find(":") is Some(_) {
        raise InvalidSyntax("invalid qualified name: " + name)
      }
      (Some(prefix), local_name)
    }
  }
}

///|
fn namespace_declaration(
  attribute : XmlAttribute,
) -> NamespaceDeclaration? raise XmlErrorKind {
  let attribute_name = attribute.name
  let namespace_uri = attribute.value
  if attribute_name == "xmlns" {
    Some({
      prefix: None,
      namespace_uri,
      span: attribute.span,
      name_span: attribute.name_span,
      value_span: attribute.value_span,
    })
  } else if attribute_name.has_prefix("xmlns:") {
    let declared_prefix = attribute_name[6:].to_owned()
    if declared_prefix == "" || declared_prefix.find(":") is Some(_) {
      raise InvalidSyntax("invalid qualified name: " + attribute_name)
    }
    Some({
      prefix: Some(declared_prefix),
      namespace_uri,
      span: attribute.span,
      name_span: attribute.name_span,
      value_span: attribute.value_span,
    })
  } else {
    None
  }
}

///|
fn apply_namespace_declaration(
  scope : Map[String, String],
  declaration : NamespaceDeclaration,
) -> Unit raise XmlErrorKind {
  let uri = declaration.namespace_uri
  match declaration.prefix {
    None => {
      if uri == xml_namespace_uri() || uri == xmlns_namespace_uri() {
        raise InvalidSyntax(
          "reserved namespace URI cannot be the default namespace",
        )
      }
      if uri == "" {
        scope.remove("")
      } else {
        scope.set("", uri)
      }
    }
    Some(prefix) => {
      if prefix == "xmlns" {
        raise InvalidSyntax("namespace prefix 'xmlns' is reserved")
      }
      if prefix == "xml" {
        if uri != xml_namespace_uri() {
          raise InvalidSyntax(
            "prefix 'xml' must be bound to " + xml_namespace_uri(),
          )
        }
      } else {
        if uri == "" {
          raise InvalidSyntax(
            "namespace prefix cannot be bound to an empty URI",
          )
        }
        if uri == xml_namespace_uri() {
          raise InvalidSyntax(
            "only prefix 'xml' may be bound to " + xml_namespace_uri(),
          )
        }
      }
      if uri == xmlns_namespace_uri() {
        raise InvalidSyntax("namespace URI " + uri + " is reserved")
      }
      scope.set(prefix, uri)
    }
  }
}

///|
fn NamespaceReader::copy_current_scope(
  self : NamespaceReader,
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  let current = self.scopes[self.scopes.length() - 1]
  for prefix, uri in current {
    result.set(prefix, uri)
  }
  result
}

///|
fn resolve_xml_name(
  qualified_name : String,
  scope : Map[String, String],
  use_default_namespace : Bool,
) -> XmlName raise XmlErrorKind {
  let (prefix, local_name) = split_qualified_name(qualified_name)
  let namespace_uri = match prefix {
    Some("xmlns") => raise InvalidSyntax("namespace prefix 'xmlns' is reserved")
    Some(prefix) =>
      match scope.get(prefix) {
        Some(uri) => Some(uri)
        None => raise InvalidSyntax("undeclared namespace prefix: " + prefix)
      }
    None => if use_default_namespace { scope.get("") } else { None }
  }
  { qualified_name, prefix, local_name, namespace_uri }
}

///|
fn NamespaceReader::resolve_element(
  self : NamespaceReader,
  element : XmlElement,
  push_scope : Bool,
) -> NamespaceElement raise XmlErrorKind {
  let scope = self.copy_current_scope()
  let declarations : Array[NamespaceDeclaration] = []
  for attribute in element.attributes {
    match namespace_declaration(attribute) {
      Some(declaration) => {
        apply_namespace_declaration(scope, declaration)
        declarations.push(declaration)
      }
      None => ()
    }
  }
  let name = resolve_xml_name(element.name, scope, true)
  let attributes : Array[NamespaceAttribute] = []
  let expanded_names : Map[String, Bool] = Map([])
  for attribute in element.attributes {
    if namespace_declaration(attribute) is None {
      let attribute_name = resolve_xml_name(attribute.name, scope, false)
      let uri = attribute_name.namespace_uri.unwrap_or("")
      let expanded_name = uri + "\u{0}" + attribute_name.local_name
      if expanded_names.contains(expanded_name) {
        let display_name = if uri == "" {
          attribute_name.local_name
        } else {
          "{" + uri + "}" + attribute_name.local_name
        }
        raise InvalidSyntax(
          "duplicate expanded attribute name: " + display_name,
        )
      }
      expanded_names.set(expanded_name, true)
      attributes.push({
        name: attribute_name,
        value: attribute.value,
        span: attribute.span,
        name_span: attribute.name_span,
        value_span: attribute.value_span,
      })
    }
  }
  if push_scope {
    self.scopes.push(scope)
  }
  { name, attributes, namespace_declarations: declarations }
}

///|
/// Read the next namespace-aware XML event.
pub fn NamespaceReader::read_event(
  self : NamespaceReader,
) -> NamespaceEvent raise XmlError {
  let event = self.reader.read_event()
  let kind = try {
    match event.kind {
      Start(element) =>
        NamespaceEventKind::Start(self.resolve_element(element, true))
      Empty(element) => Empty(self.resolve_element(element, false))
      End(qualified_name) => {
        let scope = self.scopes[self.scopes.length() - 1]
        let name = resolve_xml_name(qualified_name, scope, true)
        if self.scopes.length() > 1 {
          let _ = self.scopes.pop()
        }
        End(name)
      }
      Text(content) => Text(content)
      CData(content) => CData(content)
      Comment(content) => Comment(content)
      PI(target~, data~) => PI(target~, data~)
      Decl(version~, encoding~, standalone~) =>
        Decl(version~, encoding~, standalone~)
      DocType(name) => DocType(name)
      Eof => Eof
    }
  } catch {
    error => raise At(error~, span=event.span)
  }
  { kind, span: event.span }
}

///|
/// Read all namespace-aware events through the final `Eof` event.
pub fn NamespaceReader::read_events_until_eof(
  self : NamespaceReader,
) -> Array[NamespaceEvent] raise XmlError {
  let events : Array[NamespaceEvent] = []
  for ;; {
    let event = self.read_event()
    events.push(event)
    if event.kind is Eof {
      return events
    }
  }
}
