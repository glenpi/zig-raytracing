# zig-raytracing

A small ray tracer, written in [Zig](https://ziglang.org/), while working
through Peter Shirley's
[_Ray Tracing in One Weekend_](https://raytracing.github.io/books/RayTracingInOneWeekend.html).

This is mostly a personal exercise to learn Zig — the book is written for
C++, so most of the fun (and the bugs) came from translating its patterns
into idiomatic-ish Zig rather than from the ray tracing itself. Don't expect
production-quality code; expect a beginner's first Zig project.

## What's here

Covers the book end to end: vectors, rays, sphere intersection, antialiasing,
diffuse (Lambertian) / metal / dielectric (glass) materials, a positionable
camera, and defocus blur (depth of field).

It renders **every one of the book's 23 numbered images**, not just the final
one, so each chapter's result is a single command away. The chapters before the
book reaches materials are covered by the `Shade` modes on `Camera` (normals,
flat red, uniform hemisphere, Lambertian), plus the `reflectance`, `min_t`,
`jitter` and `linear` switches — five knobs that let one binary render chapter
5's debug image and chapter 13's cover shot.

## Running it

```sh
zig build run -Doptimize=ReleaseFast -- 23 > image_23.ppm   # one image, to stdout
zig build run -Doptimize=ReleaseFast -- all                 # all 23, to image_N.ppm
```

A single image goes to stdout; progress is logged to stderr, so it doesn't get
mixed into the redirected file. `all` writes `image_1.ppm` through
`image_23.ppm` in the working directory instead.

## The images

| # | What it shows | Notes |
| - | ------------- | ----- |
| 1 | First PPM image | 256x256 red/green ramp; no ray tracing at all |
| 2 | Blue-to-white gradient | the sky, with an empty world |
| 3 | A simple red sphere | |
| 4 | Sphere colored by normals | |
| 5 | Normals-colored sphere with ground | one sample per pixel, so aliased |
| 6 | After antialiasing | 100 jittered samples per pixel |
| 7 | First diffuse render | uniform hemisphere bounces, unlimited depth, shadow acne |
| 8 | Diffuse with limited bounces | depth capped at 50 |
| 9 | Diffuse with no shadow acne | hits nearer than `t = 0.001` ignored |
| 10 | Correct Lambertian reflection | cosine-weighted bounces |
| 11 | The renderer's gamut, linear | 10% reflectance, and far too dark |
| 12 | The gamut, gamma-corrected | every later image is gamma encoded |
| 13 | Shiny metal | materials arrive |
| 14 | Fuzzed metal | |
| 15 | Glass first | two glass balls that always refract — the book's deliberate wrong turn |
| 16 | Glass sphere that always refracts | |
| 17 | Air bubble that sometimes reflects | total internal reflection + Schlick |
| 18 | A hollow glass sphere | glass shell with an inverted-index bubble inside |
| 19 | A wide-angle view | vfov 90 |
| 20 | A distant view | camera moved to (-2, 2, 1) |
| 21 | Zooming in | vfov 20 |
| 22 | Spheres with depth-of-field | 10 degree aperture, focused at 3.4 |
| 23 | Final scene | 1200x675, 500 samples — a minute and a half, not seconds |

Skipping `-Doptimize=ReleaseFast` also works, but is dramatically slower —
Zig's default Debug build adds bounds/overflow checking that matters a lot
for a pixel-by-pixel, ray-per-sample workload like this one. Worth knowing
before you assume the renderer itself is slow.

```sh
zig build test
```

## Speed

The final scene, 1200x675 at 500 samples, against the sibling ports on the same
10-core M5:

| | wall | CPU |
| - | - | - |
| Metal (GPU) | 28.0 s | 0.02 s |
| Go | 80.2 s | 770 s |
| **Zig (this)** | **84.4 s** | 801 s |
| Rust | 98.8 s | 922 s |

The Go port needed its ray/sphere scan hand-inlined to get there — behind an
interface it was 4x slower. The same change was tried here and made no
difference (5.02 s vs 5.08 s on a 30-sample render), because `Hittable`'s
`inline else` already expands the dispatch at compile time and hands the
optimizer one flat loop. The tagged union stays: it is both the faster and the
tidier of the two.

Built and tested against Zig 0.16.0.
