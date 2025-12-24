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
/// Tests for XML escape/unescape functions

///|
test "escape special characters" {
  inspect(escape("<"), content="&lt;")
  inspect(escape(">"), content="&gt;")
  inspect(escape("&"), content="&amp;")
  inspect(escape("\""), content="&quot;")
  inspect(escape("'"), content="&apos;")
}

///|
test "escape mixed content" {
  inspect(
    escape("<div class=\"test\">"),
    content="&lt;div class=&quot;test&quot;&gt;",
  )
}

///|
test "escape no special characters" {
  inspect(escape("hello world"), content="hello world")
}

///|
test "unescape entities" {
  inspect(unescape("&lt;"), content="<")
  inspect(unescape("&gt;"), content=">")
  inspect(unescape("&amp;"), content="&")
  inspect(unescape("&quot;"), content="\"")
  inspect(unescape("&apos;"), content="'")
}

///|
test "unescape numeric entities" {
  inspect(unescape("&#65;"), content="A")
  inspect(unescape("&#x41;"), content="A")
  inspect(unescape("&#x4F;"), content="O")
}

///|
test "unescape mixed content" {
  inspect(
    unescape("&lt;div&gt; &amp; &quot;hello&quot;"),
    content="<div> & \"hello\"",
  )
}

///|
test "unescape no entities" {
  inspect(unescape("hello world"), content="hello world")
}

///|
test "unescape invalid entity error" {
  let result = try? unescape("&invalid;")
  inspect(result, content="Err(InvalidEntity(\"&invalid;\"))")
}
