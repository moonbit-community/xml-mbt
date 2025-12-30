#!/usr/bin/env python3
"""
XML Reference Parser using lxml (libxml2 bindings).

Outputs events in MoonBit format matching our Event enum exactly.
Uses lxml's docinfo API instead of regex for reliable DOCTYPE/decl parsing.
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
        self.pending_start: List[Tuple[str, str]] = []
        self.pending_text: str = ""

    def _flush_pending_starts(self):
        """Emit any pending start elements as Start events."""
        for tag, attrs_str in self.pending_start:
            self.events.append(f'Start({{name: "{tag}", attributes: {attrs_str}}})')
        self.pending_start.clear()

    def _flush_text(self):
        """Coalesce text callbacks into a single Text(...) event.

        lxml's target API may call `data()` multiple times for a single logical
        text node (implementation-dependent chunking). We coalesce to keep the
        generated expectations stable and comparable to our MoonBit parser.
        """
        if self.pending_text:
            escaped = escape_for_debug(self.pending_text)
            self.events.append(f'Text("{escaped}")')
            self.pending_text = ""

    def start(self, tag, attrib):
        """Called for element start."""
        self._flush_pending_starts()
        self._flush_text()

        if '}' in tag:
            tag = tag.split('}', 1)[1]

        attr_list = []
        for key, value in attrib.items():
            if '}' in key:
                key = key.split('}', 1)[1]
            value_escaped = escape_for_debug(value)
            attr_list.append(f'("{key}", "{value_escaped}")')
        attrs_str = "[" + ", ".join(attr_list) + "]"

        self.pending_start.append((tag, attrs_str))

    def end(self, tag):
        """Called for element end."""
        self._flush_text()
        if '}' in tag:
            tag = tag.split('}', 1)[1]

        if self.pending_start and self.pending_start[-1][0] == tag:
            pending_tag, attrs_str = self.pending_start.pop()
            if self._is_self_closing_in_source(tag):
                self.events.append(f'Empty({{name: "{tag}", attributes: {attrs_str}}})')
            else:
                self.events.append(f'Empty({{name: "{tag}", attributes: {attrs_str}}})')
        else:
            self._flush_pending_starts()
            self.events.append(f'End("{tag}")')

    def _is_self_closing_in_source(self, tag: str) -> bool:
        """Check if tag appears as self-closing in source."""
        pattern = rf'<{re.escape(tag)}(?:\s[^>]*)?\s*/>'
        return bool(re.search(pattern, self.xml_source))

    def data(self, data):
        """Called for text content."""
        self._flush_pending_starts()
        if data:
            self.pending_text += data

    def comment(self, text):
        """Called for comments."""
        self._flush_pending_starts()
        self._flush_text()
        escaped = escape_for_debug(text)
        self.events.append(f'Comment("{escaped}")')

    def pi(self, target, text):
        """Called for processing instructions (not XML decl)."""
        self._flush_pending_starts()
        self._flush_text()
        text = text or ""
        text_escaped = escape_for_debug(text)
        self.events.append(f'PI(target="{target}", data="{text_escaped}")')

    def close(self):
        """Called at end of document."""
        self._flush_pending_starts()
        self._flush_text()
        return self.events


def parse_xml(xml_content: str) -> Tuple[bool, str]:
    """Parse XML and return (success, events_string)."""
    events = []

    try:
        # Parse with lxml to get docinfo
        xml_bytes = xml_content.encode('utf-8')
        tree = etree.parse(BytesIO(xml_bytes))
        docinfo = tree.docinfo

        # Extract XML declaration from docinfo
        if docinfo.xml_version:
            version = docinfo.xml_version
            encoding = docinfo.encoding
            standalone = docinfo.standalone

            enc_str = f'Some("{encoding}")' if encoding else 'None'
            # docinfo.standalone is a bool or None
            if standalone is True:
                std_str = 'Some("yes")'
            elif standalone is False:
                std_str = 'Some("no")'
            else:
                std_str = 'None'

            # Only emit Decl if there was an actual XML declaration in source
            if xml_content.strip().startswith('<?xml'):
                events.append(f'Decl(version="{version}", encoding={enc_str}, standalone={std_str})')

        # Extract DOCTYPE from docinfo (only if there's an actual DOCTYPE)
        if docinfo.doctype or docinfo.internalDTD is not None:
            events.append(f'DocType("{docinfo.root_name}")')

        # Now parse with target to get element events
        target = MoonBitTarget(xml_content)
        parser = etree.XMLParser(target=target, recover=False)
        etree.parse(BytesIO(xml_bytes), parser)
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
        with open(sys.argv[1], 'r', encoding='utf-8') as f:
            content = f.read()
        success, result = parse_xml(content)
        print(result)
        sys.exit(0 if success else 1)
    else:
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
