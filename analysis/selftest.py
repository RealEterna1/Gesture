#!/usr/bin/env python3
"""Self-checks for the analysis pipeline.

Run:
    python analysis/selftest.py

Every check prints PASS/FAIL. These tests use synthetic data only.
"""

from __future__ import annotations

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import auth_eval as ae  # noqa: E402


def check(name, condition, detail=""):
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {name}{(' :: ' + detail) if detail else ''}")
    if not condition:
        raise SystemExit(1)


def test_dtw_identity():
    rng = np.random.default_rng(0)
    a = rng.normal(size=(32, 2))
    check("DTW(a, a) == 0", ae.dtw_distance(a, a) < 1e-9)


def test_resample():
    line = np.array([[0.0, 0.0], [10.0, 0.0]], dtype=float)
    out = ae.resample_arc(line, 11)
    check("resample keeps endpoints", np.allclose(out[0], [0, 0]) and np.allclose(out[-1], [10, 0]))
    check("resample has requested length", out.shape == (11, 2))


def test_eer_chance():
    rng = np.random.default_rng(1)
    g = rng.normal(0.0, 1.0, 400)
    i = rng.normal(0.0, 1.0, 400)
    result = ae.eer_and_curve(g, i)
    check("EER ~ 0.5 for identical distributions", 0.35 < result["eer"] < 0.65, f"EER={result['eer']:.3f}")


def test_fixture(name, expected):
    path = os.path.join(HERE, "fixtures", name)
    check(f"fixture exists: {name}", os.path.exists(path))
    samples = ae.load_samples([path], "G1")
    ae.resolve_targets(samples, True)
    genuine, impostor, _, _ = ae.build_records(samples, 64, "euclidean")
    g = np.array([r["behaviour"] for r in genuine])
    i = np.array([r["behaviour"] for r in impostor])
    result = ae.eer_and_curve(g, i)
    eer = result["eer"]
    check(
        f"{name}: behaviour EER {expected}",
        expected[0] <= eer <= expected[1],
        f"EER={eer:.3f}",
    )


def main():
    test_dtw_identity()
    test_resample()
    test_eer_chance()
    test_fixture("synthetic_separable.json", (0.0, 0.2))
    test_fixture("synthetic_random.json", (0.3, 0.7))
    print("\nAll self-checks passed.")


if __name__ == "__main__":
    main()
