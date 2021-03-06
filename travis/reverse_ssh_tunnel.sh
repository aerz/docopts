#!/usr/bin/env bash

set -euo pipefail

# Usage: a bounce host must be set before
# ansible playbook not provided yet.

# The IP here is a temporay public cloud VM
# You need to edit that IP
BOUNCEHOSTIP="51.83.248.111"

# Where to store localy the remote bounce host ssh key
TEMP_SSH_KEYS=/tmp/$USER-bounce-travis/id_rsa

fail_if_empty()
{
  local varname
  local v
  # allow multiple check on the same line
  for varname in $*
  do
    eval "v=\$$varname"
    if [[ -z "$v" ]] ; then
      echo "error: $varname empty or unset at ${BASH_SOURCE[1]}:${FUNCNAME[1]} line ${BASH_LINENO[0]}"
      exit 1
    fi
  done
}

fetch_ssh_keys()
{
  local tmp_ssh_dir=$(dirname $TEMP_SSH_KEYS)
  mkdir -p $tmp_ssh_dir
  wget -O $TEMP_SSH_KEYS http://$BOUNCEHOSTIP/id_rsa
  wget -O ${TEMP_SSH_KEYS}.pub http://$BOUNCEHOSTIP/id_rsa.pub
  chmod 600 $tmp_ssh_dir/*
}

cleanup()
{
  local tmp_ssh_dir=$(dirname $TEMP_SSH_KEYS)
  rm -rf $tmp_ssh_dir
  kill $SSH_AGENT_PID
}

bounce_host_remote_exec()
{
  NOOP_DELAY=30
  # 30 minutes
  MAX=$((30*60))
  echo 'bounce host connected'

  # generate the stop command
  echo 'pkill -f bounce_host_remote_exec; pkill -f sleep' > disconnect
  chmod a+x disconnect

  # message when disconnect kill is sent
  trap "echo 'bounce_host existing'; kill -9 $$" QUIT TERM EXIT

  local start=$SECONDS
  local elapsed
  while true
  do
      sleep $NOOP_DELAY
      elapsed=$(($SECONDS-$start))
      echo "noop ${elapsed}s"
      if [[ $elapsed -gt $MAX ]] ; then
        echo "timeout reached ${MAX}s"
        break
      fi
  done
  echo "bounce_host connection closed"
}

################################################ main

fail_if_empty BOUNCEHOSTIP TEMP_SSH_KEYS
fetch_ssh_keys

# start ssh agent and add the private key
eval $(ssh-agent)
trap "cleanup" QUIT TERM EXIT
ssh-add $TEMP_SSH_KEYS

# allow ssh back to us with the same key
mkdir -p $HOME/.ssh
chmod 700 $HOME/.ssh
cp $TEMP_SSH_KEYS.pub $HOME/.ssh/authorized_keys
chmod 600 $HOME/.ssh/authorized_keys

# for 10 min without output Success
# https://travis-ci.org/Sylvain303/docopts/builds/540455090#L1295
ssh -R 9999:localhost:22 \
  -o StrictHostKeyChecking=no travis@$BOUNCEHOSTIP \
  "$(typeset -f bounce_host_remote_exec); bounce_host_remote_exec"
