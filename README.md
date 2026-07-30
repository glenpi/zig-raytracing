# zig-raytracing

A small ray tracer, written in [Zig](https://ziglang.org/), while working
through Peter Shirley's
[_Ray Tracing in One Weekend_](https://raytracing.github.io/books/RayTracingInOneWeekend.html).

This is mostly a personal exercise to learn Zig — the book is written for
C++, so most of the fun (and the bugs) came from translating its patterns
into idiomatic-ish Zig rather than from the ray tracing itself. Don't expect
production-quality code; expect a beginner's first Zig project.

## What's here

Covers the book roughly end to end: vectors, rays, sphere intersection,
antialiasing, diffuse (Lambertian) / metal / dielectric (glass) materials,
a positionable camera, and defocus blur (depth of field). The final image
in `src/main.zig` is the book's "final render" scene — a field of randomly
generated small spheres plus three large feature spheres.

## Running it

```sh
zig build run -Doptimize=ReleaseFast > image.ppm
```

Output is a `.ppm` image, written to stdout (progress is logged to
stderr, so it doesn't get mixed into the redirected file).

Skipping `-Doptimize=ReleaseFast` also works, but is dramatically slower —
Zig's default Debug build adds bounds/overflow checking that matters a lot
for a pixel-by-pixel, ray-per-sample workload like this one. Worth knowing
before you assume the renderer itself is slow.

```sh
zig build test
```

Built and tested against Zig 0.16.0.
