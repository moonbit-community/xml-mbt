# xml

A streaming XML parser for MoonBit, inspired by [quick-xml](https://github.com/tafia/quick-xml).

## Features

- **Pull-parser model** - Read XML events one at a time (like StAX in Java)
- **Streaming** - Memory-efficient processing of large documents
- **Multi-backend** - Works on wasm, wasm-gc, js, and native
- **XML 1.0 + Namespaces 1.0** - Full Unicode name character support

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

This library is tested against the [W3C XML Conformance Test Suite](https://www.w3.org/XML/Test/).

**Current status: 827 tests passing (100%)**

Coverage:
- XML 1.0 (James Clark xmltest)
- XML 1.0 Errata 2nd/3rd/4th edition
- Namespaces 1.0
- Sun Microsystems tests

### Running Conformance Tests

```bash
# Download the W3C test suite
curl -L -o xmlts.tar.gz "https://www.w3.org/XML/Test/xmlts20130923.tar.gz"
tar -xzf xmlts.tar.gz && mv xmlconf . && rm xmlts.tar.gz

# Run all tests
moon test --target all
```

### Regenerating Test Snapshots

The conformance tests use snapshot testing to verify parsed events match the expected output. Expected values are generated using [quick-xml](https://github.com/tafia/quick-xml) as the reference implementation.

```bash
# Build the quick-xml reference tool (requires Rust)
cargo build --release --manifest-path tools/quickxml-ref/Cargo.toml

# Regenerate tests with expected snapshots from quick-xml
python3 scripts/generate_conformance_tests.py

# Update snapshots
moon test --update
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
