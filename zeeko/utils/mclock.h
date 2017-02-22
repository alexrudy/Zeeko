#include <time.h>
#include <sys/time.h>
#include <stdio.h>

#ifdef __MACH__
#include <Availability.h>
#endif

#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
#if __MAC_OS_X_VERSION_MAX_ALLOWED < 101200
#include <time.h>
#include <mach/mach_time.h>
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 0
int clock_gettime(int clk_id, struct timespec *t){
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    uint64_t time;
    time = mach_absolute_time();
    double nseconds = ((double)time * (double)timebase.numer)/((double)timebase.denom);
    double seconds = ((double)time * (double)timebase.numer)/((double)timebase.denom * 1.0e9);
    t->tv_sec = seconds;
    t->tv_nsec = nseconds - (t->tv_sec * 1.0e9);
    return 0;
}
#endif
#endif

void current_utc_time(struct timespec *ts) {
  clock_gettime(CLOCK_MONOTONIC, ts);
}
