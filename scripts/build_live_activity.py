#!/usr/bin/env python3
"""Build a compact ActivityKit widget with the installed Swift SDK (16.2+)."""
import argparse, pathlib, plistlib, subprocess
p=argparse.ArgumentParser();p.add_argument('--app',type=pathlib.Path,required=True);p.add_argument('--simulator',action='store_true');p.add_argument('--build',required=True);p.add_argument('--identity',default='-');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];app=a.app
sdkname='iphonesimulator' if a.simulator else 'iphoneos'
sdk=subprocess.check_output(['xcrun','--sdk',sdkname,'--show-sdk-path'],text=True).strip()
arch='x86_64' if a.simulator else 'arm64';target=arch+'-apple-ios16.2'+('-simulator' if a.simulator else '')
framework=app/'Frameworks/TFTaskActivity.framework';framework.mkdir(parents=True,exist_ok=True)
modules=framework/'Modules/TFTaskActivity.swiftmodule';modules.mkdir(parents=True,exist_ok=True)
(framework/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'TFTaskActivity','CFBundleIdentifier':'com.xuegao.tweakforge.activity.framework','CFBundleName':'TFTaskActivity','CFBundlePackageType':'FMWK','CFBundleVersion':a.build,'CFBundleShortVersionString':'1.0.4','MinimumOSVersion':'16.2'}))
base=['xcrun','--sdk',sdkname,'swiftc','-swift-version','5','-O','-target',target,'-sdk',sdk]
subprocess.run(base+['-emit-library','-emit-module','-module-name','TFTaskActivity','-emit-module-path',str(modules/(arch+'.swiftmodule')),'-Xlinker','-install_name','-Xlinker','@rpath/TFTaskActivity.framework/TFTaskActivity','-o',str(framework/'TFTaskActivity'),str(root/'App/AI/LiveActivity/TFTaskActivity.swift')],check=True)
widget=app/'PlugIns/TweakForgeActivity.appex';widget.mkdir(parents=True,exist_ok=True)
(widget/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'TweakForgeActivity','CFBundleIdentifier':'com.xuegao.theosmobilecompiler.activity','CFBundleName':'TweakForgeActivity','CFBundleDisplayName':'Dylix AI','CFBundlePackageType':'XPC!','CFBundleVersion':a.build,'CFBundleShortVersionString':'1.0.4','MinimumOSVersion':'16.2','UIDeviceFamily':[1,2],'NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}))
subprocess.run(base+['-application-extension','-Xlinker','-e','-Xlinker','_NSExtensionMain','-parse-as-library','-module-name','TFActivityWidget','-F',str(app/'Frameworks'),'-framework','TFTaskActivity','-Xlinker','-rpath','-Xlinker','@executable_path/../../Frameworks','-o',str(widget/'TweakForgeActivity'),str(root/'LiveActivityExtension/TFActivityWidget.swift')],check=True)
# Bundle Swift back-deployment support libraries used by the framework/widget.
subprocess.run(['xcrun','swift-stdlib-tool','--copy','--scan-executable',str(framework/'TFTaskActivity'),'--scan-executable',str(widget/'TweakForgeActivity'),'--platform',sdkname,'--destination',str(app/'Frameworks')],check=True)
for lib in (app/'Frameworks').glob('libswift*.dylib'):subprocess.run(['codesign','--force','--sign',a.identity,str(lib)],check=True)
for bundle in [framework,widget]:subprocess.run(['codesign','--force','--sign',a.identity,str(bundle)],check=True)
