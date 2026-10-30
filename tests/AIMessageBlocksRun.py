from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf-message-blocks-') as temp:
    binary = Path(temp) / 'tests'
    subprocess.run(['xcrun', 'clang', '-isysroot', '/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk', '-fobjc-arc', '-fblocks', str(root / 'tests/AIMessageBlocksTests.m'), str(root / 'App/AI/UI/TFAIMessageBlocks.m'), '-framework', 'Foundation', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
