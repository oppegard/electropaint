#include <math.h>
#include <stdio.h>

typedef double Matrix[16];

static double twixt(double current, double previous, double t)
{
    return current * t + previous * (1.0 - t);
}

static double fold_twixt(double current, double previous, double t, double range)
{
    double difference = current - previous;

    if (difference > range / 2.0) {
        return current * t + (previous + range) * (1.0 - t);
    }
    if (difference < -range / 2.0) {
        return (current + range) * t + previous * (1.0 - t);
    }
    return twixt(current, previous, t);
}

static double hls_value(double n1, double n2, double hue)
{
    if (hue > 360.0) hue -= 360.0;
    if (hue < 0.0) hue += 360.0;
    if (hue < 60.0) return n1 + (n2 - n1) * (hue / 60.0);
    if (hue < 180.0) return n2;
    if (hue < 240.0) return n1 + (n2 - n1) * ((240.0 - hue) / 60.0);
    return n1;
}

static void hls_to_rgb(double h, double l, double s, double *r, double *g, double *b)
{
    double m1;
    double m2;

    h *= 360.0;
    m2 = l <= 0.5 ? l * (1.0 + s) : l + s - l * s;
    m1 = 2.0 * l - m2;
    if (s == 0.0) {
        *r = *g = *b = l;
    } else {
        *r = hls_value(m1, m2, h + 120.0);
        *g = hls_value(m1, m2, h);
        *b = hls_value(m1, m2, h - 120.0);
    }
}

static void identity(Matrix matrix)
{
    int i;

    for (i = 0; i < 16; ++i) matrix[i] = 0.0;
    matrix[0] = matrix[5] = matrix[10] = matrix[15] = 1.0;
}

static void multiply(const Matrix left, const Matrix right, Matrix output)
{
    int column;
    int row;
    int i;
    Matrix result;

    for (column = 0; column < 4; ++column) {
        for (row = 0; row < 4; ++row) {
            double value = 0.0;
            for (i = 0; i < 4; ++i) {
                value += left[i * 4 + row] * right[column * 4 + i];
            }
            result[column * 4 + row] = value;
        }
    }
    for (i = 0; i < 16; ++i) output[i] = result[i];
}

static void translate(Matrix matrix, double x, double y, double z)
{
    Matrix transform;

    identity(transform);
    transform[12] = x;
    transform[13] = y;
    transform[14] = z;
    multiply(matrix, transform, matrix);
}

static void scale(Matrix matrix, double x, double y, double z)
{
    Matrix transform;

    identity(transform);
    transform[0] = x;
    transform[5] = y;
    transform[10] = z;
    multiply(matrix, transform, matrix);
}

static void rotate_z(Matrix matrix, double degrees)
{
    double angle = degrees * 3.14159265358979323846 / 180.0;
    Matrix transform;

    identity(transform);
    transform[0] = cos(angle);
    transform[1] = sin(angle);
    transform[4] = -sin(angle);
    transform[5] = cos(angle);
    multiply(matrix, transform, matrix);
}

static void rotate_y(Matrix matrix, double degrees)
{
    double angle = degrees * 3.14159265358979323846 / 180.0;
    Matrix transform;

    identity(transform);
    transform[0] = cos(angle);
    transform[2] = -sin(angle);
    transform[8] = sin(angle);
    transform[10] = cos(angle);
    multiply(matrix, transform, matrix);
}

static void transformed_vertex(double output[3])
{
    Matrix matrix;
    double point[4] = {0.2, 0.0, 0.0, 1.0};
    int row;

    identity(matrix);
    translate(matrix, 0.1, -0.2, 0.0);
    rotate_z(matrix, 30.0);
    translate(matrix, 0.0, 0.5, 0.0);
    rotate_y(matrix, 20.0);
    translate(matrix, 0.25, 0.0, 0.0);
    scale(matrix, 2.0, 2.0, 1.0);

    for (row = 0; row < 3; ++row) {
        output[row] = matrix[row] * point[0]
            + matrix[4 + row] * point[1]
            + matrix[8 + row] * point[2]
            + matrix[12 + row] * point[3];
    }
}

int main(void)
{
    double r;
    double g;
    double b;
    double vertex[3];
    double bounce_value = 0.95 + 0.2 * 0.5;
    double wrap_value = bounce_value;

    if (bounce_value > 1.0) bounce_value = -bounce_value + 2.0;
    if (wrap_value > 1.0) wrap_value = wrap_value - 1.0;
    hls_to_rgb(0.5, 0.5, 1.0, &r, &g, &b);
    transformed_vertex(vertex);

    printf("{\n");
    printf("  \"twixt\": %.12f,\n", twixt(20.0, 10.0, 0.25));
    printf("  \"foldTwixt\": %.12f,\n", fold_twixt(10.0, 350.0, 0.5, 360.0));
    printf("  \"bounce\": %.12f,\n", bounce_value);
    printf("  \"wrap\": %.12f,\n", wrap_value);
    printf("  \"hls\": [%.12f, %.12f, %.12f],\n", r, g, b);
    printf("  \"vertex\": [%.12f, %.12f, %.12f]\n", vertex[0], vertex[1], vertex[2]);
    printf("}\n");
    return 0;
}
