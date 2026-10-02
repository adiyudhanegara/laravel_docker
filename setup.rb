#!/usr/bin/env ruby

require_relative "setup_helpers"

### SETTINGS ###
$project_name = "laravelproject"
$host_name = "#{$project_name}.test"

# Supported database engines: mariadb, mysql, postgres.
$db_engine = "mariadb"
$db_engine_version = nil # nil uses the current official image tag.
$db_root_pw = "12345"
$db_user_pw = "123456"
$db_prod_user_pw = "1234567"

# Every local project needs a non-overlapping subnet.
$network = "172.22.0.0/24"
$forwarded_port = nil
$forwarded_db_port = nil
$forwarded_vite_port = 5173

# nil means the current official image/tool release. Existing projects are
# inspected for exact versions recorded in .php-version or composer.json.
$php_version = nil
$php_image = nil # Full override, for example "php:8.2-fpm-bullseye".
$composer_version = "2"
$node_version = "lts"
$laravel_version = nil # Example: "13.*" when creating a new application.
$imagick_extension_version = nil
$redis_extension_version = nil

# Existing project source may be cloned into webroot before setup instead.
$project_repo = nil
$project_branch = nil

# Optional development services.
$with_redis = true
$with_mailpit = true
$with_phpmyadmin = true # Only available with MariaDB/MySQL.
$with_assets = nil      # nil auto-detects; installs Node/npm in app when enabled.
$with_queue = false
$with_scheduler = false
$with_imagick = true

# Setup behavior. Destructive actions are disabled by default.
$update_app_env = true
$use_redis_drivers = true # Point cache, session, and queue at Redis in .env.
$run_migrations = false
$db_reset = false
$reset_config = false
$no_cache = false
##### END SETTINGS #####

begin
  validate_host_requirements!
  validate_settings!
  reset_generated_config! if $reset_config
  refuse_existing_generated_config!
  clone_project_if_configured!
  prepare_directories!
  analyze_laravel_project!
  validate_resolved_settings!

  create_database_init_file!
  create_docker_files!
  create_compose_file!
  build_images!

  with_setup_services do
    ensure_database_initialized!
    install_laravel_application!
    configure_laravel_environment! if $update_app_env
    install_frontend_dependencies!
    initialize_application_key!
    create_testing_environment! if $update_app_env
    link_public_storage!
    run_database_tasks!
  end

  update_hosts_file! unless $forwarded_port
  print_setup_summary
rescue SetupError => error
  warn error.message.red
  exit 1
rescue Interrupt
  warn "\nSetup interrupted.".red
  exit 130
end
