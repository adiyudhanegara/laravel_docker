#!/usr/bin/ruby
require 'fileutils'
require 'yaml'
require 'ipaddr'
require 'rbconfig'

### SETTINGS ###
$project_name     = "laravelproject"
$host_name        = $project_name + ".test"
$db_root_pw       = "12345"
$db_user_pw       = "123456"
$db_prod_user_pw  = "1234567"
$network          = "172.22.0.0/24"
$forwarded_port   = nil
$php_version      = nil
$laravel_version  = nil
##### END ######

$db_name      = $project_name.tr('-.', '_')
$db_user      = $db_name[0..16]
$db_prod_user = $db_name[0..16] + "_p" 

$net_gateway = IPAddr.new($network).succ
$net_db_ip = $net_gateway.succ
$net_app_ip = $net_db_ip.succ
$net_web_ip = $net_app_ip.succ
$net_redis_ip = $net_web_ip.succ
$net_phpmyadmin_ip = $net_redis_ip.succ

# seems to work only under linux
$forwarded_port ||= 3000 if RbConfig::CONFIG['host_os'] !~ /linux/ 

# helpers

class String
  def colorize(color_code); "\e[#{color_code}m#{self}\e[0m"; end
  def red; colorize(31); end
  def yellow; colorize(33); end
end

def with_exec command
  original_content = File.read("docker-compose.yml")
  new_content = original_content.sub(/command: .*/, "command: #{command}")
  File.write("docker-compose.yml", new_content)
  yield
ensure
  File.write("docker-compose.yml", original_content)
end

def running_container service_names, start_up_phrases, **kwargs
  compose_options = kwargs[:compose_options]
  container_name = kwargs[:container_name]
  service_names = Array(service_names)
  start_up_phrases = Array(start_up_phrases)

  raise ArgumentError, "container_name not usable with multiple services" if container_name && service_names.size > 1

  start_command = container_name ? "run --rm --name #{container_name}" : "up"

  waiting_time = 0.0
  puts "Waiting for #{service_names.join(", ")} to boot"
  begin
    system "docker compose #{start_command} -d #{compose_options} #{service_names.join(" ")}"

    started_up = start_up_phrases.map{ false }
    loop do
      start_up_phrases.each_with_index do |phrase, i|
        next if started_up[i]
        sn = service_names[i]
        if container_name
          output = `docker logs #{container_name} 2>&1`
        else
          output = `docker compose logs #{sn}`
        end

        started_up[i] = true if output.include?(phrase)
        abort "Networks are overlapping, remove old network or choose different address" if output.include?("cannot create network")
      end

      break if started_up.all? || waiting_time > 20
      print "."
      sleep 0.5
      waiting_time += 0.5
    end
    puts

    yield
  ensure
    if container_name
      system "docker stop #{container_name}"
      system "docker rm #{container_name}" # --rm seem to get ignored after sending stop
    else
      system "docker compose down"
    end
  end
end

def prompt_yn question
  print question.yellow
  print " (y/N) "
  answer = gets.chomp
  answer.downcase == "y"
end

# methods

def create_docker_files
  return if File.exist?("Dockerfile-app")

  File.write("Dockerfile-app", <<~EOF)
    FROM node:latest AS node
    FROM php:#{"#{$php_version}-" unless $php_version.nil?}fpm

    # Arguments defined in docker-compose.yml
    ARG uid
    ARG user

    # Install system dependencies
    RUN apt-get update && apt-get install -y \\
        git \\
        curl \\
        libpng-dev \\
        libonig-dev \\
        libxml2-dev \\
        zip \\
        unzip

    # Node JS
    COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
    COPY --from=node /usr/local/bin/node /usr/local/bin/node
    RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

    # For convinience
    RUN apt-get install -y vim zsh-antigen less redis-tools
    
    # Clear cache
    RUN apt-get clean && rm -rf /var/lib/apt/lists/*
    
    # Install PHP extensions
    RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd

    # Get latest Composer
    COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

    # Create system user to run Composer and Artisan Commands
    RUN useradd -G www-data,root -u $uid -d /home/$user $user
    RUN mkdir -p /home/$user/.composer && \
        chown -R $user:$user /home/$user

    # Set working directory
    WORKDIR /var/www
    COPY env/starter.sh /usr/local/bin

    USER $user
    CMD ["/usr/local/bin/starter.sh"]
  EOF

  File.write("Dockerfile-web", <<~EOF)
    FROM nginx:latest
    ARG hostname

    # SSL Certificate for https
    RUN apt-get update -qq && \\
        apt-get install -y vim && \\
        apt-get install -y openssl && \\
        mkdir -p /etc/nginx/ssl && \\
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt -subj "/C=JP/CN=$hostname" && \\
        apt-get clean && rm -r /var/lib/apt/lists/*

    COPY env/nginx.conf /etc/nginx/nginx.conf
  EOF
end

def create_compose_file
  # create docker-compose.yml
  compose = {
    "version" => "3.7",
    "services" => {
      "db" => {
        "image" => "mariadb:latest",
        "command" => "mysqld --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci",
        "volumes" => [ "./database:/var/lib/mysql" ],
        "networks" => { $project_name + "_net" => { "ipv4_address" => $net_db_ip.to_s } },
        "user" => "#$user_id",
      },
      "app" => {
        "container_name" => $project_name + "-app",
        "build" => {
          "args" => {
            "uid" => $user_id,
            "user" => $project_name  + "_user",
          },
          "context" => "./",
          "dockerfile" => "Dockerfile-app"
        },
        "restart" => "unless-stopped",
        "working_dir" => "/var/www/webroot",
        "volumes" => [
          "./:/var/www",
          "./home:/home/#{$project_name}_user"
        ],
        "environment" => {
          "TZ" => "Asia/Makassar",
          "REDIS_URL" => "redis://redis:6379/1"
        },
        "depends_on" => [ "db" ],
        "networks" => { $project_name + "_net" => { "ipv4_address" => $net_app_ip.to_s } },
      },
      "web" => {
        "image" => "nginx:latest",
        "container_name" => $project_name + "-web",
        "build" => {
          "args" => {
            "hostname" => $host_name
          },
          "context" => "./",
          "dockerfile" => "Dockerfile-web"
        },
        "restart" => "unless-stopped",
        "volumes" => [
          "./:/var/www",
          "./docker-compose/nginx:/etc/nginx/conf.d/"
        ],
        "depends_on" => [ "app" ],
        "networks" => { $project_name + "_net" => { "ipv4_address" => $net_web_ip.to_s } },
      },
      "redis" => {
        "image" => "redis:latest",
        "container_name" => $project_name + "-redis",
        "networks" => { $project_name + "_net" => { "ipv4_address" => $net_redis_ip.to_s } },
      },
      "phpmyadmin" => {
        "image" => "phpmyadmin:latest",
        "container_name" => $project_name + "-phpmyadmin",
        "environment" => {
          "PMA_HOST" => "db",
          "PMA_PORT" => 3306,
          "PMA_ARBITRARY" => 1,
          "PMA_USER" => $db_user,
          "PMA_PASSWORD" => $db_user_pw,
          "PMA_ABSOLUTE_URI" => "http://app/phpmyadmin/"
        },
        "restart" => "always",
        "depends_on" => [ "db" ],
        "networks" => { $project_name + "_net" => { "ipv4_address" => $net_phpmyadmin_ip.to_s } },
      }
    },
    "networks" => {
      $project_name + "_net" => {
        "driver" => "bridge",
        "ipam" => {
          "driver" => "default",
          "config" => [ { "subnet" => $network } ]
        }
      }
    },
    "volumes" => {
      "db" => {
        "driver" => "local"
      }
    }
  }

  File.write "docker-compose.yml", compose.to_yaml.sub("---\n", "")
end

# generate and write hosts entry
def update_hosts_file
  hosts_line = "%-15s %s # Docker Project %s" % [$net_web_ip.to_s, $host_name, $project_name]
  if Process.euid == 0
    hosts_content = File.read("/etc/hosts").split("\n")
    if line = hosts_content.find{|line| line.include? /# Docker Project #{$project_name}$/}
      line.replace hosts_line
    else
      hosts_content << hosts_line + "\n"
    end
    File.write("/etc/hosts", hosts_content.join("\n"))
  else
    puts "No root access, manually add to /etc/hosts:\n#{hosts_line}".red
  end
end

def db_init
  if File.exist?("./database/mysql")
    puts "Skipping database initialization as database is already present".red
    return
  end

  #create dbinit
  db_init_sql = <<~DBINIT_END
    CREATE USER '#{$db_user}' IDENTIFIED BY '#{$db_user_pw}';
    CREATE USER '#{$db_prod_user}' IDENTIFIED BY '#{$db_prod_user_pw}';
    CREATE USER '#{$db_user}'@'localhost' IDENTIFIED BY '#{$db_user_pw}';
    CREATE USER '#{$db_prod_user}'@'localhost' IDENTIFIED BY '#{$db_prod_user_pw}';
    CREATE DATABASE #{$db_name}_development;
    CREATE DATABASE #{$db_name}_test;
    CREATE DATABASE #{$db_name}_production;
    GRANT ALL PRIVILEGES ON #{$db_name}_development.* TO #{$db_user};
    GRANT ALL PRIVILEGES ON #{$db_name}_test.* TO #{$db_user};
    GRANT ALL PRIVILEGES ON #{$db_name}_production.* TO #{$db_prod_user};
    GRANT ALL PRIVILEGES ON #{$db_name}_development.* TO #{$db_user}@'localhost';
    GRANT ALL PRIVILEGES ON #{$db_name}_test.* TO #{$db_user}@'localhost';
    GRANT ALL PRIVILEGES ON #{$db_name}_production.* TO #{$db_prod_user}@'localhost';
    FLUSH PRIVILEGES;
  DBINIT_END

  FileUtils.mkdir_p("database")
  FileUtils.mkdir_p("db-init")
  File.write("db-init/db-init.sql", db_init_sql)

  puts "Initializing Database"
  running_container "db", "MariaDB init process done. Ready for start up.",
      compose_options: %{-v "$(pwd)/db-init:/docker-entrypoint-initdb.d" -e "MARIADB_ROOT_PASSWORD=#$db_root_pw" -e "MARIADB_INITDB_SKIP_TZINFO=1"},
      container_name: "initdb"  do
    sleep 1 # be nice and let mysqld start up a second time
    puts "Database created"
  end
end

# Laravel Init
def laravel_init
  running_container %w[db app], "mariadb: ready for connections." do
    if File.exist?("webroot/app")
      system "docker compose exec -T app composer install"
    else
      install_laravel
    end
    laravel_create_env
    laravel_dbseed
  end
end

def install_laravel
  file_content = File.read("env/laravel_new_commands.sh")
  file_content.sub!(/## laravel version ##/, ($laravel_version.nil? ? " " : ":#{$laravel_version} "))
  File.write("env/laravel_new_commands.sh", file_content)
  system "docker compose exec -T app bash < env/laravel_new_commands.sh"
  File.write("webroot/.gitignore", "\n/config/database*\n", mode: "a")
end

def laravel_create_env
  if File.exist?("webroot/.env")
    FileUtils.cp("webroot/.env", "webroot/.env.#{Time.now.strftime("%Y-%m-%d")}")
  elsif File.exist?("webroot/.env.example")
    FileUtils.cp("webroot/.env.example", "webroot/.env")
  end

  laravel_env = File.read("webroot/.env").split("\n").map do |config|
    var = config.split("=")
    case var[0]
    when "APP_NAME"
      "#{var[0]}=\"#{$project_name}\""
    when "APP_URL"
      "#{var[0]}=http://#{$net_web_ip.to_s}"
    when "DB_CONNECTION"
      "#{var[0]}=mysql"
    when "DB_HOST"
      "#{var[0]}=#{$net_db_ip}"
    when "DB_PORT"
      "#{var[0]}=3306"
    when "DB_DATABASE"
      "#{var[0]}=#{$db_name}_development"
    when "DB_USERNAME"
      "#{var[0]}=#{$db_user}"
    when "DB_PASSWORD"
      "#{var[0]}=#{$db_user_pw}"
    when "REDIS_HOST"
      "#{var[0]}=#{$net_redis_ip.to_s}"
    else
      config
    end
  end.join("\n")

  File.write "webroot/.env", laravel_env
end

def laravel_dbseed
  system "docker compose exec app php artisan migrate:fresh"
end

## MAIN ##

if RbConfig::CONFIG['host_os'] =~ /linux/ && `groups` !~ /\bdocker\b/ && Process.euid != 0
  abort "Must be docker superuser!"
end

if File.exist?("docker-compose.yml")
  abort "A docker-compose file exists. Is setup really needed?"
end

$user_id =
  if Process.uid == 0
    File.stat(__FILE__).uid
  else
    Process.uid
  end

FileUtils.mkdir("webroot") unless File.exist?("webroot")
FileUtils.chown($user_id, nil, "webroot") if Process.uid == 0
FileUtils.mkdir("database") unless File.exist?("database")
FileUtils.chown($user_id, nil, "database") if Process.uid == 0

create_docker_files
create_compose_file
system "docker compose build"

db_init
laravel_init

puts "setup finished, you may now start docker by running: 'docker compose up'".yellow
puts "Access server by: #{$forwarded_port \
                          ? "http://localhost:#{$forwarded_port} or https://localhost:#{$forwarded_port+1}" \
                          : "http://#{$net_web_ip} or https://#{$net_web_ip}" }".yellow
update_hosts_file unless $forwarded_port
