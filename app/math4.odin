package app

import "core:math"

// Column-major 4x4 matrix helpers matching the GL convention the sokol
// shaders expect (mvp * position, std140 uploads). Layout: m[col*4 + row].

Mat4 :: [16]f32

mat4_identity :: proc() -> Mat4 {
    return {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }
}

mat4_mul :: proc(a, b: Mat4) -> Mat4 {
    out: Mat4
    for col in 0..<4 {
        for row in 0..<4 {
            dot: f32
            for k in 0..<4 {
                dot += a[k * 4 + row] * b[col * 4 + k]
            }
            out[col * 4 + row] = dot
        }
    }
    return out
}

mat4_perspective :: proc(fov_y_radians, aspect, z_near, z_far: f32) -> Mat4 {
    m: Mat4
    f := 1.0 / math.tan(fov_y_radians * 0.5)
    m[0] = f / aspect
    m[5] = f
    m[10] = (z_far + z_near) / (z_near - z_far)
    m[11] = -1.0
    m[14] = (2.0 * z_far * z_near) / (z_near - z_far)
    return m
}

vec3_normalize :: proc(v: [3]f32) -> [3]f32 {
    len := math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if len == 0 {
        return {0, 0, 0}
    }
    return {v[0] / len, v[1] / len, v[2] / len}
}

vec3_cross :: proc(a, b: [3]f32) -> [3]f32 {
    return {
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    }
}

vec3_dot :: proc(a, b: [3]f32) -> f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

mat4_look_at :: proc(eye, center, up: [3]f32) -> Mat4 {
    f := vec3_normalize({center[0] - eye[0], center[1] - eye[1], center[2] - eye[2]})
    s := vec3_normalize(vec3_cross(f, up))
    u := vec3_cross(s, f)
    m: Mat4
    m[0] = s[0]; m[4] = s[1]; m[8] = s[2]
    m[1] = u[0]; m[5] = u[1]; m[9] = u[2]
    m[2] = -f[0]; m[6] = -f[1]; m[10] = -f[2]
    m[12] = -vec3_dot(s, eye)
    m[13] = -vec3_dot(u, eye)
    m[14] = vec3_dot(f, eye)
    m[15] = 1.0
    return m
}

mat4_rotation_x :: proc(angle_radians: f32) -> Mat4 {
    m := mat4_identity()
    c := math.cos(angle_radians)
    s := math.sin(angle_radians)
    m[5] = c; m[6] = s
    m[9] = -s; m[10] = c
    return m
}

mat4_rotation_y :: proc(angle_radians: f32) -> Mat4 {
    m := mat4_identity()
    c := math.cos(angle_radians)
    s := math.sin(angle_radians)
    m[0] = c; m[2] = -s
    m[8] = s; m[10] = c
    return m
}

mat4_translation :: proc(x, y, z: f32) -> Mat4 {
    m := mat4_identity()
    m[12] = x
    m[13] = y
    m[14] = z
    return m
}
