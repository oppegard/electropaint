/* Independent oracle: unchanged engine, libc RNG, native OpenGL matrices. */
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include "EPAdapter.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void reference_init(void);
void reference_display(const void *);
void reference_reshape(int,int);
static EPFrame frame;
static EPVertex pending[8];
static unsigned pendingCount, primitive;
static float color[4];
void reference_perspective(double fov,double aspect,double near,double far) {
    /* GLU multiplies a matrix directly: glFrustum rejects this inverted FOV. */
    double cot=cos(fov*M_PI/360)/sin(fov*M_PI/360);
    double matrix[16]={cot/aspect,0,0,0, 0,cot,0,0,
        0,0,-(far+near)/(far-near),-1, 0,0,-2*near*far/(far-near),0};
    glMultMatrixd(matrix);
}
void reference_clear(unsigned mask,const void *ctx) { (void)mask;(void)ctx; memset(&frame,0,sizeof(frame)); }
void reference_color(float r,float g,float b,float a,const void *ctx) {
    (void)ctx; color[0]=r;color[1]=g;color[2]=b;color[3]=a;
}
void reference_push(const void *ctx) { (void)ctx;glPushMatrix(); }
void reference_pop(const void *ctx) { (void)ctx;glPopMatrix(); }
void reference_rotate(float a,float x,float y,float z,const void *ctx) { (void)ctx;glRotatef(a,x,y,z); }
void reference_translate(float x,float y,float z,const void *ctx) { (void)ctx;glTranslatef(x,y,z); }
void reference_scale(float x,float y,float z,const void *ctx) { (void)ctx;glScalef(x,y,z); }
void reference_begin(unsigned mode,const void *ctx) { (void)ctx;primitive=mode;pendingCount=0; }
void reference_vertex(float x,float y,const void *ctx) {
    (void)ctx;
    float m[16],p[16]; glGetFloatv(GL_MODELVIEW_MATRIX,m);glGetFloatv(GL_PROJECTION_MATRIX,p);
    double v[4]={x,y,0,1},model[4]={0},clip[4]={0};
    for(int r=0;r<4;++r) for(int k=0;k<4;++k) model[r]+=m[k*4+r]*v[k];
    for(int r=0;r<4;++r) for(int k=0;k<4;++k) clip[r]+=p[k*4+r]*model[k];
    EPVertex *out=&pending[pendingCount++];
    for(int r=0;r<4;++r) out->position[r]=clip[r];
    out->position[2]=(clip[2]+clip[3])*0.5;
    memcpy(out->color,color,sizeof(color));
}
void reference_end(const void *ctx) {
    (void)ctx;
    if(!memcmp(pending[0].position,pending[1].position,sizeof(pending[0].position))) return;
    EPBatch *batch=&frame.batches[frame.batchCount++];
    *batch=(EPBatch){frame.vertexCount,primitive==GL_LINES ? pendingCount : 6,primitive==GL_LINES};
    if(batch->lines) { memcpy(&frame.vertices[frame.vertexCount],pending,pendingCount*sizeof(EPVertex));frame.vertexCount+=pendingCount; }
    else { const unsigned indices[]={0,1,2,0,2,3};for(unsigned i=0;i<6;++i) frame.vertices[frame.vertexCount++]=pending[indices[i]]; }
}
void reference_finish(const void *ctx) { (void)ctx; }
int main(void) {
    CGLPixelFormatAttribute attributes[]={kCGLPFAAllowOfflineRenderers,0};
    CGLPixelFormatObj format;GLint count;CGLContextObj context;
    assert(CGLChoosePixelFormat(attributes,&format,&count)==kCGLNoError);
    assert(CGLCreateContext(format,NULL,&context)==kCGLNoError);
    CGLDestroyPixelFormat(format);assert(CGLSetCurrentContext(context)==kCGLNoError);
    reference_init(); EPState *state=ep_create(0);
    double maxError=0;
    for(int tick=0;tick<12000;++tick) {
        int width=tick%2 ? 1920 : 960,height=tick%2 ? 1080 : 720;
        reference_reshape(width,height);reference_display(NULL);
        const EPFrame *actual=ep_step(state,width,height);
        assert(actual->vertexCount==frame.vertexCount && actual->batchCount==frame.batchCount);
        assert(!memcmp(actual->batches,frame.batches,frame.batchCount*sizeof(EPBatch)));
        for(unsigned i=0;i<frame.vertexCount;++i) for(int k=0;k<4;++k) {
            double error=fabs(actual->vertices[i].position[k]-frame.vertices[i].position[k]);
            if(error>maxError) maxError=error;
            if(error>=0.001) {
                fprintf(stderr,"tick %d vertex %u component %d actual %g reference %g error %g GL %x\n",
                    tick,i,k,actual->vertices[i].position[k],frame.vertices[i].position[k],error,glGetError());
                abort();
            }
            assert(actual->vertices[i].color[k]==frame.vertices[i].color[k]);
        }
    }
    ep_destroy(state);CGLSetCurrentContext(NULL);CGLDestroyContext(context);
    printf("Original OpenGL comparison: 12,000 frames; maximum clip-coordinate error %.9g; colors and draw order exact.\n",maxError);
}
