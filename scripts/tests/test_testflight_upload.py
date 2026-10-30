"""Exercise the release boundary with fake Xcode/Apple transport, never a live upload."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'testflight.sh'


class TestFlightUploadTests(unittest.TestCase):
    def run_release(self, *, audit_fails=False, credentials=True):
        with tempfile.TemporaryDirectory() as work:
            repo = Path(work)
            (repo / 'scripts').mkdir()
            (repo / 'docs/release').mkdir(parents=True)
            shutil.copy(SCRIPT, repo / 'scripts/testflight.sh')
            with (repo / 'docs/release/ExportOptions.plist').open('wb') as target:
                plistlib.dump({'destination': 'upload', 'manageAppVersionAndBuildNumber': True}, target)
            (repo / 'scripts/audit_tap_to_pay_build.py').write_text('''import os,sys\nfrom pathlib import Path\nwith open(os.environ['RELEASE_EVENTS'],'a') as out: out.write('audit '+sys.argv[1]+'\\n')\nif '--distribution' in sys.argv and os.environ.get('FAIL_AUDIT') == '1': sys.exit(1)\n''')
            binaries = repo / 'bin'
            binaries.mkdir()
            (binaries / 'xcodegen').write_text('#!/bin/sh\nexit 0\n')
            (binaries / 'xcrun').write_text('''#!/usr/bin/python3
import json,os,sys
if sys.argv[1] == 'simctl':
 print(json.dumps({'devices':{'iOS':[{'name':'iPhone Test','udid':'fixture'}]}}))
else:
 with open(os.environ['RELEASE_EVENTS'],'a') as out: out.write('transport '+json.dumps(sys.argv[1:])+'\\n')
''')
            (binaries / 'xcodebuild').write_text('''#!/usr/bin/python3
import json,os,plistlib,sys,zipfile
from pathlib import Path
args=sys.argv[1:]
def arg(flag): return args[args.index(flag)+1]
if 'archive' in args:
 app=Path(arg('-archivePath'))/'Products/Applications/Thorbis.app'
 app.mkdir(parents=True)
 with (app/'Info.plist').open('wb') as out: plistlib.dump({'ThorbisTapToPayEnabled':True},out)
 with open(os.environ['RELEASE_EVENTS'],'a') as out: out.write('root '+str(Path(arg('-archivePath')).parent)+'\\n')
if '-exportArchive' in args:
 with open(arg('-exportOptionsPlist'),'rb') as source: destination=plistlib.load(source)['destination']
 target=Path(arg('-exportPath')); target.mkdir()
 ipa=target/'Thorbis.ipa'
 with zipfile.ZipFile(ipa,'w') as archive: archive.writestr('Payload/Thorbis.app/Info.plist',plistlib.dumps({'ThorbisTapToPayEnabled':True}))
 with open(os.environ['RELEASE_EVENTS'],'a') as out: out.write('export '+destination+' '+str(ipa)+'\\n')
''')
            for binary in binaries.iterdir():
                binary.chmod(0o755)
            events_file = repo / 'events'
            env = {**os.environ, 'PATH':str(binaries)+':'+os.environ['PATH'],
                   'BUILD_NUMBER':'424242', 'RELEASE_EVENTS':str(events_file),
                   'FAIL_AUDIT':'1' if audit_fails else '0'}
            for key in ('THORBIS_ASC_API_KEY_ID', 'THORBIS_ASC_API_ISSUER_ID'):
                env.pop(key, None)
            if credentials:
                env.update(THORBIS_ASC_API_KEY_ID='fixture-key', THORBIS_ASC_API_ISSUER_ID='fixture-issuer')
            result = subprocess.run(['/bin/bash', str(repo/'scripts/testflight.sh')], env=env,
                                    capture_output=True, text=True)
            events = events_file.read_text().splitlines()
            for line in events:
                if line.startswith('root '): shutil.rmtree(line[5:])
            return result, events

    def test_enabled_upload_transmits_the_single_audited_export(self):
        result, events = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        exports = [line for line in events if line.startswith('export ')]
        self.assertEqual(len(exports), 1, events)
        self.assertTrue(exports[0].startswith('export export '), events)
        ipa = exports[0].split(' ', 2)[2]
        transport = next(line for line in events if line.startswith('transport '))
        self.assertIn(ipa, transport)
        distribution_audit = next(line for line in events if '/audit/Payload/' in line)
        self.assertLess(events.index(distribution_audit), events.index(transport))

    def test_failed_distribution_audit_never_uploads(self):
        result, events = self.run_release(audit_fails=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(line.startswith('transport ') or line.startswith('export upload ') for line in events), events)

    def test_missing_transport_credentials_never_reexports_or_uploads(self):
        result, events = self.run_release(credentials=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(line.startswith('transport ') or line.startswith('export upload ') for line in events), events)


if __name__ == '__main__':
    unittest.main()
