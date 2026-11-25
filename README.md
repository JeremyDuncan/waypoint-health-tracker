# Waypoint Health

A private, self-hosted health journal for your phone. Log your weight, your Zepbound shots and daily notes, then see them together on simple charts.

It runs in a single Docker container on your own server. No cloud services, no tracking and no ads.

## What it does

- **Overview:** your weight over time, with shots and notes marked on the chart.
- **Calendar:** a month view of everything you logged.
- **Injections:** how your weight changed after each shot, broken down by dose and body location.
- **Weekly review:** a day-by-day summary of each week.
- **Goals:** a target weight or a range to maintain, plus BMI if you add your height.
- **Appointment report:** a PDF to bring to your doctor.
- **Import/export:** download all your data, or import it (including Renpho scale exports).
- **Clear history:** permanently delete all your entries from Settings, after typing a confirmation.

## Run it on your computer

You only need Docker.

```sh
./script/dev/run              # start the app at http://localhost:3000
./script/dev/create-account   # create your login (first time only)
```

Code changes show up without a restart. Re-run `./script/dev/run` if you change gems or Docker files.

## Run it on a server

1. Create a settings file, using your own web address:

   ```sh
   bin/init-env health.example.net .env.production
   ```

2. Start the app and create your account:

   ```sh
   ./script/prod/run
   ./script/prod/create-account
   ```

3. Point your HTTPS proxy (nginx, Caddy, etc.) at `http://127.0.0.1:3000`. For Caddy:

   ```caddy
   health.example.net {
       reverse_proxy 127.0.0.1:3000
   }
   ```

4. Open the site in Safari on your iPhone, then tap **Share → Add to Home Screen**.

There is no public sign-up page. Accounts are created only from the command line. After you sign in, set your time zone and units in **Settings**.

**Forgot your password?** Reset it on the server:

```sh
docker compose --env-file .env.production exec app bin/account reset you@example.com
```

## Backups

Back up your data while the app is running:

```sh
name="waypoint-health-$(date +%Y%m%d-%H%M%S).sqlite3"
docker compose --env-file .env.production exec -T app bin/backup "/data/$name"
docker compose --env-file .env.production cp "app:/data/$name" "backups/$name"
```

Keep a copy somewhere other than the server, along with your `.env.production` file. Backups contain every account's data, so store them safely.

To restore a backup into a fresh copy of the app:

```sh
docker compose --env-file .env.production -p waypoint-health-recovery run --rm -T app bin/restore - < backups/your-backup.sqlite3
PORT=3001 docker compose --env-file .env.production -p waypoint-health-recovery up -d --wait
```

## Updating

Take a backup first. Then pull the latest code and run `./script/prod/run`. Database updates are applied automatically.

## Tests

```sh
bin/rails test           # app tests
npm run test:browser     # browser tests (desktop + iPhone)
```

Run the browser tests only against a test account, never your real one, because they create records.

## More details

- [docs/data-format.md](docs/data-format.md): the import and export file formats
- [docs/verification.md](docs/verification.md): how the app was tested
