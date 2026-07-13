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
/// Transform attributes to match lxml behavior:
/// - Filter out xmlns namespace declarations
/// - Strip namespace prefixes (a:attr -> attr)
fn transform_attrs_for_libxml(
  attrs : Array[XmlAttribute],
) -> Array[XmlAttribute] {
  let result : Array[XmlAttribute] = []
  for attr in attrs {
    let name = attr.name
    if name == "xmlns" || name.has_prefix("xmlns:") {
      continue
    }
    let final_name = match name.find(":") {
      Some(idx) => name[idx + 1:].to_owned()
      None => name
    }
    result.push({
      name: final_name,
      value: attr.value,
      span: attr.span,
      name_span: attr.name_span,
      value_span: attr.value_span,
    })
  }
  result
}

///|
fn strip_ns_prefix(name : String) -> String {
  match name.find(":") {
    Some(idx) => name[idx + 1:].to_owned()
    None => name
  }
}

///|
fn push_coalesced(result : Array[EventKind], event : EventKind) -> Unit {
  match event {
    Text(s) => {
      let n = result.length()
      if n > 0 {
        match result[n - 1] {
          Text(prev) => {
            result[n - 1] = Text(prev + s)
            return
          }
          _ => ()
        }
      }
      result.push(Text(s))
    }
    _ => result.push(event)
  }
}

///|
/// Convert events to libxml2/lxml format for conformance testing.
fn to_libxml_format(events : Array[Event]) -> Array[EventKind] {
  let result : Array[EventKind] = []
  let mut first_element_idx = 0
  for i, event in events {
    match event.kind {
      Start(_) | Empty(_) => {
        first_element_idx = i
        break
      }
      _ => ()
    }
  }
  let mut decl_event : EventKind? = None
  let mut doctype_event : EventKind? = None
  let prolog_others : Array[EventKind] = []
  for i = 0; i < first_element_idx; i = i + 1 {
    match events[i].kind {
      Decl(version~, encoding~, standalone~) => {
        let enc = match encoding {
          Some(e) => Some(e)
          None => Some("UTF-8")
        }
        let std = match standalone {
          Some(s) => Some(s)
          None => Some("no")
        }
        decl_event = Some(Decl(version~, encoding=enc, standalone=std))
      }
      DocType(name) => doctype_event = Some(DocType(strip_ns_prefix(name)))
      Text(_) => ()
      PI(target~, data~) =>
        prolog_others.push(PI(target~, data=data.trim_start().to_owned()))
      other => prolog_others.push(other)
    }
  }
  match decl_event {
    Some(e) => result.push(e)
    None => ()
  }
  match doctype_event {
    Some(e) => result.push(e)
    None => ()
  }
  for e in prolog_others {
    result.push(e)
  }
  let len = events.length()
  let mut i = first_element_idx
  while i < len {
    let event = events[i].kind
    match event {
      Start(elem) => {
        let filtered_elem : XmlElement = {
          name: strip_ns_prefix(elem.name),
          attributes: transform_attrs_for_libxml(elem.attributes),
        }
        if i + 1 < len {
          match events[i + 1].kind {
            End(name) =>
              if name == elem.name {
                push_coalesced(result, Empty(filtered_elem))
                i += 2
                continue
              }
            _ => ()
          }
        }
        push_coalesced(result, Start(filtered_elem))
      }
      Empty(elem) => {
        let filtered_elem : XmlElement = {
          name: strip_ns_prefix(elem.name),
          attributes: transform_attrs_for_libxml(elem.attributes),
        }
        push_coalesced(result, Empty(filtered_elem))
      }
      End(name) => push_coalesced(result, End(strip_ns_prefix(name)))
      DocType(name) => push_coalesced(result, DocType(strip_ns_prefix(name)))
      PI(target~, data~) =>
        push_coalesced(result, PI(target~, data=data.trim_start().to_owned()))
      CData(content) => push_coalesced(result, Text(content))
      _ => push_coalesced(result, event)
    }
    i += 1
  }
  result
}
