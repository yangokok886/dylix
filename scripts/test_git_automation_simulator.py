#!/usr/bin/env python3
"""Native UIKit/Keychain/dispatch regression. Launches a disposable fixture in the test app."""
import pathlib,subprocess,time,json
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'evidence/0.6.3-git-automation';OUT.mkdir(parents=True,exist_ok=True)
BUNDLE='com.xuegao.theosmobilecompiler'
def command(*args):return subprocess.check_output(args,text=True).strip()
command('xcrun','simctl','install','booted',str(ROOT/'build/simulator/TheosMobileCompiler.app'))
data=pathlib.Path(command('xcrun','simctl','get_app_container','booted',BUNDLE,'data'));report=data/'Documents/git-automation-test.json'
if report.exists():report.unlink()
command('xcrun','simctl','launch','--terminate-running-process','booted',BUNDLE,'--git-automation-test','--git-test')
deadline=time.monotonic()+58
while time.monotonic()<deadline and not report.exists():time.sleep(.4)
assert report.exists(),'native automation fixture did not finish'
r=json.loads(report.read_text());(OUT/'ios-runtime.json').write_text(json.dumps(r,ensure_ascii=False,indent=2));assert r['passed'],r
print(f"iOS automatic archive + Keychain: {r['count']} checks passed")
