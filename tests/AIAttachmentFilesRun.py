from pathlib import Path
import subprocess,tempfile,shutil,hashlib,os
root=Path(__file__).resolve().parents[1]
fixtures=root/'evidence/0.5.2-output-checkboxes/variable-names'
with tempfile.TemporaryDirectory(prefix='tf76-artifacts-') as work:
 p=Path(work);project=p/'project';project.mkdir()
 for scheme in ['rootful','rootless','roothide']:
  shutil.copyfile(next(fixtures.glob('*_'+scheme+'.deb')),project/(scheme+'.deb'))
 sources=['App/AI/Binary/TFAIBinary.m','App/AI/ClassDump/TFAIClassDump.m','App/AI/ClassDump/TFAIClassDumpExecution.m','tests/AIV2AttachmentsTests.m','App/AI/Attachments/TFAIArtifactInspection.m','App/AI/Attachments/TFAIAttachmentStore.m','App/AI/Attachments/TFAIDirectoryAccess.m','App/AI/UI/TFAIActivity.m','App/AI/Providers/TFAIProtocol.m']
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-Wno-incompatible-pointer-types','-Wno-nullability-completeness',*[str(root/s) for s in sources],'-framework','Foundation','-framework','CoreGraphics','-framework','ImageIO','-larchive','-liconv',str(root/'build/classdump-macos/libtweakforge_classdump.a'),'-o',str(p/'test')],check=True)
 original=Path(os.environ.get('DYLIX_TEST_PROJECT', str(root/'fixtures/optional-local-project')))
 copy=p/'AutoMessage-copy'
 def digest_tree(folder):
  digest=hashlib.sha256()
  for file in sorted(folder.rglob('*')):
   if file.is_file() and not file.is_symlink():
    digest.update(str(file.relative_to(folder)).encode());digest.update(file.read_bytes())
  return digest.hexdigest()
 before=digest_tree(original) if original.is_dir() else None
 if original.is_dir(): shutil.copytree(original,copy,symlinks=True)
 subprocess.run([str(p/'test')]+([str(copy)] if copy.is_dir() else []),check=True,env={**os.environ,"TF_BINARY_FIXTURE":str(root/"build/classdump-fixture.dylib")})

 if before:
  assert digest_tree(original)==before, 'Original project changed'
  print('PASS original AutoMessage source tree unchanged SHA256='+before)
