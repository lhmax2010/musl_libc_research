/* timer.c - fork+exec wall time of a child, ns resolution. build with glibc only. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sys/wait.h>

static uint64_t now_ns(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts);
    return (uint64_t)ts.tv_sec*1000000000ull+(uint64_t)ts.tv_nsec;
}
int main(int argc, char **argv){
    if (argc<2){ fprintf(stderr,"usage: timer <prog> [args...]\n"); return 2; }
    uint64_t t0=now_ns();
    pid_t pid=fork();
    if (pid<0){ perror("fork"); return 2; }
    if (pid==0){ execv(argv[1],&argv[1]); _exit(127); }
    int st=0;
    while (waitpid(pid,&st,0)<0){ if(errno!=EINTR){ perror("waitpid"); return 2; } }
    uint64_t dt=now_ns()-t0;
    if (!WIFEXITED(st)||WEXITSTATUS(st)!=0){ fprintf(stderr,"child_bad_status=%d\n",st); return 1; }
    printf("%llu\n",(unsigned long long)dt);
    return 0;
}
