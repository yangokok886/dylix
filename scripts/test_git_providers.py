#!/usr/bin/env python3
"""Offline GitHub/Gitee protocol fixtures; no real credentials or remote writes."""
import pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf-git-providers-') as directory:
 for name in ['GitHubRepositoriesTests','GiteeRepositoriesTests']:
  exe=str(pathlib.Path(directory)/name)
  subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fmodules','-I'+str(root/'App'),'-framework','Foundation',str(root/'tests'/f'{name}.m'),str(root/'App/GitHubRepositories.m'),'-o',exe],check=True)
  subprocess.run([exe],check=True)
