///|
fn benchmark_references(count : Int) -> String {
  "<root>" + "&#65;".repeat(count) + "</root>"
}

///|
fn benchmark_namespaces(depth : Int) -> String {
  let input = StringBuilder()
  input.write_string("<root")
  for i in 0..<512 {
    input.write_string(" xmlns:p\{i}='urn:\{i}'")
  }
  input.write_string(">")
  input.write_string("<p0:child>".repeat(depth))
  input.write_string("</p0:child>".repeat(depth))
  input.write_string("</root>")
  input.to_string()
}

///|
test "bench reference queue 1024" (b : @bench.T) {
  let input = benchmark_references(1024)
  b.bench(fn() {
    b.keep(try! @xml.Reader::from_string(input).read_events_until_eof())
  })
}

///|
test "bench reference queue 4096" (b : @bench.T) {
  let input = benchmark_references(4096)
  b.bench(fn() {
    b.keep(try! @xml.Reader::from_string(input).read_events_until_eof())
  })
}

///|
test "bench reference queue 16384" (b : @bench.T) {
  let input = benchmark_references(16384)
  b.bench(fn() {
    b.keep(try! @xml.Reader::from_string(input).read_events_until_eof())
  })
}

///|
test "bench namespace depth 256" (b : @bench.T) {
  let input = benchmark_namespaces(256)
  b.bench(fn() {
    b.keep(
      try! @xml.NamespaceReader::from_string(input).read_events_until_eof(),
    )
  })
}

///|
test "bench namespace depth 1024" (b : @bench.T) {
  let input = benchmark_namespaces(1024)
  b.bench(fn() {
    b.keep(
      try! @xml.NamespaceReader::from_string(input).read_events_until_eof(),
    )
  })
}

///|
test "bench nested entity markup" (b : @bench.T) {
  let input = "<!DOCTYPE root [<!ENTITY a '<child a=\"x\">value&amp;tail</child>'><!ENTITY b '&a;&a;&a;&a;'><!ENTITY c '&b;&b;&b;&b;'>]><root>" +
    "&c;".repeat(256) +
    "</root>"
  b.bench(fn() {
    b.keep(try! @xml.Reader::from_string(input).read_events_until_eof())
  })
}

///|
test "bench large document 2 MiB text" (b : @bench.T) {
  let input = "<root>" + "x".repeat(2 * 1024 * 1024) + "</root>"
  b.bench(fn() {
    b.keep(try! @xml.Reader::from_string(input).read_events_until_eof())
  })
}
