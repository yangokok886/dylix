from pathlib import Path
import subprocess,tempfile,zipfile,hashlib,struct,shutil
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf83-') as work:
 p=Path(work)
 (p/'source.m').write_text('const char *fixture_string="fixture-string"; const char *fixture_base64="Zml4dHVyZS1kZWNvZGU="; const char *fixture_hex="66697874757265"; __attribute__((noinline)) int fixture_add(int a){return a+1;} int fixture_call(int a){return fixture_add(a)+2;}')
 subprocess.run(['xcrun','--sdk','iphoneos','clang','-arch','arm64','-miphoneos-version-min=15.0','-O0','-dynamiclib',str(p/'source.m'),'-o',str(p/'fixture.dylib')],check=True)
 subprocess.run(['xcrun','--sdk','iphoneos','clang','-arch','arm64','-miphoneos-version-min=15.0','-fobjc-arc','-dynamiclib','-Wl,-no_objc_category_merging','-framework','Foundation',str(root/'tests/TFClassDumpFixture.m'),'-o',str(p/'objc.dylib')],check=True)
 for name,files in {'project.zip':{'Makefile':'TWEAK_NAME = Sample','Tweak.xm':'%hook Sample\n%end'},'headers.zip':{'Some.h':'@interface Some\n@end'},'renamed.zip':{'Payload/Sample.app/Sample':'fixture'}}.items():
  with zipfile.ZipFile(p/name,'w') as z:
   for path,text in files.items(): z.writestr(path,text)
 shutil.copyfile(next((root/'evidence/0.5.2-output-checkboxes/variable-names').glob('*_rootless.deb')),p/'sample.deb')
 binary=(p/'fixture.dylib').read_bytes()
 (p/'fat.dylib').write_bytes(struct.pack('>IIiiIII',0xcafebabe,1,0x100000c,0,28,len(binary),0)+binary)
 (p/'fat64.dylib').write_bytes(struct.pack('>IIiiQQII',0xcafebabf,1,0x100000c,0,40,len(binary),0,0)+binary)
 (p/'bad-fat.dylib').write_bytes(struct.pack('>IIiiIII',0xcafebabe,1,0x100000c,0,0xffffffff,len(binary),0)+binary)
 sources=['tests/TFBinaryIncomingTests.m','App/AI/Binary/TFAIBinary.m','App/AI/ClassDump/TFAIClassDump.m','App/AI/ClassDump/TFAIClassDumpExecution.m','App/Incoming/TFIncoming.m','App/Incoming/TFShareTransfer.m']
 subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-fblocks','-Wno-incompatible-pointer-types','-framework','Foundation',*[str(root/s) for s in sources],str(root/'build/classdump-macos/libtweakforge_classdump.a'),'-larchive','-liconv','-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),str(p)],check=True)
