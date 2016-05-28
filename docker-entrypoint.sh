#!/bin/bash

set -e

if [ "$1" = 'teamcity-server' ]; then
  SCRIPT=./bin/$1.sh

  shutdown() {
    local signal=$1
    local pid=$2

    echo Received $signal, sending TERM to PID $pid.
    pkill -TERM -P $pid
  }

  # More information: http://veithen.github.io/2014/11/16/sigterm-propagation.html
  trap 'shutdown INT  $PID' INT   # Ctrl + C.
  trap 'shutdown TERM $PID' TERM  # docker stop graceful shutdown.

  shift
  "$SCRIPT" "$@" &
  PID=$!

  echo Started with PID $PID, waiting for exit signal.
  wait $PID

  trap - INT TERM

  wait $PID
  exit $?
fi

exec "$@"
