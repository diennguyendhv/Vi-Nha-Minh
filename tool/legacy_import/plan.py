"""Dựng KẾ HOẠCH NHẬP (V2-2B) từ workbook — CHỈ ĐỌC, không ghi DB.

Chạy:  python plan.py --xlsx <file.xlsx> --out <thư mục ngoài git>

Sinh trong --out:
  import_plan.json          danh mục/trạng thái/giao dịch dự kiến (đầu vào của importer Dart)
  staging_import_plan.csv   mỗi giao dịch dự kiến + provenance (dòng Excel, raw*, cờ)
  plan_arithmetic.json      chứng minh số học 1838 = 1802 + 13 + 9 + 13 + 1; 1802 + 4 + 1 = 1807

Danh tính tất định (cùng workbook SHA-256 + cùng phiên bản importer → cùng id/clientTxId):
  id          = "imp-" + sha256("<sha>|<sheet>|<dòng>|<vai trò>")[:24]
  clientTxId  = "imp:<sha[:12]>:<sheet-slug>:<dòng>:<vai trò>"
  vai trò     = src | opening:<khóa> | migration:bank-allocation
  danh mục    = "imp_<slug>"; trạng thái = "imp_st_<danh mục>_<thứ tự>"
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audit  # noqa: E402
import normalize as N  # noqa: E402

IMPORTER_VERSION = "v2-2b-1"
SHEET_SLUG = "ghi-chep"
OPENING_DATE = "2026-01-01T00:00:00.000"
BANK_MIGRATION_DATE = "2026-09-13T00:00:00.000"
BANK_MIGRATION_AMOUNT = 70_000_000
BANK_ASSET_ID = "savings_bank"          # loại tiết kiệm "Gửi ngân hàng" có sẵn trong seed người dùng mới
UNALLOCATED = "savings_unallocated"
SYSTEM_TRANSFER_CATEGORY = "chuyen_tien_thanh_vien"
SYSTEM_SAVINGS_CATEGORY = "tiet_kiem"

STATUS_ORDER = ["Chưa chuẩn bị", "Đã chuẩn bị", "Đã gửi", "Đã dâng"]
SLUG = {"Thu nhập": "thu_nhap", "Sinh hoạt": "sinh_hoat", "Đầu tư": "dau_tu", "Tự thưởng": "tu_thuong",
        "Cho đi": "cho_di", "Dâng hiến": "dang_hien"}
COLORS = [0xFFE8A33D, 0xFF3E6FB0, 0xFF8E4FB0, 0xFFC14F7A, 0xFF13805F, 0xFF8FA3B3, 0xFF6C7A89, 0xFFB08D57]

OPENINGS = [
    # khóa, thành viên, loại pool đích, refId đích, số tiền, bằng chứng
    ("vo-available", "vo", "memberAvailable", "vo", 627000, "Tổng hợp!P3"),
    ("chong-available", "chong", "memberAvailable", "chong", 1060000, "Tổng hợp!P4"),
    ("vo-savings", "vo", "memberSavingsAsset", f"{UNALLOCATED}|vo", 2500000, "Tổng hợp!P5"),
    ("chong-savings", "chong", "memberSavingsAsset", f"{UNALLOCATED}|chong", 12000000, "Tổng hợp!P6"),
]


def h(sha, *parts):
    return hashlib.sha256("|".join([sha, *parts]).encode("utf-8")).hexdigest()


def src_ids(sha, row):
    return "imp-" + h(sha, "Ghi chép", str(row), "src")[:24], f"imp:{sha[:12]}:{SHEET_SLUG}:{row}:src"


def mig_ids(sha, key):
    return "imp-" + h(sha, "migration", key)[:24], f"imp:{sha[:12]}:migration:{key}"


def category_id_for(rec):
    cls, cat = rec["cls"], rec["rawCategory"]
    if cls == "IMPORT_REVENUE":
        return "imp_thu_nhap"
    if cls == "IMPORT_BUSINESS_EXPENSE":
        return "imp_cpkd_thu_nhap_am"
    if cls == "IMPORT_SPENDING":
        return "imp_" + SLUG[cat]
    if cls == "IMPORT_OTHER_INFLOW":
        return "imp_hoan_" + SLUG[cat]
    if cls in ("IMPORT_SAVINGS_TOPUP", "IMPORT_SAVINGS_WITHDRAW"):
        return SYSTEM_SAVINGS_CATEGORY
    if cls == "IMPORT_MEMBER_TRANSFER":
        return SYSTEM_TRANSFER_CATEGORY
    raise ValueError(cls)


def build_categories(records):
    cats = {}

    def add(cid, name, ctype, exclude=False, group_key=None, group="", raw=None, sign=1):
        cats[cid] = dict(id=cid, name=name, type=ctype, excludeFromTotals=exclude, groupKey=group_key,
                         group=group, colorValue=COLORS[len(cats) % len(COLORS)], statuses=[],
                         source=dict(rawCategory=raw, sign=sign))

    add("imp_thu_nhap", "Thu nhập", "income", group="Doanh thu", raw="Thu nhập", sign=1)
    add("imp_cpkd_thu_nhap_am", "Chi phí kinh doanh (từ Thu nhập âm)", "expense", group_key="business_expense",
        group="Chi phí kinh doanh", raw="Thu nhập", sign=-1)
    for name, slug in SLUG.items():
        if name == "Thu nhập":
            continue
        add("imp_" + slug, name, "expense", group="Chi tiêu", raw=name, sign=1)
        add("imp_hoan_" + slug, f"Hoàn / thu lại · {name}", "income", exclude=True, group="Khoản thu khác", raw=name, sign=-1)
    add("imp_so_du_dau_ky", "Số dư đầu kỳ", "income", exclude=True, group="Khoản thu khác", raw=None, sign=1)

    names = {}
    for r in records:
        if r["cls"] in N.IMPORT and r["statusProposal"]:
            cid = category_id_for(r)
            assert cid in cats, f"trạng thái trên danh mục hệ thống ({cid}) — lẽ ra đã bị bỏ"
            names.setdefault(cid, set()).add(r["statusProposal"])
    for cid, ns in names.items():
        for i, n in enumerate([s for s in STATUS_ORDER if s in ns]):
            cats[cid]["statuses"].append(dict(id=f"imp_st_{cid[4:]}_{i}", name=n, sortOrder=i))
    # Chỉ tạo danh mục thật sự được dùng (kèm số dư đầu kỳ luôn được dùng).
    used = {category_id_for(r) for r in records if r["cls"] in N.IMPORT} | {"imp_so_du_dau_ky"}
    return [c for cid, c in cats.items() if cid in used]


def build_plan(records, sha):
    cats = build_categories(records)
    status_id = {(c["id"], s["name"]): s["id"] for c in cats for s in c["statuses"]}
    txs, prov = [], []

    def pool(kind, ref):
        return kind, ref

    for r in records:
        if r["cls"] not in N.IMPORT:
            continue
        cid = category_id_for(r)
        m, cm, cls = r["member"], r["counterMember"], r["cls"]
        sid, cli = src_ids(sha, r["sourceRow"])
        base = dict(id=sid, clientTxId=cli, role="src", sourceRow=r["sourceRow"], categoryId=cid,
                    amountMinor=r["amountMinor"], date=r["date"],
                    note=(r["rawNote"].strip() if isinstance(r["rawNote"], str) else ""),
                    statusId=status_id.get((cid, r["statusProposal"])) if r["statusProposal"] else None)
        if cls in ("IMPORT_REVENUE", "IMPORT_OTHER_INFLOW"):
            base.update(type="income", transferKind=None, sourceKind="external", sourceRefId=None,
                        destinationKind="memberAvailable", destinationRefId=m)
        elif cls in ("IMPORT_BUSINESS_EXPENSE", "IMPORT_SPENDING"):
            base.update(type="expense", transferKind=None, sourceKind="memberAvailable", sourceRefId=m,
                        destinationKind="external", destinationRefId=None)
        elif cls == "IMPORT_SAVINGS_TOPUP":
            base.update(type="transfer", transferKind="savingsTopup", sourceKind="memberAvailable", sourceRefId=m,
                        destinationKind="memberSavingsAsset", destinationRefId=f"{UNALLOCATED}|{m}")
        elif cls == "IMPORT_SAVINGS_WITHDRAW":
            base.update(type="transfer", transferKind="savingsWithdraw", sourceKind="memberSavingsAsset",
                        sourceRefId=f"{UNALLOCATED}|{m}", destinationKind="memberAvailable", destinationRefId=m)
        elif cls == "IMPORT_MEMBER_TRANSFER":
            base.update(type="transfer", transferKind="memberToMember", sourceKind="memberAvailable", sourceRefId=m,
                        destinationKind="memberAvailable", destinationRefId=cm)
        txs.append(base)
        prov.append(dict(clientTxId=cli, sourceRow=r["sourceRow"], role="src", cls=cls, rawCategory=r["rawCategory"],
                         rawAmount=r["rawAmount"], rawMember=r["rawMember"], rawDate=r["rawDate"], rawStatus=r["rawStatus"],
                         flags=";".join(r["flags"]), reason=r["normalizationReason"]))

    for key, member, kind, ref, amount, evidence in OPENINGS:
        oid, cli = mig_ids(sha, "opening:" + key)
        txs.append(dict(id=oid, clientTxId=cli, role="opening:" + key, sourceRow=0, categoryId="imp_so_du_dau_ky",
                        amountMinor=amount, date=OPENING_DATE, note="", statusId=None, type="income", transferKind=None,
                        sourceKind="external", sourceRefId=None, destinationKind=kind, destinationRefId=ref))
        prov.append(dict(clientTxId=cli, sourceRow=0, role="opening:" + key, cls="OPENING_MIGRATION", rawCategory=None,
                         rawAmount=amount, rawMember=member, rawDate=OPENING_DATE, rawStatus=None, flags="", reason=f"số dư đầu kỳ — {evidence}"))
    bid, bcli = mig_ids(sha, "bank-allocation")
    txs.append(dict(id=bid, clientTxId=bcli, role="migration:bank-allocation", sourceRow=0, categoryId=SYSTEM_SAVINGS_CATEGORY,
                    amountMinor=BANK_MIGRATION_AMOUNT, date=BANK_MIGRATION_DATE,
                    note="Phân bổ Ngân hàng (nhập dữ liệu cũ)", statusId=None, type="transfer", transferKind="savingsConvert",
                    sourceKind="memberSavingsAsset", sourceRefId=f"{UNALLOCATED}|chong",
                    destinationKind="memberSavingsAsset", destinationRefId=f"{BANK_ASSET_ID}|chong"))
    prov.append(dict(clientTxId=bcli, sourceRow=0, role="migration:bank-allocation", cls="BANK_MIGRATION", rawCategory=None,
                     rawAmount=BANK_MIGRATION_AMOUNT, rawMember="Chồng", rawDate=BANK_MIGRATION_DATE, rawStatus=None, flags="",
                     reason="Tổng hợp!L8 (30+10+10+10+10 tr) + chú thích ô L8 (13/09 đạt 70tr)"))

    return dict(importerVersion=IMPORTER_VERSION, workbookSha256=sha, categories=cats, transactions=txs,
                requiredSystemCategories=[SYSTEM_TRANSFER_CATEGORY, SYSTEM_SAVINGS_CATEGORY],
                requiredSavingsAssets=[BANK_ASSET_ID]), prov


def arithmetic(records, plan):
    cc = N.class_counts(records)
    imp = sum(v for k, v in cc.items() if k in N.IMPORT)
    proof = {
        "classCounts": dict(cc),
        "meaningfulRows": sum(cc.values()),
        "import": imp,
        "mirrorsSkipped": cc.get("LEGACY_TRANSFER_MIRROR_SKIPPED", 0),
        "markers": cc.get("SKIP_MARKER_ROW", 0),
        "blankAmount": cc.get("SKIP_NO_AMOUNT", 0),
        "zeroAmount": cc.get("SKIP_ZERO_AMOUNT", 0),
        "openings": len(OPENINGS), "bankMigration": 1,
        "planTransactions": len(plan["transactions"]),
        "sourceIdentityUnique": len({t["id"] for t in plan["transactions"]}) == len(plan["transactions"])
                                and len({t["clientTxId"] for t in plan["transactions"]}) == len(plan["transactions"]),
    }
    proof["sumOfClasses"] = imp + proof["mirrorsSkipped"] + proof["markers"] + proof["blankAmount"] + proof["zeroAmount"]
    proof["sumEqualsMeaningful"] = proof["sumOfClasses"] == proof["meaningfulRows"]
    proof["expectedFinal"] = imp + proof["openings"] + proof["bankMigration"]
    return proof


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--xlsx", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    structure, _h, raw, _stray, _types, _cells, _sup = audit.extract(a.xlsx)
    sha = structure["sha256"]
    recs, mirror_report, dups = N.normalize(raw)
    plan, prov = build_plan(recs, sha)
    proof = arithmetic(recs, plan)
    json.dump(plan, open(os.path.join(a.out, "import_plan.json"), "w", encoding="utf-8"), ensure_ascii=False)
    json.dump(dict(proof, mirrorReport=mirror_report, duplicateGroups=dups),
              open(os.path.join(a.out, "plan_arithmetic.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    cols = ["clientTxId", "sourceRow", "role", "cls", "rawCategory", "rawAmount", "rawMember", "rawDate", "rawStatus", "flags", "reason"]
    tx_by_cli = {t["clientTxId"]: t for t in plan["transactions"]}
    with open(os.path.join(a.out, "staging_import_plan.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=cols + ["type", "transferKind", "categoryId", "amountMinor", "date", "statusId", "sourceKind", "sourceRefId", "destinationKind", "destinationRefId"])
        w.writeheader()
        for p in prov:
            t = tx_by_cli[p["clientTxId"]]
            w.writerow({**p, **{k: t[k] for k in ("type", "transferKind", "categoryId", "amountMinor", "date", "statusId", "sourceKind", "sourceRefId", "destinationKind", "destinationRefId")}})
    print(json.dumps({k: v for k, v in proof.items() if k != "classCounts"}, ensure_ascii=False))
    print(proof["classCounts"])


if __name__ == "__main__":
    main()
