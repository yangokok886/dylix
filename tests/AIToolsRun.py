#!/usr/bin/env python3
"""Compile isolated real tools + existing Git/archive services; only temp fixtures mutate."""
from pathlib import Path
import subprocess,tempfile,zipfile,stat,os,shutil,hashlib
root=Path(__file__).resolve().parents[1]
original=Path(os.environ.get('TFAI_APP_ROOT',str(root)))
with tempfile.TemporaryDirectory(prefix='tf-ai-tools-') as tmp:
 tmp=Path(tmp); (tmp/'project').mkdir();(tmp/'archives').mkdir()
 source_root=original.parent/'Xiaohongguo'
 hashes={}
 if source_root.exists():
  for source in list(source_root.rglob('*.xm'))[:2]+list(source_root.rglob('*.m'))[:2]:
   if source.is_file() and source.stat().st_size<300000:
    hashes[source]=(hashlib.sha256(source.read_bytes()).hexdigest(),source.stat().st_mtime_ns)
    target=tmp/'project'/'ProjectCopy'/source.relative_to(source_root);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)

 for name,entries in [('good',{'Source.m':'int source;\n'}),('traversal',{'../escape.m':'bad'}),('secret',{'.env':'fixture-secret'})]:
  with zipfile.ZipFile(tmp/'archives'/f'{name}.zip','w') as archive:
   for path,data in entries.items():archive.writestr(path,data)
 with zipfile.ZipFile(tmp/'archives/link.zip','w') as archive:
  entry=zipfile.ZipInfo('link.m');entry.create_system=3;entry.external_attr=(stat.S_IFLNK|0o777)<<16;archive.writestr(entry,'../../outside')
 sources=[root/'tests/AIToolsTests.m',*sorted((root/'App/AI/Tools').glob('*.m')),*sorted((root/'App/AI/Permissions').glob('*.m')),original/'App/GitService.m',original/'App/ArchiveImport.m',original/'App/TheosMakefile.m',original/'App/SDKResources.m']
 cmd=['xcrun','clang','-isysroot',os.environ.get('TFAI_MACOS_SDK', '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk' if Path('/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk').exists() else subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()),'-fobjc-arc','-fmodules','-DTFAI_TOOL_TEST=1','-I'+str(original/'Vendor/libgit2/include'),'-framework','Foundation','-framework','CoreFoundation','-framework','Security',*map(str,sources),str(original/'build/git-macos/libgit2.a'),'-larchive','-liconv','-o',str(tmp/'tools')]
 subprocess.run(cmd,check=True)
 subprocess.run([str(tmp/'tools'),str(tmp/'project'),str(tmp/'archives'),'--git-test'],check=True,timeout=240)
 for source,baseline in hashes.items():
  assert (hashlib.sha256(source.read_bytes()).hexdigest(),source.stat().st_mtime_ns)==baseline
 print(f'Original project read-only verified: {len(hashes)} source hashes + mtimes unchanged')
