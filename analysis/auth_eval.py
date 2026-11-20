#!/usr/bin/env python3
"""Offline evaluation for touchscreen gesture authentication (pilot).

Reads one or more JSON exports produced by the gesture collector app,
builds per-subject models from genuine samples, scores genuine (leave-one-out)
and mimic samples, and reports FAR/FRR/EER plus SVG plots.

Dependencies: Python 3.10+ and numpy only.

Example:
    python analysis/auth_eval.py \
        --input pilot/data/*.json \
        --gesture G1 \
        --outdir analysis/out \
        --assume-target-other

Note: with a 2-person pilot the EER is a feasibility indicator, not a
statistically meaningful result. The tool prints a warning in that case.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import math
import os
import re
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

TARGET_RE = re.compile(r"target\s*=\s*([A-Za-z0-9_\-]+)", re.IGNORECASE)
FEATURE_NAMES = [
    "duration_s",
    "path_px",
    "speed_mean",
    "speed_median",
    "speed_p90",
    "acc_mean_abs",
    "acc_std",
    "pressure_mean",
    "pressure_std",
    "pressure_min",
    "pressure_max",
    "pressure_slope",
    "pressure_speed_corr",
    "straightness",
]


# --------------------------------------------------------------------------
# Data model
# --------------------------------------------------------------------------


@dataclass
class Stroke:
    points: np.ndarray  # (n, 4): t_ms, x, y, pressure
    start_t: float = 0.0
    end_t: float = 0.0
    duration_ms: float = 0.0


@dataclass
class Sample:
    subject: str
    gesture: str
    condition: str
    index: int
    session: str
    strokes: List[Stroke]
    target: Optional[str]
    source: str
    notes: str

    @property
    def sid(self) -> str:
        return f"{os.path.basename(self.source)}#{self.index}"


# --------------------------------------------------------------------------
# Loading and target resolution
# --------------------------------------------------------------------------


def _clean_points(raw: Sequence[dict]) -> np.ndarray:
    """Convert raw points to ndarray, sort by time, remove duplicates/hover."""
    if not raw:
        return np.zeros((0, 4), dtype=float)
    arr = np.array(
        [
            [
                float(p.get("t", 0.0)),
                float(p.get("x", 0.0)),
                float(p.get("y", 0.0)),
                float(p.get("p", 0.0)),
            ]
            for p in raw
        ],
        dtype=float,
    )
    if arr.shape[0] == 0:
        return arr
    arr = arr[np.isfinite(arr).all(axis=1)]
    if arr.shape[0] == 0:
        return arr
    arr = arr[np.argsort(arr[:, 0], kind="stable")]
    # Keep the last occurrence of each timestamp.
    keep = np.ones(arr.shape[0], dtype=bool)
    if arr.shape[0] > 1:
        keep[:-1] = arr[1:, 0] != arr[:-1, 0]
    arr = arr[keep]
    # Stylus hover events often report zero pressure; drop them only if the
    # stroke has real pressure values and enough points remain.
    if np.any(arr[:, 3] > 0):
        mask = arr[:, 3] > 0
        if int(mask.sum()) >= 3:
            arr = arr[mask]
    return arr


def load_samples(paths: Sequence[str], gesture: Optional[str] = None) -> List[Sample]:
    samples: List[Sample] = []
    for path in paths:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
        raw_list = doc.get("samples", [])
        # 新版 App 的验证数据在 verification_logs[].raw_sample 里，
        # 样本列表不再参与验证流程；没有 samples 时自动回退到验证记录。
        if not raw_list and doc.get("verification_logs"):
            raw_list = [
                item.get("raw_sample")
                for item in doc["verification_logs"]
                if isinstance(item, dict) and item.get("raw_sample")
            ]
        for idx, raw in enumerate(raw_list):
            if not isinstance(raw, dict):
                continue
            gid = str(raw.get("gesture_id", ""))
            if gesture and gid != gesture:
                continue
            notes = str(raw.get("notes") or "")
            target = None
            match = TARGET_RE.search(notes)
            if match:
                target = match.group(1)
            strokes: List[Stroke] = []
            for st in raw.get("strokes", []):
                if st.get("cancelled"):
                    continue
                pts = _clean_points(st.get("points", []))
                if pts.shape[0] < 3:
                    continue
                strokes.append(
                    Stroke(
                        points=pts,
                        start_t=float(st.get("start_t", pts[0, 0])),
                        end_t=float(st.get("end_t", pts[-1, 0])),
                        duration_ms=float(st.get("duration_ms", pts[-1, 0] - pts[0, 0])),
                    )
                )
            if not strokes:
                continue
            condition = str(raw.get("condition", "")).strip().lower()
            samples.append(
                Sample(
                    subject=str(raw.get("subject_id", "?")),
                    gesture=gid,
                    condition=condition,
                    index=idx,
                    session=str(raw.get("session_id", "")),
                    strokes=strokes,
                    target=target,
                    source=path,
                    notes=notes,
                )
            )
    return samples


def load_manifest(path: str) -> List[dict]:
    with open(path, newline="", encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def apply_manifest(samples: Sequence[Sample], rows: Sequence[dict]) -> None:
    for sample in samples:
        for row in rows:
            file_cell = (row.get("file") or "").strip()
            if file_cell and os.path.basename(file_cell) != os.path.basename(sample.source):
                continue
            subject_cell = (row.get("subject_id") or "").strip()
            if subject_cell and subject_cell != sample.subject:
                continue
            gesture_cell = (row.get("gesture_id") or "").strip()
            if gesture_cell and gesture_cell != sample.gesture:
                continue
            index_cell = (row.get("sample_index") or "").strip()
            if index_cell:
                try:
                    if int(index_cell) != sample.index:
                        continue
                except ValueError:
                    continue
            target_cell = (row.get("target_subject") or "").strip()
            if target_cell:
                sample.target = target_cell
            break


def resolve_targets(samples: Sequence[Sample], assume_other: bool) -> None:
    subjects: Dict[str, set] = {}
    for sample in samples:
        if sample.condition == "genuine":
            subjects.setdefault(sample.gesture, set()).add(sample.subject)
    for sample in samples:
        if sample.condition != "mimic" or sample.target:
            continue
        if not assume_other:
            continue
        candidates = [
            s for s in subjects.get(sample.gesture, set()) if s != sample.subject
        ]
        if len(candidates) == 1:
            sample.target = candidates[0]
        elif len(candidates) > 1:
            raise SystemExit(
                "Cannot infer the mimic target with more than two subjects; "
                "use notes 'target=P02' or --manifest."
            )


# --------------------------------------------------------------------------
# Shape module
# --------------------------------------------------------------------------


def resample_arc(points_xy: np.ndarray, n: int = 64) -> np.ndarray:
    if points_xy.shape[0] == 0:
        return np.zeros((n, 2), dtype=float)
    diffs = np.linalg.norm(np.diff(points_xy, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(diffs)])
    total = float(cum[-1])
    if total < 1e-9:
        return np.repeat(points_xy[:1], n, axis=0)
    targets = np.linspace(0.0, total, n)
    x = np.interp(targets, cum, points_xy[:, 0])
    y = np.interp(targets, cum, points_xy[:, 1])
    return np.stack([x, y], axis=1)


def normalize_shape(points_xy: np.ndarray) -> np.ndarray:
    centred = points_xy - points_xy.mean(axis=0, keepdims=True)
    rms = math.sqrt(float(np.mean(np.sum(centred * centred, axis=1))))
    if rms < 1e-9:
        return centred
    return centred / rms


def dtw_distance(a: np.ndarray, b: np.ndarray) -> float:
    n, m = a.shape[0], b.shape[0]
    cost = ((a[:, None, :] - b[None, :, :]) ** 2).sum(axis=2)
    acc = np.full((n + 1, m + 1), np.inf, dtype=float)
    acc[0, 0] = 0.0
    for i in range(1, n + 1):
        row = cost[i - 1]
        for j in range(1, m + 1):
            acc[i, j] = row[j - 1] + min(
                acc[i - 1, j], acc[i, j - 1], acc[i - 1, j - 1]
            )
    return math.sqrt(float(acc[n, m]) / float(n + m))


def shape_distance(sample: Sample, template: Sample, resample_n: int = 64) -> float:
    if len(sample.strokes) != len(template.strokes):
        return math.inf
    distances = []
    for a, b in zip(sample.strokes, template.strokes):
        pa = normalize_shape(resample_arc(a.points[:, 1:3], resample_n))
        pb = normalize_shape(resample_arc(b.points[:, 1:3], resample_n))
        distances.append(dtw_distance(pa, pb))
    if not distances:
        return math.inf
    return float(np.mean(distances))


# --------------------------------------------------------------------------
# Behaviour module
# --------------------------------------------------------------------------


def stroke_features(stroke: Stroke) -> np.ndarray:
    pts = stroke.points
    t = pts[:, 0] / 1000.0
    xy = pts[:, 1:3]
    pressure = pts[:, 3]

    dt = np.diff(t)
    steps = np.linalg.norm(np.diff(xy, axis=0), axis=1)
    valid = dt > 1e-9
    if np.any(valid):
        speed = steps[valid] / dt[valid]
    else:
        speed = np.array([0.0], dtype=float)

    duration = max(float(t[-1] - t[0]), 1e-6)
    path = float(steps.sum())
    chord = float(np.linalg.norm(xy[-1] - xy[0]))
    straightness = chord / path if path > 1e-9 else 0.0

    if speed.shape[0] > 1:
        dt_mid = np.maximum(dt[valid][1:], 1e-9)
        acc = np.diff(speed) / dt_mid
    else:
        acc = np.array([0.0], dtype=float)

    if t.shape[0] > 1:
        slope = float(np.polyfit(t - t[0], pressure, 1)[0])
    else:
        slope = 0.0

    n = min(speed.shape[0], pressure.shape[0] - 1)
    if n > 2:
        a = pressure[1 : 1 + n]
        b = speed[:n]
        if a.std() > 1e-9 and b.std() > 1e-9:
            corr = float(np.corrcoef(a, b)[0, 1])
        else:
            corr = 0.0
    else:
        corr = 0.0

    return np.array(
        [
            duration,
            path,
            float(np.mean(speed)),
            float(np.median(speed)),
            float(np.percentile(speed, 90)),
            float(np.mean(np.abs(acc))),
            float(np.std(acc)),
            float(np.mean(pressure)),
            float(np.std(pressure)),
            float(np.min(pressure)),
            float(np.max(pressure)),
            slope,
            corr,
            straightness,
        ],
        dtype=float,
    )


def inter_features(sample: Sample) -> np.ndarray:
    durations = np.array(
        [max(st.duration_ms / 1000.0, 1e-6) for st in sample.strokes], dtype=float
    )
    total = float(durations.sum())
    relative = durations / total if total > 1e-9 else np.zeros_like(durations)
    pauses = []
    for prev, nxt in zip(sample.strokes[:-1], sample.strokes[1:]):
        gap = (nxt.start_t - prev.end_t) / 1000.0
        pauses.append(max(gap, 0.0))
    if not pauses:
        pauses = [0.0]
    pause_arr = np.array(pauses, dtype=float)
    return np.concatenate(
        [
            [total, float(pause_arr.mean()), float(pause_arr.max()), float(pause_arr.sum())],
            relative,
        ]
    )


@dataclass
class Model:
    shape_template: Sample
    stroke_medians: List[np.ndarray]
    stroke_scales: List[np.ndarray]
    stroke_zvars: List[np.ndarray]
    inter_median: np.ndarray
    inter_scale: np.ndarray
    inter_zvar: np.ndarray


def _robust_stats(matrix: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    median = np.median(matrix, axis=0)
    q75 = np.percentile(matrix, 75, axis=0)
    q25 = np.percentile(matrix, 25, axis=0)
    iqr = q75 - q25
    std = matrix.std(axis=0)
    scale = np.where(iqr > 1e-9, iqr, np.where(std > 1e-9, std, 1.0))
    var = matrix.var(axis=0)
    var_shrunk = 0.5 * var + 0.5 * float(np.mean(var))
    zvar = np.maximum(var_shrunk / (scale * scale), 1e-9)
    return median, scale, zvar


def fit_model(genuine: Sequence[Sample], resample_n: int = 64) -> Model:
    if not genuine:
        raise ValueError("Cannot fit a model without genuine samples.")
    count = len(genuine)
    dist = np.zeros((count, count), dtype=float)
    for i in range(count):
        for j in range(i + 1, count):
            value = shape_distance(genuine[i], genuine[j], resample_n)
            dist[i, j] = dist[j, i] = value
    medoid = int(np.argmin(dist.sum(axis=1)))
    template = genuine[medoid]

    n_strokes = len(template.strokes)
    per_stroke: List[List[np.ndarray]] = [[] for _ in range(n_strokes)]
    for sample in genuine:
        if len(sample.strokes) != n_strokes:
            continue
        for i, stroke in enumerate(sample.strokes):
            per_stroke[i].append(stroke_features(stroke))

    medians: List[np.ndarray] = []
    scales: List[np.ndarray] = []
    zvars: List[np.ndarray] = []
    for i in range(n_strokes):
        if per_stroke[i]:
            matrix = np.vstack(per_stroke[i])
        else:
            matrix = np.zeros((1, len(FEATURE_NAMES)), dtype=float)
        median, scale, zvar = _robust_stats(matrix)
        medians.append(median)
        scales.append(scale)
        zvars.append(zvar)

    inter = np.vstack(
        [inter_features(s) for s in genuine if len(s.strokes) == n_strokes]
    )
    inter_median, inter_scale, inter_zvar = _robust_stats(inter)
    return Model(
        shape_template=template,
        stroke_medians=medians,
        stroke_scales=scales,
        stroke_zvars=zvars,
        inter_median=inter_median,
        inter_scale=inter_scale,
        inter_zvar=inter_zvar,
    )


def behaviour_distance(sample: Sample, model: Model, metric: str = "euclidean") -> float:
    if len(sample.strokes) != len(model.shape_template.strokes):
        return math.inf
    distances: List[float] = []
    weights: List[float] = []
    for i, stroke in enumerate(sample.strokes):
        z = (stroke_features(stroke) - model.stroke_medians[i]) / model.stroke_scales[i]
        z = np.clip(z, -5.0, 5.0)
        if metric == "diag_mahalanobis":
            value = math.sqrt(float(np.mean(z * z / model.stroke_zvars[i])))
        else:
            value = math.sqrt(float(np.mean(z * z)))
        distances.append(value)
        weights.append(max(stroke.duration_ms / 1000.0, 1e-6))
    weight_arr = np.array(weights, dtype=float)
    weight_arr = weight_arr / weight_arr.sum()
    stroke_distance = float(np.sum(weight_arr * np.array(distances, dtype=float)))

    inter = (inter_features(sample) - model.inter_median) / model.inter_scale
    inter = np.clip(inter, -5.0, 5.0)
    if metric == "diag_mahalanobis":
        inter_distance = math.sqrt(float(np.mean(inter * inter / model.inter_zvar)))
    else:
        inter_distance = math.sqrt(float(np.mean(inter * inter)))
    return 0.8 * stroke_distance + 0.2 * inter_distance


# --------------------------------------------------------------------------
# Scoring and metrics
# --------------------------------------------------------------------------


def build_records(
    samples: Sequence[Sample], resample_n: int, metric: str
) -> Tuple[List[dict], List[dict], List[Sample], List[Sample]]:
    genuine_by_key: Dict[Tuple[str, str], List[Sample]] = {}
    for sample in samples:
        if sample.condition == "genuine":
            genuine_by_key.setdefault((sample.subject, sample.gesture), []).append(sample)

    genuine_records: List[dict] = []
    impostor_records: List[dict] = []
    used_genuine: List[Sample] = []
    used_impostor: List[Sample] = []

    for (subject, gesture), group in genuine_by_key.items():
        if len(group) < 2:
            print(
                f"WARNING: subject {subject} gesture {gesture} has only "
                f"{len(group)} genuine sample(s); leave-one-out is optimistic.",
                file=sys.stderr,
            )
        for i, sample in enumerate(group):
            subset = [g for j, g in enumerate(group) if j != i] or group
            model = fit_model(subset, resample_n)
            genuine_records.append(
                {
                    "sample": sample,
                    "target": subject,
                    "shape": shape_distance(sample, model.shape_template, resample_n),
                    "behaviour": behaviour_distance(sample, model, metric),
                }
            )
            used_genuine.append(sample)

    for sample in samples:
        if sample.condition != "mimic" or not sample.target:
            continue
        key = (sample.target, sample.gesture)
        if key not in genuine_by_key:
            print(
                f"WARNING: no genuine samples for target {sample.target} "
                f"gesture {sample.gesture}; mimic sample skipped.",
                file=sys.stderr,
            )
            continue
        model = fit_model(genuine_by_key[key], resample_n)
        impostor_records.append(
            {
                "sample": sample,
                "target": sample.target,
                "shape": shape_distance(sample, model.shape_template, resample_n),
                "behaviour": behaviour_distance(sample, model, metric),
            }
        )
        used_impostor.append(sample)

    return genuine_records, impostor_records, used_genuine, used_impostor


def eer_and_curve(genuine: np.ndarray, impostor: np.ndarray) -> dict:
    genuine = np.asarray(genuine, dtype=float)
    impostor = np.asarray(impostor, dtype=float)
    genuine = genuine[np.isfinite(genuine)]
    impostor = impostor[np.isfinite(impostor)]
    if genuine.size == 0 or impostor.size == 0:
        return {
            "eer": None,
            "threshold": None,
            "auc": None,
            "far": [],
            "frr": [],
            "thresholds": [],
        }

    values = np.unique(np.concatenate([genuine, impostor]))
    if values.size == 1:
        values = np.array([values[0] - 1e-6, values[0] + 1e-6])
    thresholds = np.concatenate(
        [[values[0] - 1e-6], (values[:-1] + values[1:]) / 2.0, [values[-1] + 1e-6]]
    )
    far = np.array([float(np.mean(impostor <= t)) for t in thresholds])
    frr = np.array([float(np.mean(genuine > t)) for t in thresholds])

    eer = float("nan")
    threshold = float("nan")
    diff = far - frr
    for i in range(len(diff) - 1):
        if diff[i] == 0.0:
            eer, threshold = float(far[i]), float(thresholds[i])
            break
        if diff[i] * diff[i + 1] < 0.0:
            weight = abs(diff[i]) / (abs(diff[i]) + abs(diff[i + 1]))
            eer = float(far[i] + weight * (far[i + 1] - far[i]))
            threshold = float(thresholds[i] + weight * (thresholds[i + 1] - thresholds[i]))
            break

    auc = float(np.mean(impostor[:, None] > genuine[None, :]))
    return {
        "eer": float(eer) if np.isfinite(eer) else None,
        "threshold": float(threshold) if np.isfinite(threshold) else None,
        "auc": auc,
        "far": far.tolist(),
        "frr": frr.tolist(),
        "thresholds": thresholds.tolist(),
    }


def bootstrap_eer(
    genuine: np.ndarray, impostor: np.ndarray, rounds: int, seed: int
) -> List[Optional[float]]:
    if rounds <= 0 or genuine.size == 0 or impostor.size == 0:
        return [None, None]
    rng = np.random.default_rng(seed)
    values = []
    for _ in range(rounds):
        g = rng.choice(genuine, size=genuine.size, replace=True)
        i = rng.choice(impostor, size=impostor.size, replace=True)
        result = eer_and_curve(g, i)
        if result["eer"] is not None:
            values.append(result["eer"])
    if not values:
        return [None, None]
    return [
        float(np.percentile(values, 2.5)),
        float(np.percentile(values, 97.5)),
    ]


def mode_scores(
    records: Sequence[dict],
    mode: str,
    shape_threshold: float,
    shape_norm: Tuple[float, float],
    behaviour_norm: Tuple[float, float],
    weight_shape: float,
    weight_behaviour: float,
    gate_penalty: float = 1e6,
) -> np.ndarray:
    scores = []
    for record in records:
        shape = record["shape"]
        behaviour = record["behaviour"]
        if mode == "shape":
            score = shape
        elif mode == "behaviour":
            score = behaviour
        elif mode == "gate":
            if shape <= shape_threshold:
                score = behaviour
            else:
                score = gate_penalty + (shape if np.isfinite(shape) else 0.0)
        elif mode == "weighted":
            shape_z = (shape - shape_norm[0]) / shape_norm[1]
            behaviour_z = (behaviour - behaviour_norm[0]) / behaviour_norm[1]
            score = weight_shape * shape_z + weight_behaviour * behaviour_z
        else:
            raise ValueError(f"Unknown mode: {mode}")
        scores.append(score)
    return np.asarray(scores, dtype=float)


# --------------------------------------------------------------------------
# SVG output (no matplotlib)
# --------------------------------------------------------------------------


def _svg_open(width: int, height: int) -> List[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#ffffff"/>',
    ]


def _text(x: float, y: float, value: str, size: int = 12, anchor: str = "start", weight: str = "normal", fill: str = "#222") -> str:
    return (
        f'<text x="{x:.1f}" y="{y:.1f}" font-family="Arial, sans-serif" '
        f'font-size="{size}" text-anchor="{anchor}" font-weight="{weight}" '
        f'fill="{fill}">{html.escape(value)}</text>'
    )


def write_score_svg(path: str, genuine: np.ndarray, impostor: np.ndarray, threshold: Optional[float], mode: str) -> None:
    genuine = genuine[np.isfinite(genuine)]
    impostor = impostor[np.isfinite(impostor)]
    width, height = 820, 500
    left, right, top, bottom = 80, 30, 50, 70
    plot_w, plot_h = width - left - right, height - top - bottom
    all_values = np.concatenate([genuine, impostor]) if genuine.size + impostor.size else np.array([0.0, 1.0])
    x_min, x_max = float(all_values.min()), float(all_values.max())
    if x_min == x_max:
        x_min -= 1.0
        x_max += 1.0
    bins = np.linspace(x_min, x_max, 21)

    def to_x(value: float) -> float:
        return left + (value - x_min) / (x_max - x_min) * plot_w

    def to_y(value: float) -> float:
        return top + plot_h - value * plot_h

    gen_hist, _ = np.histogram(genuine, bins=bins)
    imp_hist, _ = np.histogram(impostor, bins=bins)
    peak = max(int(gen_hist.max()) if gen_hist.size else 1, int(imp_hist.max()) if imp_hist.size else 1, 1)
    gen_hist = gen_hist / peak
    imp_hist = imp_hist / peak

    parts = _svg_open(width, height)
    parts.append(f'<rect x="{left}" y="{top}" width="{plot_w}" height="{plot_h}" fill="#fafafa" stroke="#333"/>')
    for i in range(20):
        x0 = to_x(bins[i])
        x1 = to_x(bins[i + 1])
        parts.append(f'<rect x="{x0:.1f}" y="{to_y(gen_hist[i]):.1f}" width="{max(x1-x0-1,1):.1f}" height="{gen_hist[i]*plot_h:.1f}" fill="#4c78a8" opacity="0.55"/>')
        parts.append(f'<rect x="{x0:.1f}" y="{to_y(imp_hist[i]):.1f}" width="{max(x1-x0-1,1):.1f}" height="{imp_hist[i]*plot_h:.1f}" fill="#f58518" opacity="0.55"/>')
    for k in range(6):
        value = x_min + (x_max - x_min) * k / 5
        x = to_x(value)
        parts.append(f'<line x1="{x:.1f}" y1="{top+plot_h}" x2="{x:.1f}" y2="{top+plot_h+5}" stroke="#333"/>')
        parts.append(_text(x, top + plot_h + 20, f"{value:.2f}", 11, "middle"))
    parts.append(_text(left + plot_w / 2, height - 18, f"score ({mode}); lower = more genuine", 12, "middle"))
    parts.append(_text(22, top + plot_h / 2, "normalised count", 12, "middle"))
    if threshold is not None and np.isfinite(threshold):
        x = to_x(float(threshold))
        parts.append(f'<line x1="{x:.1f}" y1="{top}" x2="{x:.1f}" y2="{top+plot_h}" stroke="#d62728" stroke-width="2" stroke-dasharray="6 4"/>')
        parts.append(_text(x + 6, top + 18, f"threshold = {threshold:.3f}", 11, fill="#d62728"))
    parts.append(f'<rect x="{left}" y="{top-30}" width="14" height="10" fill="#4c78a8" opacity="0.7"/>')
    parts.append(_text(left + 20, top - 21, "genuine", 12))
    parts.append(f'<rect x="{left+110}" y="{top-30}" width="14" height="10" fill="#f58518" opacity="0.7"/>')
    parts.append(_text(left + 130, top - 21, "impostor", 12))
    parts.append("</svg>")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(parts))


def write_det_svg(path: str, far: Sequence[float], frr: Sequence[float], eer: Optional[float]) -> None:
    width, height = 620, 560
    left, right, top, bottom = 90, 40, 50, 70
    plot_w, plot_h = width - left - right, height - top - bottom

    def to_x(value: float) -> float:
        return left + value * plot_w

    def to_y(value: float) -> float:
        return top + plot_h - value * plot_h

    parts = _svg_open(width, height)
    parts.append(f'<rect x="{left}" y="{top}" width="{plot_w}" height="{plot_h}" fill="#fafafa" stroke="#333"/>')
    for k in range(6):
        v = k / 5
        parts.append(f'<line x1="{to_x(v):.1f}" y1="{top+plot_h}" x2="{to_x(v):.1f}" y2="{top+plot_h+5}" stroke="#333"/>')
        parts.append(_text(to_x(v), top + plot_h + 20, f"{v:.1f}", 11, "middle"))
        parts.append(f'<line x1="{left-5}" y1="{to_y(v):.1f}" x2="{left}" y2="{to_y(v):.1f}" stroke="#333"/>')
        parts.append(_text(left - 10, to_y(v) + 4, f"{v:.1f}", 11, "end"))
    parts.append(f'<line x1="{to_x(0):.1f}" y1="{to_y(0):.1f}" x2="{to_x(1):.1f}" y2="{to_y(1):.1f}" stroke="#999" stroke-dasharray="4 4"/>')
    points = sorted(zip(far, frr))
    if points:
        d = " ".join(f"{to_x(float(x)):.1f},{to_y(float(y)):.1f}" for x, y in points)
        parts.append(f'<polyline points="{d}" fill="none" stroke="#4c78a8" stroke-width="2.5"/>')
    if eer is not None and np.isfinite(eer):
        parts.append(f'<circle cx="{to_x(float(eer)):.1f}" cy="{to_y(float(eer)):.1f}" r="5" fill="#d62728"/>')
        parts.append(_text(to_x(float(eer)) + 8, to_y(float(eer)) - 8, f"EER = {eer:.3f}", 11, fill="#d62728"))
    parts.append(_text(left + plot_w / 2, height - 18, "FAR", 12, "middle"))
    parts.append(_text(24, top + plot_h / 2, "FRR", 12, "middle"))
    parts.append("</svg>")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(parts))


# --------------------------------------------------------------------------
# CSV / JSON output
# --------------------------------------------------------------------------


def write_features(path: str, samples: Sequence[Sample]) -> None:
    columns = ["sample_id", "subject", "gesture", "condition", "target", "session", "stroke_count"] + FEATURE_NAMES + ["total_duration_s", "mean_pause_s", "max_pause_s", "total_pause_s"]
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=columns)
        writer.writeheader()
        for sample in samples:
            if not sample.strokes:
                continue
            matrix = np.vstack([stroke_features(st) for st in sample.strokes])
            mean_features = matrix.mean(axis=0)
            inter = inter_features(sample)
            row = {
                "sample_id": sample.sid,
                "subject": sample.subject,
                "gesture": sample.gesture,
                "condition": sample.condition,
                "target": sample.target or "",
                "session": sample.session,
                "stroke_count": len(sample.strokes),
            }
            for name, value in zip(FEATURE_NAMES, mean_features):
                row[name] = f"{float(value):.6g}"
            row["total_duration_s"] = f"{float(inter[0]):.6g}"
            row["mean_pause_s"] = f"{float(inter[1]):.6g}"
            row["max_pause_s"] = f"{float(inter[2]):.6g}"
            row["total_pause_s"] = f"{float(inter[3]):.6g}"
            writer.writerow(row)


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Offline gesture authentication evaluation (pilot).")
    parser.add_argument("--input", nargs="+", required=True, help="One or more JSON export files.")
    parser.add_argument("--gesture", default=None, help="Only use this gesture_id.")
    parser.add_argument("--outdir", default="analysis/out", help="Output directory.")
    parser.add_argument("--mode", default="all", choices=["all", "shape", "behaviour", "gate", "weighted"])
    parser.add_argument("--metric", default="euclidean", choices=["euclidean", "diag_mahalanobis"])
    parser.add_argument("--resample", type=int, default=64)
    parser.add_argument("--shape-accept", type=float, default=0.95, help="Fraction of genuine samples the shape gate should accept.")
    parser.add_argument("--w-shape", type=float, default=0.5)
    parser.add_argument("--w-behaviour", type=float, default=0.5)
    parser.add_argument("--manifest", default=None, help="CSV mapping samples to mimic targets.")
    parser.add_argument("--assume-target-other", action="store_true", help="For a 2-person pilot: mimic targets the other subject.")
    parser.add_argument("--bootstrap", type=int, default=500)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args(argv)

    samples = load_samples(args.input, args.gesture)
    if args.manifest:
        apply_manifest(samples, load_manifest(args.manifest))
    resolve_targets(samples, args.assume_target_other)

    genuine_count = sum(1 for s in samples if s.condition == "genuine")
    mimic_count = sum(1 for s in samples if s.condition == "mimic")
    if genuine_count == 0:
        raise SystemExit("No genuine samples found. Check --gesture and the export files.")
    if mimic_count == 0:
        raise SystemExit("No mimic samples found. This pilot cannot estimate impostor scores yet.")

    genuine_records, impostor_records, used_genuine, used_impostor = build_records(
        samples, args.resample, args.metric
    )
    if not genuine_records or not impostor_records:
        raise SystemExit("Not enough labelled samples to evaluate.")

    genuine_shape = np.array([r["shape"] for r in genuine_records], dtype=float)
    genuine_behaviour = np.array([r["behaviour"] for r in genuine_records], dtype=float)
    finite_shape = genuine_shape[np.isfinite(genuine_shape)]
    shape_threshold = (
        float(np.quantile(finite_shape, args.shape_accept)) if finite_shape.size else math.inf
    )

    def norm(values: np.ndarray) -> Tuple[float, float]:
        values = values[np.isfinite(values)]
        if values.size == 0:
            return 0.0, 1.0
        median = float(np.median(values))
        q75, q25 = np.percentile(values, [75, 25])
        scale = float(q75 - q25)
        if scale < 1e-9:
            scale = float(values.std())
        if scale < 1e-9:
            scale = 1.0
        return median, scale

    shape_norm = norm(genuine_shape)
    behaviour_norm = norm(genuine_behaviour)
    finite_behaviour = [
        record["behaviour"]
        for record in genuine_records + impostor_records
        if np.isfinite(record["behaviour"])
    ]
    gate_penalty = (max(finite_behaviour) + 1.0) if finite_behaviour else 1.0

    modes = ["shape", "behaviour", "gate", "weighted"] if args.mode == "all" else [args.mode]
    results = {}
    scores_by_mode = {}
    for mode in modes:
        genuine_scores = mode_scores(
            genuine_records,
            mode,
            shape_threshold,
            shape_norm,
            behaviour_norm,
            args.w_shape,
            args.w_behaviour,
            gate_penalty,
        )
        impostor_scores = mode_scores(
            impostor_records,
            mode,
            shape_threshold,
            shape_norm,
            behaviour_norm,
            args.w_shape,
            args.w_behaviour,
            gate_penalty,
        )
        metrics = eer_and_curve(genuine_scores, impostor_scores)
        ci = bootstrap_eer(genuine_scores, impostor_scores, args.bootstrap, args.seed)
        results[mode] = {
            "eer": metrics["eer"],
            "eer_ci95": ci,
            "threshold": metrics["threshold"],
            "auc": metrics["auc"],
            "n_genuine": int(genuine_scores.size),
            "n_impostor": int(impostor_scores.size),
        }
        scores_by_mode[mode] = (genuine_scores, impostor_scores, metrics)

    warning = None
    if len(impostor_records) < 20 or len({r["target"] for r in impostor_records}) < 5:
        warning = "pilot only: fewer than 20 impostor scores or 5 impostor sources; EER is unstable."
        print("WARNING: " + warning, file=sys.stderr)

    os.makedirs(args.outdir, exist_ok=True)
    write_features(os.path.join(args.outdir, "features.csv"), samples)

    primary = "gate" if args.mode == "all" else modes[0]
    genuine_scores, impostor_scores, metrics = scores_by_mode[primary]
    threshold = metrics["threshold"]
    with open(os.path.join(args.outdir, "scores.csv"), "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["sample_id", "subject", "target", "condition", "mode", "score", "accepted_at_eer"])
        for record, score in zip(genuine_records + impostor_records, np.concatenate([scores_by_mode[primary][0], scores_by_mode[primary][1]])):
            accepted = "" if threshold is None else str(bool(score <= threshold)).lower()
            writer.writerow([record["sample"].sid, record["sample"].subject, record["target"], record["sample"].condition, primary, f"{score:.6g}", accepted])

    payload = {
        "config": vars(args),
        "counts": {
            "samples": len(samples),
            "genuine": len(genuine_records),
            "impostor": len(impostor_records),
            "subjects": sorted({s.subject for s in samples}),
        },
        "shape_threshold": shape_threshold,
        "results": results,
        "warning": warning,
    }
    with open(os.path.join(args.outdir, "metrics.json"), "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, ensure_ascii=False)

    primary_metrics = scores_by_mode[primary][2]
    write_score_svg(
        os.path.join(args.outdir, "score_distribution.svg"),
        scores_by_mode[primary][0],
        scores_by_mode[primary][1],
        primary_metrics["threshold"],
        primary,
    )
    write_det_svg(
        os.path.join(args.outdir, "det_curve.svg"),
        primary_metrics["far"],
        primary_metrics["frr"],
        primary_metrics["eer"],
    )

    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
