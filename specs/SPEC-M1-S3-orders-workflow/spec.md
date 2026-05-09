# SPEC-M1-S3: Orders Workflow

## Status
Draft

## Parent
SPEC-000: Amuwak Staff Product Foundation

## Depends On
SPEC-M1-S1: Auth Foundation
SPEC-M1-S2: Staff Dashboard

## Goal
Create the first order workflow by allowing staff to open an assigned order from the dashboard and view its details.

## User Story
As a laundry staff member, I want to open an assigned order and see the customer, service, timing, item count, and notes so that I know exactly what work needs to be done.

## Requirements

### R1: Staff can tap an order card
The dashboard order cards should be tappable.

### R2: Tapping an order opens order details
When staff tap an order card, the app should navigate to an order details screen.

### R3: Order details show key information
The order details screen should show:
- Order ID
- Customer name
- Service type
- Status
- Pickup or delivery time
- Item count
- Phone placeholder
- Address placeholder
- Notes

### R4: Order details use Amuwak theme
The screen should use the same brown/orange-brown brand theme.

### R5: Screen is mobile-first
The order details screen should be easy to read on a phone.

## Out of Scope
- Real backend order data
- Status update logic
- Payment confirmation
- Delivery route map
- Customer chat

## Acceptance Criteria
- Staff can tap an order card.
- Order details screen opens.
- Details screen shows order/customer/service/status/time/items.
- Screen follows Amuwak theme.
- Back navigation works.

## Test Plan
- Run the app.
- Log in using mock credentials.
- Tap each mock order.
- Confirm details screen opens.
- Confirm data shown matches the tapped order.
- Press back and confirm dashboard returns.

## Definition of Done
This spec is done when staff can open a mock assigned order from the dashboard and view a clean order details screen.
