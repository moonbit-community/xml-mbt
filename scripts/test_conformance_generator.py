"""Keep W3C classifications and reference expectations independent of the parser."""

import contextlib
import io
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

import generate_conformance_tests as generator
from xml_reference import escape_for_debug, parse_xml


def decode_literal(literal):
    def escape(match):
        if match[1] is not None:
            return json.dumps(chr(int(match[1], 16)))[1:-1]
        return match[0]
    return json.loads(re.sub(r'\\u\{([0-9a-fA-F]+)\}|\\.', escape, literal))


def compact_events(value):
    # Ignore formatting, preserving every character inside string literals.
    tokens = [token for token in re.findall(r'"(?:[^"\\]|\\.)*"|\s+|.', value)
              if not token.isspace()]
    return ''.join(token for index, token in enumerate(tokens)
                   if token != ',' or index + 1 == len(tokens)
                   or tokens[index + 1] not in [']', '}', ')'])


class ReferenceTests(unittest.TestCase):
    def test_line_endings_defaults_and_entity_character_references(self):
        source = '\ufeff<?xml version="1.0"?><!DOCTYPE r [<!ENTITY e "a&#13;b"><!ATTLIST r a NMTOKENS " x  y ">]><r>&e;\r\nz</r>'
        success, events = parse_xml(source)
        self.assertTrue(success, events)
        self.assertIn('Decl(version="1.0", encoding=Some("UTF-8"), standalone=Some("no"))', events)
        self.assertIn('attributes: [("a", "x y")]', events)
        self.assertIn('Text("a\\rb\\nz")', events)

    def test_plain_xml_names_need_not_be_namespace_qnames(self):
        success, events = parse_xml('<:r :="x"><a:b:c/></:r>')
        self.assertTrue(success, events)
        self.assertIn('("", "x")', events)

    def test_namespace_recovery_does_not_hide_xml_syntax_errors(self):
        for source in ['<p:r a="1" a="2"/>', '<p:r>', '<p:r>&missing;</p:r>', '<p:r>&#0;</p:r>']:
            with self.subTest(source=source):
                success, _ = parse_xml(source)
                self.assertFalse(success)

    def test_debug_escaping_preserves_carriage_returns(self):
        self.assertEqual(escape_for_debug('\r\n\t\\"'), '\\r\\n\\t\\\\\\"')

    def test_all_checked_in_valid_expectations_match_independent_reference(self):
        source = generator.OUTPUT_FILE.read_text()
        tests = re.findall(r'test "(w3c/valid/[^\"]+)" \{(.*?)\n\}', source, re.S)
        self.assertGreater(len(tests), 0)
        for name, body in tests:
            with self.subTest(name=name):
                xml = decode_literal(re.search(r'let xml = ("(?:[^"\\]|\\.)*")', body)[1])
                success, reference = parse_xml(xml)
                self.assertTrue(success, reference)
                expected = re.search(r'let expected : Array\[ConformanceEvent\] = (.*?)\n  @debug.assert_eq', body, re.S)
                if expected:
                    expectation = expected[1]
                else:
                    expectation = '\n'.join(re.findall(r'^\s*#\|(.*)$', body, re.M))
                self.assertTrue(expectation, 'valid tests must assert their events')
                self.assertEqual(compact_events(expectation), compact_events(reference))


class GeneratorTests(unittest.TestCase):
    def test_byte_encoding_fixtures_cannot_be_recoded_as_valid_text(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / 'case.xml'
            for data in [b'<r>\xed\xa0\x80</r>', b'<r>\xf7\x80\x80\x80</r>', b'\xef\xbb\xbf<?xml version="1.0" encoding="iso-8859-1"?><r/>']:
                fixture.write_bytes(data)
                self.assertIsNone(generator.load_test_file(str(fixture)))
            fixture.write_bytes(b'<r>\r\nx</r>')
            self.assertEqual(generator.load_test_file(str(fixture)), '<r>\r\nx</r>')
            for name in [' utf-8', 'a/b', 'just&#41;word', 'utf:8', '@import(sys-encoding)', 'XYZ+999']:
                content = f'<?xml version="1.0" encoding="{name}"?><r/>'
                fixture.write_text(content)
                self.assertEqual(generator.load_test_file(str(fixture)), content)

    def test_reference_failure_is_fatal(self):
        with patch.object(generator, 'parse_xml', return_value=(False, 'bad reference')):
            with self.assertRaisesRegex(RuntimeError, 'bad reference'):
                generator.get_expected_events('<root/>')

    def test_valid_tests_use_typed_event_equality(self):
        generated = generator.generate_valid_test_with_events('sample', '<root/>', '', '[Empty({name: "root", attributes: []}), Eof]')
        self.assertIn('Array[ConformanceEvent]', generated)
        self.assertIn('@debug.assert_eq(to_conformance_events(events), expected)', generated)
        self.assertNotIn('assert_true', generated)

    def test_namespace_not_wf_uses_namespace_reader(self):
        for test_id in ['rmt-ns10-001', 'ht-ns10-001']:
            self.assertIn('NamespaceReader::from_string', generator.generate_not_wf_test(test_id, '<p:r/>', ''))
        self.assertIn('Reader::from_string', generator.generate_not_wf_test('xml-syntax', '<r>', ''))
        self.assertIn('XmlError::At(_)', generator.generate_not_wf_test('xml-syntax', '<r>', ''))

    def test_manifest_filters_obsolete_editions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'case.xml').write_text('<root/>')
            manifest = root / 'manifest.xml'
            manifest.write_text(''.join(
                f'<TEST TYPE="not-wf" ID="{name}" URI="case.xml"{edition}>test</TEST>'
                for name, edition in [('old', ' EDITION="1 2 3 4"'), ('current', ' EDITION="5"'), ('all', ' EDITION="1 2 3 4 5"'), ('unspecified', '')]
            ))
            tests = generator.parse_test_manifest(manifest, root)
            self.assertEqual([test[0] for test in tests], ['current', 'all', 'unspecified'])

    def test_not_wf_is_generated_even_if_reference_accepts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'xmltest').mkdir()
            (root / 'xmltest/xmltest.xml').write_text('manifest')
            case = root / 'case.xml'
            case.write_text('<p:r/>')
            output = root / 'output.mbt'
            with patch.object(generator, 'XMLCONF_DIR', root), patch.object(generator, 'OUTPUT_FILE', output), patch.object(generator, 'parse_test_manifest', return_value=[('rmt-ns10-sample', 'not-wf', str(case), '')]), patch.object(generator, 'get_expected_events', side_effect=AssertionError('not-wf must not depend on the reference')), patch.object(generator.subprocess, 'run'), contextlib.redirect_stdout(io.StringIO()):
                generator.main()
            self.assertIn('w3c/not-wf/rmt_ns10_sample', output.read_text())

    def test_missing_suite_does_not_overwrite_existing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / 'output.mbt'
            output.write_text('keep existing tests')
            with patch.object(generator, 'XMLCONF_DIR', root), patch.object(generator, 'OUTPUT_FILE', output), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, 'No W3C tests'):
                    generator.main()
            self.assertEqual(output.read_text(), 'keep existing tests')


if __name__ == '__main__':
    unittest.main()
