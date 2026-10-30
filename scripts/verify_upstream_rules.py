#!/usr/bin/env python3
"""Build isolated rule probes and run regressions without launching the app UI.
Requires Xcode, a booted simulator and the existing x86_64 simulator frameworks.
Does not rebuild, install, terminate or alter the TweakForge app.
"""
import argparse,os,pathlib,subprocess,sys,tempfile
R=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--mac-include',type=pathlib.Path);args=p.parse_args()
frameworks=R/'build/simulator/TheosMobileCompiler.app/Frameworks'
for name in ['ios_system','libLLVM','clang']:
 if not (frameworks/(name+'.framework')/name).is_file():p.error('Build the existing simulator frameworks first: missing '+name)
def run(argv,env=None):
 subprocess.run(list(map(str,argv)),env=env,check=True)
with tempfile.TemporaryDirectory(prefix='tmc-rule-probes-') as tmp:
 work=pathlib.Path(tmp);cli=work/'rules-cli';probe=work/'clang-probe'
 common=['-fobjc-arc','-fmodules','-fmodules-cache-path='+str(work/'module-cache')]
 mac=['xcrun','--sdk','macosx','clang',*common]
 if args.mac_include:mac+=['-I'+str(args.mac_include)]
 run([*mac,'-framework','Foundation',R/'tests/CompatibilityRepairCLI.m',R/'App/CompatibilityRepair.m','-o',cli])
 run(['xcrun','--sdk','iphonesimulator','clang','-arch','x86_64','-mios-simulator-version-min=15.0',*common,'-F',frameworks,'-framework','Foundation','-framework','ios_system','-Wl,-needed_framework,libLLVM','-Wl,-rpath,'+str(frameworks),R/'tests/EmbeddedClangRuleProbe.m','-o',probe])
 env=dict(os.environ,TMC_RULE_CLI=str(cli),TMC_EMBEDDED_PROBE=str(probe),TMC_RULES_PATH=str(R/'Resources/CompatibilityRules/rules.json'))
 for name in ['test_rule_library.py','test_compatibility_repair.py','test_upstream_rule_library.py']:
  run([sys.executable,R/'tests'/name],env=env)
 run(['xcrun','--sdk','iphoneos','clang','-arch','arm64','-miphoneos-version-min=15.0',*common,'-fsyntax-only',R/'App/CompatibilityRepair.m'])
print('Upstream rule verification complete; app UI/install/build outputs were not changed.')
