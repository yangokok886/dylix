from pathlib import Path
import subprocess,tempfile,plistlib
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf84-groups-') as temp:
 p=Path(temp);(p/'fixture.c').write_text('int main(void){return 0;}')
 subprocess.run(['xcrun','clang',str(p/'fixture.c'),'-o',str(p/'fixture')],check=True)
 (p/'entitlements.plist').write_bytes(plistlib.dumps({'com.apple.security.application-groups':['group.fixture.renamed']}))
 subprocess.run(['codesign','--force','--sign','-','--entitlements',str(p/'entitlements.plist'),str(p/'fixture')],check=True)
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-fblocks','-Wno-incompatible-pointer-types',str(root/'tests/TFShareGroupsTests.m'),str(root/'App/Incoming/TFShareGroups.m'),'-framework','Foundation','-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),str(p/'fixture')],check=True)
