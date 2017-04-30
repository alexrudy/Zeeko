#pragma once

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
int clock_gettime(int clk_id, struct timespec *ts){
    
    clock_serv_t cclock;
    mach_timespec_t mts;
    host_get_clock_service(mach_host_self(), CALENDAR_CLOCK, &cclock);
    clock_get_time(cclock, &mts);
    mach_port_deallocate(mach_task_self(), cclock);
    ts->tv_sec = mts.tv_sec;
    ts->tv_nsec = mts.tv_nsec;
    //
    // mach_timebase_info_data_t timebase;
    // mach_timebase_info(&timebase);
    // uint64_t time;
    // time = mach_absolute_time();
    // double nseconds = ((double)time * (double)timebase.numer)/((double)timebase.denom);
    // double seconds = ((double)time * (double)timebase.numer)/((double)timebase.denom * 1.0e9);
    // t->tv_sec = seconds;
    // t->tv_nsec = nseconds - (t->tv_sec * 1.0e9);
    return 0;
}
#else
#define __GETTIME_MACH
void current_utc_time(struct timespec *ts) {
  struct timeval tv;
  clock_gettime(CLOCK_REALTIME, &tv);
  ts->tv_sec = tv.tv_sec;
  ts->tv_nsec = tv.tv_usec * 1000;
}
#endif
#endif

#ifndef __GETTIME_MACH
void current_utc_time(struct timespec *ts) {
  clock_gettime(CLOCK_REALTIME, ts);
}
#endif
