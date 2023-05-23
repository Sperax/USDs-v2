#!/usr/bin/env bash
LC_ALL=C

local_branch="$(git rev-parse --abbrev-ref HEAD)"

valid_branch_regex="^(main|dev|(feat|wip|test|(bug|hot)fix)(\/[a-zA-Z0-9]+([-][a-zA-Z0-9]+)*){1,2}|release\/[0-9]+(\.[0-9]+)*(-(alpha|beta|rc)[0$

message="Invalid branch name, please follow: $valid_branch_regex and try again."

if [[ ! $local_branch =~ $valid_branch_regex ]]
then
    echo "$message"
    exit 1
fi

exit 0