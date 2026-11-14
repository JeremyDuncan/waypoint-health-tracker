# Waypoint Health

A self-hosted, mobile-first personal health journal. Quick weigh-ins, actual Zepbound injections and day notes share one timeline. Rails 8.1, Hotwire/Stimulus, SQLite in WAL mode, and locally bundled Chart.js 4.5.1. One container, one persistent volume, no cloud runtime, CDN, external fonts, analytics or mail server.

## Renaming an existing installation

The app is now **Waypoint Health** (suggested repository name: `waypoint-health`). Rebuild with your usual `./script/dev/run` or `./script/prod/run`; existing accounts and data stay in place. Keep your environment file and `SECRET_KEY_BASE` unchanged. The Compose projects remain `health-tracker-dev` and `health-tracker`, the production database remains `/data/hearth.sqlite3`, and the session cookie keeps its original internal name. These stable identifiers deliberately preserve existing volumes and sign-ins, even if you rename the checkout directory. Keep using any custom Compose project override you previously configured.

New exports use the `waypoint-health.personal` v1 schema. Existing Hearth JSON exports still import, including duplicate/conflict checks, and saved appearance choices carry forward. All app metadata and icon URLs now use the new branding. iPhone/iPad Home Screen installations retain the name and icon captured when added; the website cannot force an installed shortcut to change. Remove the old shortcut, open the app in Safari, and choose **Share → Add to Home Screen** to install the new branding. This does not remove server data. See [PWA metadata update behavior](https://web.dev/learn/pwa/update#safari_on_ios_ipados_and_android_browsers).

## Local development with Docker

```sh
./script/dev/run
```

Open **http://localhost:3000**. The launcher creates a development `.env` with a generated secret if it is missing, and preserves an existing file. Rails runs in **development** mode with your checkout mounted, so source changes are picked up without rebuilding the image. Re-run the launcher after changing Gemfile/Gemfile.lock or Docker configuration. No host Ruby or Node installation is needed.

Create your development account once:

```sh
./script/dev/create-account
```

The script asks for your email, password and password confirmation. Password input is hidden in an interactive terminal. Then sign in at **http://localhost:3000** using those credentials.

Development uses its own `health-tracker-dev` Compose project and persistent database volume. To view logs or stop it without deleting data:

```sh
docker compose --env-file .env -f compose.dev.yaml -p health-tracker-dev logs -f app
docker compose --env-file .env -f compose.dev.yaml -p health-tracker-dev down
```

The development port is loopback-only. Set `PORT` in `.env` to change it. Both launchers build, start in the background and wait for the database health check; they work from any current directory. Extra arguments are passed to `docker compose up`. `DEV_ENV_FILE`/`PROD_ENV_FILE` and `DEV_COMPOSE_PROJECT`/`PROD_COMPOSE_PROJECT` can select alternate configuration files and isolated projects.

Production uses **`.env.production`**, independently of development's `.env`. Set a different `PORT` in `.env.production` (for example, `3001`) to run both simultaneously and point your HTTPS proxy at that port. The production launcher retains the original `health-tracker` project/volume name, so an existing deployment in this directory keeps its data.

## Production from a clean checkout

Requirements: Docker Engine/Desktop with Compose v2, about 1 GB available memory, and an existing HTTPS reverse proxy. Ruby and Node are **not** required on the host to run the app. The initial image build downloads Ruby dependencies; the running app needs no internet service.

Create your config with your actual HTTPS hostname (the helper uses `openssl`, generates a secret, sets mode 0600, and refuses to overwrite an existing `.env.production`):

```sh
bin/init-env health.example.net .env.production
```

Replace `health.example.net` with your hostname, without scheme or port. Alternatively, copy `.env.example` to `.env.production`, generate a secret with `openssl rand -hex 64`, and set `SECRET_KEY_BASE` and `APP_HOST` yourself. Keep `FORCE_SSL=true`. Keep the secret stable between upgrades. Never commit environment files.

```sh
./script/prod/run
./script/prod/create-account
```

The account script asks for your email, then prompts twice for a 12–72 character password without echoing it or putting it in shell history. Run it after the app has started. Both account scripts work from any current directory and honor the same environment-file and project overrides as their launchers. The email is a login identifier only. There is **no public signup endpoint** and no default account. Create additional private accounts with the same command. Each has separate data.

On first login, open **Settings** and select your IANA time zone and preferred unit. New accounts initially use `America/New_York`; all input dates, chart boundaries and journals use your configured zone, never the server clock zone. Log weight remembers the last entered unit. Original readings retain the entered value and unit.

### Connect your reverse proxy and phone

Compose binds `127.0.0.1:3000` by default. Point your existing HTTPS reverse proxy at `http://127.0.0.1:3000`, preserve the Host header, and overwrite forwarded headers with your proxy's trusted values. For example, inside an existing TLS-enabled nginx `server` block:

```nginx
location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Real-IP $remote_addr;
    client_max_body_size 6m;
}
```

An existing Caddy setup can use:

```caddy
health.example.net {
    reverse_proxy 127.0.0.1:3000
}
```

Use a hostname that resolves to your lab on your phone and a certificate trusted by iOS. If the proxy is another container, attach it to the Compose network and target `app:3000`, or use a reachable host address; loopback inside that proxy container is not this app. Keep the app's HTTP port private. Add your chosen hostname to `APP_HOST`.

Open **`https://health.example.net` in iPhone Safari** or a desktop browser, sign in, and on iPhone tap **Share → Add to Home Screen → Add**. Replace this sample hostname with the one configured above. The manifest and icons support standalone launch. The service worker deliberately caches no health pages or exports.

For a **loopback-only production-mode trial** without a proxy, set `FORCE_SSL=false`, `APP_HOST=localhost,127.0.0.1` and keep `BIND_ADDRESS=127.0.0.1`; then open `http://localhost:3000`. This mode does not support phone home-screen installation or secure cookies. Restore HTTPS settings before using it through your proxy. If a browser has remembered HSTS for a hostname, use the IP or a separate local-trial hostname.

### Account administration and health

Signed-in users can open **Settings → Change password**, enter their current password, and enter and confirm a new 12–72 character password (at most 72 bytes). A successful change revokes all of that account’s sessions, including this browser, and returns to sign-in; use the new password on every device. Invalid input leaves the password and sessions unchanged. This form cannot change your email, preferences, health records, or another account. If you have forgotten your password, use the server-side reset command below; there is no email-reset service.

```sh
docker compose --env-file .env.production exec app bin/account reset you@example.com
docker compose --env-file .env.production exec app bin/verify
docker compose --env-file .env.production ps
docker compose --env-file .env.production logs --tail=50 app
```

Reset revokes all sessions for that account. `bin/verify` checks SQLite integrity and prints counts of accounts, weigh-ins, injections and day notes. `/up` checks both the running app and a real database query; Docker uses it for the container health check. Passwords are bcrypt hashes; sessions use random encrypted, HttpOnly, SameSite=Lax cookies, Secure over HTTPS. CSRF protection is enabled. Ten failed logins per IP in fifteen minutes are allowed; throttles live in SQLite and survive restarts. Successful login clears the current IP's counter. Reverse-proxy IP headers must be trustworthy for this to work correctly.

## Daily use and chart behavior

Use the **appearance icon** (monitor, sun or moon) in the page header to choose **System**, **Light**, or **Dark**. The menu marks the active preference, supports arrow keys and Escape, and stays available on the sign-in page. System follows your device, including automatic changes. The choice is remembered in this browser and applies to forms, tables, injection markers and chart colors. Only the appearance choice is saved in browser storage; health data and drafts are not.

- **Log weight** asks for a number, lb/kg and a local timestamp. Multiple weigh-ins on the same day remain separate. No optional health metrics clutter this form.
- **Log injection** records the actual date/time and dose in mg, optional site/side and notes. The previous injection site is shown. A planned reminder is a separate preference shown on the dashboard, with no push/email delivery; it never creates an injection or chart marker.
- **Journal** has a page for every calendar day, including days with no other measurements. Blank days are available on demand; no empty database rows are generated just by browsing. Save notes and the optional metrics enabled in Settings. Existing metrics remain editable even if later disabled. Deleting a journal clears only its notes/metrics.
- Every saved record is editable and deletable through its day details. Injection and weight form UUIDs prevent double taps and network retries from creating duplicates. Journal dates are unique per user.
- Open **Calendar** in the main navigation for a full-page monthly view of weigh-ins, actual injections and journal notes or metrics. Use the arrows, **This month**, or the month picker to browse. It shows the entire selected month independently of chart filters, groups events in your configured time zone, and opens any day’s journal when selected.
- The chart has one continuous date axis, actual weigh-in points, orange injection date guides and dose labels inside the weight plot, and a journal row. Diamonds mark where an injection time meets the displayed line; they are visual annotations, not weight measurements. Injection events never receive weight values or become weight data points. Nearby markers stack into lanes; zoom expands the timeline horizontally and the chart area scrolls on phones. Reset returns to the selected range.
- Choose 7D, 30D, 90D, 1Y, all time or custom **inclusive local dates**. Weight, injection and note visibility are independent. The accessible table always lists all records in that selected range, retaining entered units. Tapping points/markers opens day details.
- **Change in selected range** compares the first and last actual weigh-ins within the chosen dates, converted to your preferred unit. Both endpoints appear on the card. At least two readings are required; empty ranges and single readings show a clear message instead of a fabricated change. Latest weight and last logged injection remain your latest recorded entries.
- Raw weights keep their actual reading instants. Smooth monotone curves connect consecutive recorded points, including across days without a weigh-in; no measurement or point is invented for an unmeasured day. Smoothing changes the display only and avoids overshooting neighboring readings. Weekly and monthly modes use the arithmetic mean of **all individual weigh-ins** in each local Monday–Sunday week or calendar month within the selected range (not a mean of daily means). The point is placed at the last actual reading in that week or month. Partial periods use selected readings; empty periods have no point, and lines connect the available averages. Medication guides stay visible in all three modes, including days with no weigh-in.
- Around a fall clock change, an ambiguous repeated input time requires its actual UTC offset under **Clock change**. Nonexistent spring-forward times are rejected. Exact original offset and subsecond precision survive an edit when the input minute is unchanged.

If the server becomes unreachable while a logging form is open, its entered values remain in the DOM, saving reports **NOT saved**, and retry is safe. There is no background queue or browser-storage copy. Keep the page open and retry. Reloading, closing Safari or iOS discarding the tab can lose an unsaved draft. A lost response can mean the server saved it; retrying the same form recognizes its stable ID. A server validation error also keeps your typed values.

Health requests/exports use `Cache-Control: no-store, private`, the Turbo page cache is disabled, parameters are filtered, and application logs run at warning level without SQL query logging. Configure your reverse proxy to avoid response caching/body logging for this host. Browser downloads are files you own and must manage separately.

## Injection insights

Open **Injections** in the navigation (`/injections`) for a dedicated dashboard with a body-location diagram, calendar weight history with actual shot markers, optional aligned post-shot comparisons, individual shot changes, and comparisons by location/side and dose. Filter by injection date range, location, side and dose. Tap a chart point or shot bar to open that shot’s details, including its exact baseline/follow-up readings, original units, notes, measurement span and link to the journal. Expandable details for every selected shot and comparison tables remain available alongside the graphs. Light and dark appearances are supported.

Changes use actual measurements: the most recent weigh-in at or before the shot, within the preceding three local days, and the last recorded weigh-in after it, up to the next actual injection or seven local days, whichever comes first. Filters select injections; their follow-up readings can fall outside the selected dates. Hidden injections still end the previous shot’s window. Planned reminders never enter these calculations. No missing measurement or injection-time weight is invented; trajectory points retain their actual reading times relative to the shot.

Ongoing windows show their measured change so far. Location/dose means include only completed windows with paired readings at least 24 hours apart; missing, future-dated, ongoing and shorter spans are labeled and excluded. Comparison tables show sample counts and mean time between readings. The endpoint summary uses the earliest baseline and latest follow-up among selected paired shots, rather than adding overlapping changes. These are descriptive observations with different measurement spans, not evidence that a dose or location caused a change. **How these numbers are calculated** explains the method on the page. Graphs show the latest 12 paired trajectories and 24 shot bars for readability; the history and comparison tables cover all selected injections.

## Weekly review, goals and appointment reports

- **Weekly review** (`/review`) summarizes a local Monday–Sunday week: average weight, difference from the previous week’s average, measurement coverage, actual shots, journal highlights and averages of recorded numeric metrics. Browse earlier weeks or select a date. The current week is labeled as partial and stops at today; its comparison is with the complete previous week. Missing metrics stay missing, and disabled metrics already recorded are still included.
- **Goals** (`/goal`) supports one active target weight or maintenance range, with its own lb/kg unit and local start date. The first actual reading on or after that date is the baseline; readings after now are excluded. Target milestones mark 25%, 50%, 75% and 100% of the distance to your goal and link to the first measured crossing. They remain marked through later regain but recalculate after edits. Progress is bounded to 0–100%; no finish date is predicted. Maintenance counts the last reading on each measured local day, with unmeasured days omitted. Clearing a goal keeps all health records. Goal settings travel in personal JSON exports; milestones are recomputed from those settings and readings.
- Enable **7-day trend** on the overview to add a dashed rolling average alongside raw, weekly or monthly weights. At each actual selected reading, it averages all individual readings in the preceding 168 hours through that instant. The lower boundary is exclusive. It includes earlier context outside the selected dates, so changing the range does not change an overlapping trend value. There are no invented daily points. The trend can remain visible with Weight hidden; actual injection guides and notes remain independent.
- **Appointment report** (`/report`, also linked from Weekly review and Settings) previews up to one year of weights, actual injections, doses/locations and optional journal metrics. Free-text injection and journal notes are excluded by default; side-effect text belongs to the explicitly labeled metrics option. Choose the dates/options and click **Update preview**, then **Download PDF**. The PDF includes exact entered weights/units, timestamps with offsets, a combined weight/injection diagram, and selected notes/metrics. It is generated locally in memory using Prawn and bundled Noto fonts, with no external service or font request. Login details and planned reminders are excluded. Font coverage varies by script; the HTML preview uses your browser’s system fonts. Downloaded reports are sensitive files that you manage separately.

## Chart context and goal details

Overview and Injections have icon-opened **Filters** modals. On Injections, the button and active-filter summary are inside **Weight & injection dates**. Apply saves dates and, for Injections, location, side, dose and grouping to your signed-in account. Each page keeps its own selections across navigation, reloads, fresh sign-ins and devices. Overview also remembers raw/weekly/monthly mode and visibility toggles; Injections remembers calendar/aligned mode. Switching views keeps filters, and changing dates keeps the selected view. Mode/visibility saves show their status; failed saves keep the current view and offer Retry. Cancel discards unapplied filter edits. **Clear / defaults** resets only that page, including its view: Overview defaults to 30 days/every weigh-in/all layers/trend off; Injections defaults to 90 days/all sites, sides and doses/site + side/calendar dates. Preset ranges keep moving with the local date; custom dates remain fixed. Direct date/view query links temporarily override saved settings; Apply or an explicit chart-view change saves that displayed selection.

The injection calendar chart has the same fading weight-area gradient as Overview. The aligned comparison remains unfilled. The injection page has two compact, equal-width summary cards for shot count and recorded change with its percentage and dates. The mean-window/measurement-coverage cards were removed; detailed comparison counts remain in their tables. Overview’s three summaries are also compact, and the accessible history table starts collapsed.

The overview now shows weekday/date ticks on short ranges, daily guides and subtle weekend shading. Shot labels include dose, weekday/date and local time; tooltips add full timestamps and location. Reading tooltips include exact weekday/time and any shot logged that day. Injection diamonds follow the displayed curve without becoming weight measurements. Longer ranges use less frequent labels and include years when needed.

Weekly review shows the full Monday–Sunday axis, even during a partial week. Every point stays at its recorded time and links to that day’s journal. Labeled injection callouts show dose, location/side and weekday/time directly on the chart, stack when close together, and open the day’s details. A day-by-day list includes every original reading/unit and actual injection time, with missing days marked. On narrow screens, the chart scrolls within its card to keep weekday and shot labels legible.

Goals now shows current weight, current BMI when height is set, weight lost/gained and percentage change since the goal baseline, and remaining distance to target (or measured maintenance days). Use the pencil **Edit goal** button to open the modal. Height can be entered in cm or inches and is stored in cm independently of the goal. BMI uses kg divided by height in meters squared, following the [CDC calculation](https://www.cdc.gov/bmi/about/). The modal supports Cancel/Escape, focus return and input-preserving server errors. Clearing a goal retains height and readings. Height is included in personal JSON preferences.

All weight, average, trend and injection-trajectory lines use smooth monotone curves. The weekly and appointment-preview SVGs and appointment PDF use the same kind of curves through actual points. Curves are visual connectors, not estimated measurements or additional data.

The Injections chart defaults to **Calendar dates**, with actual weight on the vertical axis and weekday/date labels on the horizontal axis. Dose/location/date markers open shot details, and weight points open their day’s journal. **Compare after each shot** is optional: it overlays different calendar weeks by aligning every shot’s own date to day 0. Its axis is elapsed days, not weekdays, and the guide explicitly says all shots are aligned there. No medication event becomes a weight point in either view.

Percentage metrics use the same actual reading pairs as their weight-change values:

- Selected-range and within-week loss: `(first − last) ÷ first × 100`.
- Weekly average loss: `(previous week’s mean − current week’s mean) ÷ previous week’s mean × 100`. Each mean uses all individual readings in its local calendar week; current partial-week coverage is labeled. A missing comparison week stays missing.
- Injection-window loss: `(baseline − follow-up) ÷ baseline × 100`. The group mean percentage gives each eligible completed window equal weight; it is not a sum or a weekly rate.

Gains are labeled **gained**, losses **lost**, and actual zero changes **change**. Missing pairs show a dash, not 0%. Percentages appear in range summaries, weekly review, injection bars/details and appointment reports; the Goals summary also retains its percentage since baseline. Overview and weekly curves have a green gradient beneath them in light and dark appearances. The shaded region is decorative and changes no measurements.

## Backup status in Settings

**Settings → Restore the server** shows the last successful online backup, completion time, size, whether its file remains present with the same size, and any latest failed or interrupted attempt. Backups older than seven days are labeled. The existing `bin/backup` command now records this status only after its full SQLite integrity check succeeds, and retains a SHA-256 digest in server metadata. It still refuses to overwrite files. File presence/size checks in Settings are not a new integrity check; off-host copies and scheduling are not monitored. Backup status is server-wide and exposes no account record counts or backup paths. Personal exports exclude this operational metadata.

Backups made before this feature cannot be recognized retrospectively. Run a new backup using the commands below. After a fresh-volume restore, restored backup-status history is cleared so the new deployment does not claim to have created a backup; take a new one after verification.

## Move my data

In **Settings → 01 · Move my data**, download the full versioned JSON export or separate UTF-8 CSVs for weights, injections and journals. The JSON includes all entries, notes, fixed metric definitions and preferences; exports exclude login identifiers, passwords/hashes, sessions and secrets.

Upload JSON v1 for full personal-data transfer, choose **Renpho Health CSV** for Renpho exports, or use the weight CSV column-mapping preview for a scale/spreadsheet. Renpho CSVs are also auto-detected when using the generic CSV option. The preview combines Date and Time, reads lb/kg from the Weight column header, and lets you confirm the readings’ time zone. It applies the correct daylight-saving offset to each timestamp. Only weigh-ins are imported; Renpho body composition columns, BMI and Remarks are ignored, as shown in the preview. Preview lists source values, creates, duplicates, conflicts and row validation errors. Any error/conflict blocks the entire commit. Repeated files do not duplicate entries; changed stable IDs are conflicts and never overwrite edits. Preferences are shown and explicitly confirmed separately. Previews expire after one hour and are purged on your next upload.

See **[docs/data-format.md](docs/data-format.md)** for the exact schema, timestamp/offset rules, missing units, date-only noon convention, CSV ID limitations and examples. `docs/examples/` includes all record types and a scale CSV. Injection/journal CSVs are for interoperability; full restoration of these types uses JSON. Fixed metric definitions are versioned; custom metric definitions are not implemented.

## Back up the running server

This is separate from personal export. The **SQLite online backup API** takes a consistent snapshot including committed WAL data while the app is running, then performs an integrity check. Do not copy only the live `.sqlite3` file while writes are occurring.

```sh
mkdir -p backups
backup_name="waypoint-health-$(date +%Y%m%d-%H%M%S).sqlite3"
docker compose --env-file .env.production exec -T app bin/backup "/data/$backup_name"
docker compose --env-file .env.production cp "app:/data/$backup_name" "backups/$backup_name"
docker compose --env-file .env.production exec -T app bin/verify
```

Store the copied file off the Docker host as well. Each backup uses a new filename; existing destinations are never overwritten. The copy inside `/data` consumes volume space; remove old backup copies according to your retention policy after verifying your off-host copy. Backups contain **all accounts, password hashes, sessions and health records**; protect them as sensitive files. Backup files are created with mode 0600.

Back up **separately**: `.env.production` (especially `SECRET_KEY_BASE`, host and HTTPS settings), `compose.yaml` overrides, your reverse proxy config/certificate material, and the repository/image version used for the backup. There is no required Rails master key or mail configuration. Back up local proxy/VPN/DNS configuration if needed to reach the app. Restoring with a new secret works but invalidates cookies; the restore command also revokes restored sessions deliberately.

## Restore into a fresh volume

Keep the original deployment and volume intact. Choose a new, unused Compose project name so the destination is fresh. Place your backup in `backups/waypoint-health.sqlite3` (copy or rename your chosen snapshot). Load the saved `.env.production` first. The one-off restore command does **not** boot the web server or auto-create the destination database:

```sh
# Only needed on a fresh host/checkout:
docker compose --env-file .env.production build

# Stream the host backup to the fresh volume; restore refuses an existing DB.
docker compose --env-file .env.production -p waypoint-health-recovery run --rm -T app bin/restore - < backups/waypoint-health.sqlite3

# Use an unused port so the old deployment can remain available.
PORT=3001 docker compose --env-file .env.production -p waypoint-health-recovery up -d --wait
PORT=3001 docker compose --env-file .env.production -p waypoint-health-recovery exec -T app bin/verify
```

Compare counts with the backup output/previous `bin/verify`, then point your HTTPS proxy at port 3001 and **sign in with your existing account and password**. Check day details and exports. Accounts/hashes and records survive; old sessions are revoked. The app applies pending migrations on startup. Update proxy routing only after verification. To cut over to port 3000, stop the old app, set the new project's port to 3000, and recreate its container, keeping `-p waypoint-health-recovery` on every command. A project name selects its volume; do not accidentally start another empty deployment.

For an already configured fresh host with no old deployment, restoring without `-p waypoint-health-recovery` uses the default project's fresh `data` volume and the normal startup command. Restore refuses any existing database/WAL/SHM file. Do not use `down -v` as a recovery step: it deletes a volume. If integrity fails, keep the affected volume and restore an earlier verified backup into another fresh volume.

## Upgrade

1. Take an online backup and save the old `.env.production`, counts and source/image version.
2. Update the repository, then run `./script/prod/run`. Migrations run on startup; the named data volume survives container recreation.
3. Run `docker compose --env-file .env.production exec -T app bin/verify`, sign in and check recent records.

If a migration/upgrade fails, stop the app, retain its volume and logs, and restore the pre-upgrade backup with the matching older source/image into a fresh project/volume as above. Merely running older code against a newly migrated database is not a safe rollback. Never regenerate the secret during routine upgrades.

## Development and verification

For local development with Ruby 3.4+:

```sh
bundle install
bin/rails db:prepare
bin/account create you@example.com
bin/rails server
bin/rails test
bundle exec brakeman --no-pager
bundle exec bundler-audit check --update
```

The test suite exercises multiple weights, a local midnight and DST transitions, injection-only/note-only days, each range, authentication/CSRF/throttling, scoping of reads/edits/deletes/imports/exports, exact JSON round trips, stable-ID CSV reimports, conflict protection and preference validation. No production seed runs automatically.

Optional browser tests need Node 20+ and exercise a **synthetic account** in an isolated deployment. They create records, so do not target your personal account:

```sh
npm ci
npx playwright install chromium webkit
# Start a local dev server and create a synthetic account first, or use Docker smoke below.
TEST_EMAIL=demo@example.test TEST_PASSWORD=synthetic-pass-123 \
  BASE_URL=http://localhost:3000 npm run test:browser
```

Ten browser flows use Chromium at 1440px and WebKit with iPhone 13 settings at 390px. They log multiple readings, an injection on another day and a third day's note; check weekly/monthly views, the rolling trend, toggles/zoom/details, weekly review, target and maintenance goals, appointment PDF download, backup-status display and CSV mapping; and simulate a lost connection followed by retry. They also check weekday axes, shot callouts, curve-aligned injection markers, labeled shot bars, BMI/height conversion and the goal modal. Screenshots, synthetic PDFs and traces are local ignored artifacts in `test/artifacts/`.

The reproducible Docker smoke test makes a clean temporary source copy and isolated fresh projects, starts the image, creates synthetic accounts, tests online backup, recreates the container, restores to another fresh volume, compares counts, verifies password authentication and account scoping, and removes its own containers/volumes on success:

```sh
python3 script/docker_smoke.py
# Also run desktop + iPhone WebKit tests against its container:
python3 script/docker_smoke.py --browser
```

See [docs/verification.md](docs/verification.md) for the results and environment limits from this implementation.
