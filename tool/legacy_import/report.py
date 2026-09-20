"""Sinh báo cáo audit + đối soát từ đầu ra của audit.py và mô phỏng Dart.

Chạy:  python report.py --out <thư mục đầu ra>
Đọc: audit_stats.json, records.json, sim_input.json, sim_output.json (đều trong --out).
Ghi: real_data_import_audit.md, reconciliation.csv, reconciliation.md, report_facts.json
KHÔNG ghi file nguồn, KHÔNG chạm DB.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import re
from collections import Counter, defaultdict

from md_report import write_md


def load(out, name):
    with open(os.path.join(out, name), encoding="utf-8") as f:
        return json.load(f)


def money(v):
    return f"{int(v):,}".replace(",", ".")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    out = ap.parse_args().out
    stats = load(out, "audit_stats.json")
    recs = load(out, "records.json")
    sim_in = load(out, "sim_input.json")
    sim = load(out, "sim_output.json")
    cell = stats["summaryCells"]
    facts = {}

    # ---------------- phân phối ----------------
    rows = [r for r in recs]
    with_amt = [r for r in rows if r["rawAmount"] is not None]
    cat_tab = defaultdict(lambda: {"n": 0, "pos": 0, "posSum": 0, "neg": 0, "negSum": 0, "blank": 0})
    for r in rows:
        k = r["rawCategory"] if r["rawCategory"] is not None else "(trống)"
        t = cat_tab[k]
        t["n"] += 1
        a = r["rawAmount"]
        if a is None:
            t["blank"] += 1
        elif a > 0:
            t["pos"] += 1
            t["posSum"] += int(a)
        elif a < 0:
            t["neg"] += 1
            t["negSum"] += int(a)
    facts["categoryDistribution"] = cat_tab

    member_tab = Counter(repr(r["rawMember"]) for r in rows)
    member_by_class = defaultdict(Counter)
    for r in rows:
        member_by_class[r["cls"]][r["rawMember"] if r["rawMember"] is not None else "(trống)"] += 1
    facts["memberDistribution"] = dict(member_tab)
    facts["memberByClass"] = {k: dict(v) for k, v in member_by_class.items()}

    status_by_cat = defaultdict(Counter)
    for r in rows:
        if r["rawStatus"] is not None:
            status_by_cat[r["rawCategory"] or "(trống)"][r["rawStatus"]] += 1
    nostatus = sum(1 for r in rows if r["rawStatus"] is None and r["cls"].startswith("IMPORT"))
    facts["statusByRawCategory"] = {k: dict(v) for k, v in status_by_cat.items()}
    status_by_prop = defaultdict(Counter)
    for r in rows:
        if r["cls"].startswith("IMPORT") and r["statusProposal"]:
            cid = next((t["categoryId"] for t in sim_in["transactions"] if t["row"] == r["sourceRow"]), None)
            status_by_prop[cid][r["statusProposal"]] += 1
    facts["statusByProposedCategory"] = {k: dict(v) for k, v in status_by_prop.items()}
    facts["importNoStatusCount"] = nostatus

    # ---------------- ngày ----------------
    dated = [(dt.datetime.fromisoformat(r["rawDate"]), r) for r in rows if r["rawDate"]]
    tx_dated = [(d, r) for d, r in dated if r["rawAmount"] is not None]
    by_month = Counter(d.strftime("%Y-%m") for d, r in tx_dated)
    by_year = Counter(d.year for d, r in tx_dated)
    ts_counter = Counter(r["rawDate"] for d, r in tx_dated)
    dup_ts = {k: v for k, v in ts_counter.items() if v > 1}
    midnight = sum(1 for d, r in tx_dated if d.hour == d.minute == d.second == 0 and d.microsecond == 0)
    facts["dates"] = {
        "earliest": min(d for d, r in tx_dated).isoformat(), "latest": max(d for d, r in tx_dated).isoformat(),
        "byYear": dict(by_year), "byMonth": dict(sorted(by_month.items())), "invalid": sum(1 for r in rows if r["rawDate"] is None),
        "duplicateTimestampGroups": len(dup_ts), "duplicateTimestampRows": sum(dup_ts.values()),
        "dateOnlyMidnightRows": midnight,
    }
    summary_day = dt.datetime(int(cell["F1"]), int(cell["D1"]), int(cell["B1"]))
    import_day = dt.datetime(2026, 9, 20)
    facts["cutoffs"] = {"summaryOperatingDate": summary_day.date().isoformat(), "importDate": import_day.date().isoformat()}
    after_summary = [r["sourceRow"] for d, r in tx_dated if d.date() > summary_day.date()]
    future = [r for d, r in tx_dated if d.date() > import_day.date()]
    facts["afterSummaryDateRows"] = after_summary
    facts["futureRows"] = [
        {"row": r["sourceRow"], "date": r["rawDate"], "category": r["rawCategory"], "amount": r["rawAmount"],
         "member": r["rawMember"], "status": r["rawStatus"], "cls": r["cls"]} for r in future]

    # ---------------- ghi chú ----------------
    notes = [r["rawNote"] for r in rows if r["cls"] in ("IMPORT_REVENUE", "IMPORT_BUSINESS_EXPENSE", "IMPORT_SPENDING", "IMPORT_OTHER_INFLOW", "IMPORT_SAVINGS_TOPUP", "IMPORT_SAVINGS_WITHDRAW", "IMPORT_MEMBER_TRANSFER")]
    blank_notes = sum(1 for n in notes if n is None or (isinstance(n, str) and n.strip() == ""))
    padded = sum(1 for n in notes if isinstance(n, str) and n != n.strip())
    ctrl = sum(1 for n in notes if isinstance(n, str) and re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", n))
    multiline = sum(1 for n in notes if isinstance(n, str) and "\n" in n)
    facts["notes"] = {"importable": len(notes), "blank": blank_notes, "padded": padded, "controlChars": ctrl, "multiline": multiline}

    # ---------------- class sums ----------------
    class_sum = defaultdict(int)
    class_n = Counter()
    for r in rows:
        class_n[r["cls"]] += 1
        if r["cls"].startswith("IMPORT"):
            class_sum[r["cls"]] += r["amountMinor"]
    facts["classCounts"] = dict(class_n)
    facts["classSums"] = dict(class_sum)

    # ---------------- tiết kiệm ----------------
    sav = defaultdict(lambda: {"topup": 0, "topupN": 0, "withdraw": 0, "withdrawN": 0})
    for r in rows:
        if r["cls"] == "IMPORT_SAVINGS_TOPUP":
            sav[r["member"]]["topup"] += r["amountMinor"]; sav[r["member"]]["topupN"] += 1
        if r["cls"] == "IMPORT_SAVINGS_WITHDRAW":
            sav[r["member"]]["withdraw"] += r["amountMinor"]; sav[r["member"]]["withdrawN"] += 1
    facts["savings"] = {k: dict(v, net=v["topup"] - v["withdraw"]) for k, v in sav.items()}

    # ---------------- âm theo NGÀY (phân biệt lỗi thứ tự trong ngày) ----------------
    txs = sim_in["openings"] + sim_in["transactions"]
    def day_negative():
        by_day = defaultdict(list)
        for t in txs:
            by_day[t["date"][:10]].append(t)
        bal = defaultdict(int)
        neg_days = defaultdict(list)
        for day in sorted(by_day):
            for t in by_day[day]:  # cuối ngày: cộng dồn cả ngày
                if t["sourceKind"] != "external":
                    bal[(t["sourceKind"], t["sourceRefId"])] -= t["amountMinor"]
                if t["destinationKind"] != "external":
                    bal[(t["destinationKind"], t["destinationRefId"])] += t["amountMinor"]
            for k, v in bal.items():
                if v < 0:
                    neg_days[f"{k[0]}|{k[1]}"].append((day, v))
        return {k: {"days": len(v), "worst": min(x[1] for x in v), "worstDay": min(v, key=lambda x: x[1])[0]} for k, v in neg_days.items()}
    facts["endOfDayNegative"] = day_negative()

    # ---------------- ĐỐI SOÁT Excel vs engine ----------------
    recon = []

    def add(section, label, excel_cell, excel, engine):
        recon.append({"section": section, "label": label, "excelCell": excel_cell, "excel": excel,
                      "dryRun": engine, "delta": None if (excel is None or engine is None) else engine - excel})

    base, optA = sim["base"], sim["optionA_whatIf"]
    add("Số dư cuối", "Vợ Khả dụng", "Tổng hợp!L3", cell["L3"], base["availableVo"])
    add("Số dư cuối", "Chồng Khả dụng", "Tổng hợp!L7", cell["L7"], base["availableChong"])
    add("Số dư cuối", "Vợ Tiết kiệm (tổng)", "Tổng hợp!L4", cell["L4"], base["savingsVo"])
    add("Số dư cuối", "Chồng Tiết kiệm (tổng, trước phân bổ Ngân hàng)", "Tổng hợp!L8+70.000.000", cell["L8"] + 70000000, base["savingsChong"])
    add("Số dư cuối", "Chồng Tiết kiệm CHƯA PHÂN BỔ (sau khi trừ 70tr Ngân hàng)", "Tổng hợp!L8/T6", cell["L8"], optA["savingsChongByAsset"]["savings_unallocated"])
    add("Số dư cuối", "Chồng Tiết kiệm NGÂN HÀNG", "(công thức L8: 30+10+10+10+10 tr)", 70000000, optA["savingsChongByAsset"]["ngan_hang"])
    add("Số dư cuối", "Tổng tài sản", "(L3+L4+L7+L8+70tr)", cell["L3"] + cell["L4"] + cell["L7"] + cell["L8"] + 70000000, base["totalAssets"])
    add("Số dư cuối", "Thu nhập ròng cả năm (Doanh thu − Chi phí KD)", "Tổng hợp!O22", cell["O22"], base["grouped"]["netIncome"])

    # Kỳ: năm / tháng / ngày; Vợ ở cột C, Chồng ở cột H
    cats = ["Thu nhập", "Sinh hoạt", "Đầu tư", "Tự thưởng", "Cho đi", "Tiết kiệm", "Dâng hiến", "Chồng đưa vợ", "Vợ đưa chồng"]
    blocks = {"month": (5, "tháng 9/2026"), "year": (18, "cả năm 2026"), "day": (31, "ngày 17/09/2026")}
    for period, (r0, title) in blocks.items():
        p = sim["periods"][period]
        for i, c in enumerate(cats):
            r = r0 + i
            if c in ("Chồng đưa vợ", "Vợ đưa chồng"):
                add(f"Hạng mục · {title}", f"{c} (toàn bộ)", f"Tổng hợp!C{r}", cell.get(f"C{r}", 0), p["all"].get(c, 0))
            else:
                add(f"Hạng mục · {title}", f"Vợ · {c}", f"Tổng hợp!C{r}", cell.get(f"C{r}", 0), p["vo"].get(c, 0))
                add(f"Hạng mục · {title}", f"Chồng · {c}", f"Tổng hợp!H{r}", cell.get(f"H{r}", 0), p["chong"].get(c, 0))
    # Thu nhập ròng tháng 9 (O12 = C5 + H5) khớp engine grouped(month=9)
    add("Tháng 9/2026", "Thu nhập ròng tháng 9 (Vợ+Chồng)", "Tổng hợp!O12", cell["O12"], sim["groupedByMonth"]["9"]["all"]["netIncome"])
    add("Tháng 9/2026", "Vợ · Thu nhập ròng tháng 9", "Tổng hợp!C5", cell["C5"], sim["groupedByMonth"]["9"]["vo"]["netIncome"])
    add("Tháng 9/2026", "Chồng · Thu nhập ròng tháng 9", "Tổng hợp!H5", cell["H5"], sim["groupedByMonth"]["9"]["chong"]["netIncome"])
    # Trạng thái (tháng 9) — SUMIFS không lọc thành viên
    ss = sim["statusSumsSep"]
    for cell_ref, cat, st in [("L17", "Dâng hiến", "Đã chuẩn bị"), ("L18", "Dâng hiến", "Đã dâng"), ("L19", "Dâng hiến", "Đã gửi"),
                              ("L22", "Cho đi", "Chưa chuẩn bị"), ("L23", "Cho đi", "Đã chuẩn bị"), ("L24", "Cho đi", "Đã dâng"), ("L25", "Cho đi", "Đã gửi")]:
        add("Trạng thái · tháng 9/2026", f"{cat} · {st}", f"Tổng hợp!{cell_ref}", cell.get(cell_ref, 0), ss.get(f"{cat}|{st}", 0))

    facts["reconciliationUnexplainedDeltas"] = [x for x in recon if x["delta"] not in (0, None)]
    with open(os.path.join(out, "reconciliation.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=["section", "label", "excelCell", "excel", "dryRun", "delta"])
        w.writeheader()
        w.writerows(recon)
    facts["reconRows"] = len(recon)

    with open(os.path.join(out, "reconciliation.md"), "w", encoding="utf-8") as f:
        f.write("# Đối soát: Excel (giá trị cache trong 'Tổng hợp') vs mô phỏng Financial Engine\n\n")
        f.write("| Mục | Chỉ tiêu | Ô Excel | Excel | Dry-run (engine) | Δ |\n|---|---|---|---:|---:|---:|\n")
        for x in recon:
            f.write(f"| {x['section']} | {x['label']} | {x['excelCell']} | {money(x['excel'])} | {money(x['dryRun'])} | {money(x['delta'])} |\n")

    # ---------------- thứ tự GHI không làm âm pool (chỉ tính toán, không ghi) ----------------
    remaining = sorted(txs, key=lambda t: (t["date"], t["row"]))
    bal = defaultdict(int)
    placed = deferred = 0
    stuck = False
    while remaining:
        for i, t in enumerate(remaining):
            violates = t["sourceKind"] != "external" and bal[(t["sourceKind"], t["sourceRefId"])] - t["amountMinor"] < 0
            if not violates:
                if i > 0:
                    deferred += 1
                if t["sourceKind"] != "external":
                    bal[(t["sourceKind"], t["sourceRefId"])] -= t["amountMinor"]
                if t["destinationKind"] != "external":
                    bal[(t["destinationKind"], t["destinationRefId"])] += t["amountMinor"]
                remaining.pop(i)
                placed += 1
                break
        else:
            stuck = True
            break
    facts["nonNegativeInsertionOrder"] = {"feasible": not stuck, "placed": placed,
                                          "outOfChronologicalPlacements": deferred, "stuckRemaining": len(remaining)}
    byrow = {r["sourceRow"]: r for r in recs}
    facts["duplicateDetails"] = [
        {"rows": g, "category": byrow[g[0]]["rawCategory"], "amount": byrow[g[0]]["rawAmount"],
         "member": byrow[g[0]]["rawMember"], "date": byrow[g[0]]["rawDate"], "status": byrow[g[0]]["rawStatus"],
         "note": byrow[g[0]]["rawNote"], "timestampIdentical": len({byrow[x]["rawDate"] for x in g}) == 1}
        for g in stats["duplicateGroups"]]
    facts["supportSheetVsGhiChep"] = [
        {"supportRow": x, "matchingGhiChepRows": [r["sourceRow"] for r in recs
                                                  if r["rawDate"] and r["rawDate"][:10] == x["date"]
                                                  and r["rawAmount"] == x["amount"] and r["rawCategory"] == "Thu nhập"]}
        for x in stats["supportSheetRows"]]
    missing_cells = [x["excelCell"] for x in recon if x["excelCell"].startswith("Tổng hợp!") and "+" not in x["excelCell"]
                     and x["excelCell"].split("!")[1] not in cell]
    facts["excelCellsDefaultedToZero"] = missing_cells

    write_md(out, stats, facts, recs, sim)
    json.dump(facts, open(os.path.join(out, "report_facts.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    print("recon rows", len(recon), "non-zero deltas", len(facts["reconciliationUnexplainedDeltas"]))
    for x in facts["reconciliationUnexplainedDeltas"]:
        print("  DELTA", x)


if __name__ == "__main__":
    main()
