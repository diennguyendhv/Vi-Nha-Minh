# P6.1 Codex → Claude Handoff

> Historical handoff below, recorded before the 2026-09-25 follow-up. The user subsequently approved the filter structure, requested compact conditional filters and the unallocated-savings fix, and requested commit/push of the installed build. Summary/explorer verification now passes 110 tests; the latest PROD debug APK was installed in place on Pixel 7a. References below to uncommitted work describe the earlier checkpoint, not the current Git status. The unverified structural edit flows remain limitations.

## 1. Stable checkpoint before extended work

- P6.1 previously passed at commit `77eb132` (`perf(ui): refine transaction summary and amount input`).
- Scope: Transaction/Summary UX, amount-input performance, Day/Month/Year bounded filtering, and Statistics sheet.
- Schema remains v8. P7 has not started.

The working tree now contains additional **uncommitted** transaction-unification work after `77eb132`. Preserve and review it before changing anything.

## 2. Locked product requirements

1. Every canonical valid Transaction must be discoverable in Summary for its selected Day/Month/Year: Income, Expense, member transfer, Fund top-up/transfer, Fund-backed Expense, Savings top-up/withdraw/conversion, and other transaction-backed flows.
2. Visibility differs from accounting: Income contributes by Income semantics, Expense by Expense semantics, and Transfer remains visible without inflating Thu/Chi.
3. Transaction History, Summary, Fund, Savings, and other histories must use the same `Transaction.id`.
4. The overall View/Edit/Delete flow must be unified for a canonical transaction regardless of entry point.
5. Main group is immutable during edit: Income, Expense, and Transfer cannot change between groups. Same-group fields may change only when Financial Core invariants allow it.
6. Fund-backed expense remains an ordinary Expense with normal expense category and `sourceKind = FUND`; do not invent a fake “expense from fund” category.
7. A Fund filter must match both `sourceKind == FUND && sourceRefId == selectedFundId` and `destinationKind == FUND && destinationRefId == selectedFundId`.

## 3. Current uncommitted changes after `77eb132`

### Implemented

- `lib/presentation/features/fund/fund_detail_screen.dart`: replaces Fund-only `_EntryRow` with shared `TransactionRow`; tap passes the canonical `Transaction.id` to `TransactionDetailScreen`.
- `lib/presentation/features/savings/savings_screen.dart`: adds a Savings history derived from canonical transaction rows and opens `TransactionDetailScreen` by id.
- `lib/presentation/widgets/transaction_row.dart`: adds human-facing labels/context for Fund, Savings, and member transfers.
- `lib/domain/usecases/explore_transactions.dart`: adds Summary filters for transaction type, pool kind, and selected Fund id; base iteration still begins from every `isVisible` transaction.
- `lib/presentation/features/summary/summary_screen.dart`: adds compact filters for type, Quỹ/Tiết kiệm context, and named Funds.
- `lib/presentation/features/transactions/transaction_detail_screen.dart`: shows immutable main transaction type in the shared detail UI.
- `test/presentation/features/summary_explorer_test.dart`: covers transfer/Fund/Savings visibility and that Transfer does not change Thu/Chi totals.

### Partially implemented / not verified

- The shared detail flow supports existing repository-safe amount/date/note edits and delete for ordinary canonical transactions. Transfer structural endpoint editing is not implemented: the current repository update contract only accepts amount/category/note/member/date/status, not a full source/destination replacement.
- The data model does not store the spending member on an Expense whose source is Fund. Therefore filtering a Fund-backed expense by “Wife” cannot be inferred from current `Transaction` fields without a separately approved representation; do not guess from note/category.
- No Pixel DEV mutation acceptance has proved Fund/Savings edit/delete end-to-end. DEV began with no categories, so a fixture category was being created when work was stopped.

## 4. What is verified

- Targeted Summary and TransactionDetail widget tests were run after the uncommitted changes and showed no failure in captured output. Existing Drift multiple-database messages are test-fixture warnings.
- Earlier targeted Summary/Fund/Savings tests passed before the final named-Fund filter addition.
- DEV APK was rebuilt and installed in place. PROD was reopened afterward; no PROD mutation was attempted.
- A prior P6.1 stable checkpoint recorded schema v8, 1,822 transactions, integrity `ok`, clean FK, wallet prefix `3cbd8878`, and unchanged DB hash. This is a reference only, not a count to restore.
- A new read-only PROD check was attempted for this handoff but the USB device was no longer available (`adb: device not found`), so no fresh schema/count/integrity reading exists.

## 5. Known failures / unresolved behavior

1. User observed Fund-history transactions could not be edited as expected.
2. User observed Summary could show “Nạp quỹ” but lacked the expected way to find normal Fund-backed Expense rows.
3. Current Fund/Savings unification may be presentation-level only; repository/provider/canonical data path needs audit.
4. Trace `transaction_rows → repository query → provider → Summary filtering → TransactionRow` for Fund-backed Expense.
5. Trace `Fund/Savings history row → Transaction.id → TransactionDetailScreen → canonical Edit/Delete use cases` and identify why behavior differs by entry point.

## 6. Important warning to Claude

> **DO NOT CONTINUE PATCHING UI FIRST.** Audit transaction semantics and canonical data flow before editing code.

Explicitly verify whether the Summary base query excludes source/destination kind or ref, transfer kind, infrastructure/system categories, advanced categories, transaction type, or category visibility. Also establish whether edit/delete restrictions are UI-only or required Financial Core integrity constraints.

## 7. Recommended starting procedure

1. Read `CLAUDE.md`, `docs/current-project-state.md`, `docs/phase-p6-1.md`, and this file.
2. Inspect `git status`, `git diff`, and `git diff 77eb132`.
3. Review the uncommitted diff before modifying it.
4. Decide KEEP / MODIFY / REVERT for each Codex change.
5. Audit canonical transaction semantics before further implementation.
6. Do not start P7.

## 8. PROD safety checkpoint

- PROD package intended: `com.vinhamimh.vi_nha_minh`.
- PROD was reopened after DEV work. No PROD financial transaction was created, edited, deleted, imported, restored, cleared, or uninstalled.
- Earlier backup exists at `Documents/ViNhaMinh_backups/2026-09-22/p6_1_pre`; no backup restore occurred.
- Fresh read-only values are unavailable because USB disconnected during the handoff check. Live transaction count must be read, never forced to an older checkpoint.

## 9. Git state

- Branch: `master`
- HEAD: `77eb132 perf(ui): refine transaction summary and amount input`
- Modified implementation/test files: 7 (listed above).
- This handoff document and the minimal project-state note are additional uncommitted documentation changes.
- No commit was created for extended P6.1 work.
