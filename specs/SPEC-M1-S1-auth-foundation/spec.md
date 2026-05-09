# SPEC-M1-S1: Auth Foundation

## Status
Draft

## Parent
SPEC-000: Amuwak Staff Product Foundation

## Goal
Create the first secure app flow: splash/loading screen, login screen, and routing to the staff dashboard after successful login.

## User Story
As a laundry staff member, I want to log in before accessing work orders so that customer and business information is protected.

## Requirements

### R1: App starts with branded loading/splash
When the app opens, the system shall show an Amuwak-branded loading or splash experience before routing.

### R2: Login screen is the first real screen
When the user is not authenticated, the system shall show the login screen instead of the dashboard.

### R3: Staff can enter login details
The login screen shall provide fields for phone/email and password.

### R4: Login validates empty fields
When the staff member submits empty fields, the system shall show validation messages.

### R5: Successful login routes to dashboard
When login succeeds, the system shall route the user to the staff dashboard.

### R6: Dashboard is protected
When the user is not logged in, the system shall not allow direct dashboard access.

## M1 Assumption
For the first implementation, mock login is allowed.

Example:
- Phone/email: `staff@amuwak.com`
- Password: `password123`

Real backend authentication can come later.

## UI Requirements
- Use Amuwak brown-orange theme.
- Use logo-inspired colors.
- Login screen should feel clean and modern.
- Primary button should use the brand color.
- Inputs should be rounded and easy to use on mobile.

## Acceptance Criteria
- App opens without going directly to dashboard.
- Login screen appears first for unauthenticated users.
- Empty login fields show validation.
- Correct mock credentials route to staff dashboard.
- Incorrect credentials show an error.
- Dashboard is not reachable before login.

## Test Plan
- Test empty login fields.
- Test wrong credentials.
- Test correct credentials.
- Test dashboard route protection.
- Test theme is applied to login screen.

## Definition of Done
This spec is done when a user can open the app, see the login screen, enter valid mock staff credentials, and reach the staff dashboard.