# SPEC-M1-S4: Status Updates

## Status
Draft

## Parent
SPEC-000: Amuwak Staff Product Foundation

## Depends On
SPEC-M1-S1: Auth Foundation
SPEC-M1-S2: Staff Dashboard
SPEC-M1-S3: Orders Workflow

## Goal
Allow staff to update the status of a laundry order from the order details screen.

## User Story
As a laundry staff member, I want to update an order's status as work progresses so that the dashboard reflects the current state of laundry operations.

## Status Flow
Orders should move through this flow:

1. Pending pickup
2. In progress
3. Ready for delivery
4. Completed

## Requirements

### R1: Order details screen shows current status
The order details screen should clearly display the current order status.

### R2: Staff can update status
The order details screen should include an update status action.

### R3: Status update follows allowed sequence
The app should move the order to the next valid status only.

Allowed transitions:
- Pending pickup → In progress
- In progress → Ready for delivery
- Ready for delivery → Completed
- Completed → No further update

### R4: Completed orders cannot be updated further
If an order is already completed, the update action should be disabled or show that no further status change is available.

### R5: Dashboard summary reflects updated status
When staff update an order status and return to the dashboard, summary counts should reflect the new order status.

### R6: Dashboard order card reflects updated status
The selected order card should show the new status after update.

## Out of Scope
- Backend persistence
- Staff audit logs
- Status update timestamps
- Push notifications
- Customer notifications

## Acceptance Criteria
- Staff can open an order.
- Staff can update status from the details screen.
- Status changes only to the next valid status.
- Completed orders cannot move further.
- Dashboard summary counts update after returning.
- Dashboard order cards show updated status.
- App remains mobile-friendly.

## Test Plan
- Log in.
- Open a Pending pickup order.
- Tap Update status.
- Confirm it changes to In progress.
- Return to dashboard.
- Confirm summary count changed.
- Open the same order again.
- Continue until Completed.
- Confirm Completed order cannot be updated further.

## Definition of Done
This spec is done when staff can update a mock order's status through the allowed laundry workflow and see the updated state reflected on the dashboard.
