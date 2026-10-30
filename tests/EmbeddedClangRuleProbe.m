// Isolated simulator CLI probe. Uses the same cc1 ABI as the app, without opening UI.
#import <Foundation/Foundation.h>
#import <ios_system/ios_system.h>
#import <dlfcn.h>
#import <pthread.h>
#import <unistd.h>
typedef struct {const char *const *data;size_t size;} Argv;
static int (*cc1)(Argv,const char *,void *);
static int probeArgc,probeStatus=-999;static char **probeArgv;
static void finish(void *unused){if(probeStatus==-999)probeStatus=ios_getCommandStatus();fflush(thread_stdout);fflush(thread_stderr);}
static void *invoke(void *unused){@autoreleasepool{
 FILE *in=fopen("/dev/null","r"),*out=fdopen(dup(1),"w"),*err=fdopen(dup(2),"w");
 ios_switchSession(&probeStatus);ios_setStreams(in,out,err);
 thread_stdin=in;thread_stdout=out;thread_stderr=err;
 Argv args={(const char *const *)probeArgv+1,(size_t)probeArgc-1};
 pthread_cleanup_push(finish,NULL);probeStatus=cc1(args,probeArgv[0],(void *)cc1);pthread_cleanup_pop(1);
 fflush(out);fflush(err);
 }return NULL;
}
int main(int argc,char **argv){@autoreleasepool{
 thread_stdin=fopen("/dev/null","r");thread_stdout=fdopen(dup(1),"w");thread_stderr=fdopen(dup(2),"w");if(argc<3)return 2;NSString *frameworks=@(argv[1]);
 // No command registration or UIApplication environment is needed for direct cc1.
 for(NSString *name in @[@"libLLVM",@"clang"]){NSString *path=[frameworks stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework/%@",name,name]];void *handle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_GLOBAL);if(!handle){fprintf(stderr,"%s\n",dlerror());return 127;}if([name isEqual:@"clang"])cc1=dlsym(handle,"_Z8cc1_mainN4llvm8ArrayRefIPKcEES2_Pv");}
 if(!cc1)return 127;probeArgc=argc-1;probeArgv=argv+1;probeArgv[0]="clang";
 pthread_t worker;int status=pthread_create(&worker,NULL,invoke,NULL);if(status)return 127;pthread_join(worker,NULL);return probeStatus;
}}
