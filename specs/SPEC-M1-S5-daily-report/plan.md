# Plan: SPEC-M1-S5 Daily Report

## Implementation Approach
Use the current in-memory order list from the dashboard and pass it to a daily report screen.

## Files to Create or Update
- Create `lib/src/reports/daily_report_screen.dart`
- Update `lib/src/dashboard/staff_dashboard_screen.dart`

## UI Sections
1. Report header
2. Daily order summary
3. Status breakdown
4. Total items handled
5. Staff work summary

## Data Needed
The report screen receives:
- List<LaundryOrder> orders

It calculates:
- totalOrders
- pendingPickup
- inProgress
- readyForDelivery
- completed
- totalItems

## Decisions
- Keep the report local-only for M1.
- Do not export PDF yet.
- Do not calculate revenue yet.
- Do not connect to backend yet.