#!/bin/bash
echo "Starting up Rails project"
rails_pid=
sidekiq_pid=

cd "$APP_HOME"

# function start_rails() {
#   rm -f tmp/pids/server.pid
#   bundle exec rails server -b 0.0.0.0 &
#   rails_pid=$!
# }

# function start_sidekiq() {
#   if [[ ! -f "$GEM_HOME/bin/sidekiq" ]]; then
#     return
#   fi
#   bundle exec sidekiq > >(tee log/sidekiq.log) &
#   sidekiq_pid=$!
# }

# function reload_services() {
#   echo "Restarting Rails project"
#   kill $rails_pid
#   start_rails

#   if [[ -n "$sidekiq_pid" ]]; then
#     echo "Restarting Sidekiq"
#     kill $sidekiq_pid
#     start_sidekiq
#   fi
# }

# trap reload_services SIGUSR1
# start_rails
# start_sidekiq

while true
do
  tail -f /dev/null & wait $!
done
