"""Protect catalog coverage, scope decisions, and the independent W3C oracle."""

import json
from pathlib import Path
import tempfile
import unittest

import generate_conformance_tests as generator


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def catalog(self, entries, prefix=''):
        (self.root / 'xmlconf.xml').write_text(prefix + '<TESTSUITE>' + entries + '</TESTSUITE>')
        return generator.collect(self.root)

    def test_complete_xml_manifest_syntax_and_nested_base(self):
        (self.root / 'a/b').mkdir(parents=True)
        (self.root / 'a/b/input.xml').write_text('<r/>')
        cases, ledger = self.catalog("""<TESTCASES xml:base='a/'><TESTCASES xml:base='b/'>
          <TEST TYPE='valid' ID='sample' URI='input.xml'/>
        </TESTCASES></TESTCASES>""")
        self.assertEqual(ledger[0]['uri'], 'a/b/input.xml')
        self.assertEqual(len(cases), 1)

    def test_dtd_defaults_and_external_manifest_wrappers(self):
        (self.root / 'fixtures').mkdir()
        (self.root / 'fixtures/input.xml').write_text('<:r/>')
        (self.root / 'manifest.xml').write_text("<TESTCASES><TEST TYPE='valid' ID='sample' URI='input.xml'/></TESTCASES>")
        cases, _ = self.catalog("<TESTCASES xml:base='fixtures/'>&cases;</TESTCASES>",
                               """<!DOCTYPE TESTSUITE [<!ENTITY cases SYSTEM 'manifest.xml'>
                               <!ATTLIST TEST NAMESPACE CDATA 'no'>]>""")
        self.assertFalse(cases[0][0]['namespaces'])

    def test_invalid_is_accepted_without_dtd_validation(self):
        (self.root / 'input.xml').write_text('<r/>')
        cases, ledger = self.catalog("<TEST TYPE='invalid' ID='sample' URI='input.xml'/>")
        self.assertEqual(ledger[0]['assertion'], 'accept')
        self.assertIn('w3c_accept(', generator.generate(cases))

    def test_namespace_routing_uses_metadata_not_id_spelling(self):
        (self.root / 'input.xml').write_text('<p:r/>')
        cases, _ = self.catalog("""<TEST TYPE='not-wf' ID='arbitrary' URI='input.xml' RECOMMENDATION='NS1.0'/>
          <TEST TYPE='valid' ID='rmt-ns10-looking' URI='input.xml' NAMESPACE='no'/>""")
        source = generator.generate(cases)
        self.assertIn('namespaces=true', source)
        self.assertIn('namespaces=false', source)
        self.assertIn('w3c_reject(', source)

    def test_output_is_copied_verbatim_without_parsing_the_input(self):
        (self.root / 'input.xml').write_text('<this-input-is-not-parsed>')
        (self.root / 'out.xml').write_bytes(b'<r a="&#13;">&lt;&amp;</r>')
        cases, ledger = self.catalog("<TEST TYPE='valid' ID='sample' URI='input.xml' OUTPUT='out.xml'/>")
        self.assertEqual(cases[0][2], '<r a="&#13;">&lt;&amp;</r>')
        self.assertEqual(ledger[0]['assertion'], 'canonical-output')
        self.assertIn('expected=', generator.generate(cases))

    def test_notation_output_gap_does_not_remove_acceptance_test(self):
        (self.root / 'input.xml').write_text('<r/>')
        (self.root / 'out.xml').write_text('<!DOCTYPE r [<!NOTATION n SYSTEM "n">]><r></r>')
        cases, ledger = self.catalog("<TEST TYPE='valid' ID='sample' URI='input.xml' OUTPUT='out.xml'/>")
        self.assertEqual(len(cases), 1)
        self.assertEqual(ledger[0]['output_reason'], 'notation-events-unavailable')

    def test_scope_exclusions_are_accounted_for(self):
        (self.root / 'input.xml').write_text('<r/>')
        _, ledger = self.catalog(''.join(
            f'<TEST TYPE="{kind}" ID="{name}" URI="input.xml" {attributes}/>'
            for name, kind, attributes in [
                ('enabled', 'valid', ''), ('old', 'not-wf', 'EDITION="1 2 3 4"'),
                ('new', 'valid', 'EDITION="5"'), ('xml11', 'valid', 'RECOMMENDATION="XML1.1"'),
                ('external', 'not-wf', 'ENTITIES="general"'), ('optional', 'error', '')]))
        report = generator.coverage(ledger)
        self.assertEqual(report['catalog_entries'], 6)
        self.assertEqual(report['included'], 2)
        self.assertEqual(report['exclusions'], {'external-entities': 1, 'obsolete-edition': 1, 'optional-error': 1, 'xml-1.1': 1})

    def test_byte_errors_are_not_recoded_and_text_controls_are_preserved(self):
        fixture = self.root / 'input.xml'
        fixture.write_bytes(b'<r>\xed\xa0\x80</r>')
        self.assertEqual(generator.fixture_text(fixture), (None, 'byte-decoding'))
        fixture.write_bytes(b'<r>\x00\r\nx</r>')
        self.assertEqual(generator.fixture_text(fixture), ('<r>\x00\r\nx</r>', None))
        fixture.write_text('<?xml version="1.0" encoding="iso-8859-1"?><r/>')
        self.assertEqual(generator.fixture_text(fixture)[1], 'byte-encoding-declaration')
        for encoding in [' utf-8', 'a/b', 'utf:8', 'XYZ+999']:
            content = f'<?xml version="1.0" encoding="{encoding}"?><r/>'
            fixture.write_text(content)
            self.assertEqual(generator.fixture_text(fixture), (content, None))

    def test_missing_input_output_and_duplicate_ids_are_fatal(self):
        with self.assertRaises(FileNotFoundError):
            self.catalog('<TEST TYPE="valid" ID="sample" URI="missing.xml"/>')
        (self.root / 'input.xml').write_text('<r/>')
        with self.assertRaises(FileNotFoundError):
            self.catalog('<TEST TYPE="valid" ID="sample" URI="input.xml" OUTPUT="missing.xml"/>')
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.catalog('<TEST TYPE="valid" ID="sample" URI="input.xml"/>' * 2)

    def test_known_failure_keeps_the_official_accept_expectation(self):
        (self.root / 'input.xml').write_text('<r/>')
        cases, ledger = self.catalog('<TEST TYPE="invalid" ID="rmt-e3e-13" URI="input.xml"/>')
        self.assertEqual(ledger[0]['assertion'], 'accept')
        self.assertIn('#skip(', generator.generate(cases))
        self.assertIn('w3c_accept(', generator.generate(cases))
        self.assertEqual(generator.coverage(ledger)['enabled'], 0)

    def test_literals_preserve_controls_and_astral_characters(self):
        self.assertEqual(generator.literal('\x00\r\n\t\\"\U00010000'), '"\\u{0}\\r\\n\\t\\\\\\"\\u{10000}"')

    def test_checked_in_coverage_and_embedded_fixtures_agree(self):
        ledger = json.loads(generator.COVERAGE_FILE.read_text())
        source = generator.OUTPUT_FILE.read_text()
        self.assertEqual(ledger['catalog_entries'], 2585)
        self.assertEqual(ledger['included'], 1670)
        self.assertEqual(ledger['enabled'], 1669)
        self.assertEqual(sum(ledger['exclusions'].values()) + ledger['included'], 2585)
        self.assertEqual(source.count('\ntest "w3c/'), ledger['included'])
        self.assertEqual(source.count('    expected='), ledger['assertions']['canonical-output'])
        self.assertEqual(source.count('#skip('), len(ledger['known_failures']))
        for entry in ledger['cases']:
            if entry['status'] == 'included':
                self.assertIn(f'test "w3c/{entry["type"]}/{entry["id"]}"', source)
                self.assertIn(f'// {entry["uri"]}\n', source)


if __name__ == '__main__':
    unittest.main()
