from pathlib import Path
import subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[1]
fixtures=root/'evidence/0.5.2-output-checkboxes/variable-names'
with tempfile.TemporaryDirectory(prefix='tf76-artifacts-') as work:
 p=Path(work);project=p/'project';project.mkdir()
 for scheme in ['rootful','rootless','roothide']:
  shutil.copyfile(next(fixtures.glob('*_'+scheme+'.deb')),project/(scheme+'.deb'))
 sources=['App/AI/Binary/TFAIBinary.m','App/AI/ClassDump/TFAIClassDump.m','App/AI/ClassDump/TFAIClassDumpExecution.m','tests/AIArtifactInspectionTests.m','App/AI/Attachments/TFAIArtifactInspection.m','App/AI/Attachments/TFAIAttachmentStore.m','App/AI/Attachments/TFAIDirectoryAccess.m','App/AI/UI/TFAIActivity.m','App/AI/Providers/TFAIProtocol.m']
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-Wno-incompatible-pointer-types','-Wno-nullability-completeness',*[str(root/s) for s in sources],'-framework','Foundation','-framework','CoreGraphics','-framework','ImageIO','-larchive','-liconv',str(root/'build/classdump-macos/libtweakforge_classdump.a'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),str(project)],check=True)
