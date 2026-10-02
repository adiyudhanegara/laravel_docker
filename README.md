# Laravel Docker Setup

A generated Docker Compose development environment for new and existing Laravel applications. It uses PHP-FPM behind Nginx and supports MariaDB, MySQL, PostgreSQL, Redis, Vite, Mailpit, phpMyAdmin, queue workers, and Laravel's scheduler.

The template is intended for local development. It is not a production deployment image.

## Prerequisites

- Docker with the `docker compose` command
- Ruby, used only to run the setup generator
- Git, when cloning this template or an application repository
- On Linux, membership in the `docker` group

## Start a project

Clone the template into a project-specific directory:

```sh
git clone git@github.com:adiyudhanegara/laravel_docker.git my_project
cd my_project
```

The clone keeps your edited `setup.rb` as a local change, so later template updates can be pulled into the same directory.

Edit the settings block at the top of `setup.rb`. At minimum, give the project a unique name and Docker subnet:

```ruby
$project_name = "my_project"
$host_name = "my_project.test"
$network = "172.22.10.0/24"
```

Check the subnets already used by Docker before choosing one:

```sh
docker network ls -q | xargs -r docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{println}}{{end}}'
```

The setup script also checks for overlapping Docker networks and stops before generating files when it finds one.

### New Laravel application

Leave `webroot/` absent or empty. By default, setup creates the latest Laravel application. To request a specific Laravel line, set for example:

```ruby
$laravel_version = "13.*"
$php_version = "8.3"
```

### Existing Laravel application

Clone it into `webroot` before running setup:

```sh
git clone git@github.com:organization/application.git webroot
```

Alternatively, configure the repository in `setup.rb`:

```ruby
$project_repo = "git@github.com:organization/application.git"
$project_branch = "main"
```

For an existing application, setup reports the locked Laravel version, the PHP constraint, and the detected npm, Yarn, or pnpm lockfile. An exact PHP version in `.php-version` or `composer.json`'s `config.platform.php` is reused when `$php_version` is `nil`.

PHP and Laravel constraints vary between releases. If an existing project only records a range such as `^8.2`, select an explicit compatible `$php_version` when reproducibility matters.

## Configuration

### Runtime and database

| Setting | Purpose |
| --- | --- |
| `$db_engine` | `mariadb`, `mysql`, or `postgres` |
| `$db_engine_version` | Database image version; `nil` uses its current official image |
| `$php_version` | PHP image version; `nil` uses the current PHP FPM image |
| `$php_image` | Optional full image override for a legacy PHP/Debian combination |
| `$composer_version` | Composer image tag, default `2` |
| `$node_version` | Node image version, default `lts` |
| `$laravel_version` | Composer constraint used only when creating a new application |
| `$forwarded_port` | Host HTTP port; HTTPS uses the next port |
| `$forwarded_db_port` | Optional host database port |
| `$forwarded_vite_port` | Host port for the Vite development server |

On Linux, the normal workflow uses the web container's static IP and a `.test` hosts entry. On macOS and other non-Linux hosts, setup defaults to forwarded web and database ports when these settings are left `nil`.

### Optional services

| Setting | Default | Result |
| --- | ---: | --- |
| `$with_redis` | `true` | Redis service and PHP Redis extension |
| `$with_mailpit` | `true` | SMTP capture and `/mailpit` web interface |
| `$with_phpmyadmin` | `true` | `/phpmyadmin/` for MariaDB or MySQL |
| `$with_assets` | auto | Installs Node/npm in the app image and runs Vite in the app container when frontend assets exist |
| `$with_queue` | `false` | `php artisan queue:work` service |
| `$with_scheduler` | `false` | `php artisan schedule:work` service |
| `$with_imagick` | `true` | ImageMagick and the PHP Imagick extension |

`$imagick_extension_version` and `$redis_extension_version` may pin PECL releases for a PHP version that cannot use the latest extension release.

### Safety controls

| Setting | Default | Behavior |
| --- | ---: | --- |
| `$update_app_env` | `true` | Updates infrastructure values in `.env`, preserving a timestamped backup, and creates `.env.testing` |
| `$use_redis_drivers` | `true` | Also points cache, session, and queue at Redis when `$with_redis` is enabled |
| `$run_migrations` | `false` | Runs normal Laravel migrations after installation |
| `$db_reset` | `false` | **Destructive:** runs `migrate:fresh` only when explicitly enabled |
| `$reset_config` | `false` | Stops the old Compose project and regenerates Docker files; application and database data are retained |
| `$no_cache` | `false` | Builds the application image without Docker's build cache |

`$run_migrations` and `$db_reset` cannot both be enabled. Database resets and migrations are never silently performed.

### Managed `.env` values

With `$update_app_env` enabled, setup points the application at the services it generated. A missing `.env` is first copied from `.env.example`. Only the keys below are written; every other line, including comments, is left as it is.

| Area | Keys | Value |
| --- | --- | --- |
| Application | `APP_ENV`, `APP_URL` | `local` and the project URL |
| Application | `APP_NAME` | The project name, only when setup creates the application |
| Database | `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | The `db` service, the `PROJECT_development` database, and its user |
| Redis | `REDIS_CLIENT`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` | The `redis` service through phpredis |
| Redis drivers | `CACHE_STORE`, `SESSION_DRIVER`, `QUEUE_CONNECTION` | `redis`, when `$use_redis_drivers` is enabled |
| Mail | `MAIL_MAILER`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_SCHEME`, `MAIL_USERNAME`, `MAIL_PASSWORD` | SMTP delivery to the `mailpit` service |

`DB_CONNECTION` is `mariadb` when the application defines that connection and `mysql` otherwise. Applications older than Laravel 11 keep their `CACHE_DRIVER` and `MAIL_ENCRYPTION` keys.

Hosts are Compose service names, which resolve only inside the containers. Setup prints the keys it changed and saves the previous file as `.env.backup-TIMESTAMP`. Running setup again without changes leaves `.env` untouched.

With the queue on Redis, queued jobs wait until a worker runs; enable `$with_queue` or run `docker compose exec app php artisan queue:work`.

Setup also creates `.env.testing` when it does not exist. It is a copy of `.env` that uses the `PROJECT_test` database and in-memory cache, session, queue, and mail drivers. Laravel reads it instead of `.env` while testing, so copy new keys into it when `.env` gains them. Values set in `phpunit.xml` still take precedence.

When `webroot` is a Git repository, `.env.testing` and the backups are added to its local `.git/info/exclude`; the application's own `.gitignore` is not modified.

## Run setup

```sh
./setup.rb
```

The script performs these steps:

1. Validates settings, Docker access, and subnet availability.
2. Inspects an existing Laravel application when present.
3. Generates the Compose file, PHP image, Nginx image, and idempotent database initialization SQL.
4. Builds the images and waits for database health.
5. Creates a new Laravel application or installs the existing Composer dependencies.
6. Updates `.env`, installs frontend dependencies, creates `APP_KEY` only when missing, and links `public/storage`.
7. Runs database commands only when explicitly enabled.
8. Stops the temporary setup services and prints the project URL.

Any failed command stops setup immediately.

## Daily development

Start all configured services:

```sh
docker compose up
```

Run in the background:

```sh
docker compose up -d
```

Stop the project:

```sh
docker compose down
```

Open a shell:

```sh
docker compose exec app zsh
```

Interactive shells and the container's start-up log open with the banner in `env/motd.sh`. Edit that file and rebuild with `docker compose up -d --build` to change it.

Run common Laravel commands:

```sh
docker compose exec app php artisan migrate
docker compose exec app php artisan test
docker compose exec app composer install
docker compose exec app npm install
```

Run PHP, Composer, and npm through the `app` container rather than on the host, so they use the PHP and Node versions the project was built with.

### Vite

When frontend assets are enabled, the `app` container starts the Vite development server next to PHP-FPM, so `docker compose up` is all a page needs to load its assets. Its output appears in `docker compose logs -f app`. Do not start a second `npm run dev` by hand.

The browser loads assets from `http://localhost:FORWARDED_VITE_PORT`, which is published on the host's loopback interface only. Setting `$forwarded_vite_port = nil` disables the automatic Vite server; build the assets with `docker compose exec app npm run build` instead.

After changing `vite.config.js`, PHP settings, or installing dependencies, restart PHP-FPM and Vite without restarting the container:

```sh
docker compose kill -s SIGUSR1 app
```

Inside the container shell, the `reload` alias does the same.

The application is available at `http://PROJECT_NAME.test` on the Linux static-IP workflow, with self-signed HTTPS also available. With `$forwarded_port = 3000`, use `http://localhost:3000` or `https://localhost:3001`.

When enabled:

- Mailpit: `/mailpit`
- phpMyAdmin: `/phpmyadmin/`
- Vite: `http://localhost:FORWARDED_VITE_PORT`

Multiple projects cannot publish the same Vite or forwarded database port simultaneously. Assign unique ports per project.

## Generated and persistent files

The following are generated and intentionally ignored by Git:

- `docker-compose.yml`
- `Dockerfile-app`
- `Dockerfile-web`
- `nginx.conf`
- `db-init/`
- `database/`
- `mails/`
- `webroot/`

The tracked `env/nginx.conf` file is a template. Setup renders optional Nginx routes into the ignored root `nginx.conf`; it never edits the tracked template in place.
