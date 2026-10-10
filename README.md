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

Each `XmlAttribute` contains the whole attribute span plus separate name and unquoted value spans. Parse failures raise `XmlError::At`, which contains an `XmlErrorKind` and a relevant authored source span. Syntax failures normally cover input consumed while detecting the error, while an unclosed-element error points to the unmatched opening tag. Events produced by entity expansion point to the authored entity reference. Defaulted attributes point to their definitions in the internal DTD subset.

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

This library is tested against the [W3C XML Conformance Test Suite](https://www.w3.org/XML/Test/), using libxml2 (lxml) and Expat as reference parsers.

**Current status: 897/897 tests passing on wasm, wasm-gc, js, and native**

| Category | Tests | Description |
|----------|-------|-------------|
| Valid (with events) | 454 | Parser produces the reference event sequence |
| Not-well-formed | 291 | Reader or NamespaceReader rejects malformed XML |
| Unit tests | 152 | Reader, writer, escape, namespaces, source spans, properties, mutation fuzzing |

The W3C comparisons normalize reference-parser differences such as text callback boundaries, CDATA, empty elements, and namespace spellings. Separate raw-event regressions and public-API properties check those details directly. Every valid W3C fixture checks events; reference failures stop generation, and malformed fixtures follow the applicable W3C classification rather than reference-parser acceptance.

The property tests run 1,280 generated cases with fixed seeds. Mutation fuzzing runs 3,000 mutated inputs through both readers, checking source ranges on accepted documents and errors and failing on panics. CI also runs 12 Python checks, including independent reference verification of all 454 valid expectations.

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
tar -xzf xmlts.tar.gz
rm xmlts.tar.gz

# Run tests
moon test --target all --deny-warn
```

### Regenerating Tests

```bash
python3 -m pip install -r scripts/requirements.txt
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/generate_conformance_tests.py
```

### Excluded Tests

The following test categories are skipped:
- External entity references (require file I/O)
- XML 1.1 documents (we only support XML 1.0)
- DTD validation tests (`invalid` type)
- Byte decoding and encoding-mismatch fixtures that cannot be exercised through the decoded `String` API
- Tests restricted to older XML editions

## Performance checks

Run the benchmarks with:

```bash
moon bench --target native --release --filter 'bench *'
```

Inputs are built outside the measured closures; each run constructs a reader and collects all events. The cases cover character-reference queues, deep namespace scopes with 512 inherited bindings, nested replacement markup, and large text documents.

Measurements on 2026-10-10, Apple M3 Max, MoonBit `v0.10.14+7d59c7ec9`, native release builds. The baseline is commit `19e6070`; both versions used the same benchmark cases. Values are local mean timings, not portable performance thresholds.

| Case | Baseline | After optimization |
|------|----------|--------------------|
| 1,024 character references | 801 µs | 375 µs |
| 4,096 character references | 11.55 ms | 1.57 ms |
| 16,384 character references | 228.67 ms | 6.30 ms |
| Namespace depth 256 | 7.02 ms | 916 µs |
| Namespace depth 1,024 | 26.68 ms | 1.50 ms |
| 4,096 children from nested entities | 345.00 ms | 8.79 ms |
| 2 MiB of text | 11.14 ms | 10.96 ms |

Pending events are consumed by index, and namespace scopes store only changed bindings. Replacement content is parsed directly while sharing DTD tables, recursion tracking, and the document expansion budget. Attribute values retain their separate XML normalization rules.

## Limitations

- **Non-validating** - Does not validate against DTD
- **UTF-8 only** - Other encodings not supported
- **XML 1.0 only** - XML 1.1 not supported
- **Bounded entity expansion** - Internal entities are limited to 32 nesting levels and 262,144 expanded characters per document

External entity declarations are parsed, but their contents are not resolved. Referencing an external entity raises an error.

## License

Apache-2.0
