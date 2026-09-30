#pragma once
/* Native graphics interception interface; no OpenGL framework required. */
#define GL_LINES 1
#define GL_TRIANGLE_FAN 6
#define GL_COLOR_BUFFER_BIT 0x4000
#define GL_PROJECTION 0x1701
#define GL_MODELVIEW 0x1700
void wrap_glClear(unsigned mask, const void *context);
void wrap_glColor4f(float r, float g, float b, float a, const void *context);
void wrap_glPushMatrix(const void *context);
void wrap_glPopMatrix(const void *context);
void wrap_glRotatef(float angle, float x, float y, float z, const void *context);
void wrap_glTranslatef(float x, float y, float z, const void *context);
void wrap_glScalef(float x, float y, float z, const void *context);
void wrap_glBegin(unsigned mode, const void *context);
void wrap_glVertex2f(float x, float y, const void *context);
void wrap_glEnd(const void *context);
void wrap_glFinish(const void *context);
void glViewport(int x, int y, int width, int height);
void glMatrixMode(unsigned mode);
void glLoadIdentity(void);
void glTranslatef(float x, float y, float z);
void ep_gluPerspective(double fov, double aspect, double near, double far);
