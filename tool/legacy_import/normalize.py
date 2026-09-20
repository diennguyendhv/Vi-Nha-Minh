"""Chuẩn hóa sổ Excel cũ "Ghi chép" -> bản ghi giao dịch dự kiến (CHỈ ĐỌC, in-memory).

Không ghi DB, không gọi repository, không suy luận từ Ghi chú (Note chỉ được
giữ nguyên). Mỗi dòng nguồn có đúng 1 phân loại (`cls`), kèm provenance
(sourceRow, raw*) để truy ngược "dòng Excel nào sinh ra giao dịch này".

Đầu vào: list dict thô {row, cat, amt, note, member, date(ISO), status}.
Xác định: cùng đầu vào -> cùng đầu ra, cùng thứ tự (sắp theo `row`).
"""
from __future__ import annotations

import datetime as _dt
import re
from collections import Counter, defaultdict

# ---- Hằng số nghiệp vụ (theo quyết định của chủ dự án) ---------------------
INCOME_CATEGORY = "Thu nhập"
EXPENSE_CATEGORIES = ("Sinh hoạt", "Đầu tư", "Tự thưởng", "Cho đi", "Dâng hiến")
SAVINGS_CATEGORY = "Tiết kiệm"
TRANSFER_CATEGORIES = {
    "Chồng đưa vợ": ("chong", "vo"),
    "Vợ đưa chồng": ("vo", "chong"),
}
MIRROR_CATEGORY = "Vợ chồng"
MEMBERS = {"Vợ": "vo", "Chồng": "chong"}
KNOWN_STATUSES = {"Đã gửi", "Đã chuẩn bị", "Chưa chuẩn bị", "Đã dâng"}
MARKER_NOTE = re.compile(r"^\s*(Tháng\s+\d{1,2}|QL tài khoản)\s*$", re.IGNORECASE)

IMPORT = {
    "IMPORT_REVENUE", "IMPORT_BUSINESS_EXPENSE", "IMPORT_SPENDING",
    "IMPORT_OTHER_INFLOW", "IMPORT_SAVINGS_TOPUP", "IMPORT_SAVINGS_WITHDRAW",
    "IMPORT_MEMBER_TRANSFER",
}


def _blank(v) -> bool:
    return v is None or (isinstance(v, str) and v.strip() == "")


def _minor(v):
    """Số tiền nguồn -> số nguyên VND. None nếu không phải số nguyên hợp lệ."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    if float(v) != int(round(float(v))):
        return None
    return int(round(float(v)))


def _parse_date(s):
    try:
        return _dt.datetime.fromisoformat(s)
    except Exception:  # noqa: BLE001
        return None


def classify(raw: dict) -> dict:
    """Phân loại 1 dòng nguồn. Trả về bản ghi có provenance + chuẩn hóa."""
    rec = {
        "sourceSheet": "Ghi chép",
        "sourceRow": raw["row"],
        "rawCategory": raw.get("cat"),
        "rawAmount": raw.get("amt"),
        "rawNote": raw.get("note"),
        "rawMember": raw.get("member"),
        "rawDate": raw.get("date"),
        "rawStatus": raw.get("status"),
        "cls": None,
        "transactionType": None,  # income | expense | transfer
        "transferKind": None,
        "reportingGroup": None,
        "categoryProposal": None,
        "member": None,           # vo | chong | None
        "counterMember": None,    # người nhận (chuyển thành viên)
        "amountMinor": None,
        "date": raw.get("date"),
        "statusProposal": None,
        "normalizationReason": "",
        "flags": [],
    }
    cat, amt, note = raw.get("cat"), raw.get("amt"), raw.get("note")
    member, status = raw.get("member"), raw.get("status")

    def done(cls, reason):
        rec["cls"], rec["normalizationReason"] = cls, reason
        return rec

    # 1. Dòng đánh dấu (không phải giao dịch)
    if _blank(cat) and _blank(amt) and isinstance(note, str) and MARKER_NOTE.match(note):
        return done("SKIP_MARKER_ROW", "dòng đánh dấu (nhãn tháng / QL tài khoản), không có hạng mục & số tiền")
    # 2. Không có số tiền (để trống ≠ 0)
    if amt is None:
        why = "không có Hạng mục" if _blank(cat) else "Hạng mục có nhưng Thành tiền để trống (không phải 0)"
        return done("SKIP_NO_AMOUNT", why)
    m = _minor(amt)
    if m is None:
        return done("REVIEW_OTHER", f"Thành tiền không phải số nguyên VND hợp lệ: {amt!r}")
    if m == 0:
        return done("REVIEW_ZERO_AMOUNT", "Thành tiền = 0 (không đưa vào Financial Engine)")
    # 3. Ngày
    d = _parse_date(raw.get("date"))
    if d is None:
        return done("REVIEW_UNKNOWN_DATE", "Ngày tháng thiếu hoặc không hợp lệ")
    # 4. Hạng mục
    if _blank(cat):
        return done("REVIEW_UNKNOWN_CATEGORY", "có số tiền nhưng không có Hạng mục")
    known = {INCOME_CATEGORY, SAVINGS_CATEGORY, MIRROR_CATEGORY, *EXPENSE_CATEGORIES, *TRANSFER_CATEGORIES}
    if cat not in known:
        return done("REVIEW_UNKNOWN_CATEGORY", f"Hạng mục lạ: {cat!r}")
    # 5. Trạng thái (rỗng = null, KHÔNG điền bước đầu)
    if not _blank(status):
        if status not in KNOWN_STATUSES:
            return done("REVIEW_UNKNOWN_STATUS", f"Trạng thái lạ: {status!r}")
        rec["statusProposal"] = status
    # 6. Người tiêu
    mem = MEMBERS.get(member) if not _blank(member) else None
    if not _blank(member) and mem is None:
        return done("REVIEW_UNKNOWN_MEMBER", f"Người tiêu lạ: {member!r}")

    a = abs(m)
    rec["amountMinor"] = a
    rec["date"] = d.isoformat(timespec="milliseconds")

    # 7. Chuyển giữa thành viên (hướng theo Hạng mục, không theo Người tiêu)
    if cat in TRANSFER_CATEGORIES:
        src, dst = TRANSFER_CATEGORIES[cat]
        if m < 0:
            return done("REVIEW_OTHER", f"{cat} với số tiền ÂM — không rõ ý nghĩa")
        rec.update(transactionType="transfer", transferKind="memberToMember",
                   member=src, counterMember=dst, categoryProposal="Chuyển tiền giữa Vợ/Chồng")
        if mem is not None and mem != src:
            rec["flags"].append("MEMBER_CONTRADICTS_DIRECTION")
        if mem is None:
            rec["flags"].append("MEMBER_BLANK_DIRECTION_FROM_CATEGORY")
        return done("IMPORT_MEMBER_TRANSFER", f"{cat}: hướng suy từ Hạng mục ({src} → {dst})")
    if cat == MIRROR_CATEGORY:
        # Kết quả cuối (mirror skip / review) do `match_mirrors` quyết định.
        rec["member"] = mem
        return done("MIRROR_PENDING", "'Vợ chồng': chờ khớp với dòng chuyển có hướng")

    # Các loại còn lại cần biết thành viên
    if mem is None:
        return done("REVIEW_UNKNOWN_MEMBER", "Người tiêu để trống trên giao dịch cần thành viên")
    rec["member"] = mem

    if cat == INCOME_CATEGORY:
        if m > 0:
            rec.update(transactionType="income", reportingGroup="Doanh thu", categoryProposal="Thu nhập")
            return done("IMPORT_REVENUE", "Thu nhập > 0 → Doanh thu")
        rec.update(transactionType="expense", reportingGroup="Chi phí kinh doanh",
                   categoryProposal="Chi phí kinh doanh (từ Thu nhập âm)")
        return done("IMPORT_BUSINESS_EXPENSE", "Thu nhập < 0 → Chi phí kinh doanh (|số tiền|)")
    if cat in EXPENSE_CATEGORIES:
        if m > 0:
            rec.update(transactionType="expense", reportingGroup="Chi tiêu", categoryProposal=cat)
            return done("IMPORT_SPENDING", f"{cat} > 0 → Chi tiêu")
        rec.update(transactionType="income", reportingGroup="Khoản thu khác",
                   categoryProposal=f"Hoàn / thu lại · {cat}")
        return done("IMPORT_OTHER_INFLOW", f"{cat} < 0 → Khoản thu khác (|số tiền|), không phải Doanh thu")
    if cat == SAVINGS_CATEGORY:
        rec.update(transactionType="transfer", categoryProposal="Tiết kiệm")
        if m > 0:
            rec["transferKind"] = "savingsTopup"
            return done("IMPORT_SAVINGS_TOPUP", "Tiết kiệm > 0: Khả dụng → Tiết kiệm (Chưa phân bổ)")
        rec["transferKind"] = "savingsWithdraw"
        return done("IMPORT_SAVINGS_WITHDRAW", "Tiết kiệm < 0: Tiết kiệm (Chưa phân bổ) → Khả dụng")
    return done("REVIEW_OTHER", "không khớp quy tắc nào")  # pragma: no cover


def match_mirrors(records: list) -> list:
    """Khớp từng dòng 'Vợ chồng' (đối ứng) với 1 dòng chuyển có hướng.

    Đối ứng của 'Chồng đưa vợ' do Vợ ghi (số ÂM); đối ứng của 'Vợ đưa chồng' do
    Chồng ghi. Khớp 1-1: cùng |số tiền|, hướng phù hợp người ghi, gần nhau nhất.
    Độ tin cậy: HIGH = lệch ≤ 60 giây; MEDIUM = cùng ngày lịch; LOW = khác ngày
    hoặc mơ hồ (→ REVIEW_TRANSFER_MIRROR, không đoán). Trả về báo cáo từng dòng.
    """
    directional = [r for r in records if r["cls"] == "IMPORT_MEMBER_TRANSFER"]
    used = set()
    report = []
    mirrors = [r for r in records if r["cls"] == "MIRROR_PENDING"]
    scored = []
    for m in mirrors:
        md = _parse_date(m["rawDate"])
        want_cat = None
        if m["rawMember"] == "Vợ":
            want_cat = "Chồng đưa vợ"
        elif m["rawMember"] == "Chồng":
            want_cat = "Vợ đưa chồng"
        cands = []
        for d in directional:
            if want_cat and d["rawCategory"] != want_cat:
                continue
            if m["rawAmount"] >= 0 or d["amountMinor"] != abs(int(m["rawAmount"])):
                continue
            dd = _parse_date(d["rawDate"])
            cands.append((abs((dd - md).total_seconds()), d["sourceRow"], d, dd))
        cands.sort(key=lambda t: (t[0], t[1]))
        scored.append((cands[0][0] if cands else float("inf"), m["sourceRow"], m, md, cands))
    scored.sort(key=lambda t: (t[0], t[1]))  # khớp cặp gần nhất trước để tránh tranh chấp
    for _, _, m, md, cands in scored:
        free = [c for c in cands if c[2]["sourceRow"] not in used]
        entry = {"mirrorRow": m["sourceRow"], "date": m["rawDate"], "amount": m["rawAmount"],
                 "member": m["rawMember"], "note": m["rawNote"], "matchedRow": None,
                 "confidence": "NONE", "reason": ""}
        if not free:
            m["cls"] = "REVIEW_TRANSFER_MIRROR"
            m["normalizationReason"] = "không có dòng chuyển có hướng nào cùng số tiền/hướng còn trống"
            entry["reason"] = m["normalizationReason"]
            report.append(entry)
            continue
        dt, row, d, dd = free[0]
        same_day = dd.date() == md.date()
        ambiguous = len(free) > 1 and free[1][0] <= max(dt * 2, 60)
        if dt <= 60 and not ambiguous:
            conf = "HIGH"
        elif same_day and not ambiguous:
            conf = "MEDIUM"
        else:
            conf = "LOW"
        entry.update(matchedRow=row, confidence=conf,
                     reason=f"|Δt|={int(dt)}s; {'cùng ngày' if same_day else 'khác ngày'}; ứng viên còn trống={len(free)}")
        if conf in ("HIGH", "MEDIUM"):
            used.add(row)
            m["cls"] = "LEGACY_TRANSFER_MIRROR_SKIPPED"
            m["normalizationReason"] = f"đối ứng của dòng {row} ({d['rawCategory']}), độ tin cậy {conf}"
            m["mirrorOf"] = row
        else:
            m["cls"] = "REVIEW_TRANSFER_MIRROR"
            m["normalizationReason"] = f"khớp không chắc chắn với dòng {row} ({conf}): {entry['reason']}"
            m["mirrorCandidate"] = row
        report.append(entry)
    report.sort(key=lambda e: e["mirrorRow"])
    return report


def flag_exact_duplicates(records: list) -> list:
    """Gắn cờ (KHÔNG loại bỏ) các dòng giống hệt mọi trường nguồn.

    Khóa = (Hạng mục, Thành tiền, Chi tiết, Người tiêu, Ngày-giờ đến ms, Trạng thái).
    Giữ nguyên `cls` (Excel đang tính cả hai). Trả về các nhóm số dòng.
    """
    groups = defaultdict(list)
    for r in records:
        if r["rawAmount"] is None:
            continue
        key = (r["rawCategory"], r["rawAmount"], r["rawNote"], r["rawMember"], r["rawDate"], r["rawStatus"])
        groups[key].append(r["sourceRow"])
    dups = sorted(sorted(rows) for rows in groups.values() if len(rows) > 1)
    byrow = {r["sourceRow"]: r for r in records}
    for grp in dups:
        for row in grp:
            byrow[row]["flags"].append("EXACT_DUPLICATE_GROUP:" + "/".join(map(str, grp)))
    return dups


def normalize(raw_rows: list):
    """Toàn bộ pipeline. Trả về (records, mirror_report, duplicate_groups)."""
    recs = [classify(r) for r in sorted(raw_rows, key=lambda r: r["row"])]
    mirror_report = match_mirrors(recs)
    dups = flag_exact_duplicates(recs)
    return recs, mirror_report, dups


def class_counts(records: list) -> Counter:
    return Counter(r["cls"] for r in records)
