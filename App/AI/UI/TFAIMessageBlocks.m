#import "TFAIMessageBlocks.h"
static NSArray *Cells(NSString *line){
 NSString *s=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];NSMutableArray *cells=[NSMutableArray new];NSMutableString *cell=[NSMutableString new];BOOL escape=NO;NSUInteger ticks=0;
 if([s hasPrefix:@"|"])s=[s substringFromIndex:1];if([s hasSuffix:@"|"]&&![s hasSuffix:@"\\|"])s=[s substringToIndex:s.length-1];
 for(NSUInteger i=0;i<s.length;i++){unichar c=[s characterAtIndex:i];if(escape){if(c!='|')[cell appendString:@"\\"];[cell appendFormat:@"%C",c];escape=NO;continue;}if(c=='\\'){escape=YES;continue;}if(c=='`')ticks^=1;if(c=='|'&&!ticks){[cells addObject:[cell stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];[cell setString:@""];}else [cell appendFormat:@"%C",c];}
 if(escape)[cell appendString:@"\\"];[cells addObject:[cell stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];return cells;
}
static BOOL Separator(NSString *line,NSUInteger columns){NSArray *cells=Cells(line);if(cells.count!=columns||columns<2)return NO;NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"^:?-{3,}:?$" options:0 error:nil];for(NSString *c in cells)if(![rx firstMatchInString:c options:0 range:NSMakeRange(0,c.length)])return NO;return YES;}
static void Flush(NSMutableArray *out,NSMutableString *text){if(text.length){[out addObject:@{@"kind":@"text",@"text":[text copy]}];[text setString:@""];}}
static NSArray<NSDictionary *> *AIParseMessageBlocks(NSString *source){
 if(![source isKindOfClass:NSString.class])return @[];NSArray *lines=[source componentsSeparatedByString:@"\n"];NSMutableArray *out=[NSMutableArray new];NSMutableString *text=[NSMutableString new];NSUInteger i=0;
 while(i<lines.count){NSString *line=lines[i],*trim=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];NSString *fence=[trim hasPrefix:@"````"]?@"````":[trim hasPrefix:@"```"]?@"```":nil;
  if(fence){Flush(out,text);NSString *language=[[trim substringFromIndex:fence.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];NSMutableString *code=[NSMutableString new];i++;while(i<lines.count){NSString *next=lines[i];NSString *t=[next stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if([t hasPrefix:fence]&&[[t substringFromIndex:fence.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length==0){i++;break;}[code appendString:next];if(i+1<lines.count)[code appendString:@"\n"];i++;}[out addObject:@{@"kind":@"code",@"language":language,@"text":code}];continue;}
  NSArray *header=Cells(line);if(i+1<lines.count&&header.count>=2&&[line containsString:@"|"]&&Separator(lines[i+1],header.count)){
   Flush(out,text);NSMutableArray *rows=[NSMutableArray new];i+=2;while(i<lines.count){NSString *next=lines[i];NSArray *row=Cells(next);if(![next containsString:@"|"]||row.count!=header.count)break;[rows addObject:row];i++;}[out addObject:@{@"kind":@"table",@"header":header,@"rows":rows}];continue;
  }
  if(!trim.length){Flush(out,text);i++;continue;}
  [text appendString:line];if(i+1<lines.count)[text appendString:@"\n"];i++;
 }
 Flush(out,text);return out;
}

NSArray<NSDictionary *> *TFAIMessageBlocks(NSString *source){
 if(![source isKindOfClass:NSString.class])return @[];static NSCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.totalCostLimit=4*1024*1024;cache.countLimit=256;});NSArray *parts=[cache objectForKey:source];if(!parts){parts=AIParseMessageBlocks(source);[cache setObject:parts forKey:source cost:source.length*4+parts.count*96];}return parts;
}
