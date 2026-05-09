# SPEC-000: Amuwak Staff Product Foundation

## Status
Draft

## Product Name
Amuwak Staff

## Product Type
Laundry staff operations app

## Problem
Laundry staff need a simple way to manage pickup, washing, ironing, delivery, payment visibility, and daily work progress without relying only on phone calls, paper notes, or scattered WhatsApp messages.

## Goal
Build a staff-facing app that helps laundry workers log in, view assigned work, open order details, update order progress, and see a daily summary.

## Non-Goals for M1
- Customer mobile app
- Online payment integration
- Advanced analytics
- Multi-branch management
- Automated route optimization
- Full admin web dashboard

## Primary Users
### Staff
Can view assigned orders and update order status.

### Manager/Admin
Can supervise work, but advanced admin features are not part of M1.

## Modern App Flow
1. Splash/loading screen
2. Login screen
3. Role check
4. Staff dashboard
5. Order details
6. Status update
7. Daily report

## Brand Direction
The app should use the Amuwak logo identity.

The main theme color should be a warm brown/orange-brown close to the Jumia app color direction, not a bright generic orange.

Suggested palette:
- Primary brown-orange: `#A85A1F`
- Dark text: `#1F1F1F`
- Soft warm background: `#FFF8F2`
- Soft accent: `#F3E0D0`
- White: `#FFFFFF`

## Core M1 Features
- Staff login
- Role-aware routing
- Staff dashboard
- Assigned orders list
- Order details screen
- Order status update
- Daily report summary

## Success Criteria
- Staff cannot access dashboard before login.
- Staff can see only the operational screens needed for work.
- Staff can open an order and understand customer, service, pickup/delivery, and status information.
- Staff can update order status.
- Staff can see daily work summary.
- UI feels branded, clean, and mobile-first.

## Technical Direction
- Flutter app
- Clean folder structure under `lib/src`
- Material 3 theme
- Feature-based folders
- Mock data allowed in early M1
- Backend integration deferred until UI and workflow are stable

## Initial Folder Structure
```text
lib/
  main.dart
  src/
    auth/
      login_screen.dart
    dashboard/
      staff_dashboard_screen.dart
    orders/
      order_details_screen.dart
    reports/
      daily_report_screen.dart
    shared/
      app_theme.dart
      widgets/