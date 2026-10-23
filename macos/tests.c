#include "EPAdapter.h"
#include "EPClock.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static void equal_frames(const EPFrame *a, const EPFrame *b) {
    assert(a->vertexCount==b->vertexCount && a->batchCount==b->batchCount);
    assert(!memcmp(a->vertices,b->vertices,a->vertexCount*sizeof(EPVertex)));
    assert(!memcmp(a->batches,b->batches,a->batchCount*sizeof(EPBatch)));
}
static void test_clock(void) {
    const double rates[]={47.95,48,50,59.94,60,75,120,144,165,240};
    for (unsigned r=0;r<sizeof(rates)/sizeof(*rates);++r) {
        EPClock clock={0}; unsigned ticks=0, intermediates=0;
        ep_clock_advance(&clock,0);
        for (unsigned i=1;i<rates[r]*10;++i) {
            EPClockUpdate u=ep_clock_advance(&clock,i/rates[r]);
            ticks+=u.steps; intermediates+=u.fraction>0.01f && u.fraction<0.99f;
            assert(u.fraction>=0 && u.fraction<1);
        }
        ticks+=ep_clock_advance(&clock,10).steps;
        assert(ticks==600);
        if(rates[r]>=120) assert(intermediates>=590);
    }
    EPClock clock={0}; ep_clock_advance(&clock,0);
    double now=0; unsigned ticks=0;
    for(int i=0;i<1200;++i) {
        now+=1.0/(i<600 ? 120 : 144);
        ticks+=ep_clock_advance(&clock,now).steps;
    }
    assert(ticks==(unsigned)floor(now*60+1e-8));
    double phase=clock.remainder;
    ep_clock_pause(&clock);
    assert(ep_clock_advance(&clock,now+100).steps==0);
    assert(clock.remainder==phase);
    assert(ep_clock_advance(&clock,now+99).steps==0);
    assert(ep_clock_advance(&clock,now+101).steps==8);
}
static void test_interpolation(void) {
    EPState *rendered=ep_create(0), *canonical=ep_create(0), *other=ep_create(17);
    EPFrame previous=*ep_step(rendered,960,720);
    equal_frames(&previous,ep_step(canonical,960,720));
    equal_frames(&previous,ep_render(rendered,960,720,0.5f));
    unsigned changed=0;
    for(int i=1;i<12000;++i) {
        EPFrame current=*ep_step(rendered,960,720);
        equal_frames(&current,ep_step(canonical,960,720));
        equal_frames(&previous,ep_render(rendered,960,720,0));
        equal_frames(&current,ep_render(rendered,960,720,1));
        for(int j=1;j<4;++j) {
            const EPFrame *middle=ep_render(rendered,960,720,j/4.0f);
            for(unsigned k=0;k<middle->vertexCount;++k)
                for(int c=0;c<4;++c) {
                    assert(isfinite(middle->vertices[k].position[c]));
                    assert(isfinite(middle->vertices[k].color[c]));
                }
            if(middle->vertexCount==previous.vertexCount &&
               memcmp(middle->vertices,previous.vertices,middle->vertexCount*sizeof(EPVertex))) ++changed;
            ep_step(other,800,600);
            ep_render(other,800,600,0.4f);
        }
        // Resized draws must not alter either canonical endpoint or future RNG.
        ep_render(rendered,1920,1080,0.5f);
        equal_frames(&current,ep_render(rendered,960,720,1));
        previous=current;
    }
    assert(changed>10000);
    ep_destroy(rendered); ep_destroy(canonical); ep_destroy(other);
}
int main(void) {
    test_clock();
    test_interpolation();
    EPState *a=ep_create(0), *b=ep_create(0), *noise=ep_create(17);
    assert(a && b && noise);
    unsigned long total=0;
    for(int i=0;i<12000;++i) {
        int width=i%2 ? 1920 : 960, height=i%2 ? 1080 : 720;
        const EPFrame *first=ep_step(a,width,height);
        ep_step(noise,500,500);
        const EPFrame *second=ep_step(b,width,height);
        assert(first->vertexCount==second->vertexCount);
        assert(first->batchCount==second->batchCount);
        assert(memcmp(first->vertices,second->vertices,first->vertexCount*sizeof(EPVertex))==0);
        assert(memcmp(first->batches,second->batches,first->batchCount*sizeof(EPBatch))==0);
        /* Forty visible squares: at most forty fills and forty outlines. */
        assert(first->batchCount<=80);
        for(unsigned j=0;j<first->vertexCount;++j) {
            const EPVertex *v=&first->vertices[j];
            for(int k=0;k<4;++k) { assert(isfinite(v->position[k])); assert(isfinite(v->color[k])); }
        }
        for(unsigned j=0;j<first->batchCount;++j) {
            EPBatch batch=first->batches[j];
            assert(batch.first+batch.count<=first->vertexCount);
            assert(batch.lines ? batch.count==8 : batch.count==6);
        }
        total+=first->vertexCount;
    }
    assert(total>1000000);
    ep_destroy(a); ep_destroy(b); ep_destroy(noise);
    for(int i=0;i<100;++i) { EPState *s=ep_create(i); ep_step(s,320,240); ep_destroy(s); }
    printf("Passed refresh timing, 12,000 interpolation/purity checks, 12,000 canonical frames, and view lifecycles.\n");
}
