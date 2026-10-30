#!/usr/bin/env python3
import pathlib,tempfile,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf-prompt-tests-') as directory:
 exe=str(pathlib.Path(directory)/'prompt-tests')
 subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fmodules','-framework','Foundation',str(root/'tests/DeveloperPromptTests.m'),'-o',exe],check=True)
 subprocess.run([exe],check=True)
