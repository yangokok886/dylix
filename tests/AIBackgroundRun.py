from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf-background-') as temp:
 binary=Path(temp)/'tests'
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-I'+str(root/'tests/fixtures/background'),'-DTFAI_BACKGROUND_FIXTURE=1','-fobjc-arc','-fblocks',str(root/'tests/AIBackgroundTests.m'),'-framework','Foundation','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=20)
