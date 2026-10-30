from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf-runtime-budget-') as temp:
    temp=Path(temp);(temp/'UIKit').mkdir()
    (temp/'UIKit/UIKit.h').write_text('#import <Foundation/Foundation.h>\n@class UIViewController;\nextern NSString *UIApplicationDidEnterBackgroundNotification;\n')
    binary=temp/'tests'
    subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-I'+str(temp),'-fobjc-arc','-fblocks','-Wno-incomplete-implementation','-Wno-nullability-completeness',str(root/'tests/AIRuntimeBudgetTests.m'),str(root/'App/AI/Core/TFAIRecovery.m'),'-framework','Foundation','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
# Lifecycle regression guards: navigation must not be treated as stop/background.
chat=(root/'App/AI/UI/TFAIChat.m').read_text()
workspace=(root/'App/Studio.m').read_text().split('@implementation TFAIProjectWorkspace',1)[1].split('@end',1)[0]
disappear=chat.split('- (void)viewWillDisappear:',1)[1].split('\n- ',1)[0]
assert 'runtime stop' not in disappear
assert '[self.chat background]' not in workspace
assert 'cell.openFile=^(NSString *path,NSUInteger line){[weak.runtime stop]' not in chat
assert 'TFAIActiveChats()[self.activeKey]=self' in chat
assert 'if(active)' in chat and 'return active;' in chat
assert 'v.pendingApproval=show' in chat
assert 'TFAISetProjectContext(chat,self,' in (root/'App/Studio.m').read_text()
print('PASS 7 navigation lifecycle regression guards')
