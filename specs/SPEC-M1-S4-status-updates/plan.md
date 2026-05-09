# Plan: SPEC-M1-S4 Status Updates

## Implementation Approach
Move mock orders from a static constant list into dashboard state so the order status can change during the running app session.

## Files to Update
- `lib/src/dashboard/staff_dashboard_screen.dart`
- `lib/src/orders/order.dart`
- `lib/src/orders/order_details_screen.dart`

## Main Changes
1. Make dashboard stateful.
2. Store mock orders in dashboard state.
3. Add a `copyWith` method to `LaundryOrder`.
4. Pass selected order to details screen.
5. Return updated order from details screen using `Navigator.pop`.
6. Update dashboard order list when a changed order returns.
7. Recalculate summary cards from updated state.

## Status Flow
- Pending pickup → In progress
- In progress → Ready for delivery
- Ready for delivery → Completed
- Completed → No next status

## Decisions
- Keep status updates local only for M1.
- No backend persistence yet.
- No login-user audit logs yet.
- Dashboard state resets when app restarts.