#pragma once
#include <math.h>
#include <stdbool.h>

typedef struct { double last, remainder; bool anchored; } EPClock;
typedef struct { unsigned steps; float fraction; } EPClockUpdate;

static inline EPClockUpdate ep_clock_advance(EPClock *clock, double timestamp) {
    if (!clock->anchored) {
        clock->last = timestamp;
        clock->anchored = true;
    }
    double elapsed = fmax(0, timestamp - clock->last);
    if (timestamp > clock->last) clock->last = timestamp;
    clock->remainder += fmin(elapsed, 8.0 / 60.0);
    unsigned steps = (unsigned)floor(clock->remainder * 60.0 + 1e-8);
    clock->remainder = fmax(0, clock->remainder - steps / 60.0);
    return (EPClockUpdate){steps, (float)(clock->remainder * 60.0)};
}
static inline void ep_clock_pause(EPClock *clock) { clock->anchored = false; }
