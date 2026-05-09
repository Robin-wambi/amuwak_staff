# Plan: SPEC-M1-S2 Staff Dashboard

## Implementation Approach
Build a mock-data dashboard first so that the staff workflow can be designed before backend integration.

## Files to Create or Update
- Update `lib/src/dashboard/staff_dashboard_screen.dart`
- Optionally create `lib/src/dashboard/widgets/`
- Optionally create `lib/src/dashboard/models/`

## UI Sections
1. Header greeting
2. Daily summary cards
3. Quick actions
4. Assigned orders list

## Mock Order Fields
Each order should include:
- orderId
- customerName
- serviceType
- status
- timeLabel
- itemCount

## Design Direction
- Use Amuwak primary brown/orange-brown for highlights and buttons.
- Use soft warm background for the scaffold.
- Use white cards.
- Use rounded corners.
- Use clean spacing.
- Use readable mobile-first layout.

## Risks
- Dashboard may become too crowded.
- Mock data may not match the future backend shape.
- Status names may need refinement after order workflow spec.

## Decisions
- Use mock data in this spec.
- Keep dashboard simple.
- Do not add backend yet.
- Do not add complicated charts yet.