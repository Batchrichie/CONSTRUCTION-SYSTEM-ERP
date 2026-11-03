# Authentication security release gate

## Leaked-password protection

The repository README records that leaked-password protection was disabled in the connected Supabase project at the last security review.

This is a hosted Supabase Auth project setting. It is not enabled by changing a SQL migration or the frontend configuration, so it must be changed in the Supabase Dashboard by a project owner.

1. Open the CONSTRUCTION SYSTEM ERP project in the Supabase Dashboard.
2. Go to **Authentication → Sign In / Providers → Email**.
3. Enable **Prevent use of leaked passwords**.
4. Save the setting.
5. Re-run the Supabase Security Advisor and confirm the leaked-password warning is cleared.

Supabase documents this feature as available on the Pro plan and above. If the toggle is unavailable, confirm the project plan and account permissions before production launch.

**Release gate:** Do not mark authentication hardening complete or launch production until the hosted setting is enabled and the Security Advisor confirms it.
