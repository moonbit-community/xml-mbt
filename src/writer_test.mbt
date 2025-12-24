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
/// Tests for XML Writer

///|
test "write simple element" {
  let w = Writer::new()
  w.start_element("root", [])
  w.end_element("root")
  inspect(w.to_string(), content="<root></root>")
}

///|
test "write self-closing element" {
  let w = Writer::new()
  w.empty_element("br", [])
  inspect(w.to_string(), content="<br/>")
}

///|
test "write element with text" {
  let w = Writer::new()
  w.start_element("p", [])
  w.text("Hello World")
  w.end_element("p")
  inspect(w.to_string(), content="<p>Hello World</p>")
}

///|
test "write element with attributes" {
  let w = Writer::new()
  w.start_element("div", [("id", "main"), ("class", "container")])
  w.end_element("div")
  inspect(w.to_string(), content="<div id=\"main\" class=\"container\"></div>")
}

///|
test "write nested elements" {
  let w = Writer::new()
  w.start_element("ul", [])
  w.start_element("li", [])
  w.text("Item 1")
  w.end_element("li")
  w.start_element("li", [])
  w.text("Item 2")
  w.end_element("li")
  w.end_element("ul")
  inspect(w.to_string(), content="<ul><li>Item 1</li><li>Item 2</li></ul>")
}

///|
test "write CDATA" {
  let w = Writer::new()
  w.start_element("script", [])
  w.cdata("var x = 1 < 2;")
  w.end_element("script")
  inspect(w.to_string(), content="<script><![CDATA[var x = 1 < 2;]]></script>")
}

///|
test "write comment" {
  let w = Writer::new()
  w.comment(" This is a comment ")
  inspect(w.to_string(), content="<!-- This is a comment -->")
}

///|
test "write text with escaping" {
  let w = Writer::new()
  w.start_element("p", [])
  w.text("<script>alert('xss')</script>")
  w.end_element("p")
  inspect(
    w.to_string(),
    content="<p>&lt;script&gt;alert(&apos;xss&apos;)&lt;/script&gt;</p>",
  )
}

///|
test "write using events" {
  let w = Writer::new()
  w.write_event(Start(XmlElement::with_attrs("div", [("id", "main")])))
  w.write_event(Text("content"))
  w.write_event(End("div"))
  inspect(w.to_string(), content="<div id=\"main\">content</div>")
}
