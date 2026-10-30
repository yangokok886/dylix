from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf84-share-') as temp:
 binary=Path(temp)/'test'
 sources=['tests/TFShareTransferTests.m','App/Incoming/TFShareTransfer.m','App/Incoming/TFIncoming.m']
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-fblocks','-Wno-incompatible-pointer-types',*[str(root/s) for s in sources],'-framework','Foundation','-larchive','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
