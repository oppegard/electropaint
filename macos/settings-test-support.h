#pragma once
#include "EPAdapter.h"

typedef struct {
    EPMotionLimits limits;
    unsigned frames;
    uint64_t random;
} EPMotionTestState;

EPMotionTestState ep_test_motion_state(EPState *state);
