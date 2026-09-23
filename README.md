# xml

A document-buffered pull XML parser for MoonBit, inspired by [quick-xml](https://github.com/tafia/quick-xml).

## Features

- **Pull-parser model** - Read XML events one at a time (like StAX in Java)
- **Document-buffered input** - Constructors load the full input, then callers pull events one at a time
- **Multi-backend** - Works on wasm, wasm-gc, js, and native
- **XML 1.0 + Namespaces 1.0** - Unicode names plus namespace-aware events
- **Source-aware parsing** - Authored ranges for events and attributes, plus contextual spans for errors

## Usage

```moonbit
let xml = "<root><item id=\"1\">Hello</item></root>"
let reader = @xml.Reader::from_string(xml)

while true {
  let event = reader.read_event()
  match event.kind {
    Start(elem) => println("Start: \{elem.name}")
    End(name) => println("End: \{name}")
    Text(content) => println("Text: \{content}")
    Eof => break
    _ => continue
  }
}
```

Callers obtain XML text from files, network responses, or other sources before passing it to `Reader::from_string` or `NamespaceReader::from_string`.

### Namespace-aware parsing

Use `NamespaceReader` when callers need namespace URI, prefix, and local-name information. The original `Reader` remains available for raw qualified names and namespace declaration attributes.

```moonbit
let reader = @xml.NamespaceReader::from_string(
  "<p:root xmlns:p=\"urn:example\" p:id=\"1\"/>",
)

match reader.read_event().kind {
  Empty(element) => {
    println(element.name.local_name) // root
    println(element.name.namespace_uri) // Some("urn:example")
  }
  _ => ()
}
```

Namespace declarations are exposed through `NamespaceElement::namespace_declarations` and are not included in its normal attributes. Default namespaces apply to element names but not to unprefixed attribute names.

### Checked writing

`Writer` validates XML names, characters, delimiter sequences, and document structure as output is added. Its write methods and `to_string` raise `WriterError` instead of returning malformed XML; `to_string` also requires exactly one complete root element.

### Source locations

Every event returned by `Reader::read_event` includes its authored source range. Event and attribute spans are half-open; offsets count UTF-16 code units, so they can slice the original MoonBit `String` directly.

```moonbit
let input = "<root id='a&amp;b'/>"
let reader = @xml.Reader::from_string(input)
let parsed = reader.read_event()
let authored = input[parsed.span.start.offset:parsed.span.end.offset]
assert_eq(authored, input)
guard parsed.kind is Empty(element) else { abort("expected empty element") }
assert_eq(element.attributes[0].value, "a&b")
```

Each `XmlAttribute` contains the whole attribute span plus separate name and unquoted value spans. Parse failures raise `XmlError::At`, which contains an `XmlErrorKind` and a relevant authored source span. Syntax failures normally cover input consumed while detecting the error, while an unclosed-element error points to the unmatched opening tag. Events produced by entity expansion point to the authored entity reference.

## Event Types

`Event` contains an `EventKind` and a `SourceSpan`. The `EventKind` variants are:

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
- **Bounded entity expansion** - Internal entities are limited to 32 nesting levels and 262,144 expanded characters per document

External entity declarations are parsed, but their contents are not resolved. Referencing an external entity raises an error.

## License

Apache-2.0
