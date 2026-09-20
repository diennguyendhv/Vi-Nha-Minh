"""Test dựng kế hoạch nhập (V2-2B) — dữ liệu tổng hợp, không có dữ liệu thật."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import normalize as N  # noqa: E402
import plan as P  # noqa: E402

SHA = "a" * 64


def row(n, cat, amt, member="Chồng", date="2026-03-01T10:00:00.000", note=None, status=None):
    return {"row": n, "cat": cat, "amt": amt, "note": note, "member": member, "date": date, "status": status}


def build(rows, sha=SHA):
    recs, _m, _d = N.normalize(rows)
    plan, prov = P.build_plan(recs, sha)
    return recs, plan, prov


SAMPLE = [
    row(2, "Thu nhập", 1000000), row(3, "Thu nhập", -5000, status="Đã gửi"), row(4, "Sinh hoạt", 20000, note="  gửi xe "),
    row(5, "Sinh hoạt", -3000), row(6, "Tiết kiệm", 100000, status="Đã gửi"), row(7, "Chồng đưa vợ", 40000, status="Đã gửi", member=None),
    row(8, "Cho đi", 0), row(9, "Cho đi", None), row(10, None, None, note="Tháng 3"),
    row(11, "Vợ chồng", -40000, member="Vợ", date="2026-03-01T10:00:02.000"),
    row(12, "Cho đi", 40000, date="2026-10-03T00:00:00.000", status="Đã chuẩn bị"),
]


class PlanRules(unittest.TestCase):
    def test_counts_and_arithmetic(self):
        recs, plan, _ = build(SAMPLE)
        proof = P.arithmetic(recs, plan)
        # nhập = 7 (dòng 2,3,4,5,6,7,12); mirror = 1; marker = 1; blank = 1; zero = 1
        self.assertEqual((proof["import"], proof["mirrorsSkipped"], proof["markers"], proof["blankAmount"], proof["zeroAmount"]), (7, 1, 1, 1, 1))
        self.assertTrue(proof["sumEqualsMeaningful"])
        self.assertEqual(proof["planTransactions"], 7 + 4 + 1)
        self.assertEqual(proof["expectedFinal"], 12)

    def test_zero_blank_marker_mirror_rows_are_not_in_plan(self):
        _, plan, _ = build(SAMPLE)
        rows_in_plan = {t["sourceRow"] for t in plan["transactions"] if t["role"] == "src"}
        self.assertEqual(rows_in_plan, {2, 3, 4, 5, 6, 7, 12})

    def test_four_openings_and_one_bank_migration_with_exact_semantics(self):
        _, plan, _ = build(SAMPLE)
        opens = [t for t in plan["transactions"] if t["role"].startswith("opening:")]
        self.assertEqual(sorted((t["destinationRefId"], t["amountMinor"]) for t in opens), sorted([
            ("vo", 627000), ("chong", 1060000), ("savings_unallocated|vo", 2500000), ("savings_unallocated|chong", 12000000)]))
        self.assertTrue(all(t["categoryId"] == "imp_so_du_dau_ky" and t["type"] == "income" and t["sourceKind"] == "external" and t["date"] == "2026-01-01T00:00:00.000" for t in opens))
        bank = [t for t in plan["transactions"] if t["role"] == "migration:bank-allocation"]
        self.assertEqual(len(bank), 1)
        b = bank[0]
        self.assertEqual((b["type"], b["transferKind"], b["amountMinor"], b["date"]), ("transfer", "savingsConvert", 70_000_000, "2026-09-13T00:00:00.000"))
        self.assertEqual((b["sourceRefId"], b["destinationRefId"]), ("savings_unallocated|chong", "savings_bank|chong"))

    def test_opening_category_is_other_inflow_not_revenue(self):
        _, plan, _ = build(SAMPLE)
        cat = next(c for c in plan["categories"] if c["id"] == "imp_so_du_dau_ky")
        self.assertEqual((cat["type"], cat["excludeFromTotals"], cat["group"]), ("income", True, "Khoản thu khác"))

    def test_legacy_status_on_system_transfer_is_null_and_kept_only_in_provenance(self):
        _, plan, prov = build(SAMPLE)
        by_row = {t["sourceRow"]: t for t in plan["transactions"] if t["role"] == "src"}
        self.assertIsNone(by_row[6]["statusId"])
        self.assertIsNone(by_row[7]["statusId"])
        self.assertEqual(by_row[6]["note"], "")
        self.assertNotIn("Đã gửi", by_row[6]["note"] + by_row[7]["note"])
        pv = {p["sourceRow"]: p for p in prov if p["role"] == "src"}
        self.assertEqual((pv[6]["rawStatus"], pv[7]["rawStatus"]), ("Đã gửi", "Đã gửi"))
        self.assertIn("LEGACY_STATUS_DROPPED", pv[6]["flags"])

    def test_statuses_are_category_scoped_and_normal_categories_only(self):
        _, plan, _ = build(SAMPLE)
        owners = {s["id"]: c["id"] for c in plan["categories"] for s in c["statuses"]}
        self.assertEqual(sorted(set(owners.values())), ["imp_cho_di", "imp_cpkd_thu_nhap_am"])
        self.assertEqual(len(owners), len(set(owners)))
        for c in plan["categories"]:
            self.assertFalse(c["id"] in ("tiet_kiem", "chuyen_tien_thanh_vien"))

    def test_future_date_preserved_note_trimmed_and_blank_note_empty(self):
        _, plan, _ = build(SAMPLE)
        by_row = {t["sourceRow"]: t for t in plan["transactions"] if t["role"] == "src"}
        self.assertEqual(by_row[12]["date"], "2026-10-03T00:00:00.000")
        self.assertEqual(by_row[4]["note"], "gửi xe")
        self.assertEqual(by_row[2]["note"], "")

    def test_negative_amounts_never_appear_and_directions_are_correct(self):
        _, plan, _ = build(SAMPLE)
        self.assertTrue(all(t["amountMinor"] > 0 for t in plan["transactions"]))
        by_row = {t["sourceRow"]: t for t in plan["transactions"] if t["role"] == "src"}
        self.assertEqual((by_row[3]["type"], by_row[3]["categoryId"]), ("expense", "imp_cpkd_thu_nhap_am"))
        self.assertEqual((by_row[5]["type"], by_row[5]["categoryId"]), ("income", "imp_hoan_sinh_hoat"))
        self.assertEqual((by_row[7]["sourceRefId"], by_row[7]["destinationRefId"]), ("chong", "vo"))

    def test_hoan_and_business_categories_have_correct_reporting_flags(self):
        _, plan, _ = build(SAMPLE)
        cats = {c["id"]: c for c in plan["categories"]}
        self.assertTrue(cats["imp_hoan_sinh_hoat"]["excludeFromTotals"])
        self.assertEqual(cats["imp_cpkd_thu_nhap_am"]["groupKey"], "business_expense")
        self.assertFalse(cats["imp_thu_nhap"]["excludeFromTotals"])


class DeterministicIdentity(unittest.TestCase):
    def test_same_workbook_same_ids_and_clientTxIds(self):
        _, a, _ = build(SAMPLE)
        _, b, _ = build(list(reversed(SAMPLE)))
        self.assertEqual(a["transactions"], b["transactions"])
        self.assertEqual(a["categories"], b["categories"])

    def test_identity_depends_on_workbook_sha_row_and_role(self):
        _, a, _ = build(SAMPLE, sha="a" * 64)
        _, c, _ = build(SAMPLE, sha="b" * 64)
        self.assertTrue({t["id"] for t in a["transactions"]}.isdisjoint({t["id"] for t in c["transactions"]}))
        self.assertTrue(all(t["clientTxId"].startswith("imp:aaaaaaaaaaaa:") for t in a["transactions"]))

    def test_all_identities_unique_and_no_random_uuid(self):
        _, plan, _ = build(SAMPLE)
        ids = [t["id"] for t in plan["transactions"]]
        cli = [t["clientTxId"] for t in plan["transactions"]]
        self.assertEqual(len(set(ids)), len(ids))
        self.assertEqual(len(set(cli)), len(cli))
        self.assertTrue(all(i.startswith("imp-") and len(i) == 28 for i in ids))

    def test_duplicate_pair_keeps_both_with_distinct_identities(self):
        dup = [row(2, "Dâng hiến", 200000, date="2026-03-20T22:07:50.689", status="Đã gửi"),
               row(3, "Dâng hiến", 200000, date="2026-03-20T22:07:50.689", status="Đã gửi")]
        _, plan, _ = build(dup)
        src = [t for t in plan["transactions"] if t["role"] == "src"]
        self.assertEqual(len(src), 2)
        self.assertNotEqual(src[0]["clientTxId"], src[1]["clientTxId"])
        self.assertNotEqual(src[0]["id"], src[1]["id"])


if __name__ == "__main__":
    unittest.main()
