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

float cube(vec3 p, float r) {
    vec3 d = abs(p) - vec3(r);
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

float sphere(vec3 pt, float radius) {
  return length(pt) - radius;
}

float smin(float a, float b) {
    float k = 0.2;
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1);
    return mix(b, a, h) - k * h * (1 - h);
}

float twistedColumn(vec3 pt) {
    float t = pt.y * PI / 8;
    return cube(vec3(
    pt.x * cos(t) + pt.z * sin(t),
    pt.y / 4,
    -pt.x * sin(t) + pt.z * cos(t)), 1) / 4;
}

float taperedTwist(vec3 pt) {
    pt.x *= (pt.y + 3);
    pt.z *= (pt.y + 3);
    return twistedColumn(pt);
}

float tetrahedron(vec3 p) {
    return (max(abs(p.x + p.y) - p.z, abs(p.x - p.y) + p.z) - 1) / 3;
}

float getColumnSdf(vec3 p) {
    float column = taperedTwist(p) / 4;
    float ball = sphere(p - vec3(0, 4, 0), 0.425);
    return min(ball, column);
}

float getRepeatedColumns(vec3 p) {
    float n = 7;
    float offset = 5;

    float d = RENDER_DEPTH;
    for (float i = -floor(n / 2); i < ceil(n / 2); i++) {
        float col1 = getColumnSdf(p - vec3(i * offset, 0, 6));
        float col2 = getColumnSdf(p - vec3(i * offset, 0, -6));
        d = min(d, min(col1, col2));
    }
    return d;
}

float getSdf(vec3 p) {
    return min(getRepeatedColumns(p), tetrahedron(vec3(p.x / 12, p.y / 4, p.z / 4)));
}

float getPlaneSdf(vec3 p) {
    return p.y + 1;
}

vec3 getPlaneNormal(vec3 pt) {
  return normalize(GRADIENT(pt, getPlaneSdf));
}

vec3 getNormal(vec3 pt) {
  return normalize(GRADIENT(pt, getSdf));
}

vec3 getColor(vec3 pt) {
  return vec3(1);
}

vec3 getPlaneColor(vec3 pt) {
    float d = mod(getSdf(pt), 5);
    return d >= 4.75 ? BLACK : mix(GREEN, BLUE, mod(d, 1));
}

///////////////////////////////////////////////////////////////////////////////

float shadow(vec3 pt, vec3 lightPos) {
    vec3 lightDir = normalize(lightPos - pt);
    float kd = 1.0;
    int step = 0;
    for (float t = 0.1; t < length(lightPos - pt) && step < RENDER_DEPTH && kd > CLOSE_ENOUGH; ) {
        float d = abs(getSdf(pt + t * lightDir));
        if (d < CLOSE_ENOUGH) {
            kd = 0;
        } else {
            kd = min(kd, 16 * d / t);
        }
        t += d;
        step++;
    }
    return kd;
}

float shade(vec3 eye, vec3 pt, vec3 n) {
  float val = 0;
  float k_a = 0.1, k_d = 1.0, k_s = 1.0, alpha = 256;

  val += k_a;  // Ambient

  for (int i = 0; i < LIGHT_POS.length(); i++) {
    vec3 l = normalize(LIGHT_POS[i] - pt);
    float k_shadow = 1.0; // shadow(pt, LIGHT_POS[i]);
    float diffuse = k_d * max(dot(n, l), 0) * k_shadow;

    vec3 r = reflect(l, n);
    vec3 v = normalize(eye);
    float specular = k_s * pow(max(-dot(r, v), 0), alpha) * k_shadow;

    val += specular + diffuse;
  }
  return val;
}

vec3 illuminate(vec3 camPos, vec3 rayDir, vec3 pt) {
  vec3 c, n;
  bool isPlane = abs(getPlaneSdf(pt)) <= CLOSE_ENOUGH;
  if (isPlane) {
    n = getPlaneNormal(pt);
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