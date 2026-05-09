# Plan: SPEC-M1-S3 Orders Workflow

## Implementation Approach
Use the mock order data already shown on the dashboard and pass the selected order into a new order details screen.

## Files to Create or Update
- Create `lib/src/orders/order_details_screen.dart`
- Update `lib/src/dashboard/staff_dashboard_screen.dart`

## UI Sections
1. Order header
2. Customer section
3. Service details section
4. Pickup/delivery section
5. Notes section
6. Action placeholder

## Data Needed
The dashboard order model should include:
- orderId
- customerName
- serviceType
- status
- timeLabel
- itemCount
- phone
- address
- notes

## Decisions
- Continue using mock data.
- Keep status update button as placeholder.
- Real update flow comes in SPEC-M1-S4.