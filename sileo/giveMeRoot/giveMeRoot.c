#import <stdint.h>
#import <stdlib.h>
#import <stdio.h>
#import <unistd.h>
#import <string.h>
#import <sys/syslimits.h>
#import <sys/stat.h>
#import <sysexits.h>
#include <dlfcn.h>

extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
#define PROC_PIDPATHINFO_MAXSIZE  (1024)
/* Set platform binary flag */
#define FLAG_PLATFORMIZE (1 << 1)


const char *getBuildtimeAppPath(void) {
    const char *path = NULL;
#ifndef MAC
    
#ifdef PREBOOT
    
#ifdef NIGHTLY
    path = "/var/jb/Applications/Sileo-Nightly.app/Sileo-Preboot";
#elif BETA
    path = "/var/jb/Applications/Sileo-Beta.app/Sileo-Preboot";
#else
    path = "/var/jb/Applications/Sileo.app/Sileo-Preboot";
#endif
    
#else
    
#ifdef NIGHTLY
    path = "/Applications/Sileo-Nightly.app/Sileo";
#elif BETA
    path = "/Applications/Sileo-Beta.app/Sileo";
#else
    path = "/Applications/Sileo.app/Sileo";
#endif
    
#endif
    
#endif
    
    return path;
}

void patch_setuid() {
    void* handle = dlopen("/usr/lib/libjailbreak.dylib", RTLD_LAZY);
    if (!handle) return;
    
    // Reset errors
    dlerror();
    
    typedef void (*fix_setuid_prt_t)(pid_t pid);
    fix_setuid_prt_t ptr = (fix_setuid_prt_t)dlsym(handle, "jb_oneshot_fix_setuid_now");
    
    ptr(getpid());
    
    setuid(0);
}

char *copyRuntimeAppPath(void) {
    const char *buildtimePath = getBuildtimeAppPath();
    if (buildtimePath == NULL) {
        return NULL;
    }
    return realpath(buildtimePath, NULL);
}

int main(int argc, const char *argv[]) {
    int retval = 0;
    
    char *sileoAppPath = NULL;
    char *parentPath = NULL;
    
#ifndef MAC
    pid_t parentPID = getppid();
    size_t parentPathSize = PATH_MAX;
    parentPath = calloc(parentPathSize, sizeof(char));
    if (parentPath != NULL) {
        proc_pidpath(parentPID, parentPath, parentPathSize);
    }
#endif
    
    patch_setuid();
    
    setuid(0);
    setgid(0);
    
    retval = 0;
    
end:
    if (sileoAppPath != NULL) {
        free(sileoAppPath);
    }
    if (parentPath != NULL) {
        free(parentPath);
    }
    
    if (retval == 0) {
        if (argc < 2) {
            return 0;
        }
        
        if (strcmp(argv[1], "whoami") == 0) {
            printf("root\n");
            return 0;
        }
        
        const char **remainingArgs = (const char **)((uintptr_t)argv + (1 * sizeof(char *)));
        execv(remainingArgs[0], (char **)remainingArgs);
        
        fprintf(stderr, "Error: failed to execv specified task");
        return EX_OSERR;
    }
    else {
        return retval;
    }
}
