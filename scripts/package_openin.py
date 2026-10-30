#!/usr/bin/env python3
"""Make a group-free file-opening IPA from the completed device build.
Full Share Extension distribution still requires matching App Group profiles.
"""
from pathlib import Path
import tempfile,shutil,subprocess,zipfile,plistlib,json,hashlib
root=Path(__file__).resolve().parents[1]
source=root/'build/device/TheosMobileCompiler.app'
info=plistlib.loads((source/'Info.plist').read_bytes())
output=root/'build'/f"TweakForge-{info['CFBundleShortVersionString']}-build{info['CFBundleVersion']}-OpenIn-unsigned.ipa"
with tempfile.TemporaryDirectory(prefix='tf-openin-') as temp:
 app=Path(temp)/'Payload'/source.name
 shutil.copytree(source,app)
 shutil.rmtree(app/'PlugIns',ignore_errors=True)
 subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
 ent=subprocess.run(['codesign','-d','--entitlements',':-',str(app)],capture_output=True,check=True).stdout
 assert b'com.apple.security.application-groups' not in ent
 with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
  for p in app.rglob('*'):
   if p.is_file():z.write(p,p.relative_to(Path(temp)))
 with zipfile.ZipFile(output) as z:assert z.testzip() is None
print(json.dumps(dict(ipa=str(output),bytes=output.stat().st_size,sha256=hashlib.sha256(output.read_bytes()).hexdigest())))
