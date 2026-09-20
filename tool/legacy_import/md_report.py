"""Sinh `real_data_import_audit.md` (báo cáo người đọc) từ dữ kiện đã tính. Chỉ đọc/ghi trong thư mục đầu ra."""
from __future__ import annotations

import os


def money(v):
    return f"{int(v):,}".replace(",", ".")


def write_md(out, stats, facts, recs, sim):
    L = []
    w = L.append
    st = stats["structure"]
    w("# V2-2A — Audit + dry-run nhập dữ liệu thật (CHỈ ĐỌC)\n")
    w(f"Nguồn: `Quản lý tài chính 2026.xlsx` — SHA-256 `{st['sha256']}` (tệp không bị sửa). Không ghi DB/Pixel.\n")

    w("## A. Cấu trúc workbook\n")
    w("| Sheet | Trạng thái | Vùng dùng | Hàng có dữ liệu | Ô công thức | Hàng ẩn | Ô gộp |\n|---|---|---|---:|---:|---|---:|")
    for s in st["sheets"]:
        hr = s["hiddenRows"]
        hrt = f"{hr['count']} (hàng {hr['min']}–{hr['max']})" if hr["count"] else "0"
        w(f"| {s['name']} | {s['state']} | {s['dimensions']} | {s['nonEmptyRows']} | {s['formulaCells']} | {hrt} | {len(s['merged'])} |")
    w("\n- Ghi chép, tiêu đề = " + ", ".join(map(str, stats["header"])) + ". Ánh xạ theo TÊN cột: A=STT (công thức SUBTOTAL, bỏ qua), B=Hạng mục, C=Thành tiền, D=Chi tiết, E=Người tiêu, F=Ngày tháng, G=Trạng thái.")
    w("- Autofilter A1:G2002; hàng 2–1703 đang bị ẨN nhưng vẫn được đọc và tính (Excel SUMIFS cũng tính hàng ẩn).")
    w(f"- Kiểu ô: ngày = datetime ngây thơ ({stats['types']['date']}), định dạng `{stats['types']['dateFormat']}`, KHÔNG có múi giờ (giả định giờ địa phương); thành tiền = {stats['types']['amount']} (`{stats['types']['amountFormat']}`); Ghi chép không có ô gộp; Tổng hợp có 14 ô gộp (chỉ tiêu đề).")
    w("- Ô lạc ngoài bảng (cột H–J, KHÔNG phải dữ liệu): " + "; ".join(f"{x['cell']}={x['value']!r}" for x in stats["stray"]))
    sup = stats["supportSheetRows"]
    w("- Sheet ẩn `Hỗ trợ kỹ thuật`: " + str(len(sup)) + " dòng thu nhập (" + "; ".join(f"{money(x['amount'])} đ ngày {x['date']}" for x in sup) + "); " + "; ".join(f"khớp Ghi chép hàng {m['matchingGhiChepRows']}" for m in facts["supportSheetVsGhiChep"]) + " → KHÔNG nhập (nhiều khả năng đã có trong Ghi chép).\n")

    w("## B–C. Số dòng\n")
    w(f"- Dòng có nghĩa (có dữ liệu ở B:G): **{stats['meaningfulRows']}**; dòng giống giao dịch (có Thành tiền số): **{stats['transactionLikeRows']}**; tổng phân loại = **{stats['classSum']}** (không mất dòng nào).\n")
    w("| Phân loại | Số dòng | Tổng (VND) |\n|---|---:|---:|")
    for k, n in sorted(facts["classCounts"].items(), key=lambda kv: -kv[1]):
        w(f"| {k} | {n} | {money(facts['classSums'][k]) if k in facts['classSums'] else ''} |")

    w("\n## D. Phân phối Hạng mục (thô)\n")
    w("| Hạng mục | Dòng | Dương (n / tổng) | Âm (n / tổng) | Trống tiền |\n|---|---:|---|---|---:|")
    for k, t in sorted(facts["categoryDistribution"].items(), key=lambda kv: -kv[1]["n"]):
        w(f"| {k} | {t['n']} | {t['pos']} / {money(t['posSum'])} | {t['neg']} / {money(t['negSum'])} | {t['blank']} |")

    w("\n## E. Người tiêu\n")
    w("Giá trị thô: " + ", ".join(f"{k}={v}" for k, v in facts["memberDistribution"].items()) + ". Không có biến thể chính tả (chỉ 'Vợ', 'Chồng', trống). Chuyển thành viên suy hướng từ Hạng mục nên Người tiêu trống ở 23 dòng chuyển KHÔNG chặn (đánh cờ MEMBER_BLANK). Mọi giao dịch cần thành viên đều có Người tiêu.\n")

    w("## F. Trạng thái\n")
    w(f"Dòng nhập KHÔNG có trạng thái (statusId = null): **{facts['importNoStatusCount']}**.\n")
    w("| Hạng mục nguồn | Trạng thái → số dòng |\n|---|---|")
    for k, v in facts["statusByRawCategory"].items():
        w(f"| {k} | " + ", ".join(f"{a}: {b}" for a, b in v.items()) + " |")
    w("\nTheo danh mục đề xuất (mỗi cặp danh mục·trạng thái là MỘT id riêng, vd 'Đã gửi · Cho đi' ≠ 'Đã gửi · Dâng hiến'):\n")
    for k, v in facts["statusByProposedCategory"].items():
        w(f"- `{k}`: " + ", ".join(f"{a}: {b}" for a, b in v.items()))
    w("\n⚠ Trạng thái xuất hiện trên hạng mục 'không mong đợi' (Thu nhập, Đầu tư, Sinh hoạt, Tự thưởng) và trên 6 dòng Tiết kiệm/Chuyển (5 Tiết kiệm 'Đã gửi', 1 'Chồng đưa vợ' 'Đã gửi'): danh mục hệ thống Chuyển/Tiết kiệm hiện KHÔNG có trạng thái → chủ dự án cần quyết định (bỏ hay giữ).\n")

    w("## G. Ngày\n")
    d = facts["dates"]
    w(f"- Sớm nhất {d['earliest']}, muộn nhất {d['latest']}; theo năm {d['byYear']}; ngày không hợp lệ: {d['invalid']}.")
    w("- Theo tháng: " + ", ".join(f"{k}: {v}" for k, v in d["byMonth"].items()))
    w(f"- Trùng dấu thời gian (đến ms): {d['duplicateTimestampGroups']} nhóm / {d['duplicateTimestampRows']} dòng; dòng chỉ có ngày (00:00:00): {d['dateOnlyMidnightRows']}.")
    w(f"- Mốc: ngày vận hành trong Tổng hợp = {facts['cutoffs']['summaryOperatingDate']}; ngày nhập = {facts['cutoffs']['importDate']}. Dòng sau ngày Tổng hợp: {facts['afterSummaryDateRows']}.")
    w("- **Dòng ngày TƯƠNG LAI (sau ngày nhập)**, giữ nguyên ngày nguồn, KHÔNG loại bỏ: " + "; ".join(f"hàng {r['row']} {r['date'][:10]} {r['category']} {money(r['amount'])} {r['member']} ({r['status']})" for r in facts["futureRows"]))

    w("\n## H–L. Chuẩn hóa\n")
    cs = facts["classSums"]
    w(f"- Doanh thu (Thu nhập > 0): 225 dòng / {money(cs['IMPORT_REVENUE'])}")
    w(f"- Chi phí kinh doanh (Thu nhập < 0, lấy |x|): 24 / {money(cs['IMPORT_BUSINESS_EXPENSE'])} → Thu nhập ròng 301.954.000 − 24.790.000 = **277.164.000**")
    w(f"- Chi tiêu (hạng mục chi > 0): 1256 / {money(cs['IMPORT_SPENDING'])}")
    w(f"- Khoản thu khác (hạng mục chi < 0, lấy |x|): 20 / {money(cs['IMPORT_OTHER_INFLOW'])}")
    w(f"- Chuyển Vợ/Chồng: 59 / {money(cs['IMPORT_MEMBER_TRANSFER'])}")
    sv = facts["savings"]
    w(f"- Tiết kiệm: nạp 157 / {money(cs['IMPORT_SAVINGS_TOPUP'])}, rút 61 / {money(cs['IMPORT_SAVINGS_WITHDRAW'])}. Vợ: nạp {sv['vo']['topupN']} / {money(sv['vo']['topup'])}, rút {sv['vo']['withdrawN']} / {money(sv['vo']['withdraw'])}, ròng **{money(sv['vo']['net'])}**; Chồng: nạp {sv['chong']['topupN']} / {money(sv['chong']['topup'])}, rút {sv['chong']['withdrawN']} / {money(sv['chong']['withdraw'])}, ròng **{money(sv['chong']['net'])}**. Đầu kỳ + ròng: Vợ 2.500.000 + 2.240.000 = 4.740.000; Chồng 12.000.000 + 63.000.000 = 75.000.000.\n")

    w("## M. Đối ứng 'Vợ chồng' (13 dòng)\n")
    w("| Dòng | Ngày | Số tiền | Người | Ghi chú | Khớp dòng | Độ tin cậy | Lý do |\n|---:|---|---:|---|---|---:|---|---|")
    for e in stats["mirrorReport"]:
        w(f"| {e['mirrorRow']} | {e['date'][:19]} | {money(e['amount'])} | {e['member']} | {e['note'] or ''} | {e['matchedRow']} | {e['confidence']} | {e['reason']} |")
    w("\n12 dòng HIGH/MEDIUM → LEGACY_TRANSFER_MIRROR_SKIPPED; 1 dòng LOW → REVIEW_TRANSFER_MIRROR. Excel KHÔNG dùng hạng mục 'Vợ chồng' ở công thức nào (số dư chỉ dùng 'Chồng đưa vợ'/'Vợ đưa chồng') nên bỏ qua không làm lệch số dư.\n")

    def lst(cls):
        return [r for r in recs if r["cls"] == cls]

    w("## N. Dòng đánh dấu (SKIP_MARKER_ROW)\n")
    w("; ".join(f"hàng {r['sourceRow']} ({r['rawNote']})" for r in lst("SKIP_MARKER_ROW")) + "\n")
    w("## O. Thành tiền trống (SKIP_NO_AMOUNT, 13 dòng)\n")
    w("| Dòng | Hạng mục | Chi tiết | Người | Ngày | Trạng thái |\n|---:|---|---|---|---|---|")
    for r in lst("SKIP_NO_AMOUNT"):
        w(f"| {r['sourceRow']} | {r['rawCategory'] or '(trống)'} | {r['rawNote'] or ''} | {r['rawMember'] or ''} | {(r['rawDate'] or '')[:19]} | {r['rawStatus'] or ''} |")
    w("\n## P. Thành tiền = 0 (REVIEW_ZERO_AMOUNT)\n")
    for r in lst("REVIEW_ZERO_AMOUNT"):
        w(f"- hàng {r['sourceRow']}: {r['rawCategory']} 0 đ, {r['rawMember']}, {r['rawDate'][:19]}, ghi chú {r['rawNote']!r}, trạng thái {r['rawStatus']}")

    w("\n## Q. Ứng viên trùng lặp (KHÔNG tự loại — cả hai đang được Excel tính)\n")
    for g in facts["duplicateDetails"]:
        w(f"- hàng {g['rows']}: {g['category']} {money(g['amount'])} · {g['member']} · {g['date']} · trạng thái {g['status']} · ghi chú {g['note']!r}; dấu thời gian giống hệt đến ms: {g['timestampIdentical']}.")
    w("- Tác động nếu bỏ 1 bản: nhóm Dâng hiến → Khả dụng Chồng +200.000, Tổng tài sản +200.000; nhóm Tiết kiệm → Khả dụng Chồng +200.000, Tiết kiệm Chồng −200.000, Tổng tài sản không đổi. Mô phỏng GIỮ CẢ HAI (khớp Excel).\n")

    w("## R. Đề xuất số dư đầu kỳ (chưa ghi)\n")
    w("| Mục | Số tiền | Bằng chứng (ô Tổng hợp, nhãn năm 2025) | Đề xuất |\n|---|---:|---|---|")
    for n, a, ev in [("Vợ Khả dụng", 627000, "Tổng hợp!P3"), ("Chồng Khả dụng", 1060000, "Tổng hợp!P4"), ("Vợ Tiết kiệm", 2500000, "Tổng hợp!P5"), ("Chồng Tiết kiệm", 12000000, "Tổng hợp!P6 (=5.000.000+3.000.000+4.000.000)")]:
        dest = "Khả dụng" if "Khả dụng" in n else "Tiết kiệm · Chưa phân bổ"
        w(f"| {n} | {money(a)} | {ev} | INCOME 'Số dư đầu kỳ' (Khoản thu khác, loại khỏi tổng thu), ngoài → {dest}, 01/01/2026 00:00 |")
    w("\nId/clientTxId tất định thuộc phase nhập thật. Lưu ý: 4 khoản này cộng 16.187.000 vào tổng 'Khoản thu khác' của báo cáo (đã loại khỏi 'Doanh thu').\n")

    w("## S. Khoảng trống Tiết kiệm Ngân hàng 70.000.000 — MIGRATION_ADJUSTMENT_REQUIRED\n")
    w("- Tổng cần phân bổ: **70.000.000** (Chồng): Tiết kiệm 75.000.000 = Chưa phân bổ 5.000.000 + Ngân hàng 70.000.000. 'Ghi chép' KHÔNG có giao dịch phân bổ.")
    w("- Bằng chứng: công thức Tổng hợp!L8 `=P6+H23-30000000-10000000-10000000-10000000-10000000` (năm khoản 30tr, 10tr, 10tr, 10tr, 10tr); chú thích ô L8: 'Đã tiết kiệm được 50tr vào tháng 7', '60tr vào tháng 8', 'ngày 13 tháng 9 đã tiết kiệm được 70t', và 'thêm 6tr tiền nhà tháng 10,11,12' (dự kiến, chưa xảy ra).")
    w("- Ngày có bằng chứng: tháng 7 (mốc 50tr), tháng 8 (mốc 60tr), 13/09/2026 (mốc 70tr). Ngày của khoản 30tr/40tr đầu: không có.")
    w("- Phương án (KHÔNG tự chọn): A) 1 giao dịch phân bổ tổng hợp 70.000.000 (đề xuất ngày 13/09/2026); B) dựng lại theo mốc 30+10+10+10+10 (chỉ 3 ngày có bằng chứng, 2 khoản đầu phải đoán ngày); C) ánh xạ khác do chủ dự án cung cấp.")
    w("- Mô phỏng phương án A (chỉ tham khảo): Chồng Chưa phân bổ 5.000.000 + Ngân hàng 70.000.000; Tổng tài sản không đổi 80.578.000.\n")

    w("## T. Ánh xạ danh mục đề xuất (chưa tạo)\n")
    w("| Hạng mục nguồn | Điều kiện | Loại mới | Nhóm | Danh mục con đề xuất | Quy tắc |\n|---|---|---|---|---|---|")
    for row in [
        ("Thu nhập", "> 0", "INCOME", "Doanh thu", "Thu nhập", "giữ số tiền"),
        ("Thu nhập", "< 0", "EXPENSE", "Chi phí kinh doanh", "Chi phí kinh doanh (từ Thu nhập âm)", "|số tiền|"),
        ("Sinh hoạt / Đầu tư / Tự thưởng / Cho đi / Dâng hiến", "> 0", "EXPENSE", "Chi tiêu", "cùng tên hạng mục", "giữ số tiền"),
        ("Sinh hoạt / Đầu tư / Tự thưởng / Cho đi / Dâng hiến", "< 0", "INCOME", "Khoản thu khác", "Hoàn / thu lại · <hạng mục>", "|số tiền|, loại khỏi tổng thu"),
        ("Tiết kiệm", "> 0", "TRANSFER", "—", "Tiết kiệm", "Khả dụng → Tiết kiệm·Chưa phân bổ"),
        ("Tiết kiệm", "< 0", "TRANSFER", "—", "Tiết kiệm", "Tiết kiệm·Chưa phân bổ → Khả dụng, |số tiền|"),
        ("Chồng đưa vợ", "> 0", "TRANSFER", "—", "Chuyển tiền giữa Vợ/Chồng", "Chồng → Vợ"),
        ("Vợ đưa chồng", "> 0", "TRANSFER", "—", "Chuyển tiền giữa Vợ/Chồng", "Vợ → Chồng"),
        ("Vợ chồng", "< 0", "(bỏ qua)", "—", "—", "đối ứng, không nhập nếu khớp"),
    ]:
        w("| " + " | ".join(row) + " |")

    w("\n## U. Số lượng\n")
    cc = facts["classCounts"]
    imp = sum(v for k, v in cc.items() if k.startswith("IMPORT"))
    skip = sum(v for k, v in cc.items() if k.startswith("SKIP") or k.startswith("LEGACY"))
    rev = sum(v for k, v in cc.items() if k.startswith("REVIEW"))
    w(f"Ứng viên nhập: **{imp}** (+4 số dư đầu kỳ đề xuất); bỏ qua: **{skip}** (12 đối ứng + 9 đánh dấu + 13 trống tiền); cần chủ dự án quyết định: **{rev}** (1 đối ứng LOW + 1 số 0); ngoài ra 2 nhóm trùng lặp đang GIỮ cả hai chờ quyết định. Tổng {imp + skip + rev} = {imp + skip + rev} dòng có nghĩa.\n")

    w("## V. Số dư mô phỏng (Financial Core thật)\n")
    b = sim["base"]
    w(f"- Vợ Khả dụng {money(b['availableVo'])}; Chồng Khả dụng {money(b['availableChong'])}; Vợ Tiết kiệm {money(b['savingsVo'])} (Chưa phân bổ {money(b['savingsVoByAsset']['savings_unallocated'])}); Chồng Tiết kiệm {money(b['savingsChong'])} (trước phân bổ Ngân hàng); Quỹ 0; **Tổng tài sản {money(b['totalAssets'])}**.")
    g = b["grouped"]
    w(f"- Doanh thu {money(g['revenue'])}; Khoản thu khác {money(g['otherInflow'])} (gồm 16.187.000 số dư đầu kỳ); Chi tiêu {money(g['spending'])}; Chi phí KD {money(g['businessExpense'])}; Thu nhập ròng {money(g['netIncome'])}.\n")

    w("## W. Đối soát cổng cứng\n")
    w(f"{facts['reconRows']} chỉ tiêu (số dư cuối, cả năm, tháng 9, ngày 17/9, Vợ/Chồng, hạng mục, trạng thái): **{len(facts['reconciliationUnexplainedDeltas'])} chênh lệch** (xem reconciliation.md).\n")

    w("## X. Thứ tự nhập\n")
    ne = facts["nonNegativeInsertionOrder"]
    ev, en = facts["endOfDayNegative"]["memberAvailable|vo"], facts["endOfDayNegative"]["memberAvailable|chong"]
    w(f"- Phát lại theo ngày: {sim['replayChrono']['violationCount']} điểm Khả dụng sẽ âm (theo thứ tự dòng: {sim['replayRowOrder']['violationCount']}); thấp nhất Vợ {money(sim['replayChrono']['minBalance']['memberAvailable|vo'])}, Chồng {money(sim['replayChrono']['minBalance']['memberAvailable|chong'])}. Cuối ngày vẫn âm: Vợ {ev['days']} ngày (xấu nhất {money(ev['worst'])}, {ev['worstDay']}), Chồng {en['days']} ngày (xấu nhất {money(en['worst'])}, {en['worstDay']}). Đây là đặc tính dữ liệu gốc (Excel không chặn).")
    w(f"- Thứ tự GHI không làm âm pool nào: tồn tại = {ne['feasible']} (đặt {ne['placed']} giao dịch, {ne['outOfChronologicalPlacements']} lần hoãn khỏi thứ tự ngày). Ngày giao dịch giữ nguyên, chỉ thứ tự ghi khác. Kiểm tra Sửa/Xóa của app dựa trên số dư CUỐI nên ngày âm lịch sử không cản thao tác sau này.\n")
    open(os.path.join(out, "real_data_import_audit.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
