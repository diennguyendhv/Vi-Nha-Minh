"""Test quy tắc chuẩn hóa — CHỈ dùng dữ liệu tổng hợp (không có dữ liệu thật).

Chạy:  python -m unittest discover -s tool/legacy_import/tests -v   (từ thư mục gốc repo)
"""
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import audit  # noqa: E402
import normalize as N  # noqa: E402


def row(n, cat, amt, member="Chồng", date="2026-03-01T10:00:00.000", note=None, status=None):
    return {"row": n, "cat": cat, "amt": amt, "note": note, "member": member, "date": date, "status": status}


def run(*rows):
    recs, mirrors, dups = N.normalize(list(rows))
    return {r["sourceRow"]: r for r in recs}, mirrors, dups


class ClassificationRules(unittest.TestCase):
    def test_positive_income_is_revenue(self):
        r = run(row(2, "Thu nhập", 500000))[0][2]
        self.assertEqual(r["cls"], "IMPORT_REVENUE")
        self.assertEqual((r["transactionType"], r["reportingGroup"], r["amountMinor"]), ("income", "Doanh thu", 500000))

    def test_negative_income_is_business_expense_with_abs_amount(self):
        r = run(row(2, "Thu nhập", -300000))[0][2]
        self.assertEqual(r["cls"], "IMPORT_BUSINESS_EXPENSE")
        self.assertEqual((r["transactionType"], r["reportingGroup"], r["amountMinor"]), ("expense", "Chi phí kinh doanh", 300000))

    def test_positive_expense_category_is_spending(self):
        for cat in N.EXPENSE_CATEGORIES:
            r = run(row(2, cat, 1000))[0][2]
            self.assertEqual(r["cls"], "IMPORT_SPENDING", cat)
            self.assertEqual((r["reportingGroup"], r["categoryProposal"]), ("Chi tiêu", cat))

    def test_negative_expense_category_is_other_inflow_not_revenue(self):
        r = run(row(2, "Sinh hoạt", -387000))[0][2]
        self.assertEqual(r["cls"], "IMPORT_OTHER_INFLOW")
        self.assertEqual((r["transactionType"], r["reportingGroup"], r["amountMinor"]), ("income", "Khoản thu khác", 387000))

    def test_savings_positive_is_topup_negative_is_withdraw_never_negative_amount(self):
        pos = run(row(2, "Tiết kiệm", 1000000))[0][2]
        neg = run(row(2, "Tiết kiệm", -400000))[0][2]
        self.assertEqual((pos["cls"], pos["transferKind"], pos["amountMinor"]), ("IMPORT_SAVINGS_TOPUP", "savingsTopup", 1000000))
        self.assertEqual((neg["cls"], neg["transferKind"], neg["amountMinor"]), ("IMPORT_SAVINGS_WITHDRAW", "savingsWithdraw", 400000))

    def test_blank_amount_is_skipped_not_zero(self):
        r = run(row(2, "Cho đi", None))[0][2]
        self.assertEqual(r["cls"], "SKIP_NO_AMOUNT")

    def test_zero_amount_needs_review(self):
        r = run(row(2, "Cho đi", 0))[0][2]
        self.assertEqual(r["cls"], "REVIEW_ZERO_AMOUNT")

    def test_marker_rows(self):
        recs = run(row(2, None, None, member=None, note="Tháng 3"), row(3, None, None, note="QL tài khoản"))[0]
        self.assertEqual(recs[2]["cls"], "SKIP_MARKER_ROW")
        self.assertEqual(recs[3]["cls"], "SKIP_MARKER_ROW")

    def test_unknown_category_member_status_date_are_reviews_not_silent(self):
        recs = run(
            row(2, "Lạ", 1000), row(3, "Sinh hoạt", 1000, member="Bố"),
            row(4, "Sinh hoạt", 1000, status="Xong"), row(5, "Sinh hoạt", 1000, date=None),
            row(6, "Sinh hoạt", 1000, member=None),
        )[0]
        self.assertEqual([recs[i]["cls"] for i in range(2, 7)], [
            "REVIEW_UNKNOWN_CATEGORY", "REVIEW_UNKNOWN_MEMBER", "REVIEW_UNKNOWN_STATUS",
            "REVIEW_UNKNOWN_DATE", "REVIEW_UNKNOWN_MEMBER"])

    def test_null_status_stays_null_and_actual_status_is_kept(self):
        recs = run(row(2, "Cho đi", 1000), row(3, "Cho đi", 1000, status="Đã gửi"))[0]
        self.assertIsNone(recs[2]["statusProposal"])
        self.assertEqual(recs[3]["statusProposal"], "Đã gửi")

    def test_future_date_is_preserved_not_dropped_or_moved(self):
        r = run(row(2, "Cho đi", 40000, date="2026-10-03T00:00:00.000"))[0][2]
        self.assertEqual(r["cls"], "IMPORT_SPENDING")
        self.assertEqual(r["date"], "2026-10-03T00:00:00.000")

    def test_amount_is_integer_vnd(self):
        r = run(row(2, "Sinh hoạt", 12000.0))[0][2]
        self.assertIsInstance(r["amountMinor"], int)
        self.assertEqual(run(row(2, "Sinh hoạt", 12000.5))[0][2]["cls"], "REVIEW_OTHER")


class TransfersAndMirrors(unittest.TestCase):
    def test_directional_transfers(self):
        recs = run(row(2, "Chồng đưa vợ", 1000000), row(3, "Vợ đưa chồng", 200000, member="Vợ"))[0]
        self.assertEqual((recs[2]["cls"], recs[2]["member"], recs[2]["counterMember"]), ("IMPORT_MEMBER_TRANSFER", "chong", "vo"))
        self.assertEqual((recs[3]["member"], recs[3]["counterMember"]), ("vo", "chong"))

    def test_blank_member_on_transfer_is_flagged_not_blocked(self):
        r = run(row(2, "Chồng đưa vợ", 1000000, member=None))[0][2]
        self.assertEqual(r["cls"], "IMPORT_MEMBER_TRANSFER")
        self.assertIn("MEMBER_BLANK_DIRECTION_FROM_CATEGORY", r["flags"])

    def test_mirror_matched_high_confidence_is_skipped(self):
        recs, mirrors, _ = run(
            row(2, "Chồng đưa vợ", 1000000, date="2026-03-01T10:00:00.000"),
            row(3, "Vợ chồng", -1000000, member="Vợ", date="2026-03-01T10:00:20.000"),
        )
        self.assertEqual(recs[3]["cls"], "LEGACY_TRANSFER_MIRROR_SKIPPED")
        self.assertEqual((mirrors[0]["matchedRow"], mirrors[0]["confidence"]), (2, "HIGH"))

    def test_mirror_same_day_only_is_medium_and_skipped(self):
        recs, mirrors, _ = run(
            row(2, "Chồng đưa vợ", 500000, date="2026-03-01T20:00:00.000"),
            row(3, "Vợ chồng", -500000, member="Vợ", date="2026-03-01T00:00:00.000"),
        )
        self.assertEqual(mirrors[0]["confidence"], "MEDIUM")
        self.assertEqual(recs[3]["cls"], "LEGACY_TRANSFER_MIRROR_SKIPPED")

    def test_mirror_different_day_is_not_guessed(self):
        recs, mirrors, _ = run(
            row(2, "Vợ đưa chồng", 400000, member="Vợ", date="2026-02-22T13:00:00.000"),
            row(3, "Vợ chồng", -400000, member="Chồng", date="2026-02-24T22:00:00.000"),
        )
        self.assertEqual(recs[3]["cls"], "REVIEW_TRANSFER_MIRROR")
        self.assertEqual(mirrors[0]["confidence"], "LOW")

    def test_mirror_without_any_directional_row_needs_review(self):
        recs, mirrors, _ = run(row(3, "Vợ chồng", -700000, member="Vợ"))
        self.assertEqual(recs[3]["cls"], "REVIEW_TRANSFER_MIRROR")
        self.assertIsNone(mirrors[0]["matchedRow"])

    def test_one_directional_row_matches_only_one_mirror(self):
        recs, _, _ = run(
            row(2, "Chồng đưa vợ", 1000000, date="2026-03-01T10:00:00.000"),
            row(3, "Vợ chồng", -1000000, member="Vợ", date="2026-03-01T10:00:05.000"),
            row(4, "Vợ chồng", -1000000, member="Vợ", date="2026-03-01T10:00:09.000"),
        )
        skipped = [n for n in (3, 4) if recs[n]["cls"] == "LEGACY_TRANSFER_MIRROR_SKIPPED"]
        self.assertEqual(len(skipped), 1)


class DuplicatesAndDeterminism(unittest.TestCase):
    def test_exact_duplicates_are_flagged_and_both_kept(self):
        a = row(2, "Dâng hiến", 200000, date="2026-03-20T22:07:50.689", status="Đã gửi")
        b = dict(a, row=3)
        recs, _, dups = run(a, b)
        self.assertEqual(dups, [[2, 3]])
        self.assertEqual((recs[2]["cls"], recs[3]["cls"]), ("IMPORT_SPENDING", "IMPORT_SPENDING"))
        self.assertTrue(any(f.startswith("EXACT_DUPLICATE_GROUP") for f in recs[3]["flags"]))

    def test_different_timestamp_is_not_a_duplicate(self):
        _, _, dups = run(row(2, "Sinh hoạt", 1000, date="2026-03-01T10:00:00.000"), row(3, "Sinh hoạt", 1000, date="2026-03-01T10:00:00.001"))
        self.assertEqual(dups, [])

    def test_no_row_is_lost_and_result_is_deterministic(self):
        rows = [row(2, "Thu nhập", 1), row(3, "Sinh hoạt", -2), row(4, "Tiết kiệm", 3), row(5, None, None, note="Tháng 1"),
                row(6, "Cho đi", None), row(7, "Cho đi", 0), row(8, "Chồng đưa vợ", 9)]
        first = N.normalize(list(rows))[0]
        shuffled = list(rows)
        random.Random(1).shuffle(shuffled)
        second = N.normalize(shuffled)[0]
        self.assertEqual(first, second)
        self.assertEqual(sum(N.class_counts(first).values()), len(rows))


class ProposedCategoryAndStatusIdentity(unittest.TestCase):
    def test_same_status_text_under_different_categories_are_different_ids(self):
        recs = N.normalize([row(2, "Cho đi", 1000, status="Đã gửi"), row(3, "Dâng hiến", 1000, status="Đã gửi")])[0]
        cats = audit.category_table(recs)
        cho_di = [s["id"] for s in cats["cho_di"]["statuses"]]
        dang_hien = [s["id"] for s in cats["dang_hien"]["statuses"]]
        self.assertTrue(set(cho_di).isdisjoint(dang_hien))
        tx = {t["row"]: t for t in (audit.to_sim_tx(r, cats) for r in recs)}
        self.assertNotEqual(tx[2]["statusId"], tx[3]["statusId"])

    def test_negative_income_status_belongs_to_the_business_expense_category(self):
        recs = N.normalize([row(2, "Thu nhập", -5000, status="Đã gửi")])[0]
        cats = audit.category_table(recs)
        tx = audit.to_sim_tx(recs[0], cats)
        self.assertEqual(tx["categoryId"], "cpkd_thu_nhap_am")
        self.assertTrue(tx["statusId"].startswith("st_cpkd_thu_nhap_am_"))


if __name__ == "__main__":
    unittest.main()
