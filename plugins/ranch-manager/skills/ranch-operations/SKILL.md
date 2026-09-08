---
name: ranch-operations
description: Use for VIMO Ranch Management questions and tasks involving cows, calves, milk, feed/stock, doctor history, pregnancy, purchases, sales, expenses, reports, family roles, Firebase sync, or safe changes to the existing Flutter app.
---

# VIMO Ranch Operations

## Product context
VIMO is an offline-first Flutter ranch management app. Browser-local Hive data syncs to Firebase/Firestore for authenticated ranch members. Preserve the existing UI and working flow unless the user explicitly asks for a redesign.

## Safety and data rules
- Treat Firestore as the shared source of truth for cloud ranch data and Hive as offline local state.
- Never bypass Firestore security rules or ranch membership roles.
- For destructive actions such as deleting animals, sales, medical history, or ranch records, require explicit user intent and explain the affected record before writing.
- Prefer non-destructive updates and additive audit-friendly records.
- Do not repeat or rename the one-time prelaunch reset migration marker.
- Never expose Firebase secrets, service-account credentials, tokens, or private user data.

## Ranch roles
Respect the app's current roles: Admin, Editor, Data Entry/Basic Entry, and Viewer according to Firestore rules. Do not grant broader permissions in code unless the user explicitly requests a role-system change.

## Core ranch domains
Support these areas:
- Animals: cows, calves/heifers, lifecycle, birth, pregnancy, lactation, death.
- Milk: morning/afternoon/evening entries, per-cow totals, trends, ranking, available milk and sales impact.
- Feed and stock: Vaikol, Thavudu and other stock purchases/usages with correct inventory arithmetic.
- Doctor: problem, medicine/injection, pregnancy-related treatment, cost and dates.
- Finance: purchases, sales, expenses and monthly totals.
- Reports: cow performance, milk totals, doctor costs, feed/stock consumption, profit/expense summaries and exports.
- Family: ranch membership, join requests and role-aware workflows.

## Analysis behavior
When live MCP ranch-data tools are available, use them instead of asking the user to copy data manually. For analysis:
1. Identify the relevant date range.
2. Read only the collections needed.
3. Reconcile totals before presenting them.
4. Call out missing or inconsistent records instead of guessing.
5. Keep milk, stock usage, purchase expense and sale accounting separate to avoid double counting.

## Development behavior
When changing the Flutter app:
- Keep existing UI, Liquid Glass styling, navigation and working flow unless asked otherwise.
- Inspect the relevant code and Firestore rules before modifying sync or permissions.
- Make changes on a branch and prefer a pull request over direct main-branch edits.
- Preserve offline-first behavior and automatic cloud sync.
- Check Android/web compatibility for shared Dart changes.
- Avoid large unrelated refactors while fixing a focused issue.

## Useful future live-data actions
When the VIMO MCP server is connected, prefer tools equivalent to:
- get_ranch_summary
- list_animals / get_animal
- get_milk_records / add_milk_record
- get_stock_summary / add_stock_purchase / record_stock_usage
- get_doctor_history / add_doctor_record
- get_expense_summary / add_expense
- get_sales_summary / add_sale
- get_report

Any write action must enforce authenticated ranch membership and server-side role checks.
