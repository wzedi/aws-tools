#! /bin/bash

#
# An EC2 Cron Locking script.
#
# This script locks on a specific EC2 instance tag.
# Requires:
# 1. AWS CLI installed
# 2. ec2:CreateTags, ec2:DeleteTags and ec2:DescribeInstances permissions.
#
# As the number of servers running this script increases so does the likelihood
#   that the cron will never execute. MAX_ATTEMPTS should be increased as the
#   number of instances increases.
#

# Find the AWS CLI executable
AWS_EXEC=$(which aws)
[[ -z $AWS_EXEC ]] && PATH=$PATH:/usr/local/bin && AWS_EXEC=$(which aws)

# Instance ID as reported by EC2 metadata
INSTANCE_ID=$(curl -s -S http://169.254.169.254/latest/meta-data/instance-id)

# The AWS region derived from the availability zone metadata
AVAILABILITY_ZONE=$(curl -s -S http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=${AVAILABILITY_ZONE%?}

# The code for the EC2 running state
EC2_RUNNING_STATE_CODE=16

# The number of minutes before a lock is deemed to have expired
LOCK_AGE_THRESHOLD=120

# Current timestamp
TIMESTAMP=$(date +%s)

# Collection of existing locks
CRON_LOCKS=()

# Number of attempts and maximum number of attempts
ATTEMPTS=0
MAX_ATTEMPTS=3

# The command to run if the lock is established, this is arg 1
[[ -z $1 ]] && CRON_COMMAND="logger 'Running cron'" || CRON_COMMAND=$1

# The EC2 tag key to use for the lock, uses arg 2 if provided, defaults to EC2_CRON_LOCK
[[ -z $2 ]] && LOCK_TAG_KEY=EC2_CRON_LOCK || LOCK_TAG_KEY=$2

# Get list of running instances with a cron lock claim
query () {
  CRON_LOCKS=()
  # Execute describe instances
  DESCRIBE_INSTANCES=$($AWS_EXEC ec2 describe-instances --region ap-southeast-2 --output text --filters "Name=tag-key,Values='$LOCK_TAG_KEY'" "Name=instance-state-code,Values=$EC2_RUNNING_STATE_CODE" --query "Reservations[*].Instances[*].[Tags[?Key=='$LOCK_TAG_KEY'].Value]")
  # Split the response into an array
  PIECES=(${DESCRIBE_INSTANCES//\s/ })

  # Iterate over the array to find locks that have not yet expired
  for i in "${PIECES[@]}"; do
    LOCK_AGE=$(($TIMESTAMP-$i))
    [[ "$LOCK_AGE" -lt "$LOCK_AGE_THRESHOLD" ]] && log "Adding $LOCK_AGE" && CRON_LOCKS+=($LOCK_AGE)
  done
}

# Stake a cron lock claim
claim () {
  # Add the cron lock tag with the current timestamp to the instance
  log "Claiming lock for $LOCK_TAG_KEY - attempt $ATTEMPTS"
  $AWS_EXEC ec2 create-tags --region $REGION --resources $INSTANCE_ID --tags "Key=$LOCK_TAG_KEY,Value=$(date +%s)"
}

# Release a cron lock
release () {
  # Remove the cron lock tag from the instance
  log "Releasing lock for $LOCK_TAG_KEY"
  $AWS_EXEC ec2 delete-tags --region $REGION --resources $INSTANCE_ID --tags "Key=$LOCK_TAG_KEY"
}

# Random pause
pause () {
  PAUSE_DURATION=$[ ( $RANDOM % 10 ) + 1 ]s
  log "Pausing before next claim for $PAUSE_DURATION seconds"
  sleep $PAUSE_DURATION
}

negotiate () {
  ## Release any existing locks for this instance
  release

  ## Obtain list of current locks
  query
  log "Found ${#CRON_LOCKS[@]} after release"
  if [[ "${#CRON_LOCKS[@]}" -eq "0" ]]; then
    ## if CRON_LOCKS is empty then claim, otherwise cancel, a lock has already been established by another instance
    claim

    ## Obtain list of current locks again to confirm this instance is the only lock
    query
    log "Found ${#CRON_LOCKS[@]} after claim"
    if [[ "${#CRON_LOCKS[@]}" -ne "1" ]]; then
      ## If CRON_LOCK count is not exactly 1 then release and try again
      log "Other claims found or my claim failed, releasing"
      release
      ATTEMPTS=$(($ATTEMPTS+1))
      if [[ "$ATTEMPTS" -le "$MAX_ATTEMPTS" ]]; then
        ## If max attempts has not been reached then try again, otherwise exit
        pause
        negotiate
      else
        log "Max attempts reached. Exiting." "warning"
      fi
    elif [[ "${#CRON_LOCKS[@]}" -eq "1" ]]; then
      ## If CRON_LOCK count is exactly 1 lock is established, run cron
      log "Running cron command."
      $($CRON_COMMAND)
    fi
  else
    log "Locks already established. Exiting"
  fi
}

log () {
  [[ -z "$2" ]] && LOG_PRIORITY=user.notice || LOG_PRIORITY=user.$2
  logger -t 'EC2 CRON LOCK' -i -p $LOG_PRIORITY "$1"
}

log "Starting EC2 CRON lock negotiation"
log "Instance ID: $INSTANCE_ID"
log "Region: $REGION"
[[ -z $AWS_EXEC ]] && log "Cannot find AWS CLI executable in $PATH. Exiting" "error" && exit
log "AWS CLI Path: $AWS_EXEC"
log "Command: $CRON_COMMAND"

negotiate
log "Done EC2 CRON lock negotiation"
