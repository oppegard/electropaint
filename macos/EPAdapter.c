#include "EPAdapter.h"
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static double ep_random(void);
static void ep_seed(long seed);
#define glViewport ep_viewport
#define glMatrixMode ep_matrixMode
#define glLoadIdentity ep_loadIdentity
#define glTranslatef ep_translate
#define ep_gluPerspective ep_perspective
#define drand48 ep_random
#define srand48 ep_seed
#define TEST 1
#define OPENGL10 1
#include "vendor/ep.c"
#undef drand48
#undef srand48

/* Swap all mutable C globals under a lock; heap graphs belong to each view. */
#define EP_GLOBALS(X) \
    X(oflag) X(bflag) X(outlinecolRGBA) X(colRGBA) X(acttable) X(sflag) \
    X(currentFrame) X(relFrame) X(baseFrame) X(absFrame) X(wheel) \
    X(x) X(y) X(dzoom) X(arm) X(wrist) X(dtwist) X(flip) X(spin) \
    X(hue) X(light) X(alpha) X(alphaout) X(size) X(outline) X(fill) \
    X(gflip) X(gspin) X(nlimit) X(n) X(t) X(seqList) X(editSeq)
#define FIELD(v) __typeof__(v) saved_##v;
struct EPState {
    EP_GLOBALS(FIELD)
    uint64_t random;
    double model[32][16], projection[16];
    unsigned stack, mode, primitive, pendingCount;
    float color[4];
    EPVertex pending[8];
    EPFrame frame;
};
#undef FIELD
static pthread_mutex_t engineLock = PTHREAD_MUTEX_INITIALIZER;
static EPState *active;

static void save(EPState *s) {
#define SAVE(v) memcpy(&s->saved_##v, &v, sizeof(v));
    EP_GLOBALS(SAVE)
#undef SAVE
}
static void restore(EPState *s) {
#define RESTORE(v) memcpy(&v, &s->saved_##v, sizeof(v));
    EP_GLOBALS(RESTORE)
#undef RESTORE
}
static double ep_random(void) {
    active->random = (active->random * UINT64_C(0x5deece66d) + 11) & UINT64_C(0xffffffffffff);
    return (double)active->random / 281474976710656.0;
}
static void ep_seed(long seed) { active->random = ((uint64_t)(uint32_t)seed << 16) | 0x330e; }
static void identity(double *m) {
    memset(m, 0, 16 * sizeof(double));
    m[0] = m[5] = m[10] = m[15] = 1;
}
static void multiply(double *a, const double *b) {
    double result[16] = {0};
    for (int c = 0; c < 4; ++c)
        for (int r = 0; r < 4; ++r)
            for (int k = 0; k < 4; ++k) result[c*4+r] += a[k*4+r] * b[c*4+k];
    memcpy(a, result, sizeof(result));
}
static double *matrix(EPState *s) { return s->mode == GL_PROJECTION ? s->projection : s->model[s->stack]; }
void glViewport(int x0, int y0, int width, int height) { (void)x0; (void)y0; (void)width; (void)height; }
void glMatrixMode(unsigned mode) { active->mode = mode; }
void glLoadIdentity(void) { identity(matrix(active)); }
void ep_gluPerspective(double fov, double aspect, double near, double far) {
    double m[16] = {0}, cotangent = 1 / tan(fov * M_PI / 360);
    m[0] = cotangent / aspect; m[5] = cotangent;
    m[10] = -(far+near)/(far-near); m[11] = -1;
    m[14] = -2*far*near/(far-near);
    multiply(matrix(active), m);
}
void wrap_glTranslatef(float x0, float y0, float z0, const void *context) {
    EPState *s = (EPState *)context;
    double m[16]; identity(m); m[12]=x0; m[13]=y0; m[14]=z0; multiply(matrix(s),m);
}
void glTranslatef(float x0, float y0, float z0) { wrap_glTranslatef(x0,y0,z0,active); }
void wrap_glScalef(float x0, float y0, float z0, const void *context) {
    double m[16]; identity(m); m[0]=x0; m[5]=y0; m[10]=z0; multiply(matrix((EPState *)context),m);
}
void wrap_glRotatef(float angle, float x0, float y0, float z0, const void *context) {
    double m[16]; identity(m);
    double c=cos(angle*M_PI/180), s=sin(angle*M_PI/180);
    /* The original uses unit rotations around one axis at a time. */
    assert(x0+y0+z0 == 1);
    if (x0) { m[5]=c; m[6]=s; m[9]=-s; m[10]=c; }
    if (y0) { m[0]=c; m[2]=-s; m[8]=s; m[10]=c; }
    if (z0) { m[0]=c; m[1]=s; m[4]=-s; m[5]=c; }
    multiply(matrix((EPState *)context),m);
}
void wrap_glPushMatrix(const void *context) {
    EPState *s=(EPState *)context; assert(s->stack < 31);
    memcpy(s->model[s->stack+1],s->model[s->stack],sizeof(s->model[0])); ++s->stack;
}
void wrap_glPopMatrix(const void *context) { EPState *s=(EPState *)context; assert(s->stack); --s->stack; }
void wrap_glColor4f(float r,float g,float b,float a,const void *context) {
    EPState *s=(EPState *)context; s->color[0]=r; s->color[1]=g; s->color[2]=b; s->color[3]=a;
}
void wrap_glClear(unsigned mask,const void *context) {
    (void)mask; EPState *s=(EPState *)context; s->frame.vertexCount=s->frame.batchCount=0;
}
void wrap_glBegin(unsigned mode,const void *context) {
    EPState *s=(EPState *)context; s->primitive=mode; s->pendingCount=0;
}
void wrap_glVertex2f(float x0,float y0,const void *context) {
    EPState *s=(EPState *)context; assert(s->pendingCount < 8);
    double model[4]={0}, clip[4]={0}, v[4]={x0,y0,0,1};
    for(int r=0;r<4;++r) for(int k=0;k<4;++k) model[r]+=s->model[s->stack][k*4+r]*v[k];
    for(int r=0;r<4;++r) for(int k=0;k<4;++k) clip[r]+=s->projection[k*4+r]*model[k];
    EPVertex *out=&s->pending[s->pendingCount++];
    for(int r=0;r<4;++r) out->position[r]=(float)clip[r];
    /* OpenGL clip depth [-w,w] becomes Metal clip depth [0,w]. */
    out->position[2]=(float)((clip[2]+clip[3])*0.5);
    memcpy(out->color,s->color,sizeof(s->color));
}
static int distinct(const EPVertex *a,const EPVertex *b) {
    return a->position[0]*b->position[3] != b->position[0]*a->position[3] ||
           a->position[1]*b->position[3] != b->position[1]*a->position[3];
}
void wrap_glEnd(const void *context) {
    EPState *s=(EPState *)context;
    /* Zero-size mirrored primitives must not turn into Metal line particles. */
    if (s->pendingCount < 2 || !distinct(&s->pending[0],&s->pending[1])) return;
    unsigned count=s->primitive==GL_LINES ? s->pendingCount : (s->pendingCount-2)*3;
    assert(s->frame.batchCount < 512 && s->frame.vertexCount+count <= 4096);
    EPBatch *b=&s->frame.batches[s->frame.batchCount++];
    *b=(EPBatch){s->frame.vertexCount,count,s->primitive==GL_LINES};
    if(b->lines) {
        memcpy(&s->frame.vertices[s->frame.vertexCount],s->pending,count*sizeof(EPVertex));
        s->frame.vertexCount+=count;
    } else for(unsigned i=1;i+1<s->pendingCount;++i) {
        s->frame.vertices[s->frame.vertexCount++]=s->pending[0];
        s->frame.vertices[s->frame.vertexCount++]=s->pending[i];
        s->frame.vertices[s->frame.vertexCount++]=s->pending[i+1];
    }
}
void wrap_glFinish(const void *context) { (void)context; }
EPState *ep_create(uint32_t seed) {
    EPState *s=calloc(1,sizeof(*s)); if(!s) return NULL;
    pthread_mutex_lock(&engineLock); active=s; restore(s); bflag=1;
    init_ep(); ep_seed(seed); save(s); identity(s->model[0]);
    pthread_mutex_unlock(&engineLock); return s;
}
const EPFrame *ep_step(EPState *s,int width,int height) {
    assert(s && width>0 && height>0);
    pthread_mutex_lock(&engineLock); active=s; restore(s);
    reshape__GiT1(width,height); display__Gv(s); save(s);
    assert(s->stack==0); pthread_mutex_unlock(&engineLock); return &s->frame;
}
void ep_destroy(EPState *s) {
    if(!s) return;
    for(unsigned i=0;i<1024;++i) free(s->saved_acttable[i]);
    struct animSeq *seq=s->saved_seqList;
    while(seq) {
        struct animSeq *next=seq->next;
        struct animCommand *cmd=seq->cmd_g;
        while(cmd) { struct animCommand *nextCmd=cmd->next; free(cmd); cmd=nextCmd; }
        free(seq); seq=next;
    }
    free(s);
}
