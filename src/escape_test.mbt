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
  @debug.debug_inspect(
    escape("<"),
    content=(
      #|"&lt;"
    ),
  )
  @debug.debug_inspect(
    escape(">"),
    content=(
      #|"&gt;"
    ),
  )
  @debug.debug_inspect(
    escape("&"),
    content=(
      #|"&amp;"
    ),
  )
  @debug.debug_inspect(
    escape("\""),
    content=(
      #|"&quot;"
    ),
  )
  @debug.debug_inspect(
    escape("'"),
    content=(
      #|"&apos;"
    ),
  )
}

///|
test "escape mixed content" {
  @debug.debug_inspect(
    escape("<div class=\"test\">"),
    content=(
      #|"&lt;div class=&quot;test&quot;&gt;"
    ),
  )
}

///|
test "escape no special characters" {
  @debug.debug_inspect(
    escape("hello world"),
    content=(
      #|"hello world"
    ),
  )
}

///|
test "unescape entities" {
  @debug.debug_inspect(
    unescape("&lt;"),
    content=(
      #|"<"
    ),
  )
  @debug.debug_inspect(
    unescape("&gt;"),
    content=(
      #|">"
    ),
  )
  @debug.debug_inspect(
    unescape("&amp;"),
    content=(
      #|"&"
    ),
  )
  @debug.debug_inspect(
    unescape("&quot;"),
    content=(
      #|"\""
    ),
  )
  @debug.debug_inspect(
    unescape("&apos;"),
    content=(
      #|"'"
    ),
  )
}

///|
test "unescape numeric entities" {
  @debug.debug_inspect(
    unescape("&#65;"),
    content=(
      #|"A"
    ),
  )
  @debug.debug_inspect(
    unescape("&#x41;"),
    content=(
      #|"A"
    ),
  )
  @debug.debug_inspect(
    unescape("&#x4F;"),
    content=(
      #|"O"
    ),
  )
}

///|
test "unescape mixed content" {
  @debug.debug_inspect(
    unescape("&lt;div&gt; &amp; &quot;hello&quot;"),
    content=(
      #|"<div> & \"hello\""
    ),
  )
}

///|
test "unescape no entities" {
  @debug.debug_inspect(
    unescape("hello world"),
    content=(
      #|"hello world"
    ),
  )
}

///|
test "unescape unknown entity error" {
  // Unknown entities raise InvalidEntity error
  let result = try? unescape("&invalid;")
  @debug.debug_inspect(result, content="Err(InvalidEntity(\"&invalid;\"))")
}
