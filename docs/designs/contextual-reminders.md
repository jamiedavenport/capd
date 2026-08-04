# Contextual reminders

Capd observes the page in the frontmost supported browser and, after a short dwell,
looks up its canonical URL in the capture store. A saved page produces a passive HUD
with its original capture date, note, and revisit history. Observation is opt-in and
stops as soon as the setting is disabled.

## Context pipeline

`AmbientContextMonitor` owns observation and delegates every decision after identity
resolution. `ContextReminderPolicy` applies dwell time, once-per-session handling, and
suppression. `ContextInsightEngine` asks ordered `ContextInsightProvider` implementations
for an insight; the initial provider performs an exact capture lookup.

Providers return a common `ContextInsight` rather than HUD content. Related captures,
source changes, conflicts, projects, and other insights can therefore reuse observation,
privacy, suppression, and presentation without adding browser-specific monitors.

## Privacy

The monitor reads the visible browser URL through Accessibility and does not copy page
contents, fetch unseen pages, or persist browsing history. Secure input suspends
observation. Unsupported applications and non-web URLs produce no context.

The setting defaults off. New users can opt in during onboarding, and any user can turn
it off in Settings. A disabled monitor retains no pending observation.

## Capd-originated links

Links opened from Capd register a short-lived local suppression and, while contextual
reminders are enabled, add `utm_source=capd.jxd.dev&utm_medium=app`. Existing campaign
attribution is never replaced. Local, signed, authentication, checkout, and payment URLs
are not modified.

The raw URL is inspected for Capd attribution before canonicalization. URL normalization
then removes the campaign parameters, so the attributed page retains the same capture
identity. Local suppression remains the reliable fallback when a destination removes its
campaign parameters before the monitor observes the page.
