#!/bin/bash
while true
do
  FOO=$(expr $(expr $(date +%s) - $(stat -f %a best_step)) / 60)
  if [ $FOO -gt 80]; then
    killall -9 luajit
  fi
  sleep 10
done