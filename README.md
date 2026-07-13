# xml

A streaming XML parser for MoonBit, inspired by [quick-xml](https://github.com/tafia/quick-xml).

## Features

- **Pull-parser model** - Read XML events one at a time (like StAX in Java)
- **Streaming** - Memory-efficient processing of large documents
- **Multi-backend** - Works on wasm, wasm-gc, js, and native
- **XML 1.0 + Namespaces 1.0** - Unicode names plus namespace-aware events
- **Source-aware parsing** - Exact ranges for events, attributes, and errors

## Usage

```moonbit
// From string
let xml = "<root><item id=\"1\">Hello</item></root>"
let reader = @xml.Reader::from_string(xml)

// From file (resolves external entities)
let reader = @xml.Reader::from_file("document.xml")

while true {
  let event = reader.read_event()
  match event {
    Start(elem) => println("Start: \{elem.name}")
    End(name) => println("End: \{name}")
    Text(content) => println("Text: \{content}")
    Eof => break
    _ => continue
  }
}
```

### Namespace-aware parsing

Use `NamespaceReader` when callers need namespace URI, prefix, and local-name information. The original `Reader` remains available for raw qualified names and namespace declaration attributes.

```moonbit
let reader = @xml.NamespaceReader::from_string(
  "<p:root xmlns:p=\"urn:example\" p:id=\"1\"/>",
)

match reader.read_event() {
  Empty(element) => {
    println(element.name.local_name) // root
    println(element.name.namespace_uri) // Some("urn:example")
  }
  _ => ()
}
```

Namespace declarations are exposed through `NamespaceElement::namespace_declarations` and are not included in its normal attributes. Default namespaces apply to element names but not to unprefixed attribute names.

### Source locations

Use `Reader::read_spanned_event` when parsed values must map back to their authored source. Event and attribute spans are half-open; offsets count UTF-16 code units, so they can slice the original MoonBit `String` directly.

```moonbit
let input = "<root id='a&amp;b'/>"
let reader = @xml.Reader::from_string(input)
let parsed = reader.read_spanned_event()
let authored = input[parsed.span.start.offset:parsed.span.end.offset]
assert_eq(authored, input)
assert_eq(parsed.attributes[0].value, "a&b")
```

Each `SpannedAttribute` contains the whole attribute span plus separate name and unquoted value spans. `read_spanned_event` raises `LocatedXmlError`, which preserves the original `XmlError` and the position where parsing detected it. Events produced by entity expansion point to the authored entity reference.

## Event Types

| Event | Description |
|-------|-------------|
| `Start(XmlElement)` | Opening tag `<name>` |
| `End(String)` | Closing tag `</name>` |
| `Empty(XmlElement)` | Self-closing tag `<name/>` |
| `Text(String)` | Text content (entities decoded) |
| `CData(String)` | CDATA section `<![CDATA[...]]>` |
| `Comment(String)` | Comment `<!-- ... -->` |
| `PI(target, data)` | Processing instruction `<?target data?>` |
| `Decl(version, encoding, standalone)` | XML declaration |
| `DocType(String)` | DOCTYPE declaration |
| `Eof` | End of document |

## W3C Conformance

This library is tested against the [W3C XML Conformance Test Suite](https://www.w3.org/XML/Test/), using libxml2 (lxml) as the reference parser.

**Current status: 817/817 tests passing**

| Category | Tests | Description |
|----------|-------|-------------|
| Valid (with events) | 448 | Parser produces correct event sequence |
| Valid (error-only) | 6 | Parser does not error on valid XML |
| Not-well-formed | 281 | Parser correctly rejects malformed XML |
| Unit tests | 82 | Reader, writer, escape, namespace, source spans, conformance tests |

Coverage:
- XML 1.0 (James Clark xmltest)
- XML 1.0 Errata 2nd/3rd/4th edition
- Namespaces 1.0
- Sun Microsystems tests
- IBM XML 1.0 tests

### Running Conformance Tests

```bash
# Download the W3C test suite
curl -L -o xmlts.tar.gz "https://www.w3.org/XML/Test/xmlts20130923.tar.gz"
tar -xzf xmlts.tar.gz && mv xmlconf . && rm xmlts.tar.gz

# Run tests
moon test
```

### Regenerating Tests

```bash
# Requires: libxml2 (xmllint), lxml (pip install lxml)
python3 scripts/generate_conformance_tests.py
```

### Excluded Tests

The following test categories are skipped:
- External entity references (require file I/O)
- XML 1.1 documents (we only support XML 1.0)
- DTD validation tests (`invalid` type)

## Limitations

- **Non-validating** - Does not validate against DTD
- **UTF-8 only** - Other encodings not supported
- **XML 1.0 only** - XML 1.1 not supported

Note: External entities (`SYSTEM`) are resolved when using `Reader::from_file()`.

## License

Apache-2.0
