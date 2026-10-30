#import <UIKit/UIKit.h>
UIViewController *TMCStudioHome(void);
#if TARGET_OS_SIMULATOR
UIViewController *TMCStudioSettingsRegression(void);
UIViewController *TMCStudioFileActionsRegression(void);
UIViewController *TMCStudioEditorRegression(void);
UIViewController *TMCStudioDiagnosticJumpRegression(void);
UIViewController *TMCStudioBuildPreferencesRegression(void);
UIViewController *TMCStudioProjectSettingsRegression(void);
UIViewController *TMCStudioRepairRegression(void);
UIViewController *TMCStudioAboutRegression(void);
#endif

#if TARGET_OS_SIMULATOR
UIViewController *TMCMaintenanceRegression(void);
#endif

#if TARGET_OS_SIMULATOR
UIViewController *TFAIIntegrationRegression(void);
#endif

#if TARGET_OS_SIMULATOR
UIViewController *TFAIVisualRegression(void);
UIViewController *TFAIChat93Regression(void);
UIViewController *TFAIControlsVisualRegression(void);
UIViewController *TFAIProbeVisualRegression(void);
UIViewController *TFAIApprovalVisualRegression(void);
#endif

UIViewController *TMCStudioRoot(void);

#if TARGET_OS_SIMULATOR
UIViewController *TFAIV2Regression(void);
UIViewController *TFAIRecovery110Regression(void);
UIViewController *TFAIAudio110Regression(void);
UIViewController *TFAIAttachments108Regression(void);
#endif

void TMCOpenAIConversation(UIViewController *root,NSString *sessionID,NSString *projectID);

UIViewController *TMCStudioSDKRegression(void);
