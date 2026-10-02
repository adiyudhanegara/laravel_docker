require "fileutils"
require "ipaddr"
require "json"
require "open3"
require "rbconfig"
require "shellwords"
require "time"
require "yaml"

class SetupError < StandardError; end

class String
  def colorize(code)
    "\e[#{code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def yellow
    colorize(33)
  end

  def green
    colorize(32)
  end
end

GENERATED_FILES = %w[docker-compose.yml Dockerfile-app Dockerfile-web nginx.conf].freeze
SUPPORTED_DATABASES = %w[mariadb mysql postgres].freeze

def host_uid
  @host_uid ||= if Process.euid.zero?
    (ENV["SUDO_UID"] || File.stat(__FILE__).uid).to_i
  else
    Process.uid
  end
end

def host_gid
  @host_gid ||= if Process.euid.zero?
    (ENV["SUDO_GID"] || File.stat(__FILE__).gid).to_i
  else
    Process.gid
  end
end

def run!(*command, stdin_data: nil)
  printable = command.map { |part| Shellwords.escape(part.to_s) }.join(" ")
  puts "$ #{printable}".yellow

  if stdin_data
    status = nil
    Open3.popen2e(*command.map(&:to_s)) do |input, output, wait_thread|
      input.write(stdin_data)
      input.close
      IO.copy_stream(output, $stdout)
      status = wait_thread.value
    end
    raise SetupError, "Command failed: #{printable}" unless status.success?
  else
    raise SetupError, "Command failed: #{printable}" unless system(*command.map(&:to_s))
  end
end

def capture(*command, allow_failure: false)
  stdout, stderr, status = Open3.capture3(*command.map(&:to_s))
  unless status.success? || allow_failure
    details = stderr.strip.empty? ? stdout.strip : stderr.strip
    raise SetupError, "Command failed: #{command.join(' ')}\n#{details}"
  end
  [stdout, stderr, status]
end

def validate_host_requirements!
  unless system("docker", "compose", "version", out: File::NULL, err: File::NULL)
    raise SetupError, "Docker Compose is required and must be available as 'docker compose'."
  end

  if RbConfig::CONFIG["host_os"] =~ /linux/ && Process.euid != 0
    groups = capture("id", "-nG").first.split
    raise SetupError, "Your user must belong to the docker group." unless groups.include?("docker")
  end
end

def validate_settings!
  unless RbConfig::CONFIG["host_os"] =~ /linux/
    $forwarded_port ||= 3000
    $forwarded_db_port ||= ($db_engine == "postgres" ? 5432 : 3306)
  end

  unless $project_name.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
    raise SetupError, "$project_name must contain only lowercase letters, numbers, dashes, and underscores."
  end
  raise SetupError, "$project_name must be 40 characters or fewer." if $project_name.length > 40

  unless $host_name.match?(/\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/)
    raise SetupError, "$host_name is not a valid local hostname."
  end

  unless SUPPORTED_DATABASES.include?($db_engine)
    raise SetupError, "$db_engine must be one of: #{SUPPORTED_DATABASES.join(', ')}."
  end

  if $with_phpmyadmin && $db_engine == "postgres"
    raise SetupError, "$with_phpmyadmin is only supported with MariaDB or MySQL."
  end

  if $db_reset && $run_migrations
    raise SetupError, "Choose either $db_reset or $run_migrations, not both."
  end

  [$forwarded_port, $forwarded_db_port, $forwarded_vite_port].compact.each do |port|
    raise SetupError, "Forwarded ports must be integers from 1 to 65535." unless port.is_a?(Integer) && port.between?(1, 65_535)
  end
  raise SetupError, "$forwarded_port must be 65534 or lower because HTTPS uses the next port." if $forwarded_port == 65_535

  validate_network!
end

def validate_resolved_settings!
  published_ports = [
    $forwarded_port,
    ($forwarded_port + 1 if $forwarded_port),
    $forwarded_db_port,
    ($forwarded_vite_port if $with_assets)
  ].compact
  return if published_ports.uniq.length == published_ports.length

  raise SetupError, "Forwarded web, HTTPS, database, and Vite ports must be unique."
end

def validate_network!
  network = IPAddr.new($network)
  raise SetupError, "$network must be an IPv4 subnet." unless network.ipv4?
  address_count = network.to_range.end.to_i - network.to_range.begin.to_i + 1
  raise SetupError, "$network must provide at least 16 addresses." if address_count < 16

  network_ids = capture("docker", "network", "ls", "-q").first.lines.map(&:strip).reject(&:empty?)
  return if network_ids.empty?

  output = capture("docker", "network", "inspect", *network_ids).first
  own_network = "#{$project_name}_#{$project_name}_net"
  conflict = JSON.parse(output).find do |candidate|
    next false if candidate["Name"] == own_network

    Array(candidate.dig("IPAM", "Config")).any? do |config|
      subnet = config["Subnet"]
      next false if subnet.nil?

      begin
        candidate = IPAddr.new(subnet)
        candidate_begin = candidate.to_range.begin.to_i
        candidate_end = candidate.to_range.end.to_i
        network_begin = network.to_range.begin.to_i
        network_end = network.to_range.end.to_i
        candidate_begin <= network_end && network_begin <= candidate_end
      rescue IPAddr::InvalidAddressError
        false
      end
    end
  end

  return unless conflict

  raise SetupError, "Subnet #{$network} overlaps Docker network '#{conflict['Name']}'. Choose another $network."
rescue IPAddr::InvalidAddressError
  raise SetupError, "$network is not a valid subnet."
rescue JSON::ParserError
  raise SetupError, "Docker returned invalid network inspection data."
end

def clone_project_if_configured!
  return if $project_repo.nil? || $project_repo.strip.empty?

  if Dir.exist?("webroot") && !Dir.empty?("webroot")
    raise SetupError, "webroot is not empty; refusing to clone $project_repo over it."
  end

  FileUtils.rm_rf("webroot") if Dir.exist?("webroot")
  command = ["git", "clone"]
  command.concat(["--branch", $project_branch]) if $project_branch && !$project_branch.empty?
  command.concat([$project_repo, "webroot"])
  run!(*command)
end

def prepare_directories!
  %w[webroot database db-init home].each do |directory|
    FileUtils.mkdir_p(directory)
    FileUtils.chown(host_uid, host_gid, directory) if Process.euid.zero?
  end
  FileUtils.chown_R(host_uid, host_gid, "webroot") if Process.euid.zero?

  if $with_mailpit
    FileUtils.mkdir_p("mails")
    FileUtils.chown(host_uid, host_gid, "mails") if Process.euid.zero?
  end
end

def analyze_laravel_project!
  $existing_project = File.file?("webroot/artisan") && File.file?("webroot/composer.json")
  $package_manager = detect_package_manager

  if $existing_project
    composer = JSON.parse(File.read("webroot/composer.json"))
    framework_constraint = composer.dig("require", "laravel/framework")
    php_constraint = composer.dig("require", "php")
    locked_framework = locked_package_version("laravel/framework")

    puts "Existing Laravel project found.".yellow
    puts "  Laravel: #{locked_framework || framework_constraint || 'not recorded'}"
    puts "  PHP requirement: #{php_constraint || 'not recorded'}"
    puts "  Package manager: #{$package_manager}"

    detected_php = exact_php_version(composer)
    if $php_version.nil? && detected_php
      $php_version = detected_php
      puts "  Using detected PHP #{$php_version}.".yellow
    elsif $php_version.nil? && php_constraint
      puts "  PHP is not pinned; the current official PHP image will be used for constraint #{php_constraint}.".yellow
    end
  elsif !Dir.empty?("webroot")
    visible_entries = Dir.children("webroot").reject { |entry| entry == ".gitkeep" }
    raise SetupError, "webroot contains files but is not a Laravel application." unless visible_entries.empty?
  else
    puts "No Laravel application found; setup will create a new project.".yellow
  end

  $with_assets = !$existing_project || File.file?("webroot/package.json") if $with_assets.nil?
rescue JSON::ParserError
  raise SetupError, "webroot/composer.json is not valid JSON."
end

def locked_package_version(package_name)
  return nil unless File.file?("webroot/composer.lock")

  lock = JSON.parse(File.read("webroot/composer.lock"))
  packages = Array(lock["packages"]) + Array(lock["packages-dev"])
  packages.find { |package| package["name"] == package_name }&.fetch("version", nil)
rescue JSON::ParserError
  raise SetupError, "webroot/composer.lock is not valid JSON."
end

def exact_php_version(composer)
  version_file = "webroot/.php-version"
  if File.file?(version_file)
    value = File.read(version_file).strip.sub(/\Av/, "")
    return value if value.match?(/\A\d+\.\d+(?:\.\d+)?\z/)
  end

  value = composer.dig("config", "platform", "php")
  value.to_s.match?(/\A\d+\.\d+(?:\.\d+)?\z/) ? value.to_s : nil
end

def detect_package_manager
  return "pnpm" if File.file?("webroot/pnpm-lock.yaml")
  return "yarn" if File.file?("webroot/yarn.lock")

  "npm"
end

def reset_generated_config!
  run!("docker", "compose", "down", "--remove-orphans") if File.file?("docker-compose.yml")
  GENERATED_FILES.each { |file| FileUtils.rm_f(file) }
end

def refuse_existing_generated_config!
  existing = GENERATED_FILES.select { |file| File.exist?(file) }
  return if existing.empty?

  raise SetupError, "Generated files already exist (#{existing.join(', ')}). Set $reset_config = true to regenerate them."
end

def database_names
  base = $project_name.tr("-.", "_")
  {
    development: "#{base}_development",
    test: "#{base}_test",
    production: "#{base}_production"
  }
end

def database_users
  base = $project_name.tr("-.", "_")[0, 28]
  { development: base, production: "#{base[0, 26]}_p" }
end

def sql_string(value)
  value.to_s.gsub("'", "''")
end

def create_database_init_file!
  names = database_names
  users = database_users

  sql = if %w[mariadb mysql].include?($db_engine)
    <<~SQL
      CREATE USER IF NOT EXISTS '#{users[:development]}'@'%' IDENTIFIED BY '#{sql_string($db_user_pw)}';
      ALTER USER '#{users[:development]}'@'%' IDENTIFIED BY '#{sql_string($db_user_pw)}';
      CREATE USER IF NOT EXISTS '#{users[:production]}'@'%' IDENTIFIED BY '#{sql_string($db_prod_user_pw)}';
      ALTER USER '#{users[:production]}'@'%' IDENTIFIED BY '#{sql_string($db_prod_user_pw)}';
      CREATE DATABASE IF NOT EXISTS `#{names[:development]}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
      CREATE DATABASE IF NOT EXISTS `#{names[:test]}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
      CREATE DATABASE IF NOT EXISTS `#{names[:production]}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
      GRANT ALL PRIVILEGES ON `#{names[:development]}`.* TO '#{users[:development]}'@'%';
      GRANT ALL PRIVILEGES ON `#{names[:test]}`.* TO '#{users[:development]}'@'%';
      GRANT ALL PRIVILEGES ON `#{names[:production]}`.* TO '#{users[:production]}'@'%';
      FLUSH PRIVILEGES;
    SQL
  else
    <<~SQL
      SELECT 'CREATE USER #{users[:development]} WITH PASSWORD ''#{sql_string($db_user_pw)}'''
        WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{users[:development]}')\\gexec
      ALTER USER #{users[:development]} WITH PASSWORD '#{sql_string($db_user_pw)}';
      SELECT 'CREATE USER #{users[:production]} WITH PASSWORD ''#{sql_string($db_prod_user_pw)}'''
        WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{users[:production]}')\\gexec
      ALTER USER #{users[:production]} WITH PASSWORD '#{sql_string($db_prod_user_pw)}';
      SELECT 'CREATE DATABASE #{names[:development]} OWNER #{users[:development]}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '#{names[:development]}')\\gexec
      SELECT 'CREATE DATABASE #{names[:test]} OWNER #{users[:development]}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '#{names[:test]}')\\gexec
      SELECT 'CREATE DATABASE #{names[:production]} OWNER #{users[:production]}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '#{names[:production]}')\\gexec
    SQL
  end

  File.write("db-init/01-phpdock.sql", sql)
end

def php_image
  return $php_image if $php_image && !$php_image.empty?

  $php_version ? "php:#{$php_version}-fpm" : "php:fpm"
end

def node_image
  version = $node_version.nil? || $node_version == "lts" ? "lts" : $node_version
  distribution = php_image[/-(bullseye|bookworm|trixie)(?:-|$)/, 1] || "bookworm"
  "node:#{version}-#{distribution}-slim"
end

def create_docker_files!
  packages = %w[
    ca-certificates curl git less libfreetype6-dev libicu-dev libjpeg62-turbo-dev
    libonig-dev libpng-dev libsqlite3-dev libwebp-dev libxml2-dev libzip-dev unzip vim xclip zip
    zsh
  ]
  extensions = %w[bcmath exif gd intl mbstring pcntl pdo_sqlite zip]

  if $db_engine == "postgres"
    packages.concat(%w[libpq-dev postgresql-client])
    extensions << "pdo_pgsql"
  else
    packages << "default-mysql-client"
    extensions << "pdo_mysql"
  end

  if $with_imagick
    packages.concat(%w[imagemagick libmagickwand-dev])
  end

  pecl_commands = []
  if $with_imagick
    imagick_package = $imagick_extension_version ? "imagick-#{$imagick_extension_version}" : "imagick"
    pecl_commands << "pecl install #{imagick_package} && docker-php-ext-enable imagick"
  end
  if $with_redis
    redis_package = $redis_extension_version ? "redis-#{$redis_extension_version}" : "redis"
    pecl_commands << "pecl install #{redis_package} && docker-php-ext-enable redis"
  end

  install_layers = [
    [
      "apt-get update -qq",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends #{packages.uniq.sort.join(' ')}",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*"
    ],
    [
      "docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp",
      "docker-php-ext-install -j \"$(nproc)\" #{extensions.uniq.sort.join(' ')}"
    ],
    [
      "if php -m | grep -qi '^Zend OPcache$'; then echo 'Zend OPcache is already available'; else docker-php-ext-install -j \"$(nproc)\" opcache; fi"
    ],
    *pecl_commands.map { |command| [command] }
  ]
  install_separator = " && \\" + "\n    "
  install_layers = install_layers.map do |commands|
    "RUN #{commands.join(install_separator)}"
  end.join("\n\n")
  build_stages = ["FROM composer:#{$composer_version || '2'} AS composer"]
  build_stages << "FROM #{node_image} AS node" if $with_assets
  node_tools = if $with_assets
    <<~DOCKERFILE.chomp
      COPY --from=node /usr/local/bin/node /usr/local/bin/node
      COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
      RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \\
          ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \\
          if [ -f /usr/local/lib/node_modules/corepack/dist/corepack.js ]; then \\
            ln -sf ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack; \\
          fi
    DOCKERFILE
  else
    ""
  end
  user_commands = [
    'if ! getent group "$gid" >/dev/null; then groupadd --gid "$gid" user; fi',
    'useradd --uid "$uid" --gid "$gid" --home-dir /home/user --shell /bin/zsh user',
    'mkdir -p "$APP_HOME" "$COMPOSER_HOME"',
    'chown -R "$uid:$gid" "$APP_HOME" /home/user'
  ]

  dockerfile = <<~DOCKERFILE
    #{build_stages.join("\n")}
    FROM #{php_image}

    ARG uid
    ARG gid

    ENV APP_HOME=/app
    ENV HOME=/home/user
    ENV LANG=C.UTF-8
    ENV COMPOSER_HOME=/home/user/.composer

    #{install_layers}

    COPY --from=composer /usr/bin/composer /usr/local/bin/composer

    #{node_tools}

    RUN #{user_commands.join(" && \\\n        ")}

    WORKDIR $APP_HOME

    COPY env/starter.sh /usr/local/bin/starter.sh
    COPY env/php.ini /usr/local/etc/php/conf.d/99-phpdock.ini
    RUN chmod +x /usr/local/bin/starter.sh

    USER $uid:$gid
    CMD ["/usr/local/bin/starter.sh"]
  DOCKERFILE

  web_dockerfile = <<~DOCKERFILE
    FROM nginx:stable
    ARG hostname

    RUN apt-get update -qq && apt-get install -y --no-install-recommends openssl && \\
        mkdir -p /etc/nginx/ssl && \\
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \\
          -keyout /etc/nginx/ssl/nginx.key \\
          -out /etc/nginx/ssl/nginx.crt \\
          -subj "/C=ID/CN=$hostname" && \\
        apt-get clean && rm -rf /var/lib/apt/lists/*

    COPY nginx.conf /etc/nginx/nginx.conf
  DOCKERFILE

  nginx = File.read("env/nginx.conf")
  mailpit_location = if $with_mailpit
    <<~NGINX.chomp
      location /mailpit {
        proxy_pass http://mailpit:8025;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $http_host;
        proxy_read_timeout 1800;
        proxy_redirect off;
      }
    NGINX
  else
    ""
  end
  phpmyadmin_location = if $with_phpmyadmin
    <<~NGINX.chomp
      location ^~ /phpmyadmin/ {
        proxy_pass http://phpmyadmin/;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $http_host;
      }
    NGINX
  else
    ""
  end
  nginx.sub!("{{MAILPIT_LOCATION}}", mailpit_location.lines.map { |line| "    #{line}" }.join.rstrip)
  nginx.sub!("{{PHPMYADMIN_LOCATION}}", phpmyadmin_location.lines.map { |line| "    #{line}" }.join.rstrip)

  File.write("Dockerfile-app", dockerfile)
  File.write("Dockerfile-web", web_dockerfile)
  File.write("nginx.conf", nginx)
end

def network_addresses
  gateway = IPAddr.new($network).succ
  {
    db: gateway.succ,
    app: gateway.succ.succ,
    web: gateway.succ.succ.succ,
    redis: gateway.succ.succ.succ.succ,
    mailpit: gateway.succ.succ.succ.succ.succ,
    phpmyadmin: gateway.succ.succ.succ.succ.succ.succ
  }.transform_values(&:to_s)
end

def app_build_config
  {
    "context" => ".",
    "dockerfile" => "Dockerfile-app",
    "args" => { "uid" => host_uid, "gid" => host_gid }
  }
end

# Application settings are deliberately left to .env: a container-level value
# wins over both .env and phpunit.xml, so APP_ENV here would make the test
# suite run as "local" and REDIS_URL would override REDIS_HOST and REDIS_DB.
def app_environment
  { "TZ" => "Asia/Makassar" }
end

def vite_published?
  $with_assets && !$forwarded_vite_port.nil?
end

def app_volumes
  ["./webroot:/app", "./home:/home/user"]
end

def app_dependencies
  dependencies = { "db" => { "condition" => "service_healthy" } }
  dependencies["redis"] = { "condition" => "service_healthy" } if $with_redis
  dependencies
end

def database_service(addresses)
  image = "#{$db_engine}:#{$db_engine_version || 'latest'}"
  service = {
    "image" => image,
    "restart" => "unless-stopped",
    "volumes" => ["./database:/var/lib/#{ $db_engine == 'postgres' ? 'postgresql/data' : 'mysql' }", "./db-init:/docker-entrypoint-initdb.d:ro"],
    "networks" => { "#{$project_name}_net" => { "ipv4_address" => addresses[:db] } }
  }

  if $db_engine == "postgres"
    service["environment"] = {
      "POSTGRES_PASSWORD" => $db_root_pw,
      "POSTGRES_INITDB_ARGS" => "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    }
    service["healthcheck"] = {
      "test" => ["CMD-SHELL", "pg_isready -U postgres"],
      "interval" => "2s", "timeout" => "5s", "retries" => 30, "start_period" => "10s"
    }
    service["ports"] = ["#{$forwarded_db_port}:5432"] if $forwarded_db_port
  else
    prefix = $db_engine.upcase
    service["command"] = "#{$db_engine}d --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci"
    service["environment"] = {
      "#{prefix}_ROOT_PASSWORD" => $db_root_pw,
      "#{prefix}_INITDB_SKIP_TZINFO" => "1"
    }
    client = $db_engine == "mariadb" ? "mariadb-admin" : "mysqladmin"
    password_var = "#{prefix}_ROOT_PASSWORD"
    service["healthcheck"] = {
      "test" => ["CMD-SHELL", "#{client} ping -h 127.0.0.1 -uroot -p\"$${#{password_var}}\" --silent"],
      "interval" => "2s", "timeout" => "5s", "retries" => 30, "start_period" => "15s"
    }
    service["ports"] = ["#{$forwarded_db_port}:3306"] if $forwarded_db_port
  end

  service
end

def create_compose_file!
  addresses = network_addresses
  network_name = "#{$project_name}_net"
  services = {
    "db" => database_service(addresses),
    "app" => {
      "build" => app_build_config,
      "restart" => "unless-stopped",
      "user" => "#{host_uid}:#{host_gid}",
      "working_dir" => "/app",
      "environment" => app_environment,
      "volumes" => app_volumes,
      "depends_on" => app_dependencies,
      "stop_grace_period" => "5s",
      "networks" => { network_name => { "ipv4_address" => addresses[:app] } }
    },
    "web" => {
      "build" => {
        "context" => ".", "dockerfile" => "Dockerfile-web",
        "args" => { "hostname" => $host_name }
      },
      "restart" => "unless-stopped",
      "volumes" => ["./webroot:/app:ro"],
      "depends_on" => { "app" => { "condition" => "service_started" } },
      "networks" => { network_name => { "ipv4_address" => addresses[:web] } }
    }
  }

  if $forwarded_port
    services["web"]["ports"] = ["#{$forwarded_port}:80", "#{$forwarded_port + 1}:443"]
  end
  if vite_published?
    # starter.sh runs Vite on VITE_PORT and the browser loads it from
    # localhost, so the port is the same on both sides and bound to loopback.
    services["app"]["environment"] = app_environment.merge("VITE_PORT" => $forwarded_vite_port.to_s)
    services["app"]["ports"] = ["127.0.0.1:#{$forwarded_vite_port}:#{$forwarded_vite_port}"]
  end

  if $with_redis
    services["redis"] = {
      "image" => "redis:latest",
      "restart" => "unless-stopped",
      "healthcheck" => {
        "test" => ["CMD", "redis-cli", "ping"],
        "interval" => "2s", "timeout" => "3s", "retries" => 30
      },
      "networks" => { network_name => { "ipv4_address" => addresses[:redis] } }
    }
  end

  if $with_mailpit
    services["mailpit"] = {
      "image" => "axllent/mailpit:latest",
      "restart" => "unless-stopped",
      "volumes" => ["./mails:/data"],
      "environment" => {
        "MP_MAX_MESSAGES" => "5000", "MP_DATABASE" => "/data/mailpit.db",
        "MP_WEBROOT" => "/mailpit", "MP_SMTP_AUTH_ACCEPT_ANY" => "1",
        "MP_SMTP_AUTH_ALLOW_INSECURE" => "1"
      },
      "networks" => { network_name => { "ipv4_address" => addresses[:mailpit] } }
    }
  end

  if $with_phpmyadmin
    public_url = $forwarded_port ? "http://localhost:#{$forwarded_port}" : "http://#{$host_name}"
    services["phpmyadmin"] = {
      "image" => "phpmyadmin:latest",
      "restart" => "unless-stopped",
      "environment" => {
        "PMA_HOST" => "db", "PMA_PORT" => "3306", "PMA_ARBITRARY" => "0",
        "PMA_ABSOLUTE_URI" => "#{public_url}/phpmyadmin/"
      },
      "depends_on" => { "db" => { "condition" => "service_healthy" } },
      "networks" => { network_name => { "ipv4_address" => addresses[:phpmyadmin] } }
    }
  end

  # Nginx resolves every proxy_pass host at startup and exits when one is
  # missing, so each proxied service has to be running before web starts.
  %w[mailpit phpmyadmin].each do |proxied_service|
    next unless services.key?(proxied_service)

    services["web"]["depends_on"][proxied_service] = { "condition" => "service_started" }
  end

  if $with_queue
    services["queue"] = {
      "build" => app_build_config,
      "restart" => "unless-stopped",
      "user" => "#{host_uid}:#{host_gid}",
      "working_dir" => "/app",
      "command" => ["php", "artisan", "queue:work", "--sleep=1", "--tries=3", "--timeout=90"],
      "environment" => app_environment,
      "volumes" => app_volumes,
      "depends_on" => app_dependencies,
      "networks" => [network_name]
    }
  end

  if $with_scheduler
    services["scheduler"] = {
      "build" => app_build_config,
      "restart" => "unless-stopped",
      "user" => "#{host_uid}:#{host_gid}",
      "working_dir" => "/app",
      "command" => ["php", "artisan", "schedule:work"],
      "environment" => app_environment,
      "volumes" => app_volumes,
      "depends_on" => app_dependencies,
      "networks" => [network_name]
    }
  end

  compose = {
    "name" => $project_name,
    "services" => services,
    "networks" => {
      network_name => {
        "driver" => "bridge",
        "ipam" => { "driver" => "default", "config" => [{ "subnet" => $network }] }
      }
    }
  }

  File.write("docker-compose.yml", YAML.dump(compose).sub(/\A---\s*\n/, ""))
end

def build_images!
  command = ["docker", "compose", "build"]
  command << "--no-cache" if $no_cache
  run!(*command)
end

def with_setup_services
  services = ["db"]
  services << "redis" if $with_redis
  services << "app"
  run!("docker", "compose", "up", "-d", *services)
  wait_for_database!
  yield
ensure
  system("docker", "compose", "down", "--remove-orphans") if File.file?("docker-compose.yml")
end

def database_probe_command
  if $db_engine == "postgres"
    ["docker", "compose", "exec", "-T", "db", "pg_isready", "-U", "postgres"]
  else
    client = $db_engine == "mariadb" ? "mariadb-admin" : "mysqladmin"
    ["docker", "compose", "exec", "-T", "db", client, "ping", "-h", "127.0.0.1", "-uroot", "-p#{$db_root_pw}", "--silent"]
  end
end

def wait_for_database!
  print "Waiting for #{$db_engine}"
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 90

  loop do
    _stdout, _stderr, status = capture(*database_probe_command, allow_failure: true)
    if status.success?
      puts " ready".green
      return
    end

    raise SetupError, "Database did not become ready within 90 seconds. Check 'docker compose logs db'." if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    print "."
    sleep 1
  end
end

def ensure_database_initialized!
  sql = File.read("db-init/01-phpdock.sql")
  if $db_engine == "postgres"
    command = ["docker", "compose", "exec", "-T", "db", "psql", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"]
  else
    client = $db_engine == "mariadb" ? "mariadb" : "mysql"
    command = ["docker", "compose", "exec", "-T", "db", client, "-uroot", "-p#{$db_root_pw}"]
  end
  run!(*command, stdin_data: sql)
end

def install_laravel_application!
  if File.file?("webroot/artisan") && File.file?("webroot/composer.json")
    run!("docker", "compose", "exec", "-T", "app", "composer", "install", "--prefer-dist", "--no-interaction")
    return
  end

  non_placeholder_entries = Dir.children("webroot").reject { |entry| entry == ".gitkeep" }
  raise SetupError, "webroot must be empty before creating a Laravel project." unless non_placeholder_entries.empty?

  FileUtils.rm_f("webroot/.gitkeep")
  script = File.read("env/laravel_new_commands.sh")
  command = ["docker", "compose", "exec", "-T", "-e", "LARAVEL_VERSION=#{$laravel_version}", "app", "bash"]
  run!(*command, stdin_data: script)
end

def dotenv_value(value)
  string = value.to_s
  return string if string.match?(%r{\A[A-Za-z0-9_:/\.@+\-]+\z})

  %Q{"#{string.gsub('\\', '\\\\').gsub('"', '\\"')}"}
end

def update_dotenv(content, values)
  lines = content.lines(chomp: true)
  values.each do |key, value|
    replacement = "#{key}=#{dotenv_value(value)}"
    indexes = lines.each_index.select { |index| lines[index].match?(/\A\s*#?\s*#{Regexp.escape(key)}\s*=/) }
    if indexes.empty?
      lines << replacement
    else
      lines[indexes.first] = replacement
      indexes.drop(1).reverse_each { |index| lines.delete_at(index) }
    end
  end
  lines.join("\n") + "\n"
end

def dotenv_values(content)
  content.lines(chomp: true).each_with_object({}) do |line, values|
    match = line.match(/\A\s*([A-Za-z0-9_]+)\s*=(.*)\z/)
    values[match[1]] = match[2] if match
  end
end

# An unknown version is treated as current, which is what a new project gets.
def modern_laravel?
  version = locked_package_version("laravel/framework")
  version.nil? || version[/\d+/].to_i >= 11
end

# Laravel 11 renamed a few .env keys. Keep whichever spelling the application
# already uses, and fall back to the one its Laravel version expects.
def dotenv_key(content, modern, legacy)
  present = ->(key) { content.match?(/^\s*#?\s*#{Regexp.escape(key)}\s*=/) }
  return modern if present.call(modern)
  return legacy if present.call(legacy)

  modern_laravel? ? modern : legacy
end

def laravel_database_connection
  return "pgsql" if $db_engine == "postgres"
  return "mysql" unless $db_engine == "mariadb"

  config_path = "webroot/config/database.php"
  has_mariadb_connection = if File.file?(config_path)
    File.read(config_path).match?(/['"]mariadb['"]\s*=>\s*\[/)
  else
    modern_laravel?
  end
  has_mariadb_connection ? "mariadb" : "mysql"
end

# Infrastructure values only: everything here points the application at a
# service this setup generated. Application-level choices are left alone.
def laravel_environment_values(content)
  names = database_names
  users = database_users
  app_url = $forwarded_port ? "http://localhost:#{$forwarded_port}" : "http://#{$host_name}"

  values = {}
  values["APP_NAME"] = $project_name unless $existing_project
  values.merge!(
    "APP_ENV" => "local",
    "APP_URL" => app_url,
    "DB_CONNECTION" => laravel_database_connection,
    "DB_HOST" => "db",
    "DB_PORT" => $db_engine == "postgres" ? 5432 : 3306,
    "DB_DATABASE" => names[:development],
    "DB_USERNAME" => users[:development],
    "DB_PASSWORD" => $db_user_pw
  )

  if $with_redis
    values.merge!("REDIS_CLIENT" => "phpredis", "REDIS_HOST" => "redis", "REDIS_PASSWORD" => "null", "REDIS_PORT" => 6379)
    if $use_redis_drivers
      values.merge!(
        dotenv_key(content, "CACHE_STORE", "CACHE_DRIVER") => "redis",
        "SESSION_DRIVER" => "redis",
        "QUEUE_CONNECTION" => "redis"
      )
    end
  end

  if $with_mailpit
    values.merge!(
      "MAIL_MAILER" => "smtp",
      dotenv_key(content, "MAIL_SCHEME", "MAIL_ENCRYPTION") => "null",
      "MAIL_HOST" => "mailpit",
      "MAIL_PORT" => 1025,
      "MAIL_USERNAME" => "null",
      "MAIL_PASSWORD" => "null"
    )
  end

  values
end

# Keeps the files setup writes next to .env out of the application's
# `git status` without touching its tracked .gitignore.
def exclude_generated_env_files!
  return unless Dir.exist?("webroot/.git")

  exclude_path = "webroot/.git/info/exclude"
  FileUtils.mkdir_p(File.dirname(exclude_path))
  existing = File.exist?(exclude_path) ? File.read(exclude_path) : ""
  missing = %w[.env.backup-* .env.testing].reject { |pattern| existing.lines.map(&:strip).include?(pattern) }
  return if missing.empty?

  separator = existing.empty? || existing.end_with?("\n") ? "" : "\n"
  File.write(exclude_path, existing + separator + missing.join("\n") + "\n")
  FileUtils.chown(host_uid, host_gid, exclude_path) if Process.euid.zero?
end

def write_application_file(path, content)
  File.write(path, content)
  FileUtils.chown(host_uid, host_gid, path) if Process.euid.zero?
end

def configure_laravel_environment!
  env_path = "webroot/.env"
  example_path = "webroot/.env.example"
  FileUtils.cp(example_path, env_path) if !File.exist?(env_path) && File.exist?(example_path)
  File.write(env_path, "") unless File.exist?(env_path)

  original = File.read(env_path)
  values = laravel_environment_values(original)
  updated = update_dotenv(original, values)
  if updated == original
    puts "webroot/.env already matches this Docker setup.".yellow
    return
  end

  exclude_generated_env_files!
  unless original.empty?
    timestamp = Time.now.iso8601.gsub(":", "-")
    backup_path = "#{env_path}.backup-#{timestamp}"
    FileUtils.cp(env_path, backup_path)
    FileUtils.chown(host_uid, host_gid, backup_path) if Process.euid.zero?
    puts "Previous .env saved as #{backup_path}.".yellow
  end
  write_application_file(env_path, updated)

  before = dotenv_values(original)
  after = dotenv_values(updated)
  changed = values.keys.select { |key| before[key] != after[key] }
  puts "Updated webroot/.env: #{changed.join(', ')}".yellow
end

# Laravel reads .env.testing instead of .env when APP_ENV is "testing", so it
# is a full copy pointed at the test database with in-memory drivers.
def create_testing_environment!
  env_path = "webroot/.env"
  testing_path = "webroot/.env.testing"
  return unless File.file?(env_path)

  if File.exist?(testing_path)
    puts "webroot/.env.testing already exists; it was left unchanged.".yellow
    return
  end

  content = File.read(env_path)
  values = {
    "APP_ENV" => "testing",
    "BCRYPT_ROUNDS" => 4,
    "DB_DATABASE" => database_names[:test],
    dotenv_key(content, "CACHE_STORE", "CACHE_DRIVER") => "array",
    "SESSION_DRIVER" => "array",
    "QUEUE_CONNECTION" => "sync",
    "MAIL_MAILER" => "array"
  }

  exclude_generated_env_files!
  write_application_file(testing_path, update_dotenv(content, values))
  puts "Created webroot/.env.testing for the #{database_names[:test]} database.".yellow
end

def install_frontend_dependencies!
  return unless $with_assets && File.file?("webroot/package.json")

  $package_manager = detect_package_manager
  command = case $package_manager
  when "pnpm"
    ["sh", "-lc", "corepack pnpm install --frozen-lockfile"]
  when "yarn"
    ["sh", "-lc", "corepack yarn install"]
  when "npm"
    File.file?("webroot/package-lock.json") ? ["npm", "ci"] : ["npm", "install"]
  end
  run!("docker", "compose", "exec", "-T", "app", *command)
end

def initialize_application_key!
  return unless File.file?("webroot/artisan") && File.file?("webroot/.env")

  key_line = File.readlines("webroot/.env").find { |line| line.start_with?("APP_KEY=") }
  return if key_line && !key_line.split("=", 2).last.to_s.strip.empty?

  run!("docker", "compose", "exec", "-T", "app", "php", "artisan", "key:generate", "--force", "--no-interaction")
end

def link_public_storage!
  return unless File.file?("webroot/artisan") && Dir.exist?("webroot/storage/app/public")
  return if File.exist?("webroot/public/storage") || File.symlink?("webroot/public/storage")

  run!("docker", "compose", "exec", "-T", "app", "php", "artisan", "storage:link", "--no-interaction")
end

def run_database_tasks!
  if $db_reset
    puts "Database reset was explicitly enabled.".red
    run!("docker", "compose", "exec", "-T", "app", "php", "artisan", "migrate:fresh", "--force", "--no-interaction")
  elsif $run_migrations
    run!("docker", "compose", "exec", "-T", "app", "php", "artisan", "migrate", "--force", "--no-interaction")
  else
    puts "Database migrations were not run ($run_migrations and $db_reset are false).".yellow
  end
end

def update_hosts_file!
  address = network_addresses[:web]
  hosts_line = format("%-15s %s # Docker Project %s", address, $host_name, $project_name)

  unless Process.euid.zero?
    puts "Add this line to /etc/hosts:".yellow
    puts hosts_line
    return
  end

  lines = File.readlines("/etc/hosts", chomp: true)
  marker = /# Docker Project #{Regexp.escape($project_name)}\z/
  index = lines.index { |line| line.match?(marker) }
  index ? lines[index] = hosts_line : lines << hosts_line
  File.write("/etc/hosts", lines.join("\n") + "\n")
end

def print_setup_summary
  url = if $forwarded_port
    "http://localhost:#{$forwarded_port} (HTTPS: https://localhost:#{$forwarded_port + 1})"
  else
    "http://#{$host_name} (HTTPS: https://#{$host_name})"
  end

  puts "\nSetup finished successfully.".green
  puts "Start the project: docker compose up"
  puts "Application URL: #{url}"
  puts "Mailpit: #{url.split.first}/mailpit" if $with_mailpit
  puts "phpMyAdmin: #{url.split.first}/phpmyadmin/" if $with_phpmyadmin
end
