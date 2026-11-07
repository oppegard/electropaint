#include "EPAdapter.c"
#include "settings-test-support.h"

EPMotionTestState ep_test_motion_state(EPState *state) {
    return (EPMotionTestState){state->motionLimits, state->canonicalFrames, state->random};
}
