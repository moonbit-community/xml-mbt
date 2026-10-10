///|
fn assert_rejected_document(input : String) -> Unit raise {
  try @xml.Reader::from_string(input).read_events_until_eof() catch {
    @xml.XmlError::At(_) => ()
  } noraise {
    _ => fail("expected malformed XML to be rejected: " + input)
  }
}

///|
test "audit/source spans after nested DTD groups" {
  let input = "<!DOCTYPE root [<!ELEMENT root ((a,b))>]><root><a/><b/></root>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  let expected = [
    "<!DOCTYPE root [<!ELEMENT root ((a,b))>]>", "<root>", "<a/>", "<b/>", "</root>",
    "",
  ]
  for i, event in events {
    assert_eq(
      input[event.span.start.offset:event.span.end.offset].to_owned(),
      expected[i],
    )
    assert_eq(event.span.start.column, event.span.start.offset + 1)
    assert_eq(event.span.end.column, event.span.end.offset + 1)
  }
}

///|
test "audit/reject malformed XML declarations" {
  for
    input in [
      "<?xml?><root/>", "<?xml version='1.0' <root/>", "<?xml version='1.0'?><?xml version='1.0'?><root/>",
      "\u{FEFF}<?xml version='1.0'?><?xml version='1.0'?><root/>",
    ] {
    assert_rejected_document(input)
  }
}

///|
test "audit/preserve XML declaration after a BOM" {
  let input = "\u{FEFF}<?xml version='1.0' encoding='UTF-8' standalone='yes'?><root/>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  assert_eq(
    events[0].kind,
    @xml.EventKind::Decl(
      version="1.0",
      encoding=Some("UTF-8"),
      standalone=Some("yes"),
    ),
  )
  assert_eq(events[0].span.start.offset, 1)
}

///|
test "audit/normalize literal line endings in attributes" {
  for newline in ["\r", "\r\n", "\n"] {
    let input = "<root a='x" + newline + "y'/>"
    let event = @xml.Reader::from_string(input).read_event()
    guard event.kind is Empty(element) else { fail("expected empty element") }
    assert_eq(element.get("a"), Some("x y"))
    assert_eq(event.span.end.offset, input.length())
    let span = element.attributes[0].value_span
    assert_eq(
      input[span.start.offset:span.end.offset].to_owned(),
      "x" + newline + "y",
    )
  }
}

///|
test "audit/normalize literal line endings in CDATA comments and PI" {
  for newline in ["\r", "\r\n", "\n"] {
    let input = "<root><![CDATA[x" +
      newline +
      "y]]><!--x" +
      newline +
      "y--><?p x" +
      newline +
      "y?></root>"
    let events = @xml.Reader::from_string(input).read_events_until_eof()
    assert_eq(events[1].kind, @xml.EventKind::CData("x\ny"))
    assert_eq(events[2].kind, @xml.EventKind::Comment("x\ny"))
    assert_eq(events[3].kind, @xml.EventKind::PI(target="p", data="x\ny"))
  }
}

///|
test "audit/preserve character references during attribute normalization" {
  let input = "<!DOCTYPE root [<!ATTLIST root a NMTOKENS #IMPLIED>]><root a=' x&#9;y&#10;z&#13;q '/>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  guard events[1].kind is Empty(element) else { fail("expected empty element") }
  assert_eq(element.get("a"), Some("x\ty\nz\rq"))
}

///|
test "audit/reject literal markup introduced by attribute entities" {
  for
    declaration in [
      "<!ENTITY e '<child/>'>", "<!ENTITY e '&#60;'>", "<!ENTITY nested '<child/>'><!ENTITY e '&nested;'>",
    ] {
    assert_rejected_document(
      "<!DOCTYPE root [" + declaration + "]><root a='&e;'/>",
    )
  }
}

///|
test "audit/allow escaped markup and preserve character references in attribute entities" {
  let input = "<!DOCTYPE root [<!ENTITY e '&lt;&#38;#9;'>]><root a='&e;'/>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  guard events[1].kind is Empty(element) else { fail("expected empty element") }
  assert_eq(element.get("a"), Some("<\t"))
}

///|
test "audit/do not expand entity references inside replacement comments or PI" {
  for
    (value, expected) in [
      ("<!-- &missing; --><?p &missing;?>", "&missing;"),
      ("<!-- &#38; --><?p &#38;?>", "&"),
      ("&#60;!-- &#38; -->&#60;?p &#38;?>", "&"),
    ] {
    let input = "<!DOCTYPE root [<!ENTITY e '" + value + "'>]><root>&e;</root>"
    let events = @xml.Reader::from_string(input).read_events_until_eof()
    assert_eq(events[2].kind, @xml.EventKind::Comment(" " + expected + " "))
    assert_eq(events[3].kind, @xml.EventKind::PI(target="p", data=expected))
  }
}

///|
test "audit/inherit DTD attribute types in entity content" {
  let input = "<!DOCTYPE root [<!ATTLIST child a NMTOKENS #IMPLIED><!ENTITY e '<child a=\" x   y \"/>'>]><root>&e;</root>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  guard events[2].kind is Empty(element) else { fail("expected empty element") }
  assert_eq(element.get("a"), Some("x y"))
}

///|
test "audit/normalize entity literals before expanding character references" {
  let input = "<!DOCTYPE root [<!ENTITY literal 'x\r\ny'><!ENTITY reference '&#13;'>]><root>&literal;&reference;</root>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  assert_eq(events[2].kind, @xml.EventKind::Text("x\ny"))
  assert_eq(events[3].kind, @xml.EventKind::Text("\r"))
}

///|
test "audit/accept nested DTD content model connectors and occurrences" {
  for model in ["((a,b)|(c,d))", "(a,(b|c)*)", "((a,b)?,c)", "(a)"] {
    let input = "<!DOCTYPE root [<!ELEMENT root " + model + ">]><root/>"
    let _ = @xml.Reader::from_string(input).read_events_until_eof()
  }
}

///|
test "audit/reject malformed internal DTD grammar" {
  for
    subset in [
      "garbage", "<!BOGUS foo>", "<!ENTITY e UNKNOWN>", "<!ENTITY e SYSTEM>", "<!ENTITY e SYSTEM'file'>",
      "<!ENTITY e 'hi' garbage>", "<!ENTITY e 'hi'><!ENTITY e '&#0;'>", "<!NOTATION n>",
      "<!ENTITY e '%'>", "<!ENTITY % p '&#0;'>", "<!ENTITY % p '&#xZZ;'>", "<!ENTITY % p '&bad name;'>",
      "<!ELEMENT root (a,)>", "<!ELEMENT root (,a)>", "<!ELEMENT root (a,,b)>", "<!ELEMENT root (a|b,c)>",
      "<!ATTLISTroot a CDATA #IMPLIED>",
    ] {
    assert_rejected_document("<!DOCTYPE root [" + subset + "]><root/>")
  }
}

///|
test "audit/supply DTD defaults with authored spans and explicit overrides" {
  let input = "<!DOCTYPE root [<!ATTLIST root a CDATA 'default' b NMTOKENS ' x   y ' c CDATA #FIXED 'fixed'>]><root a='explicit'/>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  guard events[1].kind is Empty(element) else { fail("expected empty element") }
  assert_eq(element.get("a"), Some("explicit"))
  assert_eq(element.get("b"), Some("x y"))
  assert_eq(element.get("c"), Some("fixed"))
  let attribute = element.attributes[1]
  assert_eq(
    input[attribute.name_span.start.offset:attribute.name_span.end.offset].to_owned(),
    "b",
  )
  assert_eq(
    input[attribute.value_span.start.offset:attribute.value_span.end.offset].to_owned(),
    " x   y ",
  )
}

///|
test "audit/default attributes respect the first declaration" {
  let input = "<!DOCTYPE root [<!ATTLIST root a CDATA #IMPLIED b CDATA 'first'><!ATTLIST root a CDATA 'ignored' b CDATA 'second'>]><root/>"
  let events = @xml.Reader::from_string(input).read_events_until_eof()
  guard events[1].kind is Empty(element) else { fail("expected empty element") }
  assert_eq(element.get("a"), None)
  assert_eq(element.get("b"), Some("first"))
}

///|
test "audit/inherit DTD defaults in entity content and namespace resolution" {
  let input = "<!DOCTYPE root [<!ATTLIST child a CDATA 'default' xmlns CDATA 'urn:child'><!ENTITY e '<child/>'>]><root>&e;</root>"
  let events = @xml.NamespaceReader::from_string(input).read_events_until_eof()
  guard events[2].kind is Empty(element) else { fail("expected empty element") }
  assert_eq(element.name.namespace_uri, Some("urn:child"))
  assert_eq(element.attributes[0].value, "default")
}

///|
test "audit/emit DTD comments and PI without requiring following whitespace" {
  for whitespace in ["", "\n"] {
    let input = "<!DOCTYPE root [<!--note--><?p x?>]>" + whitespace + "<root/>"
    let events = @xml.Reader::from_string(input).read_events_until_eof()
    assert_eq(
      events
      .filter(fn(event) { event.kind is Comment(_) })
      .map(fn(event) { event.kind }),
      [@xml.EventKind::Comment("note")],
    )
    assert_eq(
      events
      .filter(fn(event) { event.kind is PI(_) })
      .map(fn(event) { event.kind }),
      [@xml.EventKind::PI(target="p", data="x")],
    )
  }
}

///|
test "audit/Writer preserves carriage returns in text" {
  for value in ["x\ry", "x\r\ny", "\r", "x&#13;y"] {
    let writer = @xml.Writer::new()
    writer.start_element("root", [])
    writer.text(value)
    writer.end_element("root")
    let events = @xml.Reader::from_string(writer.to_string()).read_events_until_eof()
    let text = events
      .filter(fn(event) { event.kind is Text(_) })
      .map(fn(event) {
        match event.kind {
          Text(value) => value
          _ => ""
        }
      })
      .join("")
    assert_eq(text, value)
  }
}
