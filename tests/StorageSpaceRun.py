from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf-storage-tests-') as temp:
 binary=Path(temp)/'tests'
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-fblocks','-DTMC_STORAGE_TEST=1','-Wno-deprecated-declarations','-Wno-incompatible-pointer-types',str(root/'tests/StorageSpaceTests.m'),str(root/'App/StorageSpace.m'),'-framework','Foundation','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=60)
