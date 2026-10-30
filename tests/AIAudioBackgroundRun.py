from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf-audio-') as temp:
 binary=Path(temp)/'tests'
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-I'+str(root/'tests/fixtures/audio'),'-I'+str(root/'tests/fixtures/background'),'-fobjc-arc','-fblocks',str(root/'tests/AIAudioBackgroundTests.m'),'-framework','Foundation','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=15)
