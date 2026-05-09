# Tasks: SPEC-M1-S4 Status Updates

## M1-S4-01: Make order model update-friendly
- [ ] Add `copyWith` method to `LaundryOrder`
- [ ] Keep all existing fields unchanged

## M1-S4-02: Make dashboard stateful
- [ ] Convert `StaffDashboardScreen` from `StatelessWidget` to `StatefulWidget`
- [ ] Move mock orders into state
- [ ] Recalculate summary cards from state

## M1-S4-03: Return updated order from details screen
- [ ] Update status in order details screen
- [ ] Use `Navigator.pop(context, updatedOrder)`
- [ ] Disable update when order is completed

## M1-S4-04: Update dashboard after return
- [ ] Await navigation result when order card is tapped
- [ ] Replace changed order in list
- [ ] Confirm order card status updates
- [ ] Confirm summary cards update

## M1-S4-05: Verify status flow
- [ ] Pending pickup changes to In progress
- [ ] In progress changes to Ready for delivery
- [ ] Ready for delivery changes to Completed
- [ ] Completed cannot update further