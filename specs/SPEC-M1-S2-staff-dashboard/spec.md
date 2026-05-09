# SPEC-M1-S2: Staff Dashboard

## Status
Draft

## Parent
SPEC-000: Amuwak Staff Product Foundation

## Depends On
SPEC-M1-S1: Auth Foundation

## Goal
Create the main staff dashboard that appears after successful login.

## User Story
As a laundry staff member, I want to see today’s assigned laundry work immediately after logging in so that I can know what needs pickup, washing, ironing, delivery, or completion.

## Requirements

### R1: Dashboard appears after login
After successful login, the user should land on the staff dashboard.

### R2: Dashboard shows staff greeting
The dashboard should show a friendly greeting and indicate that this is the staff workspace.

### R3: Dashboard shows today’s summary
The dashboard should show summary cards for:
- Total assigned orders
- Pending pickup
- In progress
- Ready for delivery
- Completed today

### R4: Dashboard shows assigned orders
The dashboard should list assigned laundry orders using clean order cards.

### R5: Order cards show key information
Each order card should show:
- Customer name
- Order ID
- Service type
- Status
- Pickup or delivery time
- Number of items

### R6: Dashboard uses Amuwak theme
The dashboard should use the brown/orange-brown brand theme from the logo direction.

### R7: Dashboard is mobile-first
The layout should be readable and usable on a phone screen.

## Mock Data
For M1-S2, mock order data is allowed.

Backend integration is not required in this spec.

## Acceptance Criteria
- Dashboard opens after successful mock login.
- Dashboard shows greeting text.
- Dashboard shows today’s summary cards.
- Dashboard shows a list of mock assigned orders.
- Each order card shows customer, order ID, service, status, time, and item count.
- UI follows Amuwak brand colors.
- The screen scrolls properly on small screens.

## Test Plan
- Run the app.
- Log in using mock credentials.
- Confirm dashboard appears.
- Confirm summary cards are visible.
- Confirm assigned order cards are visible.
- Resize browser/mobile view and confirm the dashboard remains usable.

## Definition of Done
This spec is done when staff can log in and see a branded dashboard showing today’s laundry workload and assigned mock orders.