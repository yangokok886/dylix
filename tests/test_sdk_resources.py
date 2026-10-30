"""Exercise the actual native SDK extractor, corruption handling and ldid scan."""
import hashlib,json,pathlib,plistlib,shutil,subprocess,tempfile,zipfile
R=pathlib.Path(__file__).resolve().parents[1]
def run(*args,ok=True):
    p=subprocess.run(list(map(str,args)),capture_output=True,text=True)
    assert (p.returncode==0)==ok,(args,p.returncode,p.stderr)
    return p.stdout.strip()
with tempfile.TemporaryDirectory(prefix='tf80-sdk-') as tmp:
    t=pathlib.Path(tmp);exe=t/'sdk-test'
    run('xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-framework','Foundation','-larchive',R/'tests/SDKResourcesHarness.m',R/'App/SDKResources.m',R/'App/ArchiveImport.m',R/'App/TheosMakefile.m','-o',exe)
    app=t/'Fixture.app';app.mkdir()
    (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.sdk.fixture','CFBundlePackageType':'APPL'}))
    built=R/'build/device/TheosMobileCompiler.app'
    for name in ['SDK.zip','SDKResource.plist']:shutil.copy2(built/name,app/name)
    cache=t/'cache';path=pathlib.Path(run(exe,app,cache));marker=path/'.complete'
    stamp=marker.stat().st_mtime_ns
    assert run(exe,app,cache)==str(path) and marker.stat().st_mtime_ns==stamp
    checked=0
    with zipfile.ZipFile(app/'SDK.zip') as z:
        for info in z.infolist():
            if any(part=='.DS_Store' or part=='__MACOSX' or part.startswith('._') for part in pathlib.PurePosixPath(info.filename).parts):continue
            assert (path/info.filename).read_bytes()==z.read(info),info.filename
            checked+=1
    marker.unlink();assert run(exe,app,cache)==str(path) and marker.exists()
    # Purged caches are reconstructed; malformed/mismatched resources fail closed.
    shutil.rmtree(cache);assert run(exe,app,cache)==str(path)
    shutil.rmtree(cache);raw=(app/'SDK.zip').read_bytes();(app/'SDK.zip').write_bytes(raw[:-32]);run(exe,app,cache,ok=False)
    (app/'SDK.zip').write_bytes(raw);(app/'SDKResource.plist').write_bytes(plistlib.dumps({'sha256':'../invalid'}));run(exe,app,cache,ok=False)
    # Reproduce the original signer failure, then scan the fixed whole app.
    old=t/'old';old.mkdir()
    with zipfile.ZipFile(R/'build/TweakForge-1.0.1-build79-unsigned.ipa') as z:z.extractall(old)
    run('ldid','-S',old/'Payload/TheosMobileCompiler.app',ok=False)
    fixed=t/'fixed';shutil.copytree(built,fixed/'TheosMobileCompiler.app')
    run('ldid','-S',fixed/'TheosMobileCompiler.app')
    # Verify the deliverable's Apple ad-hoc signature, before third-party signing.
    # macOS codesign is not a verifier for every ldid/iOS signature format.
    run('codesign','--verify','--deep','--strict',built)
    result={'passed':True,'sdkFilesByteCompared':checked,'cacheReuse':True,'interruptedRecovery':True,'purgedCacheRecovery':True,'corruptArchiveRejected':True,'invalidManifestRejected':True,'oldIPAReproducesLdidFailure':True,'newBundleLdidSigning':True,'deliverableCodesignVerification':True,'signer':'local ldid -S whole bundle; TrollStore device installation still pending'}
    out=R/'evidence/1.0.1-build80-trollstore';out.mkdir(parents=True,exist_ok=True);(out/'sdk-signing-tests.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
