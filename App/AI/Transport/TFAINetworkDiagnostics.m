#import "TFAINetworkDiagnostics.h"
NSDictionary *TFAINetworkFailureDetails(NSError *error,NSURLRequest *request,NSURLSessionConfiguration *config){
 NSMutableDictionary *out=[NSMutableDictionary new];
 if(request)out[@"requestPolicy"]=@{@"allowsCellular":@(request.allowsCellularAccess),@"allowsExpensive":@(request.allowsExpensiveNetworkAccess),@"allowsConstrained":@(request.allowsConstrainedNetworkAccess)};
 if(config)out[@"sessionPolicy"]=@{@"allowsCellular":@(config.allowsCellularAccess),@"allowsExpensive":@(config.allowsExpensiveNetworkAccess),@"allowsConstrained":@(config.allowsConstrainedNetworkAccess),@"waitsForConnectivity":@(config.waitsForConnectivity)};
 NSMutableArray *chain=[NSMutableArray new];NSError *current=error;
 for(NSUInteger i=0;current&&i<5;i++){
  NSMutableDictionary *item=[@{@"domain":current.domain,@"code":@(current.code)} mutableCopy];
  NSNumber *reason=current.userInfo[NSURLErrorNetworkUnavailableReasonKey];
  if([reason isKindOfClass:NSNumber.class]){item[@"unavailableReasonCode"]=reason;item[@"unavailableReason"]=@{@0:@"当前请求不允许使用蜂窝网络",@1:@"当前请求不允许使用昂贵网络",@2:@"当前请求不允许使用低数据模式网络"}[reason]?:@"系统返回其他网络约束原因";}
  // Read a diagnostic string already supplied by CFNetwork, without private API calls.
  id path=current.userInfo[@"_NSURLErrorNWPathKey"];
  if(path){NSString *description=[path description];if(description.length)item[@"path"]=[description substringToIndex:MIN(2048,description.length)];}
  for(NSString *key in @[@"_kCFStreamErrorDomainKey",@"_kCFStreamErrorCodeKey"]){id value=current.userInfo[key];if([value isKindOfClass:NSNumber.class])item[key]=value;}
  [chain addObject:item];id next=current.userInfo[NSUnderlyingErrorKey];current=[next isKindOfClass:NSError.class]?next:nil;
 }
 out[@"errorChain"]=chain;return out;
}
