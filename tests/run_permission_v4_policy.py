#!/usr/bin/env python3
"""Compile and execute local-only policy regression without an iOS device."""
from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
cli_sdk = Path('/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk')
sdk = str(cli_sdk) if cli_sdk.exists() else subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
with tempfile.TemporaryDirectory(prefix='tweakforge-permission-v4-') as work:
    work = Path(work)
    include = json.dumps(str(root / 'tests/AIPermissionV4Regression.inc'), ensure_ascii=False)
    main = work / 'main.m'
    main.write_text('''#import <Foundation/Foundation.h>
#import ''' + include + '''
int main(void){@autoreleasepool{__block NSUInteger count=0,fail=0;
TFAIPermissionV4PolicyRegression(^(BOOL ok,NSString *name){count++;if(!ok)fail++;
printf("%s %s\\n",ok?"PASS":"FAIL",name.UTF8String);});
printf("RESULT %lu checks %lu failures\\n",(unsigned long)count,(unsigned long)fail);return fail?1:0;}}
''')
    output = work / 'permission-v4'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-isysroot', sdk, '-framework', 'Foundation', str(main), str(root / 'App/AI/Core/AIPolicy.m'), str(root / 'App/AI/Permissions/TFAIPolicy.m'), '-o', str(output)], check=True)
    subprocess.run([str(output)], check=True)
