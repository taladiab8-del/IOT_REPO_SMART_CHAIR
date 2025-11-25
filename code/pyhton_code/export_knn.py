import numpy as np
import pandas as pd

# ---------- CONFIG ----------
INPUT_XLSX  = "sensor_samples.xlsx"
OUTPUT_H    = "dataset.h"

ROW_TYPE_COL = None
ROW_TYPE_TRAIN_VALUE = "train"

LABEL_COL = "label"

# p1, dp1, p2, dp2, p3, dp3, p4, dp4, p5, dp5, r
P_COLS  = ["p1", "p2", "p3", "p4", "p5"]
DP_COLS = ["dp1", "dp2", "dp3", "dp4", "dp5"]
R_COL   = "r"

# [dp1..dp5, p1..p5, r]
FEATURE_ORDER = DP_COLS + P_COLS + [R_COL]

def sanitize_df(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df.columns = [str(c).strip() for c in df.columns]
    return df

def filter_training_rows(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()

    if ROW_TYPE_COL is not None and ROW_TYPE_COL in df.columns:
        df = df[df[ROW_TYPE_COL].astype(str).str.strip().str.lower() == ROW_TYPE_TRAIN_VALUE]

    needed = FEATURE_ORDER + [LABEL_COL]
    for c in needed:
        if c not in df.columns:
            raise ValueError(f"Missing required column: '{c}'")

    df = df.dropna(subset=needed)
    return df

def compute_mean_std(X: np.ndarray):
    mean = X.mean(axis=0)
    std = X.std(axis=0, ddof=0)
    std[std == 0.0] = 1.0
    return mean, std

def scale_z(X: np.ndarray, mean: np.ndarray, std: np.ndarray) -> np.ndarray:
    return (X - mean) / std

def write_dataset_h(path: str, X_scaled: np.ndarray, y: np.ndarray, mean: np.ndarray, std: np.ndarray):
    n_samples, n_features = X_scaled.shape

    def ffmt(v: float) -> str:
        return f"{v:.6f}f"

    with open(path, "w", encoding="utf-8") as f:
        f.write("#pragma once\n\n")
        f.write(f"#define N_SAMPLES {n_samples}\n")
        f.write(f"#define N_FEATURES {n_features}\n\n")

        # mean/std used on-board before distance calculation
        f.write("const float FEATURE_MEAN[N_FEATURES] = {\n  ")
        f.write(", ".join(ffmt(v) for v in mean))
        f.write("\n};\n\n")

        f.write("const float FEATURE_STD[N_FEATURES] = {\n  ")
        f.write(", ".join(ffmt(v) for v in std))
        f.write("\n};\n\n")

        f.write("const float TRAIN_SAMPLES[N_SAMPLES][N_FEATURES] = {\n")
        for i in range(n_samples):
            row = ", ".join(ffmt(v) for v in X_scaled[i])
            f.write(f"  {{{row}}}")
            f.write(",\n" if i != n_samples - 1 else "\n")
        f.write("};\n\n")

        f.write("const int TRAIN_LABELS[N_SAMPLES] = {\n  ")
        f.write(", ".join(str(int(v)) for v in y))
        f.write("\n};\n")

    print(f"[OK] Wrote: {path}")
    print(f"     Samples: {n_samples}, Features: {n_features}")
    print(f"     Feature order used: {FEATURE_ORDER}")

def main():
    df = pd.read_excel(INPUT_XLSX)
    df = sanitize_df(df)

    df_train = filter_training_rows(df)

    # Build X in correct order: [dp1..dp5, p1..p5, r]
    X = df_train[FEATURE_ORDER].astype(float).to_numpy()
    y = df_train[LABEL_COL].astype(int).to_numpy()

    mean, std = compute_mean_std(X)
    X_scaled = scale_z(X, mean, std)

    write_dataset_h(OUTPUT_H, X_scaled, y, mean, std)

if __name__ == "__main__":
    main()
