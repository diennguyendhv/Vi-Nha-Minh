# Phase P6.1 — Transaction and Summary UX

# Phase P6.1 — Transaction / Summary UX and amount input

Transaction is a fast chronological ledger for one selected month. Summary is
analysis: it supports only Day, Month, or Year, each with a previous/next
navigator. The product does not expose an all-time transaction view.

Both surfaces use `TransactionRow`: category or transfer meaning is primary,
note and member are secondary, and the amount is right aligned. Transaction
groups rows by date and shows the daily net subtotal.

The add-transaction amount field owns a local `ValueNotifier<int>`. A
keystroke runs the lightweight digit formatter, updates that local value, then
only rebuilds the amount preview and save button. It does not call `setState`,
write/query Drift, or invalidate Riverpod providers. Financial validation and
persistence remain on Save.

Summary's `Số liệu` sheet labels flow metrics with the selected period and
member, savings, fund, and asset balances as current-state values. Its asset
totals come from `computeFinancialSummary`, the shared domain read model.

## Findings and decisions

- Wallet's record filters and analytics are separate surfaces, while transfers
  are excluded from income/expense and cash-flow reporting. P6.1 follows that
  mental model: Transaction is the ledger, Summary is the explorer, and
  Transfer remains separate from income and external expense.
- A direct digit-only amount field is quicker and more accessible than a
  custom keypad. `AmountInputFormatter` preserves the existing nine-digit cap,
  removes leading zeroes, and leaves grouped currency formatting to the
  preview.
- Rebuilding the whole add/edit sheet on every amount keystroke was the root
  cause of avoidable input work. Local `ValueNotifier<int>` state confines the
  rebuild to preview and Save; no provider invalidation or persistence happens
  until Save.

Sources: [Wallet filters](https://support.budgetbakers.com/hc/en-us/articles/7076754432146-Working-with-Filters)
and [Wallet statistics semantics](https://support.budgetbakers.com/hc/en-us/articles/36544649033618-How-to-exclude-an-account-records-or-transfers-from-your-statistics).

## Verification

- Widget and unit coverage exercises date scope, member/category/status/search
  filters, shared row layout, statistics sheet, digit normalization, maximum
  length, Save enablement, and the guarantee that typing does not write the
  repository.
- Pixel DEV acceptance: Summary shows only Day/Month/Year plus `Số liệu`; the
  amount field normalized `001200000` to `1200000` and previewed
  `1.200.000 đ` without saving. PROD read-only baseline and post-check matched:
  schema v8, integrity `ok`, no foreign-key violations, 1,822 transactions,
  wallet `3cbd8878…`, and SHA-256 `803de56…420771eb6`.
- The installed PROD binary predates P6.1 (it still shows an `All` time chip
  and the previous row layout), so it cannot visually accept the new UI unless
  a P6.1 PROD build is installed. No PROD update was attempted.

## Extended review — canonical transaction unification (2026-09-26)

Audit result: Summary's base iteration filters only `isVisible` (no source/destination kind, transfer kind, category or type exclusion), so every canonical Transaction is discoverable; `computeGroupedTotals` and `ExplorerResult` count only Income/Expense, so Transfer never inflates Thu/Chi. A Fund-backed Expense is an ordinary `EXPENSE` (real category, `sourceKind = FUND`) and matches the Fund filter through either endpoint. Fund and Savings history rows open `TransactionDetailScreen(transactionId)`, which drives the single `updateTransaction` / `deleteTransaction` use cases. The reported gaps were presentation-only (the old Fund-only `_EntryRow` had no tap target; Summary lacked Fund context filters) and are fixed by `23991a6`.

One Financial-Core hole closed: `LocalTransactionRepository.updateTransaction` now rejects a `categoryId` whose type differs from the transaction's type (`MainGroupChangeException`), so Income/Expense/Transfer cannot be switched through any caller. UI already offered only same-type categories.

Known limitation (needs a separately approved data representation, no schema change made): a Fund-backed Expense stores no spending member, so "by member" filtering cannot include it; Transfer endpoint replacement (source/destination) is not editable.

Tests: `test/data/repositories/transaction_unification_test.dart` (real in-memory DB: Husband→Fund, Fund expense, Wife↔Husband, Savings top-up/withdraw/convert, single id, edit, exact-once delete, main-group immutability) and `test/presentation/features/canonical_transaction_entry_test.dart` (Fund/Savings rows → canonical detail → edit/delete).
