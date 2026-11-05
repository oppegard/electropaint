#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct EPState EPState;
typedef struct { float position[4]; float color[4]; } EPVertex;
typedef struct { unsigned first, count; int lines; } EPBatch;
typedef struct {
    EPVertex vertices[4096];
    EPBatch batches[512];
    unsigned vertexCount, batchCount;
} EPFrame;

typedef struct {
    double maxSpinDegreesPerSecond, maxFlipDegreesPerSecond;
} EPMotionLimits;

extern const EPMotionLimits EPDefaultMotionLimits;
extern const EPMotionLimits EPMaximumMotionLimits;

/* New engines use the original script maxima. Zero stops only that axis.
   Reject nonfinite, negative or above-maximum limits without changing either.
   Accepted limits affect future steps and preserve existing trail samples. */
EPState *ep_create(uint32_t seed);
bool ep_set_motion_limits(EPState *state, EPMotionLimits limits);
void ep_destroy(EPState *state);
const EPFrame *ep_step(EPState *state, int width, int height);

/* Draw between the last two steps without advancing script, RNG or history.
   Call after ep_step; returned frame storage is reused by either operation. */
const EPFrame *ep_render(EPState *state, int width, int height, float fraction);
