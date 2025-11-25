# build_dataset.py
#
# Reads Arduino training stream and appends rows into ONE Excel file:
#   sensor_samples.xlsx
#
# Expected Arduino lines:
#   BASELINE_SAVED
#   BASE_RAW_CSV=s1,s2,s3,s4,s5
#   SAMPLE_RAW_CSV=s1..s11
#   END_SAMPLE
#

import os
import time
import math
import serial
import pandas as pd


PORT = "COM4"
BAUDRATE = 115200

OUT_XLSX = "sensor_samples.xlsx"

EPS = 1.0

S_COLS = [f"s{i}" for i in range(1, 12)]  # s1..s11
B_COLS = [f"b{i}" for i in range(1, 6)]   # b1..b5


PD_COLS = ["p1", "dp1", "p2", "dp2", "p3", "dp3", "p4", "dp4", "p5", "dp5"]
R_COL = "r"
LABEL_COL = "label"

ALL_COLS = S_COLS + [LABEL_COL] + B_COLS + PD_COLS + [R_COL]

def parse_csv_after(prefix: str, line: str, expected_n: int):
    if not line.startswith(prefix):
        return None
    part = line[len(prefix):].strip()
    items = [x.strip() for x in part.split(",")]
    if len(items) != expected_n:
        return None
    try:
        return [float(x) for x in items]
    except ValueError:
        return None


def load_or_create_df(path: str) -> pd.DataFrame:
    if os.path.exists(path):
        df = pd.read_excel(path)
        df.columns = [str(c).strip() for c in df.columns]
        # ensure all columns exist
        for c in ALL_COLS:
            if c not in df.columns:
                df[c] = None
        df = df[ALL_COLS]
        print(f"[+] Loaded existing: {path} (rows={len(df)})")
        return df
    else:
        df = pd.DataFrame(columns=ALL_COLS)
        print(f"[+] Created new dataset: {path}")
        return df


def save_to_excel_or_fail(df: pd.DataFrame, primary_path: str) -> str:
    """
    Save ONLY to primary_path.
    If the file is open in Excel (PermissionError), print a clear message and re-raise.
    """
    try:
        df.to_excel(primary_path, index=False)
        print(f"[OK] Saved: {primary_path}")
        return primary_path
    except PermissionError as e:
        print(
            f"[ERROR] Couldn't write '{primary_path}' because it is open/locked.\n"
            f"        Close Excel (or any program holding the file) and rerun."
        )
        raise


def compute_features(sample_s1_5, baseline_b1_5):
    # baseline distribution (pb)
    Bsum = sum(baseline_b1_5)
    pb = [(b / (Bsum + EPS)) for b in baseline_b1_5]

    # sample distribution (p)
    S = sum(sample_s1_5)
    p = [(x / (S + EPS)) for x in sample_s1_5]

    # dp = p - pb
    dp = [p[i] - pb[i] for i in range(5)]

    # r = log((S+eps)/(Bsum+eps))
    r = math.log((S + EPS) / (Bsum + EPS))

    return p, dp, r


def append_row(df: pd.DataFrame, s_vals_11, label, baseline_b1_5, p, dp, r):
    row = {}

    # s1..s11
    for i, col in enumerate(S_COLS):
        row[col] = float(s_vals_11[i])

    row[LABEL_COL] = int(label)

    # b1..b5
    for i, col in enumerate(B_COLS):
        row[col] = float(baseline_b1_5[i])

    # p/dp interleaved
    row["p1"] = float(p[0]); row["dp1"] = float(dp[0])
    row["p2"] = float(p[1]); row["dp2"] = float(dp[1])
    row["p3"] = float(p[2]); row["dp3"] = float(dp[2])
    row["p4"] = float(p[3]); row["dp4"] = float(dp[3])
    row["p5"] = float(p[4]); row["dp5"] = float(dp[4])

    row[R_COL] = float(r)

    df.loc[len(df)] = row
    return df


def main():
    ser = serial.Serial(PORT, baudrate=BAUDRATE, timeout=1)
    time.sleep(2)

    df = load_or_create_df(OUT_XLSX)

    baseline_b = None  # list of 5 floats

    print("\n=== TRAINING LOGGER ===")
    print("1) Flip OFF->ON once in NORMAL posture to CAPTURE baseline.")
    print("   Arduino prints BASELINE_SAVED + BASE_RAW_CSV=...")
    print("2) Then each OFF->ON creates one sample row (SAMPLE_RAW_CSV + END_SAMPLE).")
    print("3) Python will ask you label 1..6 for each sample.\n")

    while True:
        line = ser.readline().decode("ascii", errors="ignore").strip()
        if not line:
            continue

        print("[ARDUINO]", line)

        # baseline capture
        if line == "BASELINE_SAVED":
            # next line should be BASE_RAW_CSV
            while True:
                l2 = ser.readline().decode("ascii", errors="ignore").strip()
                if not l2:
                    continue
                print("[ARDUINO]", l2)
                vals = parse_csv_after("BASE_RAW_CSV=", l2, 5)
                if vals is not None:
                    baseline_b = vals
                    print("[OK] Baseline stored (b1..b5). Now start collecting samples.\n")
                    break
            continue

        # sample capture start
        sample = parse_csv_after("SAMPLE_RAW_CSV=", line, 11)
        if sample is None:
            continue

        # wait for END_SAMPLE
        while True:
            end_line = ser.readline().decode("ascii", errors="ignore").strip()
            if not end_line:
                continue
            print("[ARDUINO]", end_line)
            if end_line == "END_SAMPLE":
                break

        if baseline_b is None:
            print("[!] No baseline yet. Flip OFF->ON once to capture baseline first.\n")
            continue

        # ask label
        label_str = input("Enter label (1-6): ").strip()
        try:
            label = int(label_str)
            if not (1 <= label <= 6):
                raise ValueError()
        except ValueError:
            print("[!] Invalid label. Sample skipped.\n")
            continue

        s1_5 = sample[0:5]
        p, dp, r = compute_features(s1_5, baseline_b)

        df = append_row(df, sample, label, baseline_b, p, dp, r)

        saved_path = save_to_excel_or_fail(df, OUT_XLSX)
        print(f"[+] Row added. Total rows={len(df)} (saved to {saved_path})\n")


if __name__ == "__main__":
    main()
