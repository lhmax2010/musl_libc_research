/* micro.c - musl vs glibc quick demo probe (one-day edition)
 * subcommands: startup | threads N | malloc T ITERS | dns NAME | locale | mem
 * output: key=value lines, machine-parseable. all libc errors printed with errno+line.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <locale.h>
#include <langinfo.h>
#include <iconv.h>
#include <pthread.h>
#include <netdb.h>
#include <sys/socket.h>

#define DIE(msg) do{ fprintf(stderr,"FATAL %s errno=%d(%s) at %s:%d\n",(msg),errno,strerror(errno),__FILE__,__LINE__); _exit(2);}while(0)

static uint64_t now_ns(void){
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts)) DIE("clock_gettime");
    return (uint64_t)ts.tv_sec*1000000000ull + (uint64_t)ts.tv_nsec;
}

static void print_status_fields(void){
    FILE *f = fopen("/proc/self/status","r");
    if (!f) DIE("open /proc/self/status");
    char line[256];
    while (fgets(line,sizeof line,f)){
        if (!strncmp(line,"VmSize",6)||!strncmp(line,"VmRSS",5)||
            !strncmp(line,"VmData",6)||!strncmp(line,"Threads",7)){
            line[strcspn(line,"\n")]=0;
            char *p=line; for(char*q=line;*q;q++) if(*q=='\t'||*q==' ') ; /* keep raw */
            printf("status.%s\n", p);
        }
    }
    fclose(f);
}

/* ---------- threads ---------- */
static pthread_barrier_t g_bar;
static void* thr_wait(void *arg){ (void)arg; pthread_barrier_wait(&g_bar); for(;;) pause(); return NULL; }

static int cmd_threads(int n){
    if (pthread_barrier_init(&g_bar,NULL,(unsigned)n+1)) DIE("barrier_init");
    pthread_t *t = calloc((size_t)n,sizeof *t);
    if(!t) DIE("calloc");
    int created=0;
    for (int i=0;i<n;i++){
        int rc = pthread_create(&t[i],NULL,thr_wait,NULL);
        if (rc){ printf("threads.create_failed_at=%d rc=%d\n", i, rc); break; }
        created++;
    }
    printf("threads.requested=%d\nthreads.created=%d\n", n, created);
    if (created==n) pthread_barrier_wait(&g_bar);
    print_status_fields();
    fflush(stdout);
    _exit(0);
}

/* ---------- malloc ---------- */
#define SLOTS 1024
static const size_t g_classes[] = {16,32,64,128,256,512,1024,2048,4096,8192,16384,32768,65536};
#define NCLASSES (sizeof g_classes / sizeof g_classes[0])

typedef struct { int iters; uint32_t seed; uint64_t ns; uint64_t sum; } warg_t;
static pthread_barrier_t m_bar;

static inline uint32_t xs32(uint32_t *s){ uint32_t x=*s; x^=x<<13; x^=x>>17; x^=x<<5; return *s=x; }

static void* malloc_worker(void *ap){
    warg_t *a = ap;
    void *slot[SLOTS]; size_t ssz[SLOTS];
    memset(slot,0,sizeof slot);
    uint32_t s = a->seed;
    uint64_t chk = 0;
    pthread_barrier_wait(&m_bar);
    uint64_t t0 = now_ns();
    for (int i=0;i<a->iters;i++){
        uint32_t r = xs32(&s);
        int idx = (int)(r % SLOTS);
        if (slot[idx]){ chk += ((unsigned char*)slot[idx])[0]; free(slot[idx]); slot[idx]=NULL; }
        else {
            size_t sz = g_classes[(r>>10) % NCLASSES];  /* log-ish class pick */
            unsigned char *p = malloc(sz);
            if(!p) DIE("malloc");
            p[0]=(unsigned char)r; p[sz-1]=(unsigned char)(r>>8); /* allocator mode: first+last byte */
            slot[idx]=p; ssz[idx]=sz;
        }
    }
    a->ns = now_ns()-t0;
    for (int i=0;i<SLOTS;i++) if (slot[i]){ chk+=ssz[i]; free(slot[i]); }
    a->sum = chk;
    return NULL;
}

static int cmd_malloc(int nthr, int iters){
    if (pthread_barrier_init(&m_bar,NULL,(unsigned)nthr)) DIE("barrier_init");
    pthread_t t[64]; warg_t a[64];
    if (nthr<1||nthr>64) DIE("threads 1..64");
    for (int i=0;i<nthr;i++){ a[i].iters=iters; a[i].seed=0x9E3779B9u+(uint32_t)i*2654435761u; a[i].ns=0;
        if (pthread_create(&t[i],NULL,malloc_worker,&a[i])) DIE("pthread_create"); }
    uint64_t worst=0, sum=0, chk=0;
    for (int i=0;i<nthr;i++){ if (pthread_join(t[i],NULL)) DIE("join");
        sum+=a[i].ns; if(a[i].ns>worst) worst=a[i].ns; chk^=a[i].sum; }
    printf("malloc.threads=%d\nmalloc.iters_per_thread=%d\n", nthr, iters);
    printf("malloc.ns_per_op_mean=%.1f\n", (double)sum/((double)nthr*(double)iters));
    printf("malloc.wall_worst_thread_ns=%llu\n",(unsigned long long)worst);
    printf("malloc.checksum=%llx\n",(unsigned long long)chk); /* defeat DCE */
    return 0;
}

/* ---------- dns ---------- */
static int cmd_dns(const char *name){
    struct addrinfo hints, *res=NULL, *p;
    memset(&hints,0,sizeof hints);
    hints.ai_family=AF_UNSPEC; hints.ai_socktype=SOCK_STREAM;
    uint64_t t0=now_ns();
    int rc = getaddrinfo(name,NULL,&hints,&res);
    uint64_t dt=now_ns()-t0;
    printf("dns.name=%s\ndns.rc=%d\ndns.gai=%s\ndns.ns=%llu\n",
           name, rc, rc? gai_strerror(rc):"OK",(unsigned long long)dt);
    int n=0;
    for (p=res; p && n<4; p=p->ai_next, n++){
        char host[64]="?";
        getnameinfo(p->ai_addr,p->ai_addrlen,host,sizeof host,NULL,0,NI_NUMERICHOST);
        printf("dns.addr%d=%s fam=%d\n", n, host, p->ai_family);
    }
    if (res) freeaddrinfo(res);
    return rc?1:0;
}

/* ---------- locale ---------- */
static int cmd_locale(void){
    char *l = setlocale(LC_ALL,"");
    printf("locale.setlocale=%s\n", l?l:"NULL");
    printf("locale.codeset=%s\n", nl_langinfo(CODESET));
    time_t tt=1735689600; /* fixed date */
    struct tm tmv; localtime_r(&tt,&tmv);
    char buf[128];
    strftime(buf,sizeof buf,"%A %d %B",&tmv);
    printf("locale.strftime=%s\n", buf);
    int c1 = strcoll("\xe8\x8b\xb9\xe6\x9e\x9c","\xe9\xa6\x99\xe8\x95\x89"); /* 苹果 vs 香蕉 */
    printf("locale.strcoll_zh_sign=%d\n", (c1>0)-(c1<0));
    iconv_t a = iconv_open("EUC-KR","UTF-8");
    printf("locale.iconv_utf8_to_euckr=%s\n", a==(iconv_t)-1?"UNAVAILABLE":"OK");
    if (a!=(iconv_t)-1) iconv_close(a);
    iconv_t b = iconv_open("UTF-8","EUC-KR");
    printf("locale.iconv_euckr_to_utf8=%s\n", b==(iconv_t)-1?"UNAVAILABLE":"OK");
    if (b!=(iconv_t)-1) iconv_close(b);
    return 0;
}

int main(int argc, char **argv){
    if (argc==1){ printf("smoke=ok\n"); return 0; }
    if (argc>=2 && !strcmp(argv[1],"startup")) _exit(0); /* nothing before this on purpose */
    if (argc>=2 && !strcmp(argv[1],"mem")){ printf("mem.pid=%d\n",(int)getpid()); fflush(stdout); for(;;) pause(); }
    if (argc>=3 && !strcmp(argv[1],"threads")) return cmd_threads(atoi(argv[2]));
    if (argc>=4 && !strcmp(argv[1],"malloc"))  return cmd_malloc(atoi(argv[2]),atoi(argv[3]));
    if (argc>=3 && !strcmp(argv[1],"dns"))     return cmd_dns(argv[2]);
    if (argc>=2 && !strcmp(argv[1],"locale"))  return cmd_locale();
    fprintf(stderr,"usage: %s startup|mem|threads N|malloc T ITERS|dns NAME|locale\n",argv[0]);
    return 2;
}
