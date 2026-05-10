# SPEC-M1-S5: Daily Report

## Status
Draft

## Parent
SPEC-000: Amuwak Staff Product Foundation

## Depends On
SPEC-M1-S1: Auth Foundation
SPEC-M1-S2: Staff Dashboard
SPEC-M1-S3: Orders Workflow
SPEC-M1-S4: Status Updates

## Goal
Create a daily report screen that summarizes the staff member's laundry work for the day.

## User Story
As a laundry staff member, I want to see a daily summary of assigned orders, completed work, pending work, and total handled items so that I can understand the day’s progress.

## Requirements

### R1: Staff can open daily report
The dashboard quick action named Report should open the daily report screen.

### R2: Report shows order summary
The report should show:
- Total assigned orders
- Pending pickup
- In progress
- Ready for delivery
- Completed today

### R3: Report shows total items
The report should show the total number of laundry items across assigned orders.

### R4: Report reflects current local order state
If an order status is updated, the daily report should use the updated dashboard order state.

### R5: Report uses Amuwak theme
The report screen should use the same brown/orange-brown Amuwak branding.

### R6: Report is mobile-first
The report should be readable and scrollable on a phone screen.

## Out of Scope
- PDF export
- Backend persistence
- Manager approval
- Revenue calculation
- Payment reconciliation
- Multi-day reports
- Staff attendance reports

## Acceptance Criteria
- Staff can tap Report from the dashboard.
- Daily report screen opens.
- Report shows total assigned orders.
- Report shows status breakdown.
- Report shows total item count.
- Report reflects status updates made during the current app session.
- Back navigation returns to dashboard.

## Test Plan
- Run the app.
- Log in using mock credentials.
- Open Report.
- Confirm summary values are visible.
- Go back to dashboard.
- Open an order and update its status.
- Return to dashboard.
- Open Report again.
- Confirm report values changed correctly.

## Definition of Done
This spec is done when staff can open a daily report from the dashboard and see a branded daily summary based on the current mock order data.
