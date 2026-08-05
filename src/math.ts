import type { Vec4Color } from "./types";

export type Mat4 = number[];

export const identity = (): Mat4 => [
  1, 0, 0, 0,
  0, 1, 0, 0,
  0, 0, 1, 0,
  0, 0, 0, 1,
];

export function multiply(a: Mat4, b: Mat4): Mat4 {
  const out = new Array<number>(16).fill(0);
  for (let column = 0; column < 4; column += 1) {
    for (let row = 0; row < 4; row += 1) {
      let value = 0;
      for (let i = 0; i < 4; i += 1) {
        value += (a[i * 4 + row] ?? 0) * (b[column * 4 + i] ?? 0);
      }
      out[column * 4 + row] = value;
    }
  }
  return out;
}

export const translation = (x: number, y: number, z: number): Mat4 => [
  1, 0, 0, 0,
  0, 1, 0, 0,
  0, 0, 1, 0,
  x, y, z, 1,
];

export const scaling = (x: number, y: number, z: number): Mat4 => [
  x, 0, 0, 0,
  0, y, 0, 0,
  0, 0, z, 0,
  0, 0, 0, 1,
];

const radians = (degrees: number): number => (degrees * Math.PI) / 180;

export function rotationX(degrees: number): Mat4 {
  const c = Math.cos(radians(degrees));
  const s = Math.sin(radians(degrees));
  return [1, 0, 0, 0, 0, c, s, 0, 0, -s, c, 0, 0, 0, 0, 1];
}

export function rotationY(degrees: number): Mat4 {
  const c = Math.cos(radians(degrees));
  const s = Math.sin(radians(degrees));
  return [c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, 0, 0, 0, 1];
}

export function rotationZ(degrees: number): Mat4 {
  const c = Math.cos(radians(degrees));
  const s = Math.sin(radians(degrees));
  return [c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
}

export function transformPoint(
  matrix: Mat4,
  point: readonly [number, number, number],
): [number, number, number] {
  const [x, y, z] = point;
  return [
    (matrix[0] ?? 0) * x + (matrix[4] ?? 0) * y + (matrix[8] ?? 0) * z + (matrix[12] ?? 0),
    (matrix[1] ?? 0) * x + (matrix[5] ?? 0) * y + (matrix[9] ?? 0) * z + (matrix[13] ?? 0),
    (matrix[2] ?? 0) * x + (matrix[6] ?? 0) * y + (matrix[10] ?? 0) * z + (matrix[14] ?? 0),
  ];
}

export function perspective(fovDegrees: number, aspect: number, near: number, far: number): Mat4 {
  const f = 1 / Math.tan(radians(fovDegrees) / 2);
  const nf = 1 / (near - far);
  return [
    f / aspect, 0, 0, 0,
    0, f, 0, 0,
    0, 0, (far + near) * nf, -1,
    0, 0, 2 * far * near * nf, 0,
  ];
}

export function hlsToRgb(hue: number, lightness: number, saturation: number): Vec4Color {
  let h = hue * 360;
  const value = (n1: number, n2: number, valueHue: number): number => {
    let adjusted = valueHue;
    if (adjusted > 360) adjusted -= 360;
    if (adjusted < 0) adjusted += 360;
    if (adjusted < 60) return n1 + (n2 - n1) * (adjusted / 60);
    if (adjusted < 180) return n2;
    if (adjusted < 240) return n1 + (n2 - n1) * ((240 - adjusted) / 60);
    return n1;
  };

  if (saturation === 0) {
    return { r: lightness, g: lightness, b: lightness, a: 1 };
  }
  const m2 = lightness <= 0.5
    ? lightness * (1 + saturation)
    : lightness + saturation - lightness * saturation;
  const m1 = 2 * lightness - m2;
  h %= 360;
  return {
    r: value(m1, m2, h + 120),
    g: value(m1, m2, h),
    b: value(m1, m2, h - 120),
    a: 1,
  };
}

export const wrap = (value: number, min: number, max: number): number => {
  const range = max - min;
  if (range === 0) return min;
  return ((value - min) % range + range) % range + min;
};

export function twixt(current: number, previous: number, t: number): number {
  return current * t + previous * (1 - t);
}

export function foldTwixt(current: number, previous: number, t: number, range: number): number {
  const difference = current - previous;
  if (difference > range / 2) return current * t + (previous + range) * (1 - t);
  if (difference < -range / 2) return (current + range) * t + previous * (1 - t);
  return twixt(current, previous, t);
}
