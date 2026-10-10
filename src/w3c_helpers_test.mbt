// W3C Second Canonical Form: xmlconf/sun/cxml.html.
// This adapter preserves qualified names, namespace declarations, attribute
// values and non-separator PI data. Raw event boundaries and source spans
// have separate tests.

///|
fn w3c_data(buffer : StringBuilder, value : String) -> Unit {
  for c in value {
    match c {
      '&' => buffer.write_string("&amp;")
      '<' => buffer.write_string("&lt;")
      '>' => buffer.write_string("&gt;")
      '"' => buffer.write_string("&quot;")
      '\t' => buffer.write_string("&#9;")
      '\n' => buffer.write_string("&#10;")
      '\r' => buffer.write_string("&#13;")
      _ => buffer.write_char(c)
    }
  }
}

///|
fn w3c_name_compare(a : String, b : String) -> Int {
  let a = a.to_array()
  let b = b.to_array()
  for i in 0..<a.length().min(b.length()) {
    let order = a[i].compare(b[i])
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
fn w3c_start(buffer : StringBuilder, element : @xml.XmlElement) -> Unit {
  buffer.write_string("<" + element.name)
  let attributes = element.attributes.copy()
  attributes.sort_by(fn(a, b) { w3c_name_compare(a.name, b.name) })
  for attribute in attributes {
    buffer.write_string(" " + attribute.name + "=\"")
    w3c_data(buffer, attribute.value)
    buffer.write_string("\"")
  }
  buffer.write_string(">")
}

///|
fn w3c_canonical(events : Array[@xml.Event]) -> String {
  let buffer = StringBuilder()
  let mut depth = 0
  for event in events {
    match event.kind {
      Start(element) => {
        w3c_start(buffer, element)
        depth += 1
      }
      Empty(element) => {
        w3c_start(buffer, element)
        buffer.write_string("</" + element.name + ">")
      }
      End(name) => {
        depth -= 1
        buffer.write_string("</" + name + ">")
      }
      Text(value) | CData(value) => if depth > 0 { w3c_data(buffer, value) }
      PI(target~, data~) => {
        buffer.write_string("<?" + target + " ")
        let mut separator = true
        for c in data {
          if separator && (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            continue
          }
          separator = false
          buffer.write_char(c)
        }
        buffer.write_string("?>")
      }
      Comment(_) | Decl(_) | DocType(_) | Eof => ()
    }
  }
  buffer.to_string()
}

///|
fn w3c_accept(
  source : String,
  namespaces~ : Bool,
  expected? : String,
) -> Unit raise {
  if namespaces {
    let _ = @xml.NamespaceReader::from_string(source).read_events_until_eof()
  }
  let events = @xml.Reader::from_string(source).read_events_until_eof()
  if expected is Some(value) {
    @debug.assert_eq(w3c_canonical(events), value)
  }
}

///|
fn w3c_reject(source : String, namespaces~ : Bool) -> Unit raise {
  try {
    if namespaces {
      let _ = @xml.NamespaceReader::from_string(source).read_events_until_eof()
    } else {
      let _ = @xml.Reader::from_string(source).read_events_until_eof()
    }
  } catch {
    @xml.XmlError::At(_) => ()
  } noraise {
    _ => fail("expected malformed XML to raise")
  }
}

///|
test "W3C canonical adapter preserves names, values and Unicode ordering" {
  let source = "<p:r xmlns:p=\"urn:p\" z=\"&#13;\" aa=\"&#9;&amp;\" \u{10000}=\"astral\" \u{f900}=\"bmp\"><![CDATA[<&]]><?pi   x  ?></p:r>"
  let events = @xml.Reader::from_string(source).read_events_until_eof()
  @debug.assert_eq(
    w3c_canonical(events),
    "<p:r aa=\"&#9;&amp;\" xmlns:p=\"urn:p\" z=\"&#13;\" \u{f900}=\"bmp\" \u{10000}=\"astral\">&lt;&amp;<?pi x  ?></p:r>",
  )
}
