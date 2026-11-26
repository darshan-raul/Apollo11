# Apollo11 documentation improvement report

Prepared 2026-10-05 against Apollo11 base `143cac8` and apollo11-docs `d041b64`.
The implementation changes are uncommitted. No Git commit, push, cloud action,
or cluster mutation was performed. The adjoining docs repository is read-only
in this session, so its edited pages are delivered as a companion patch.

## What changed and what the evidence establishes

The largest documentation problem was a mismatch between the words, the pinned
revision, and the behavior a learner could observe. Several pages compiled
successfully while describing commands that could not work at their pinned
revision. The fix therefore needs both code and teaching changes.

The code changes implement context isolation for installation, verification,
teardown, and Argo scripts; explicit context propagation for certificate
creation; strict cluster-and-namespace ownership for EBS cleanup; runtime-owned
certificates; optional HTTPS listeners without dangling references; HTTPS
frontend API URLs; restored login verification; token-automount protection;
explicit cache bypass; and booking-creation SLO recordings. New guides describe
an ordered signal path and a controlled cache comparison.

This is implementation evidence, not a replacement for live lifecycle proof.
The sandbox denies Docker access and network connections to the kind API.
Promtool and k6 are not installed. Browser acceptance, the outage drills,
Prometheus rule evaluation, measured cache improvement, Argo convergence, and
AWS teardown behavior must remain pending until independently demonstrated.
The candidate must not be labeled a newly verified release.

## Changes prepared in the adjoining docs

| Page | Problem addressed | Teaching improvement |
|---|---|---|
| `docs/launchpad.md`, `docs/ignition.md` | Old revision contradicted the updated setup | Aligns both entry points with the candidate base plus companion patch |
| `docs/learn/observability/signals-and-metrics.md` | Invented booking metrics and seconds buckets | Uses the real service selector, millisecond buckets, and PromQL fences |
| `docs/learn/observability/discovery-and-collection.md` | Incorrect release-label requirement and unavailable curl in the Booking image | Shows the actual Prometheus selector and a host port-forward, separating exposure from collection |
| `docs/start/prerequisites.md` | Pinned revision predates the fix and lacks the benchmark | Identifies base commit plus companion patch; requires image rebuild and revision evidence |
| `docs/labs/setup.md` | A tested-version heading was stronger than current evidence | Explains the patch boundary and distinguishes historical proof from current candidate |
| `docs/status.md` | “Supported local path” could be read as proof of the current working tree | Separates historical lifecycle evidence, implemented candidates, and planned missions |
| `docs/stage-2.md` | Incorrect ReferenceGrant explanation in the diagram/troubleshooting; incomplete Envoy TLS account | Distinguishes Route attachment permission from backend reference permission; explains HTTPS API and certificate trust checks |
| `docs/stage-4.md` | Requests described as a physical reservation guarantee | Explains scheduler capacity accounting without promising physical memory or application performance |
| `docs/start/terminal-git-and-yaml.md` | Setup link pointed to the old tested-revision heading | Links to the explicit candidate preparation boundary |
| `docs/stage-5.md` | Old pass totals looked like current acceptance criteria | Labels them historical and requires behavioral checks for the actual revision |
| `docs/stage-6.md` | Ordered signals were not connected to runnable resources | Points to the metrics → dashboards → alerts/SLO → logs → traces → correlation guide |
| `docs/stage-7.md` | Scaling discussion lacked a reproducible cache comparison | Connects the stage to the controlled benchmark before the HPA experiment |
| `docs/stage-8.md` | Directory absence was treated as implementation status | Reads the placeholder README and asks for lifecycle evidence instead of inferring implementation from directory existence |
| `docs/learn/observability/queries-alerts-and-objectives.md` | Nonexistent metrics, incorrect units and error-budget arithmetic, no concrete SLO experiment | Uses real series names and milliseconds; defines eligible booking requests; adds an observable failure/recovery lab |
| `docs/learn/scaling/measurement-baseline.md` | Two benchmark runs with an unspecified optimization between them | Specifies cache states, fixed rate, populated responses, warmup, replica/HPA controls, summaries, and recovery |

The patch now covers 16 pages. It builds successfully with Docusaurus's broken-link/image checks enabled
and passes the project's TypeScript check. These checks establish rendering and
type correctness, not execution of the commands in the pages.

## Highest-value improvements to make next

### 1. Publish a verified revision contract

A hands-on page should identify exactly which source revision supports its
commands. The current candidate is a base commit plus a patch because the user
has not requested a commit or publication. That is reviewable and reproducible
locally, but it should not become the permanent public setup flow.

After an explicitly authorized commit and a clean lifecycle, replace the patch
step with one immutable commit or release tag in prerequisites, setup, and
status. Keep one authoritative revision declaration and generate repeated
references from it. Validate that every cited lab path exists at that revision,
not merely on the author's current checkout. The former missing k6 path is the
concrete regression this gate should prevent.

Acceptance: a fresh clone at the documented revision can follow every required
local stage without consulting an unpublished working tree; the report records
its manual failure/recovery behavior and teardown residue.

### 2. Make each lab executable as written

A learner should know the working directory, starting resources, required tools,
expected response body, recovery command, and cleanup boundary before starting.
Commands such as “introduce optimization” are explanatory placeholders, not lab
steps. Port-forward terminals should be named and kept separate from commands
that restart their target Pods. Fixed dates should be replaced with an explicit
seeded-date selection or UTC date calculation plus a persistence caveat.

Use the five-part contract consistently: Build, Inspect, Break, Recover,
Explain. Recovery must end with a booking, populated search, advancing metric,
new log record, or linked trace. An object becoming Ready can support that
proof but cannot replace it. Explain precisely what the evidence establishes
and what remains outside the experiment's scope.

Acceptance: another person can run the page from a clean baseline, induce the
specified failure, recover without inventing commands, and answer the closing
questions using observations from the lab.

### 3. Use the application's actual vocabulary

The booking service exports `http_requests_total` and
`http_request_duration_ms`, not booking-prefixed metrics or a seconds histogram.
Queries should include the intended service, method, and path labels. Screenshots
and expected output should use those same names and units.

ReferenceGrant authorizes selected cross-namespace backend references. Route
attachment across namespaces is governed by the Gateway's allowedRoutes and
parentRef. A diagram must not suggest that the frontend's attachment is made
possible by a grant it does not use. The existing grant is a reference example
unless the learner moves a Route and demonstrates a cross-namespace backend.
Label that boundary rather than advertising an inert manifest as enforcement.

Acceptance: each example query returns the intended series under lab traffic;
each claimed routing permission is exercised by a matching failure experiment.
The [Kubernetes Gateway API reference](https://kubernetes.io/docs/concepts/services-networking/gateway/)
is the primary source for the resource model.

### 4. Teach TLS as a complete client-to-application path

Separate three questions: does the listener accept TLS, is the certificate
trusted for the requested hostname, and do browser API workflows succeed?
`curl -k` answers only part of the first question. A frontend can return HTML
over HTTPS while its HTTP API calls fail as mixed content.

The revised source uses HTTPS API URLs from the canonical Envoy stage onward.
Document name resolution for all API hostnames, public certificate extraction,
local browser/OS trust, explicit renewal, and trust updates after replacement.
Use `curl --cacert` with the DNS hostname and SNI, a negative hostname check,
and a browser login/search/booking exercise. Keep private keys outside rendered
manifests and repository artifacts.

Acceptance: all browser API requests use HTTPS, trust checks succeed for intended
hosts and fail for an unrelated hostname, and deletion/recovery of the Secret
has the predicted effect on HTTPS while the separate HTTP baseline is explained.

### 5. Keep SLO mathematics tied to the measurement

A request-based 99.5% availability objective permits failure of 0.5% of eligible
requests. It cannot automatically be translated into a time allowance. A
separate time-based objective permits 3.6 hours in a 30-day month, or 3.36 hours
in 28 days. The previous 216-hour statement was mathematically wrong.

Define the denominator: the implemented booking objective counts POST
`/api/bookings` responses that are 2xx or 5xx and excludes authentication and
validation failures. Define zero-traffic behavior explicitly. Show why budget
spending can remain after service recovery and why a short local history cannot
prove a 28-day objective. Availability and latency remain separate measurements;
the current latency histogram lacks response-status labels for a combined SLI.

Acceptance: successful requests, server errors, no traffic, and client errors
produce the documented recording results. The provided fixture still needs
execution with [Prometheus rule testing](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/).

### 6. Make performance comparisons falsifiable

The updated benchmark uses six seeded routes, nonempty result checks, a fixed
arrival rate, a two-minute measured window, an explicit warmup, and assertions
that fail the process when the intended workload or cache state is not achieved.
The guide saves and restores the HPA, replica count, and cache setting. It uses
the same direct-Service route in both runs and records that choice.

Record the image, revision/patch, UTC seed date, node capacity, Pod CPU, achieved
throughput, errors, dropped iterations, cache hit ratio, and latency distribution.
Do not claim improvement merely because a hit ratio rose. A small dataset may
show negligible benefit, and that is a valid result. Keep load thresholds and
production objectives conceptually separate. The [k6 threshold reference](https://grafana.com/docs/k6/latest/using-k6/thresholds/)
explains how failure criteria affect process exit status.

Acceptance: both summaries correspond to the same workload and environment,
cache-off responses are MISS, cache-on responses predominantly HIT, and state
returns to its starting configuration after the experiment.

### 7. Consolidate narrative and reference pages

The docs contain mission narratives, stage guides, conceptual chapters, and
command references. These can coexist, but each should have a clear job:
mission pages motivate the problem; concept pages explain the model; stage pages
own the exact lab; reference pages index commands and failure symptoms.

Avoid maintaining two subtly different command sequences for the same lab.
Link to one authoritative procedure and repeat only the explanation needed by
the current page. Keep diagrams close to the corresponding commands and status
conditions. Add expected outputs from an actual run, clearly marking variable
values such as Pod names, IPs, timestamps, and IDs.

Acceptance: a learner can tell which page to read, which page to execute, and
which page to use when a command fails; the same experiment has one maintained
command sequence.

### 8. Replace broad completion language with scoped evidence

Words such as “production-ready,” “complete,” and “supported” need a concrete
scope. Local kind validation does not establish cloud readiness, hosted CI/GHCR
publication, public certificate trust, or a successful Argo reconciliation.
Large check counts are historical observations tied to a revision, environment,
and verifier; adding checks changes the total without proving more behavior.

Use a small evidence block: source revision, environment, automated result,
manual outcome, residue audit, date, and known limitation. Keep historical audit
notes explicitly historical. Stage 8's placeholder and Stage 9–11's planned
status are curriculum boundaries, not evidence of implemented labs.

Acceptance: every completion claim is traceable to the lifecycle it describes;
no page claims an unsupported runtime effect or promotes a candidate based only
on static renders.

## Suggested quality gates

1. On every docs change: Docusaurus build, TypeScript check, broken-link/image
   checks, and a source-path audit against the documented revision.
2. On any changed command or metric example: execute it against the matching lab
   and save concise expected output. Test units and selectors, not just syntax.
3. On any changed installation or runtime behavior: clean apply, inspect, exact
   break, behavioral recovery, teardown, and an ownership/residue audit.
4. On any revision promotion: rebuild all application images, rerun affected
   downstream stages, and update the evidence block and docs pin together.
5. On any new concept: require an active mechanism, a safe failure experiment,
   and observable recovery before listing the concept as taught.

These gates should prevent drift without making the maintainer verifier the
learner's only interaction with Kubernetes. The learner should still predict,
observe, and explain what happened.

## Deliverables and outstanding boundaries

The edited docs are in `/tmp/apollo11-docs-fixes`; the durable patch is
`verification-runs/apollo11-docs-gap-fixes.patch`. The source patch is
`verification-runs/apollo11-gap-fixes.patch`. Apply the docs patch from the
adjoining repository with `git apply`; no commit is required. This session
cannot apply it there because that repository is outside the writable roots.

`verification-runs/GAP_CLOSURE.md` records implementation disposition, completed
checks, and pending runtime proof. Planned Stage 8–11 implementation is a
separate scope decision; absent further steering, their planned status is retained. This
report does not silently redefine those missions as completed.
