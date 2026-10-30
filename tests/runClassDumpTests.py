#!/usr/bin/env python3
import pathlib,tempfile,subprocess,zipfile,struct
root=pathlib.Path(__file__).resolve().parents[1]
import contextlib,os
with (contextlib.nullcontext(tempfile.mkdtemp(prefix='tf-classdump-debug-')) if os.getenv('TF_CLASSDUMP_DEBUG') else tempfile.TemporaryDirectory(prefix='tf-classdump-test-')) as temp:
    d=pathlib.Path(temp)
    subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-dynamiclib','-Wl,-no_objc_category_merging','-framework','Foundation',str(root/'tests/TFClassDumpFixture.m'),'-o',str(d/'fixture.dylib')],check=True)
    binary=(d/'fixture.dylib').read_bytes()
    with zipfile.ZipFile(d/'fixture.ipa','w') as z:
        z.writestr('Payload/Fixture.app/Fixture',binary)
        z.writestr('Payload/Fixture.app/Frameworks/Extras.framework/Extras',binary)
        z.writestr('Payload/Fixture.app/Resource.txt','hello')
    with zipfile.ZipFile(d/'nested.ipa','w') as z:
        z.writestr('Payload/Fixture.app/PlugIns/Test.appex/Test',binary)
        z.writestr('Payload/Fixture.app/Frameworks/Outer.framework/Frameworks/Extras.framework/Extras',binary)
    with (d/'large.dylib').open('wb') as f:
        f.write(binary);f.truncate(769*1024*1024)
    with zipfile.ZipFile(d/'bad.ipa','w') as z:z.writestr('../evil','bad')
    # Valid minimal ARM64 image carrying an encrypted LC_ENCRYPTION_INFO_64.
    (d/'encrypted.dylib').write_bytes(struct.pack('<8I',0xfeedfacf,0x100000c,0,6,1,24,0,0)+struct.pack('<6I',0x2c,24,0,0,1,0))
    (d/'truncated.dylib').write_bytes(binary[:40])
    exe=d/'tests'
    subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-fblocks','-Wno-incompatible-pointer-types','-framework','Foundation',str(root/'tests/TFClassDumpTests.m'),str(root/'App/AI/ClassDump/TFAIClassDump.m'),str(root/'App/AI/ClassDump/TFAIClassDumpExecution.m'),str(root/'build/classdump-macos/libtweakforge_classdump.a'),'-larchive','-liconv','-o',str(exe)],check=True)
    subprocess.run(['env','NSUnbufferedIO=YES',str(exe),str(d)],check=True)
    with zipfile.ZipFile(d/'export.zip') as z: assert 'index.json' in z.namelist()
