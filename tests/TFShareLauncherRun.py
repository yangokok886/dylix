from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf86-launch-') as temp:
 binary=Path(temp)/'test'
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-fblocks',str(root/'tests/TFShareLauncherTests.m'),str(root/'ShareExtension/TFShareLauncher.m'),'-framework','Foundation','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=10)
