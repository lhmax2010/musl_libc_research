#include "rpmalloc.h"

static void __attribute__((constructor))
initialize_rpmalloc_process(void) {
    rpmalloc_initialize();
}
