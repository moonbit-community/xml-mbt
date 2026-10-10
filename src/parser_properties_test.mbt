///|
fn generated_xml_text(values : Array[Int]) -> String {
  let palette = [
    'a', ' ', '<', '>', '&', '\'', '"', '\t', '\r', '\n', '中', '😀',
  ]
  let result = StringBuilder()
  for value in values {
    result.write_char(
      palette[(value.reinterpret_as_uint() %
      palette.length().reinterpret_as_uint()).reinterpret_as_int()],
    )
  }
  result.to_string()
}

///|
fn assert_source_span(input : String, span : @xml.SourceSpan) -> Unit raise {
  assert_true(span.start.offset >= 0)
  assert_true(span.start.offset <= span.end.offset)
  assert_true(span.end.offset <= input.length())
  assert_true(span.start.line > 0 && span.start.column > 0)
  assert_true(span.end.line > 0 && span.end.column > 0)
  let _ = input[span.start.offset:span.end.offset]
}

///|
fn assert_event_spans(input : String, events : Array[@xml.Event]) -> Unit raise {
  assert_eq(events.last().unwrap().kind, @xml.EventKind::Eof)
  for event in events {
    assert_source_span(input, event.span)
    match event.kind {
      Start(element) | Empty(element) =>
        for attribute in element.attributes {
          assert_source_span(input, attribute.span)
          assert_source_span(input, attribute.name_span)
          assert_source_span(input, attribute.value_span)
        }
      _ => ()
    }
  }
}

///|
test "property/Writer preserves generated Unicode text and attributes" {
  @quickcheck.check(
    fn(values : Array[Int]) -> Bool raise {
      let value = generated_xml_text(values)
      let writer = @xml.Writer::new()
      writer.start_element("root", [("value", value)])
      writer.text(value)
      writer.end_element("root")
      let input = writer.to_string()
      let events = @xml.Reader::from_string(input).read_events_until_eof()
      assert_event_spans(input, events)
      guard events[0].kind is Start(element) else {
        fail("expected root start")
      }
      assert_eq(element.get("value"), Some(value))
      let text = StringBuilder()
      for event in events {
        if event.kind is Text(value) {
          text.write_string(value)
        }
      }
      assert_eq(text.to_string(), value)
      true
    },
    count=512,
    max_size=128,
    seed=0x584D4C01,
  )
}

///|
test "property/internal entities preserve escaped text and authored reference spans" {
  @quickcheck.check(
    fn(values : Array[Int]) -> Bool raise {
      let value = generated_xml_text(values)
      // Keep escapes until replacement content is parsed, as XML entity values require.
      let replacement = @xml.escape(value).replace(old="&#13;", new="&#38;#13;")
      let input = "<!DOCTYPE root [<!ENTITY e '" +
        replacement +
        "'>]><root>&e;</root>"
      let events = @xml.Reader::from_string(input).read_events_until_eof()
      assert_event_spans(input, events)
      if value == "" {
        assert_eq(events[2].kind, @xml.EventKind::End("root"))
      } else {
        assert_eq(events[2].kind, @xml.EventKind::Text(value))
        assert_eq(
          input[events[2].span.start.offset:events[2].span.end.offset],
          "&e;",
        )
      }
      true
    },
    count=512,
    max_size=128,
    seed=0x584D4C02,
  )
}

///|
test "property/namespace rebinding restores every enclosing scope" {
  @quickcheck.check(
    fn(values : Array[Int]) -> Bool raise {
      let input = StringBuilder()
      input.write_string("<root xmlns:p='urn:root'>")
      for value in values {
        input.write_string(
          "<p:node xmlns:p='urn:\{value}'><p:empty xmlns:p='urn:empty'/><p:sibling/>",
        )
      }
      input.write_string("</p:node>".repeat(values.length()))
      input.write_string("<p:last/></root>")
      let reader = @xml.NamespaceReader::from_string(input.to_string())
      guard reader.read_event().kind is Start(_) else { fail("expected root") }
      for value in values {
        guard reader.read_event().kind is Start(element) else {
          fail("expected node")
        }
        assert_eq(element.name.namespace_uri, Some("urn:\{value}"))
        guard reader.read_event().kind is Empty(empty) else {
          fail("expected empty")
        }
        assert_eq(empty.name.namespace_uri, Some("urn:empty"))
        guard reader.read_event().kind is Empty(sibling) else {
          fail("expected sibling")
        }
        assert_eq(sibling.name.namespace_uri, Some("urn:\{value}"))
      }
      for i = values.length() - 1; i >= 0; i = i - 1 {
        guard reader.read_event().kind is End(name) else {
          fail("expected node end")
        }
        assert_eq(name.namespace_uri, Some("urn:\{values[i]}"))
      }
      guard reader.read_event().kind is Empty(last) else {
        fail("expected last sibling")
      }
      assert_eq(last.name.namespace_uri, Some("urn:root"))
      guard reader.read_event().kind is End(_) else {
        fail("expected root end")
      }
      assert_eq(reader.read_event().kind, @xml.NamespaceEventKind::Eof)
      true
    },
    count=256,
    max_size=64,
    seed=0x584D4C03,
  )
}

///|
test "fuzz/deterministic syntax mutations never panic and retain valid spans" {
  let corpus = [
    "<root/>", "\u{FEFF}<?xml version='1.0'?><root a='😀&amp;中'>x&#13;y</root>",
    "<!DOCTYPE root [<!ENTITY e '<child/>'><!ATTLIST child a CDATA 'default'>]><root>&e;</root>",
    "<!DOCTYPE root [<!ELEMENT root ((a,b)|(c,d))><!--note--><?p data?>]><root/>",
    "<root xmlns:p='urn:p'><p:child p:a='x'/><![CDATA[&<]]><!--note--><?p x?></root>",
  ]
  let palette = [
    '<', '>', '&', ';', '/', '!', '?', '\'', '"', '[', ']', '=', '%', ':', ' ', '\r',
    '\n', '\u{0}', '😀',
  ]
  let mutations : Array[Array[Int]] = @quickcheck.spawn().samples(
    count=3000,
    size=32,
    seed=0x584D4C04,
  )
  for index, mutation in mutations {
    let input = corpus[index % corpus.length()].to_array()
    for value in mutation {
      let bits = value.reinterpret_as_uint()
      let position = (bits % (input.length() + 1).reinterpret_as_uint()).reinterpret_as_int()
      let c = palette[((bits >> 8) % palette.length().reinterpret_as_uint()).reinterpret_as_int()]
      match (bits >> 16) % 3 {
        0 => input.insert(position, c)
        1 => if position < input.length() { let _ = input.remove(position) }
        _ => if position < input.length() { input[position] = c }
      }
    }
    let text = String::from_array(input)
    try @xml.Reader::from_string(text).read_events_until_eof() catch {
      At(span~, ..) => assert_source_span(text, span)
    } noraise {
      events => assert_event_spans(text, events)
    }
    try @xml.NamespaceReader::from_string(text).read_events_until_eof() catch {
      At(span~, ..) => assert_source_span(text, span)
    } noraise {
      events =>
        for event in events {
          assert_source_span(text, event.span)
        }
    }
  }
}

///|
test "regression/raw events retain namespace spellings CDATA and text boundaries" {
  let input = "\u{FEFF}<?xml version='1.0'?>\n<p:root xmlns:p='urn:p' p:a='x'>a&amp;b<![CDATA[c]]><?p  data?><p:child></p:child></p:root>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  assert_event_spans(input, events)
  guard events[1].kind is Start(element) else { fail("expected root start") }
  assert_eq(element.name, "p:root")
  assert_eq(element.attributes.map(fn(a) { (a.name, a.value) }), [
    ("xmlns:p", "urn:p"),
    ("p:a", "x"),
  ])
  assert_eq(
    events[0].kind,
    @xml.EventKind::Decl(version="1.0", encoding=None, standalone=None),
  )
  assert_eq(events[2].kind, @xml.EventKind::Text("a"))
  assert_eq(events[3].kind, @xml.EventKind::Text("&"))
  assert_eq(events[4].kind, @xml.EventKind::Text("b"))
  assert_eq(events[5].kind, @xml.EventKind::CData("c"))
  assert_eq(events[6].kind, @xml.EventKind::PI(target="p", data=" data"))
  guard events[7].kind is Start(child) else {
    fail("expected explicit child start")
  }
  assert_eq(child.name, "p:child")
  assert_eq(events[8].kind, @xml.EventKind::End("p:child"))
  assert_eq(events[9].kind, @xml.EventKind::End("p:root"))
  assert_eq(events.length(), 11)
}

///|
test "regression/entity recursion crosses content and attribute contexts" {
  let input = "<!DOCTYPE root [<!ENTITY e '<child a=\"&e;\"/>'>]><root>&e;</root>"
  try @xml.Reader::from_string(input).read_events_until_eof() catch {
    At(error=InvalidEntity(message), span~) => {
      assert_eq(message, "recursive entity reference: &e;")
      assert_eq(input[span.start.offset:span.end.offset], "&e;")
    }
    _ => fail("expected a recursive entity error")
  } noraise {
    _ => fail("expected recursive entity to raise")
  }
}

///|
test "regression/replacement markup and attribute entities share one output budget" {
  for extra in [0, 1] {
    // The markup contributes 13 literal characters, excluding &value; spelling.
    let value = "x".repeat(262_144 - 13 + extra)
    let input = "<!DOCTYPE root [<!ENTITY value '" +
      value +
      "'><!ENTITY e '<child a=\"&value;\"/>'>]><root>&e;</root>"
    try @xml.Reader::from_string(input).read_events_until_eof() catch {
      At(error=InvalidEntity(message), span~) => {
        assert_eq(extra, 1)
        assert_eq(message, "entity expansion limit exceeded")
        assert_eq(input[span.start.offset:span.end.offset], "&e;")
      }
      _ => fail("expected entity output budget error")
    } noraise {
      events => {
        assert_eq(extra, 0)
        guard events[2].kind is Empty(child) else { fail("expected child") }
        assert_eq(child.get("a"), Some(value))
      }
    }
  }
}

///|
test "regression/nested entity content inherits DTD attribute defaults and types" {
  let input = "<!DOCTYPE root [<!ENTITY value ' x  y '><!ENTITY child '<child/>'><!ENTITY outer '&child;&child;'><!ATTLIST child tokens NMTOKENS '&value;'>]><root>&outer;</root>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  assert_event_spans(input, events)
  for index in [2, 3] {
    guard events[index].kind is Empty(child) else { fail("expected child") }
    assert_eq(child.get("tokens"), Some("x y"))
    assert_eq(
      input[events[index].span.start.offset:events[index].span.end.offset],
      "&outer;",
    )
  }
}

///|
test "regression/large pending batches retain order and reset between text segments" {
  let input = "<root>" +
    "&#65;&#66;".repeat(2048) +
    "<child/>" +
    "&#67;&#68;".repeat(2048) +
    "</root>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  assert_event_spans(input, events)
  assert_eq(events.length(), 8196)
  for index in 0..<4096 {
    assert_eq(
      events[index + 1].kind,
      @xml.EventKind::Text(if index % 2 == 0 { "A" } else { "B" }),
    )
    assert_eq(
      events[index + 4098].kind,
      @xml.EventKind::Text(if index % 2 == 0 { "C" } else { "D" }),
    )
  }
}

///|
test "regression/namespace NCName rules preserve raw XML Names and reach replacement content" {
  let inputs = [
    "<?p:t data?><root/>", "<!DOCTYPE root [<!ENTITY e:f 'x'>]><root/>", "<!DOCTYPE root [<!ENTITY e '&unknown:name;'>]><root/>",
    "<!DOCTYPE root [<!NOTATION n:t SYSTEM 'notation'>]><root/>", "<!DOCTYPE root [<!ENTITY e SYSTEM 'external' NDATA n:t>]><root/>",
    "<!DOCTYPE root [<!ENTITY e '<?p:t?>'>]><root>&e;</root>",
  ]
  for input in inputs {
    assert_event_spans(
      input,
      @xml.Reader::from_string(input).read_events_until_eof(),
    )
    try @xml.NamespaceReader::from_string(input).read_events_until_eof() catch {
      At(span~, ..) => assert_source_span(input, span)
    } noraise {
      _ => fail("expected namespace NCName violation")
    }
  }
}
