#!/usr/bin/env python3
"""
XML Reference Parser using lxml (libxml2 bindings).

Outputs events in MoonBit format matching our Event enum exactly.
"""

from lxml import etree
from io import BytesIO
from typing import List, Tuple
import re


def escape_for_debug(s: str) -> str:
    """Escape string for MoonBit Debug format."""
    result = []
    for c in s:
        code = ord(c)
        if c == '\\':
            result.append('\\\\')
        elif c == '"':
            result.append('\\"')
        elif c == '\n':
            result.append('\\n')
        elif c == '\t':
            result.append('\\t')
        elif c == '\r':
            result.append('\\r')
        elif code < 0x20:
            result.append(f'\\u{{{code:02x}}}')
        elif code == 0x7F:
            result.append('\\u{7f}')
        elif 0x80 <= code <= 0x9F:
            result.append(f'\\u{{{code:02x}}}')
        else:
            result.append(c)
    return ''.join(result)


class MoonBitTarget:
    """SAX-like target that collects events in MoonBit format."""

    def __init__(self, xml_source: str):
        self.events: List[str] = []
        self.xml_source = xml_source
        # Stack to track pending start elements (for detecting Empty)
        self.pending_start: List[Tuple[str, str]] = []  # [(tag, attrs_str), ...]

    def _flush_pending(self):
        """Emit any pending start elements as Start events."""
        for tag, attrs_str in self.pending_start:
            self.events.append(f'Start({{name: "{tag}", attributes: {attrs_str}}})')
        self.pending_start.clear()

    def start(self, tag, attrib):
        """Called for element start."""
        # Flush any pending starts first
        self._flush_pending()

        # Remove namespace prefix if present
        if '}' in tag:
            tag = tag.split('}', 1)[1]

        # Build attributes string
        attr_list = []
        for key, value in attrib.items():
            if '}' in key:
                key = key.split('}', 1)[1]
            value_escaped = escape_for_debug(value)
            attr_list.append(f'("{key}", "{value_escaped}")')
        attrs_str = "[" + ", ".join(attr_list) + "]"

        # Don't emit yet - wait to see if it's self-closing
        self.pending_start.append((tag, attrs_str))

    def end(self, tag):
        """Called for element end."""
        if '}' in tag:
            tag = tag.split('}', 1)[1]

        if self.pending_start and self.pending_start[-1][0] == tag:
            # The start is still pending - this is a self-closing or empty element
            pending_tag, attrs_str = self.pending_start.pop()
            # Check if it was written as self-closing in source
            if self._is_self_closing_in_source(tag):
                self.events.append(f'Empty({{name: "{tag}", attributes: {attrs_str}}})')
            else:
                # Empty but written as <tag></tag>
                self.events.append(f'Start({{name: "{tag}", attributes: {attrs_str}}})')
                self.events.append(f'End("{tag}")')
        else:
            # Normal end tag
            self._flush_pending()
            self.events.append(f'End("{tag}")')

    def _is_self_closing_in_source(self, tag: str) -> bool:
        """Check if tag appears as self-closing in source."""
        # Look for <tag.../> pattern
        pattern = rf'<{re.escape(tag)}(?:\s[^>]*)?\s*/>'
        return bool(re.search(pattern, self.xml_source))

    def data(self, data):
        """Called for text content."""
        # Flush pending starts before text
        self._flush_pending()
        if data:
            escaped = escape_for_debug(data)
            self.events.append(f'Text("{escaped}")')

    def comment(self, text):
        """Called for comments."""
        self._flush_pending()
        escaped = escape_for_debug(text)
        self.events.append(f'Comment("{escaped}")')

    def pi(self, target, text):
        """Called for processing instructions (not XML decl)."""
        self._flush_pending()
        text = text or ""
        text_escaped = escape_for_debug(text)
        self.events.append(f'PI(target="{target}", data="{text_escaped}")')

    def close(self):
        """Called at end of document."""
        self._flush_pending()
        return self.events


def parse_xml(xml_content: str) -> Tuple[bool, str]:
    """Parse XML and return (success, events_string)."""
    events = []

    try:
        # Extract XML declaration if present (lxml doesn't report it via target)
        decl_match = re.match(r'<\?xml\s+([^?]*)\?>', xml_content)
        if decl_match:
            decl_content = decl_match.group(1)
            version = "1.0"
            encoding = None
            standalone = None

            v_match = re.search(r'version\s*=\s*["\']([^"\']+)["\']', decl_content)
            if v_match:
                version = v_match.group(1)
            e_match = re.search(r'encoding\s*=\s*["\']([^"\']+)["\']', decl_content)
            if e_match:
                encoding = e_match.group(1)
            s_match = re.search(r'standalone\s*=\s*["\']([^"\']+)["\']', decl_content)
            if s_match:
                standalone = s_match.group(1)

            enc_str = f'Some("{encoding}")' if encoding else 'None'
            std_str = f'Some("{standalone}")' if standalone else 'None'
            events.append(f'Decl(version="{version}", encoding={enc_str}, standalone={std_str})')

        # Extract DOCTYPE if present (lxml doesn't report internal subset well)
        # Match: <!DOCTYPE name ...> or <!DOCTYPE name [...] >
        doctype_match = re.search(r'<!DOCTYPE\s+([a-zA-Z_:][\w:.-]*)(?:\s+[^>\[]*)?(?:\s*\[[^\]]*\])?\s*>', xml_content)
        if doctype_match:
            doctype_name = doctype_match.group(1)
            events.append(f'DocType("{doctype_name}")')

        # Handle text/whitespace between declaration/doctype and first element
        # But skip comments and PIs - those are handled by lxml
        first_elem_match = re.search(r'<[a-zA-Z_:]', xml_content)
        if first_elem_match:
            prolog_end = 0
            if decl_match:
                prolog_end = decl_match.end()
            # Skip past DOCTYPE if present
            if doctype_match and doctype_match.start() >= prolog_end:
                prolog_end = doctype_match.end()

            between = xml_content[prolog_end:first_elem_match.start()]
            # Remove comments and PIs from the between text
            between = re.sub(r'<!--.*?-->', '', between, flags=re.DOTALL)
            between = re.sub(r'<\?.*?\?>', '', between, flags=re.DOTALL)
            if between:
                escaped = escape_for_debug(between)
                events.append(f'Text("{escaped}")')

        # Parse with lxml using target interface
        target = MoonBitTarget(xml_content)
        parser = etree.XMLParser(target=target, recover=False)
        etree.parse(BytesIO(xml_content.encode('utf-8')), parser)
        target_events = target.close()
        events.extend(target_events)
        events.append("Eof")

        return True, "[" + ", ".join(events) + "]"

    except etree.XMLSyntaxError as e:
        return False, f"Error: {e}"


def main():
    """Command-line interface."""
    import sys

    if len(sys.argv) > 1:
        # File mode
        with open(sys.argv[1], 'r', encoding='utf-8') as f:
            content = f.read()
        success, result = parse_xml(content)
        print(result)
        sys.exit(0 if success else 1)
    else:
        # Interactive mode
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            xml_content = line.replace('\\n', '\n').replace('\\r', '\r').replace('\\\\', '\\')
            success, result = parse_xml(xml_content)
            print(result)
            sys.stdout.flush()


if __name__ == "__main__":
    main()
