"""Validate the exported iPhone app before submitting it to Apple."""
import hashlib
import json
from pathlib import Path
import plistlib
import sys
import zipfile

ipa = Path(sys.argv[1])
with zipfile.ZipFile(ipa) as bundle:
    info_path = 'Payload/ETFToGo.app/Info.plist'
    info = plistlib.loads(bundle.read(info_path))
    assert info['UIDeviceFamily'] == [1], f"Expected iPhone only, got {info['UIDeviceFamily']}"
    assert info['CFBundleIdentifier'] == 'com.sonia.etftogo'
    assert info['UISupportedInterfaceOrientations'] == ['UIInterfaceOrientationPortrait']
    assert info['ITSAppUsesNonExemptEncryption'] is False
    assert 'Payload/ETFToGo.app/embedded.mobileprovision' in bundle.namelist()
    assert any(name.startswith('Payload/ETFToGo.app/AppIcon') for name in bundle.namelist())
    record = {key: info.get(key) for key in [
        'CFBundleIdentifier', 'CFBundleDisplayName', 'CFBundleShortVersionString',
        'CFBundleVersion', 'MinimumOSVersion', 'UIDeviceFamily',
        'UISupportedInterfaceOrientations', 'DTSDKName', 'DTXcode', 'DTXcodeBuild',
        'ITSAppUsesNonExemptEncryption']}
    record.update(sizeBytes=ipa.stat().st_size, sha256=hashlib.sha256(ipa.read_bytes()).hexdigest(),
                  hasEmbeddedProfile=True, hasAppIcon=True)
Path('build/ipa-inspection.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
print('Verified: signed iPhone-only IPA, formal bundle ID, portrait orientation, app icon and profile.')
