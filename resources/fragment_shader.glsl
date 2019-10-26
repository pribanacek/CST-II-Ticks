#version 330

uniform vec2 resolution;
uniform float currentTime;
uniform vec3 camPos;
uniform vec3 camDir;
uniform vec3 camUp;
uniform sampler2D tex;
uniform bool showStepDepth;

in vec3 pos;

out vec3 color;

#define PI 3.1415926535897932384626433832795
#define RENDER_DEPTH 800
#define CLOSE_ENOUGH 0.00001

#define BACKGROUND -1
#define BALL 0
#define BASE 1

#define GRADIENT(pt, func) vec3( \
    func(vec3(pt.x + 0.0001, pt.y, pt.z)) - func(vec3(pt.x - 0.0001, pt.y, pt.z)), \
    func(vec3(pt.x, pt.y + 0.0001, pt.z)) - func(vec3(pt.x, pt.y - 0.0001, pt.z)), \
    func(vec3(pt.x, pt.y, pt.z + 0.0001)) - func(vec3(pt.x, pt.y, pt.z - 0.0001)))

#define GREEN vec3(0.4, 1, 0.4)
#define BLUE vec3(0.4, 0.4, 1)
#define BLACK vec3(0, 0, 0)


const vec3 LIGHT_POS[] = vec3[](vec3(5, 18, 10));

///////////////////////////////////////////////////////////////////////////////

vec3 getBackground(vec3 dir) {
  float u = 0.5 + atan(dir.z, -dir.x) / (2 * PI);
  float v = 0.5 - asin(dir.y) / PI;
  vec4 texColor = texture(tex, vec2(u, v));
  return texColor.rgb;
}

vec3 getRayDir() {
  vec3 xAxis = normalize(cross(camDir, camUp));
  return normalize(pos.x * (resolution.x / resolution.y) * xAxis + pos.y * camUp + 5 * camDir);
}

///////////////////////////////////////////////////////////////////////////////

float cube(vec3 p) {
    vec3 d = abs(p) - vec3(1);
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

float sphere(vec3 pt) {
  return length(pt) - 1;
}

float smin(float a, float b) {
    float k = 0.2;
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1);
    return mix(b, a, h) - k * h * (1 - h);
}

float getSdf(vec3 p) {
    float objects[4];
    vec3 positions[4] = vec3[4](vec3(-3, 0, -3), vec3(3, 0, 3), vec3(-3, 0, 3), vec3(3, 0, -3));
    objects[0] = min(cube(p - positions[0]), sphere(p - positions[0] - vec3(1, 0, 1)));
    objects[1] = max(cube(p - positions[1]), sphere(p - positions[1] - vec3(1, 0, 1)));
    objects[2] = smin(cube(p - positions[2]), sphere(p - positions[2] - vec3(1, 0, 1)));
    objects[3] = max(cube(p - positions[3]), -sphere(p - positions[3] - vec3(1, 0, 1)));

    float minimum = RENDER_DEPTH;
    for (int i = 0; i < objects.length(); i++) {
        minimum = min(minimum, objects[i]);
    }
    return minimum;
}

float getPlaneSdf(vec3 p) {
    return p.y + 1;
}

vec3 getNormal(vec3 pt) {
  return normalize(GRADIENT(pt, getSdf));
}

vec3 getColor(vec3 pt) {
  return vec3(1);
}

vec3 getPlaneColor(vec3 pt) {
    float d = mod(getSdf(pt), 5.25);
    return d > 5 ? BLACK : mix(GREEN, BLUE, mod(d, 1));
}

///////////////////////////////////////////////////////////////////////////////

float shade(vec3 eye, vec3 pt, vec3 n) {
  float val = 0;

  val += 0.1;  // Ambient

  for (int i = 0; i < LIGHT_POS.length(); i++) {
    vec3 l = normalize(LIGHT_POS[i] - pt);
    val += max(dot(n, l), 0);
  }
  return val;
}

vec3 illuminate(vec3 camPos, vec3 rayDir, vec3 pt) {
  vec3 c, n;
  bool isPlane = abs(getPlaneSdf(pt)) <= CLOSE_ENOUGH;
  if (isPlane) {
    n = vec3(0, 1, 0);
    c = getPlaneColor(pt);
  } else {
    n = getNormal(pt);
    c = getColor(pt);
  }
  return shade(camPos, pt, n) * c;
}

///////////////////////////////////////////////////////////////////////////////

vec3 raymarch(vec3 camPos, vec3 rayDir) {
  int step = 0;
  float t = 0;

  for (float d = 1000; step < RENDER_DEPTH && abs(d) > CLOSE_ENOUGH; t += abs(d)) {
    vec3 pos = camPos + t * rayDir;
    d = min(getPlaneSdf(pos), getSdf(pos));
    step++;
  }

  if (step == RENDER_DEPTH) {
    return getBackground(rayDir);
  } else if (showStepDepth) {
    return vec3(float(step) / RENDER_DEPTH);
  } else {
    return illuminate(camPos, rayDir, camPos + t * rayDir);
  }
}

///////////////////////////////////////////////////////////////////////////////

void main() {
  color = raymarch(camPos, getRayDir());
}