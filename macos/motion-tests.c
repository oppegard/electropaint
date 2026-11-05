#include "EPAdapter.c"
#include <stdio.h>

static void equal_frames(const EPFrame *a, const EPFrame *b) {
    assert(a->vertexCount == b->vertexCount && a->batchCount == b->batchCount);
    assert(!memcmp(a->vertices, b->vertices, a->vertexCount * sizeof(EPVertex)));
    assert(!memcmp(a->batches, b->batches, a->batchCount * sizeof(EPBatch)));
}

static struct EPGlobals globals(const EPState *s) {
    struct EPGlobals result = {0};
#define COPY(v) memcpy(&result.saved_##v, &s->saved_##v, sizeof(v));
    EP_GLOBALS(COPY)
#undef COPY
    return result;
}

static int command_index(const struct animSeq *seq, const struct animCommand *target) {
    if (!target) return -1;
    int index = 0;
    for (const struct animCommand *cmd = seq->cmd_g; cmd; cmd = cmd->next, ++index)
        if (cmd == target) return index;
    assert(0);
    return -1;
}

static void equal_script(const EPState *a, const EPState *b) {
    const struct animSeq *left = a->saved_seqList, *right = b->saved_seqList;
    while (left && right) {
        assert(left->seq == right->seq);
        assert(!memcmp(left->pad_b, right->pad_b, sizeof(left->pad_b)));
        assert(left->seqFrame == right->seqFrame && left->flt_d == right->flt_d);
        assert(left->flt_e == right->flt_e && left->flt_f == right->flt_f);
        assert((left == a->saved_editSeq) == (right == b->saved_editSeq));
        assert(command_index(left, left->cmd_h) == command_index(right, right->cmd_h));
        assert(command_index(left, left->cmd_i) == command_index(right, right->cmd_i));
        const struct animCommand *lc = left->cmd_g, *rc = right->cmd_g;
        while (lc && rc) {
            assert(lc->type == rc->type && lc->pad_b == rc->pad_b);
            assert(lc->cmdFrame == rc->cmdFrame && lc->flt_d == rc->flt_d);
            assert((lc->seq_e == NULL) == (rc->seq_e == NULL));
            if (lc->seq_e) assert(lc->seq_e->seq == rc->seq_e->seq);
            lc = lc->next; rc = rc->next;
        }
        assert(!lc && !rc);
        left = left->next; right = right->next;
    }
    assert(!left && !right);
}

static void equal_nonangular_state(const EPState *a, const EPState *b) {
    struct EPGlobals left = globals(a), right = globals(b);
    assert(a->random == b->random);
    for (unsigned i = 0; i < NELEMS(a->saved_acttable); ++i) {
        assert((a->saved_acttable[i] == NULL) == (b->saved_acttable[i] == NULL));
        if (a->saved_acttable[i])
            assert(!memcmp(a->saved_acttable[i], b->saved_acttable[i], sizeof(struct act)));
    }
    equal_script(a,b);
    memset(left.saved_acttable, 0, sizeof(left.saved_acttable));
    memset(right.saved_acttable, 0, sizeof(right.saved_acttable));
    left.saved_seqList = right.saved_seqList = NULL;
    left.saved_editSeq = right.saved_editSeq = NULL;
    memset(left.saved_spin, 0, sizeof(left.saved_spin));
    memset(right.saved_spin, 0, sizeof(right.saved_spin));
    memset(left.saved_flip, 0, sizeof(left.saved_flip));
    memset(right.saved_flip, 0, sizeof(right.saved_flip));
    left.saved_gspin = right.saved_gspin = 0;
    left.saved_gflip = right.saved_gflip = 0;
    assert(!memcmp(&left, &right, sizeof(left)));
}

static void force_rates(EPState *s, float spinRate, float flipRate) {
    for (struct animSeq *seq=s->saved_seqList; seq; seq=seq->next) seq->pad_b[0] = 0;
    s->saved_acttable[80]->pad_a[0] = 0;
    s->saved_acttable[80]->flt_g = spinRate;
    s->saved_acttable[87]->pad_a[0] = 0;
    s->saved_acttable[87]->flt_g = flipRate;
}

static void test_contract(void) {
    double spinMinimum = 0, spinMaximum = 0, flipMinimum = 0, flipMaximum = 0;
    for (const char *line = defaultScript; line; line = strchr(line, '\n')) {
        if (*line == '\n') ++line;
        unsigned limit, actuator;
        double value;
        if (sscanf(line, "actlim%u: %u, %lf", &limit, &actuator, &value) == 3) {
            if (actuator == 80) {
                spinMinimum = fmin(spinMinimum, value);
                spinMaximum = fmax(spinMaximum, value);
            }
            if (actuator == 87) {
                flipMinimum = fmin(flipMinimum, value);
                flipMaximum = fmax(flipMaximum, value);
            }
        }
    }
    assert(spinMinimum == -spinMaximum && flipMinimum == -flipMaximum);
    assert(fabs(spinMaximum * 60 - EPMaximumMotionLimits.maxSpinDegreesPerSecond) < 1e-10);
    assert(fabs(flipMaximum * 60 - EPMaximumMotionLimits.maxFlipDegreesPerSecond) < 1e-10);
    assert(EPDefaultMotionLimits.maxSpinDegreesPerSecond == 120);
    assert(EPDefaultMotionLimits.maxFlipDegreesPerSecond == 120);
    EPState *s = ep_create(0);
    assert(s->motionLimits.maxSpinDegreesPerSecond == EPMaximumMotionLimits.maxSpinDegreesPerSecond);
    assert(s->motionLimits.maxFlipDegreesPerSecond == EPMaximumMotionLimits.maxFlipDegreesPerSecond);
    ep_step(s,960,720);
    struct EPGlobals before = globals(s);
    assert(ep_set_motion_limits(s, EPDefaultMotionLimits));
    struct EPGlobals after = globals(s);
    assert(!memcmp(&before,&after,sizeof(before)));
    const EPMotionLimits invalid[] = {
        {NAN, 1}, {1, NAN}, {INFINITY, 1}, {1, INFINITY}, {-INFINITY, 1}, {1, -INFINITY},
        {-1, 1}, {1, -1}, {313.800001, 0}, {0, 600.000001},
    };
    for (unsigned i=0; i<NELEMS(invalid); ++i) {
        assert(!ep_set_motion_limits(s, invalid[i]));
        assert(s->motionLimits.maxSpinDegreesPerSecond == EPDefaultMotionLimits.maxSpinDegreesPerSecond);
        assert(s->motionLimits.maxFlipDegreesPerSecond == EPDefaultMotionLimits.maxFlipDegreesPerSecond);
    }
    assert(!ep_set_motion_limits(NULL, EPDefaultMotionLimits));
    assert(ep_set_motion_limits(s, (EPMotionLimits){0,0}));
    assert(ep_set_motion_limits(s, EPMaximumMotionLimits));
    ep_destroy(s);
}

static void test_signed_steps(void) {
    const EPMotionLimits limits[] = {{120,120}, {0,120}, {120,0}, {0,0}, {30,90}};
    const float rates[][2] = {{5.23f,10}, {-5.23f,-10}, {5.23f,-10}, {-5.23f,10}, {.23f,-.75f}, {2,-2}};
    const float starts[] = {0,359,-359};
    for (unsigned l=0; l<NELEMS(limits); ++l)
        for (unsigned r=0; r<NELEMS(rates); ++r)
            for (unsigned p=0; p<NELEMS(starts); ++p) {
                EPState *s = ep_create(0), *original = ep_create(0);
                ep_step(s,960,720); ep_step(original,960,720);
                assert(ep_set_motion_limits(s, limits[l]));
                s->saved_gspin = original->saved_gspin = starts[p];
                s->saved_gflip = original->saved_gflip = -starts[p];
                force_rates(s,rates[r][0],rates[r][1]);
                force_rates(original,rates[r][0],rates[r][1]);
                EPFrame frame = *ep_step(s,960,720);
                ep_step(original,960,720);
                assert(s->saved_acttable[80]->flt_g == rates[r][0]);
                assert(s->saved_acttable[87]->flt_g == rates[r][1]);
                float spinStep = (float)(limits[l].maxSpinDegreesPerSecond / 60);
                float flipStep = (float)(limits[l].maxFlipDegreesPerSecond / 60);
                float expectedSpin = fmodf(starts[p] + copysignf(fminf(fabsf(rates[r][0]),spinStep), rates[r][0]),360);
                float expectedFlip = fmodf(-starts[p] + copysignf(fminf(fabsf(rates[r][1]),flipStep), rates[r][1]),360);
                assert(s->saved_gspin == expectedSpin && s->saved_spin[s->saved_n] == expectedSpin);
                assert(s->saved_gflip == expectedFlip && s->saved_flip[s->saved_n] == expectedFlip);
                equal_nonangular_state(s,original);
                equal_frames(&frame,ep_render(s,960,720,1));
                if (fabsf(rates[r][0])<=spinStep && fabsf(rates[r][1])<=flipStep)
                    equal_frames(&frame,&original->frame);
                ep_destroy(s); ep_destroy(original);
            }
    EPState *s = ep_create(0);
    ep_step(s,960,720);
    force_rates(s,5,10);
    s->saved_t = 0;
    s->saved_acttable[45]->pad_a[0] = 0;
    s->saved_acttable[45]->flt_g = .25f;
    assert(ep_set_motion_limits(s,(EPMotionLimits){0,0}));
    int index = s->saved_n;
    float angle = s->saved_gspin;
    ep_step(s,960,720);
    assert(s->saved_n == index && s->saved_gspin == angle);
    ep_destroy(s);
}

static void test_script_and_render(void) {
    EPState *capped = ep_create(0), *original = ep_create(0), *canonical = ep_create(0);
    assert(ep_set_motion_limits(capped, EPDefaultMotionLimits));
    assert(ep_set_motion_limits(canonical, EPDefaultMotionLimits));
    EPFrame previous = {0};
    unsigned spinSigns=0, flipSigns=0, wraps=0, changed=0, unchanged=0;
    for (int i=0; i<12000; ++i) {
        float startSpin = capped->saved_gspin, startFlip = capped->saved_gflip;
        int index = capped->saved_n;
        float oldSpin[128], oldFlip[128];
        memcpy(oldSpin, capped->saved_spin, sizeof(oldSpin));
        memcpy(oldFlip, capped->saved_flip, sizeof(oldFlip));
        EPFrame current = *ep_step(capped,960,720);
        equal_frames(&current,ep_step(canonical,960,720));
        ep_step(original,960,720);
        equal_nonangular_state(capped,original);
        for (int h=0; h<128; ++h) if (h != capped->saved_n) {
            assert(capped->saved_spin[h] == oldSpin[h]);
            assert(capped->saved_flip[h] == oldFlip[h]);
        }
        float spinRate = capped->saved_acttable[80]->flt_g;
        float flipRate = capped->saved_acttable[87]->flt_g;
        if (capped->saved_n != index) {
            float expectedSpin = fabsf(spinRate)>2 ? fmodf(startSpin+copysignf(2,spinRate),360) : fmodf(startSpin+spinRate,360);
            float expectedFlip = fabsf(flipRate)>2 ? fmodf(startFlip+copysignf(2,flipRate),360) : fmodf(startFlip+flipRate,360);
            assert(capped->saved_gspin == expectedSpin && capped->saved_gflip == expectedFlip);
            assert(capped->saved_spin[capped->saved_n] == expectedSpin);
            assert(capped->saved_flip[capped->saved_n] == expectedFlip);
            if (fabsf(spinRate)>2) spinSigns |= spinRate>0 ? 1 : 2;
            if (fabsf(flipRate)>2) flipSigns |= flipRate>0 ? 1 : 2;
            wraps += fabsf(expectedSpin-startSpin)>300 || fabsf(expectedFlip-startFlip)>300;
            if (fabsf(spinRate)<=2 && fabsf(flipRate)<=2) ++unchanged;
            else ++changed;
        }
        struct EPGlobals before = globals(capped);
        uint64_t random = capped->random;
        if (i) equal_frames(&previous,ep_render(capped,960,720,0));
        equal_frames(&current,ep_render(capped,960,720,1));
        for (int j=1; j<4; ++j) {
            const EPFrame *middle = ep_render(capped,960,720,j/4.0f);
            for (unsigned v=0; v<middle->vertexCount; ++v)
                for (int c=0; c<4; ++c) assert(isfinite(middle->vertices[v].position[c]));
        }
        ep_render(capped,1920,1080,.4f);
        struct EPGlobals after = globals(capped);
        assert(!memcmp(&before,&after,sizeof(before)) && random == capped->random);
        equal_nonangular_state(capped,canonical);
        previous = current;
    }
    fprintf(stderr,"Burst sign masks spin=%u flip=%u, wraps=%u, capped=%u, unchanged=%u.\n",spinSigns,flipSigns,wraps,changed,unchanged);
    assert(spinSigns && flipSigns && wraps && changed && unchanged);
    struct EPGlobals before = globals(capped);
    assert(ep_set_motion_limits(capped, (EPMotionLimits){0,600}));
    struct EPGlobals after = globals(capped);
    assert(!memcmp(&before,&after,sizeof(before)));
    force_rates(capped,5,10);
    float spin = capped->saved_gspin, flip = capped->saved_gflip;
    ep_step(capped,960,720);
    assert(capped->saved_gspin == spin && capped->saved_gflip == fmodf(flip+10,360));
    assert(canonical->motionLimits.maxSpinDegreesPerSecond == 120);
    assert(original->motionLimits.maxSpinDegreesPerSecond == 313.8);
    ep_destroy(capped); ep_destroy(original); ep_destroy(canonical);
    printf("Passed 12,000 capped script steps, actual fast bursts, wrap, source-state parity, and render purity.\n");
}

int main(void) {
    test_contract();
    test_signed_steps();
    test_script_and_render();
    puts("Passed motion bounds, atomic validation, signed/zero/independent caps, unchanged slow motion, and per-view policy.");
}
