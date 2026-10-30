from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf77-webtests-') as work:
 p=Path(work)/'test'
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-DTFAI_WEB_TEST=1','-Wno-incompatible-pointer-types',str(root/'tests/AIWebToolsTests.m'),str(root/'App/AI/Tools/TFAIWebTools.m'),'-framework','Foundation','-framework','Security','-o',str(p)],check=True)
 subprocess.run([str(p)],check=True,timeout=90)
