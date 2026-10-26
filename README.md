# ReUseNSUT - Verified Campus Sharing Marketplace

DBMS project backend: MySQL schema, views, triggers, stored procedures, sample data, and a Python program that prints the output tables.

## Run it in VS Code on Windows

Requirements: MySQL Server 8.0.16+ and Python 3.8+. The project uses its own MySQL data folder under `%LOCALAPPDATA%\ReUseNSUT` and port `3307`; it does not require the Windows MySQL service or administrator access. Keeping the database outside OneDrive avoids file-lock issues during setup.

1. Open this project folder in VS Code.
2. Open the integrated terminal with **Terminal > New Terminal** (or press **Ctrl+`**).
3. Run:

   ```powershell
   .\run-project.ps1 -Action web
   ```

The script starts the local MySQL server, backs up a stale orphaned `reusensut` folder if it finds one, installs the Python dependencies into the currently selected Python environment if missing, recreates the database, and launches the browser UI at `http://127.0.0.1:5000`. If the old project MySQL server is still using the former OneDrive data folder, the script verifies and stops that project-owned server before starting the new local-app-data instance. Keep the VS Code terminal running while using the UI. The database server keeps running in the background.

If PowerShell blocks the script, run it with a temporary execution-policy bypass:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-project.ps1 -Action web
```

## Host the UI on Render

`render.yaml` defines the Flask web service. The app still requires a reachable **MySQL** database: Render's managed relational database is PostgreSQL, which this MySQL project cannot use directly. Create a MySQL database with a provider that allows connections from Render, and keep the database and web service in nearby regions when possible. The local `mysql_data` folder on your PC is not remotely accessible to Render.

1. Create a public GitHub repository and push the project files. Do **not** upload `venv/`, `mysql_data/`, `.env` files, or database backups; `.gitignore` excludes these local files.
2. Create a dedicated, empty MySQL database named `reusensut` and a database user with access only to that database. Use the provider's TLS settings.
3. Initialize that fresh database from a trusted MySQL client: create/select the `reusensut` database, then run `01_schema.sql` followed by `02_logic.sql`. Optionally run `03_seed.sql` only with data you are permitted to publish. `01_schema.sql` now only creates tables; do not run `python main.py setup` against a hosted database, because that local reset command drops and recreates the database.
4. In Render, choose **New > Blueprint**, connect the repository, and deploy `render.yaml`. Enter the MySQL host, port, username, and password when prompted for the `DB_*` environment variables.
5. If your MySQL provider supplies a CA certificate, add it in Render as a **Secret File** and set `DB_SSL_CA` to the mounted file path. The app verifies the certificate when this variable is configured. Leave it unset only if your provider does not require a CA certificate.
6. Wait for the `/healthz` check and deploy to pass, then open the `onrender.com` URL shown for your service.

The current UI is a **public, read-only demo**: it has no login or write actions. Do not load real student, contact, or loan data into a public deployment unless you have authorization and have added appropriate access controls. `03_seed.sql` uses synthetic student names, placeholder emails, and zero-prefixed phone values. The MySQL provider may charge separately, and Render's free web service can sleep when idle.

After the first run, use the same terminal for:

```powershell
.\run-project.ps1 -Action demo
.\run-project.ps1 -Action menu
.\run-project.ps1 -Action workflow
```

To rebuild only the sample database, run `python main.py setup`. **Setup drops and recreates `reusensut`, resetting its data.** To stop the project's local MySQL server when finished:

```powershell
.\stop-project-db.ps1
```

The scripts use the MySQL installation path `C:\Program Files\MySQL\MySQL Server 8.0`. If yours is installed elsewhere, update `$mysqlBase` in `run-project.ps1` and `$mysqladmin` in `stop-project-db.ps1`.

## Files

| File | What it has |
|---|---|
| `01_schema.sql` | 17 tables with PK/FK/UNIQUE/CHECK rules (the 15 from your ER diagram + `notifications` and `sustainability_points`) |
| `02_logic.sql` | 10 views, 14 triggers, 8 stored procedures |
| `03_seed.sql` | 12 users, 16 items, 15 listings, orders, loans, reviews, disputes |
| `04_queries.sql` | the demo queries as plain SQL |
| `main.py` | connects to MySQL, runs setup, prints tables |
| `web_app.py` | local Flask marketplace UI |
| `templates/` and `static/` | HTML templates and responsive UI styles |
| `run-project.ps1` | starts local MySQL, sets up the database, and launches the selected app mode |
| `stop-project-db.ps1` | stops the local MySQL server |
| `render.yaml` | Render web-service deployment settings |

## How your 11 modules map to the code

| Module | Tables | Logic |
|---|---|---|
| 1 User and Verification | `users` | email must end in `@nsut.ac.in`, roll number format check, `verify_user()` (admin only), only verified users can post/request (triggers) |
| 2 Item and Category | `items`, `categories`, `item_images` | |
| 3 Listing | `listings` | sell/lend/exchange/donate; deposit only for lend; donate must be free; one live listing per item |
| 4 Request and Order | `listing_requests`, `transactions` | no self-request; exchange needs your own offered item; `accept_request()` creates the order with handover place/time and auto-rejects other pending requests |
| 5 Loan and Return | `loans` | `return_item()`; late = returned after due date |
| 6 Payment and Deposit | `payments` | deposit `held` -> `refunded` if on time and good condition, else stays `held`; admin can mark `deducted` in `resolve_dispute()`; a sale cannot complete before payment is `paid` |
| 7 Review and Trust | `reviews` + `v_trust_scores` | only the two students of a completed order can review |
| 8 Dispute | `disputes`, `reports`, `report_actions` | admins are notified; `resolve_dispute()` |
| 9 Notification | `notifications` | filled automatically by triggers; `refresh_overdue()` adds due-tomorrow and overdue messages |
| 10 Sustainability | `sustainability_points` + `v_leaderboard` | on completion: giver gets 20 (donate), 15 (lend/exchange), 10 (sell); receiver gets 5 |
| 11 Admin | `users.account_role`, procedures | |

**Trust score (0-100)** = 14 x average rating + 3 x on-time returns (max 10 counted) - 5 x late returns. Students with no reviews start at a neutral rating of 3.

**Money saved** = original price - amount paid, for completed sell/donate/exchange orders (loans are not counted).

## Changes I made to your design (and why)

Your ER diagram did not have a few things the document text needs, so I added them:
- `users`: `branch`, `study_year`, `residence` (Module 1 says to store these)
- `items`: `semester` (for "3rd semester textbooks under a price") and `original_price` (for "money saved")
- `listings`: `max_loan_days` (to compute the due date)
- `transactions`: `handover_location`, `handover_time` (Module 4)
- `loans`: `borrowed_at`, `returned_good_condition`, `reminder_sent`
- new tables `notifications` and `sustainability_points` (Modules 9 and 10 had no table in the ER diagram)
- `transactions.status` has no `disputed` value; disputes are tracked in `disputes`

Update your ER and schema diagrams to match before submitting.

## Synthetic demo data

Seed users use generic names (`Student 02`, etc.), placeholder `demo.*@nsut.ac.in` emails, and zero-prefixed phone values. These are synthetic examples, not real account credentials. The seed password hash is only for database procedure demonstrations; the browser UI has no login.
