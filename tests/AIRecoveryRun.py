from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf-recovery-') as work:
 binary=Path(work)/'tests'
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-fblocks','-Wno-nullability-completeness','-Wno-incompatible-pointer-types',str(root/'tests/AIRecoveryTests.m'),str(root/'App/AI/Core/TFAIRecovery.m'),str(root/'App/AI/Sessions/TFAISessions.m'),'-framework','Foundation','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=20)
