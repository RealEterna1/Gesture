#!/usr/bin/env python3
"""Generate synthetic pilot data to test the analysis pipeline.

The output is clearly marked as synthetic and must never be reported as
experimental data. It exists only to verify that the pipeline runs end to end
and that FAR/FRR/EER behave sensibly on a separable and a non-separable case.

Usage:
    python analysis/fixtures/make_fixture.py
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone

import numpy as np

GESTURE = "G1"
BASE_SHAPES = [
    [(200.0, 200.0), (600.0, 200.0)],
    [(600.0, 200.0), (500.0, 400.0), (400.0, 500.0)],
    [(400.0, 500.0), (250.0, 350.0), (250.0, 550.0)],
]


def densify(control, step=2.0):
    points = []
    for (x0, y0), (x1, y1) in zip(control[:-1], control[1:]):
        length = float(np.hypot(x1 - x0, y1 - y0))
        count = max(int(length / step), 1)
        for k in range(count):
            t = k / count
            points.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    points.append(control[-1])
    return np.asarray(points, dtype=float)


def build_stroke(control, speed, pressure_base, pressure_noise, jitter, offset_ms, rng):
    dense = densify(control)
    seg = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    total = float(cum[-1])
    duration_s = max(total / max(speed, 1.0), 0.12)

    times = np.arange(0.0, duration_s, 0.004)
    if times.size < 3:
        times = np.linspace(0.0, duration_s, 3)
    distances = np.clip(speed * times, 0.0, total)
    x = np.interp(distances, cum, dense[:, 0])
    y = np.interp(distances, cum, dense[:, 1])
    xy = np.stack([x, y], axis=1) + rng.normal(0.0, jitter, size=(times.size, 2))

    phase = rng.uniform(0.0, 2.0 * np.pi)
    pressure = (
        pressure_base
        + 0.035 * np.sin(2.0 * np.pi * times / max(duration_s, 1e-6) + phase)
        + rng.normal(0.0, pressure_noise, size=times.size)
    )
    pressure = np.clip(pressure, 0.03, 0.64)

    points = [
        {
            "t": round(float(times[i] * 1000.0), 2),
            "raw_us": int((offset_ms + times[i] * 1000.0) * 1000),
            "x": round(float(xy[i, 0]), 3),
            "y": round(float(xy[i, 1]), 3),
            "p": round(float(pressure[i]), 4),
            "p_min": 0.0,
            "p_max": 1.0,
            "size": 0.0,
            "tilt": 0.707,
        }
        for i in range(times.size)
    ]
    stroke = {
        "index": 0,
        "kind": "stylus",
        "start_t": round(float(offset_ms), 2),
        "end_t": round(float(offset_ms + times[-1] * 1000.0), 2),
        "duration_ms": round(float(times[-1] * 1000.0), 2),
        "cancelled": False,
        "point_count": len(points),
        "points": points,
    }
    return stroke, offset_ms + times[-1] * 1000.0 + 20.0


def build_sample(subject, condition, target, index, behavior, rng):
    offset = 0.0
    strokes = []
    for i, control in enumerate(BASE_SHAPES):
        stroke, offset = build_stroke(
            control,
            speed=behavior["speed"],
            pressure_base=behavior["pressure"],
            pressure_noise=behavior["pressure_noise"],
            jitter=behavior["jitter"],
            offset_ms=offset,
            rng=rng,
        )
        stroke["index"] = i
        strokes.append(stroke)
        offset += behavior["pause_ms"]

    for stroke in strokes:
        stroke["start_t"] = round(stroke["start_t"], 2)
        stroke["end_t"] = round(stroke["end_t"], 2)

    notes = f"target={target}" if condition == "mimic" else ""
    return {
        "schema": "gesture-sample-v1",
        "subject_id": subject,
        "gesture_id": GESTURE,
        "condition": condition,
        "sample_index": index,
        "session_id": f"SYNTH_{subject}",
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "device": {
            "platform": "android",
            "manufacturer": "SYNTHETIC",
            "model": "FIXTURE",
            "device": "FIXTURE",
            "board": "fixture",
            "hardware": "fixture",
            "android_release": "15",
            "sdk_int": 35,
            "app_version": "test",
        },
        "canvas": {
            "width": 1254.0,
            "height": 513.33,
            "device_pixel_ratio": 1.5,
            "refresh_rate_hz": 90.0,
        },
        "input_mode": "stylus_only",
        "multi_touch_detected": False,
        "stroke_count": len(strokes),
        "strokes": strokes,
        "notes": notes,
        "stats": {},
        "synthetic": True,
    }


def make_dataset(separable: bool, seed: int = 7):
    rng = np.random.default_rng(seed)
    if separable:
        behaviors = {
            "P01": dict(speed=950.0, pressure=0.46, pressure_noise=0.030, jitter=3.0, pause_ms=110.0),
            "P02": dict(speed=520.0, pressure=0.24, pressure_noise=0.020, jitter=4.0, pause_ms=260.0),
        }
    else:
        same = dict(speed=720.0, pressure=0.35, pressure_noise=0.030, jitter=4.0, pause_ms=180.0)
        behaviors = {"P01": dict(same), "P02": dict(same)}

    samples = []
    index = 0
    for subject, behavior in behaviors.items():
        for _ in range(10):
            samples.append(build_sample(subject, "genuine", None, index, behavior, rng))
            index += 1

    for subject in behaviors:
        target = "P02" if subject == "P01" else "P01"
        for _ in range(10):
            samples.append(
                build_sample(subject, "mimic", target, index, behaviors[subject], rng)
            )
            index += 1

    return {
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "sample_count": len(samples),
        "synthetic": True,
        "note": "SYNTHETIC DATA FOR PIPELINE TESTING ONLY - NOT EXPERIMENTAL RESULTS",
        "samples": samples,
    }


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    for name, separable in [("synthetic_separable.json", True), ("synthetic_random.json", False)]:
        payload = make_dataset(separable)
        path = os.path.join(here, name)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False)
        print(f"wrote {path} ({payload['sample_count']} samples)")


if __name__ == "__main__":
    main()
