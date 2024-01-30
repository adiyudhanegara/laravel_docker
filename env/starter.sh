#!/bin/bash
echo "Starting up Laravel project"
laravel_pid=

cd "$APP_HOME"

function start_laravel() {
  rm -f tmp/pids/server.pid
  php artisan serve --host=0.0.0.0 --port=3000 &
  laravel_pid=$!
}

function reload_services() {
  echo "Restarting Laravel project"
  kill $laravel_pid
  start_laravel
}

trap reload_services SIGUSR1
start_laravel

while true
do
  tail -f /dev/null & wait $!
done
