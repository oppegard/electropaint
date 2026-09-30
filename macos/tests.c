#include "EPAdapter.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

int main(void) {
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
    printf("Passed 12,000 frames, independent views, resizing, and 100 create/destroy cycles.\n");
}
