# ADR 0010: Visitor Counter Semantics — Page Views vs. Unique Visitors

## Status

Accepted

## Context

The platform exposes a live counter in the footer of the web resume, labelled **"Unique Visitors"**. The underlying implementation is a serverless atomic counter: every `DOMContentLoaded` event fires a `POST /count` to API Gateway → Lambda → DynamoDB `ADD 1`. The counter is incremented unconditionally on every page load.

This is a **page view counter**, not a unique visitor counter. The distinction matters:

| Metric          | Definition                                                  | What the current system measures |
| --------------- | ----------------------------------------------------------- | -------------------------------- |
| Page Views      | Every load of the page, regardless of who or how many times | ✅ Yes — every POST increments   |
| Unique Visitors | Distinct individuals, deduplicated across sessions          | ❌ No — no deduplication exists  |

The current label is therefore factually incorrect. A single person refreshing the page 10 times increments the counter by 10. There is no mechanism to recognise a returning visitor or suppress duplicate counts within any time window.

Implementing true unique visitor deduplication requires a client or server-side identity signal that persists across requests. Several approaches exist, each with different accuracy, complexity, and privacy trade-off profiles:

1. **Client-side token (cookie / localStorage UUID)** — generate a UUID on first visit and send it with every API call. Lambda performs a conditional DynamoDB write: increment only if the UUID is unseen. Simple to implement but fragile — cleared by browser data wipes, incognito sessions generate new IDs, and any client-side token can be spoofed or blocked by extensions.

2. **IP-based deduplication** — hash the source IP (available via API Gateway `requestContext.http.sourceIp`) and store it as a seen-set in DynamoDB with a TTL. Reasonable accuracy for individuals on residential connections; degrades for shared NAT (corporate networks, universities) where many people share one IP, or mobile users who cycle IPs frequently.

3. **IP + User-Agent composite hash** — hash `IP + User-Agent` together to improve discrimination between devices behind the same NAT. More granular than IP alone, but still not a true unique person identifier. More resistant to collisions than pure IP.

4. **Probabilistic data structures (HyperLogLog)** — store a HyperLogLog sketch in DynamoDB rather than an exact seen-set. Provides cardinality estimates with ~2% error and O(1) storage regardless of visitor volume. Adds implementation complexity and requires a HLL library in the Lambda runtime.

5. **Third-party analytics (Cloudflare Web Analytics, Plausible, Fathom)** — delegate the problem entirely to a privacy-respecting analytics provider. Zero backend changes required; trade-off is adding an external dependency and third-party script to the frontend, which conflicts with the current zero-external-dependency posture of the build pipeline.

No approach produces a perfectly accurate unique visitor count. All involve trade-offs between accuracy, infrastructure complexity, privacy exposure, and maintenance burden.

## Decision

**Rename the counter label from "Unique Visitors" to "Page Views"** in the web template (`src/templates/resume.html.j2`).

The backend implementation is left unchanged. The counter continues to perform an unconditional `ADD 1` on every page load, which is an accurate description of page views.

Implementation of true unique visitor deduplication is explicitly **deferred**. No approach is selected at this time. The decision will be revisited when there is a concrete reason to distinguish unique visitors from page views (e.g., sharing the site publicly, using the metric to evaluate reach).

## Alternatives Considered

### Implement deduplication now

Rejected for this decision. The counter is a telemetry vanity metric on a portfolio site. The engineering cost of any deduplication approach (conditional DynamoDB writes, TTL management, client token lifecycle) outweighs the value of the metric at the current scale and audience. Premature implementation would also lock in a specific approach before the accuracy / privacy trade-offs are well understood.

### Remove the counter entirely

Rejected. The visitor counter is a deliberate architectural demonstration — it exists to show the full serverless stack (API Gateway → Lambda → DynamoDB) is live and operational, not purely as an analytics tool. Removing it would eliminate a visible proof-point of the platform's compute layer.

### Add a third-party analytics script

Rejected for now. It would introduce an external runtime dependency into a build pipeline specifically designed to produce a self-contained, zero-external-dependency artifact. This trade-off would require its own ADR.

## Consequences

### Positive

- **Label is now accurate.** "Page Views" correctly describes what the counter measures. No misleading claims are made to visitors.
- **Zero backend changes.** The Lambda function, DynamoDB table, and API Gateway remain untouched. No regression risk.
- **Options remain open.** By deferring the deduplication decision, no approach is prematurely locked in. The comparison in the Context section above serves as a starting point for the future ADR when the decision is revisited.

### Negative / Operational Overheads

- **Counter is less impressive as a metric.** Page views inflate faster than unique visitors. The number shown is not a reliable proxy for "how many people have seen this resume."
- **Deduplication work is explicitly deferred, not cancelled.** A future implementation decision will need to revisit the approaches outlined above, select one, and likely introduce new DynamoDB access patterns and Lambda logic. That work should be tracked as a separate backlog item.
