"""Báo cáo đối soát STAGING (V2-2B): Excel  vs  DB staging đã đóng/mở lại.

Chạy:  python staging_report.py --xlsx <file.xlsx> --dir <thư mục staging (ngoài git)>
Đọc:   import_plan.json, plan_arithmetic.json, staging_result.json, staging.sqlite (chỉ đọc)
Ghi:   staging_reconciliation.csv, staging_import_schedule.csv, staging_import_result.md
KHÔNG ghi file nguồn/DB.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audit  # noqa: E402


def money(v):
    return f"{int(v):,}".replace(",", ".")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--xlsx", required=True)
    ap.add_argument("--dir", required=True)
    a = ap.parse_args()
    D = a.dir
    ld = lambda n: json.load(open(os.path.join(D, n), encoding="utf-8"))  # noqa: E731
    plan, arith, res = ld("import_plan.json"), ld("plan_arithmetic.json"), ld("staging_result.json")
    structure, _h, _raw, _stray, _types, cell, _sup = audit.extract(a.xlsx)
    assert structure["sha256"] == plan["workbookSha256"], "workbook khác với kế hoạch"
    st = res["afterReopen"]
    summ, counts = st["summary"], st["counts"]
    rows = []  # (section, label, excelCell/expected-source, expected, actual)

    def chk(section, label, ref, expected, actual):
        rows.append(dict(section=section, label=label, ref=ref, expected=expected, actual=actual,
                         delta=None if not isinstance(expected, (int, float)) or not isinstance(actual, (int, float)) else actual - expected,
                         ok=expected == actual))

    # ---------- 66 chỉ tiêu (giống V2-2A) trên DB đã lưu ----------
    chk("Số dư cuối", "Vợ Khả dụng", "Tổng hợp!L3", cell["L3"], summ["availableVo"])
    chk("Số dư cuối", "Chồng Khả dụng", "Tổng hợp!L7", cell["L7"], summ["availableChong"])
    chk("Số dư cuối", "Vợ Tiết kiệm (tổng)", "Tổng hợp!L4", cell["L4"], summ["savingsVo"])
    chk("Số dư cuối", "Chồng Tiết kiệm (tổng)", "Tổng hợp!L8+70.000.000", cell["L8"] + 70000000, summ["savingsChong"])
    chk("Số dư cuối", "Chồng Tiết kiệm CHƯA PHÂN BỔ", "Tổng hợp!L8/T6", cell["L8"], summ["savingsChongByAsset"]["savings_unallocated"])
    chk("Số dư cuối", "Chồng Tiết kiệm NGÂN HÀNG", "L8: 30+10+10+10+10 tr", 70000000, summ["savingsChongByAsset"]["savings_bank"])
    chk("Số dư cuối", "Tổng tài sản", "L3+L4+L7+L8+70tr", cell["L3"] + cell["L4"] + cell["L7"] + cell["L8"] + 70000000, summ["totalAssets"])
    chk("Số dư cuối", "Thu nhập ròng cả năm", "Tổng hợp!O22", cell["O22"], summ["grouped"]["netIncome"])
    cats = ["Thu nhập", "Sinh hoạt", "Đầu tư", "Tự thưởng", "Cho đi", "Tiết kiệm", "Dâng hiến", "Chồng đưa vợ", "Vợ đưa chồng"]
    for period, (r0, title) in {"month": (5, "tháng 9/2026"), "year": (18, "cả năm 2026"), "day": (31, "ngày 17/09/2026")}.items():
        p = st["periods"][period]
        for i, c in enumerate(cats):
            r = r0 + i
            if c in ("Chồng đưa vợ", "Vợ đưa chồng"):
                chk(f"Hạng mục · {title}", f"{c} (toàn bộ)", f"Tổng hợp!C{r}", cell.get(f"C{r}", 0), p["all"].get(c, 0))
            else:
                chk(f"Hạng mục · {title}", f"Vợ · {c}", f"Tổng hợp!C{r}", cell.get(f"C{r}", 0), p["vo"].get(c, 0))
                chk(f"Hạng mục · {title}", f"Chồng · {c}", f"Tổng hợp!H{r}", cell.get(f"H{r}", 0), p["chong"].get(c, 0))
    g9 = st["groupedByMonth"]["9"]
    chk("Tháng 9/2026", "Thu nhập ròng tháng 9 (Vợ+Chồng)", "Tổng hợp!O12", cell["O12"], g9["all"]["netIncome"])
    chk("Tháng 9/2026", "Vợ · Thu nhập ròng tháng 9", "Tổng hợp!C5", cell["C5"], g9["vo"]["netIncome"])
    chk("Tháng 9/2026", "Chồng · Thu nhập ròng tháng 9", "Tổng hợp!H5", cell["H5"], g9["chong"]["netIncome"])
    ss = st["statusSumsSep"]
    for ref, cat, s in [("L17", "Dâng hiến", "Đã chuẩn bị"), ("L18", "Dâng hiến", "Đã dâng"), ("L19", "Dâng hiến", "Đã gửi"),
                        ("L22", "Cho đi", "Chưa chuẩn bị"), ("L23", "Cho đi", "Đã chuẩn bị"), ("L24", "Cho đi", "Đã dâng"), ("L25", "Cho đi", "Đã gửi")]:
        chk("Trạng thái · tháng 9/2026", f"{cat} · {s}", f"Tổng hợp!{ref}", cell.get(ref, 0), ss.get(f"{cat}|{s}", 0))
    n_excel_checks = len(rows)

    # ---------- Chỉ tiêu báo cáo theo chủ dự án ----------
    grp = summ["grouped"]
    chk("Báo cáo", "Doanh thu", "chủ dự án", 301954000, grp["revenue"])
    chk("Báo cáo", "Chi phí kinh doanh", "chủ dự án", 24790000, grp["businessExpense"])
    chk("Báo cáo", "Thu nhập ròng", "chủ dự án", 277164000, grp["netIncome"])
    chk("Báo cáo", "Chi tiêu", "chủ dự án", 220559000, grp["spending"])
    chk("Báo cáo", "Khoản thu khác (tổng sau nhập)", "7.786.000 + 16.187.000", 23973000, grp["otherInflow"])
    chk("Báo cáo", "Quỹ (số dư lịch sử nhập)", "chủ dự án", 0, summ["totalFunds"])

    # ---------- Đếm & định danh (từ dòng đã lưu) ----------
    chk("Đếm", "Số giao dịch trong DB", "1.802 + 4 + 1", 1807, counts["transactions"])
    chk("Đếm", "Số giao dịch kế hoạch", "plan", 1807, counts["planTransactions"])
    chk("Đếm", "Danh mục nhập", "plan", len(plan["categories"]), counts["importedCategories"])
    chk("Đếm", "Trạng thái nhập", "plan", sum(len(c["statuses"]) for c in plan["categories"]), counts["importedStatuses"])
    chk("Đếm", "clientTxId khác nhau", "= số giao dịch", 1807, counts["distinctClientTxIds"])
    chk("Đếm", "id khác nhau", "= số giao dịch", 1807, counts["distinctIds"])
    chk("Toàn vẹn", "Dòng lưu khác kế hoạch", "0", 0, counts["mismatchedVsPlan"])
    chk("Toàn vẹn", "Cặp danh mục/trạng thái sai", "0", 0, counts["invalidCategoryStatusPairs"])
    chk("Toàn vẹn", "Tham chiếu danh mục treo", "0", 0, counts["danglingCategoryRefs"])
    chk("Toàn vẹn", "Pool bảo vệ âm", "0", 0, len(counts["negativeProtectedPools"]))
    chk("Toàn vẹn", "Số tiền ≤ 0", "0", 0, counts["zeroOrNegativeAmounts"])
    chk("Toàn vẹn", "Trạng thái trên Chuyển/Tiết kiệm", "0", 0, counts["statusOnSystemTransfer"])
    chk("Migration", "Giao dịch số dư đầu kỳ", "4", 4, counts["openingTransactions"])
    chk("Migration", "Giao dịch phân bổ Ngân hàng (SAVINGS_CONVERT)", "1", 1, counts["bankConverts"])
    chk("Idempotency", "Lần 2: giao dịch mới tạo", "0", 0, res["secondRun"]["transactionsCreated"])
    chk("Idempotency", "Lần 2: danh mục mới tạo", "0", 0, res["secondRun"]["categoriesCreated"])
    chk("Idempotency", "Lần 2: trạng thái mới tạo", "0", 0, res["secondRun"]["statusesCreated"])
    chk("Idempotency", "Lần 2: tổng giao dịch", "1807", 1807, res["afterSecondRun"]["counts"]["transactions"])
    chk("Idempotency", "Số dư không đổi sau lần 2", "true", True, res["idempotent"])

    # ---------- SQLite (chỉ đọc) ----------
    db = sqlite3.connect("file:" + os.path.join(D, "staging.sqlite").replace("\\", "/") + "?mode=ro", uri=True)
    q = lambda s: db.execute(s).fetchall()  # noqa: E731
    chk("SQLite", "user_version", "7", 7, q("pragma user_version")[0][0])
    chk("SQLite", "integrity_check", "ok", "ok", q("pragma integrity_check")[0][0])
    chk("SQLite", "foreign_key_check (số dòng)", "0", 0, len(q("pragma foreign_key_check")))
    chk("SQLite", "clientTxId trùng", "0", 0, q("select count(*) from (select client_tx_id from transaction_rows group by client_tx_id having count(*)>1)")[0][0])
    chk("SQLite", "Cặp danh mục/trạng thái sai (SQL)", "0", 0, q("select count(*) from transaction_rows t join status_rows s on s.id=t.status_id where s.category_id<>t.category_id")[0][0])
    chk("SQLite", "reversal/correction treo", "0", 0, q("""select count(*) from transaction_rows t where
        (t.reversal_of_tx_id is not null and t.reversal_of_tx_id not in (select id from transaction_rows)) or
        (t.reversed_by_tx_id is not null and t.reversed_by_tx_id not in (select id from transaction_rows)) or
        (t.corrects_tx_id is not null and t.corrects_tx_id not in (select id from transaction_rows))""")[0][0])
    chk("SQLite", "Giao dịch amount ≤ 0", "0", 0, q("select count(*) from transaction_rows where amount_minor<=0")[0][0])
    chk("SQLite", "SAVINGS_CONVERT 70.000.000", "1", 1, q("select count(*) from transaction_rows where transfer_kind='savingsConvert' and amount_minor=70000000")[0][0])
    chk("SQLite", "Giao dịch số dư đầu kỳ", "4", 4, q("select count(*) from transaction_rows where category_id='imp_so_du_dau_ky'")[0][0])
    chk("SQLite", "Danh mục không thuộc hệ thống/kế hoạch", "0", 0, q("select count(*) from category_rows where is_default=0 and id not like 'imp\\_%' escape '\\'")[0][0])
    chk("SQLite", "Danh mục tên 'Vợ chồng'", "0", 0, q("select count(*) from category_rows where name like '%Vợ chồng%'")[0][0])
    chk("SQLite", "Quỹ", "an_uong (mặc định, 0 đ)", ["an_uong"], [r[0] for r in q("select id from fund_rows")])
    chk("SQLite", "Loại tiết kiệm", "savings_bank", ["savings_bank"], [r[0] for r in q("select id from savings_asset_type_rows")])
    src_rows = {int(t["sourceRow"]) for t in plan["transactions"] if t["role"] == "src"}
    skipped_rows = {e["mirrorRow"] for e in arith["mirrorReport"]}
    chk("SQLite", "Dòng 'Vợ chồng' (13) được nhập", "0", 0, len(src_rows & skipped_rows))
    chk("SQLite", "Dòng 978 (số 0) được nhập", "0", 0, 1 if 978 in src_rows else 0)
    chk("SQLite", "Giao dịch ngày tương lai giữ nguyên", "3 dòng", 3, len(counts["futureDated"]))
    db.close()

    ok_all = all(r["ok"] for r in rows)
    with open(os.path.join(D, "staging_reconciliation.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=["section", "label", "ref", "expected", "actual", "delta", "ok"])
        w.writeheader()
        w.writerows(rows)

    # ---------- lịch ghi ----------
    order = res["firstRun"]["schedule"]["order"]
    plan_by = {t["clientTxId"]: t for t in plan["transactions"]}
    chrono = sorted(plan["transactions"], key=lambda t: (t["date"], t["sourceRow"], t["id"]))
    chrono_idx = {t["clientTxId"]: i + 1 for i, t in enumerate(chrono)}
    with open(os.path.join(D, "staging_import_schedule.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["writePosition", "chronologicalPosition", "delayedBy", "clientTxId", "sourceRow", "role", "date", "type", "amountMinor"])
        for o in order:
            t = plan_by[o["clientTxId"]]
            w.writerow([o["pos"], chrono_idx[o["clientTxId"]], max(0, o["pos"] - chrono_idx[o["clientTxId"]]), o["clientTxId"], t["sourceRow"], t["role"], t["date"], t["type"], t["amountMinor"]])

    sch = res["firstRun"]["schedule"]
    L = []
    w_ = L.append
    w_("# V2-2B — Staging import: kết quả\n")
    w_(f"Workbook SHA-256 `{plan['workbookSha256']}` · importer `{plan['importerVersion']}` · DB staging (KHÔNG phải Pixel/app).\n")
    w_(f"**Kết luận đối soát: {'PASS' if ok_all else 'FAIL'}** — {sum(1 for r in rows if r['ok'])}/{len(rows)} chỉ tiêu đạt (trong đó {n_excel_checks} chỉ tiêu Excel↔DB, chênh lệch 0).\n")
    w_(f"- Lần nhập 1: tạo {res['firstRun']['categoriesCreated']} danh mục, {res['firstRun']['statusesCreated']} trạng thái, {res['firstRun']['transactionsCreated']} giao dịch. Lần 2: tạo 0/0/0, {res['secondRun']['transactionsExisting']} giao dịch đã có.")
    w_(f"- Lập lịch ghi: {sch['total']} giao dịch; {sch['skipAheadPlacements']} lần bỏ qua giao dịch sớm hơn; {sch['delayedTransactions']} giao dịch ghi muộn hơn vị trí theo ngày; số dư nhỏ nhất mỗi pool: {sch['minBalances']}.")
    w_("- Quy tắc: sắp theo (ngày, dòng nguồn, id); lặp: ghi giao dịch ĐẦU TIÊN mà pool nguồn đủ tiền (`wouldGoNegative` của Financial Core); không ngẫu nhiên; không có → dừng.\n")
    w_("| Mục | Chỉ tiêu | Tham chiếu | Kỳ vọng | Thực tế | Δ |\n|---|---|---|---:|---:|---:|")
    for r in rows:
        num = isinstance(r["expected"], (int, float)) and not isinstance(r["expected"], bool)
        w_(f"| {r['section']} | {r['label']} | {r['ref']} | {money(r['expected']) if num else r['expected']} | {money(r['actual']) if num else r['actual']} | {money(r['delta']) if r['delta'] is not None else ''} |")
    open(os.path.join(D, "staging_import_result.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
    print("checks", len(rows), "ok", sum(1 for r in rows if r["ok"]), "excel-checks", n_excel_checks, "ALL OK" if ok_all else "FAIL")
    for r in rows:
        if not r["ok"]:
            print("  FAIL", r)


if __name__ == "__main__":
    main()
