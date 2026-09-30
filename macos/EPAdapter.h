#pragma once
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

EPState *ep_create(uint32_t seed);
void ep_destroy(EPState *state);
const EPFrame *ep_step(EPState *state, int width, int height);
