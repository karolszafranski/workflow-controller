#!/usr/bin/env bash

# set -x

GITHUB_TOKEN="$(gopass show ks/github-token/karolszafranski@gmail.com)"

# git config --global user.email "rjs@eclipsesource.com"
# git config --global user.name "Robert Schmidt"

REMOTE="tb"
EXECUTION_ID=$(date +%y%m%d%H%M)
BRANCH_NAME="prefix_${EXECUTION_ID}"

REPO_OWNER="tabris"
REPO_NAME="tabris-ios"

WORKFLOW_ID="535074"
HEAD_SHA="$(git rev-list HEAD | head -n 1)"

echo "Create branch \"${BRANCH_NAME}\""
git checkout -b $BRANCH_NAME

echo "Push branch \"${BRANCH_NAME}\" to \"${REMOTE}\" remote"
git push --set-upstream "${REMOTE}" "${BRANCH_NAME}"

sleep 5

RUNS_OUTPUT_JSON_FILE="output.json"

function update_runs_json_file {
	curl \
	--silent \
	--location \
	--request GET \
	--header 'Accept: application/vnd.github.everest-preview+json' \
	--header 'Content-Type: application/json' \
	--header "Authorization: token $GITHUB_TOKEN" \
	--header 'cache-control: no-cache' \
	"https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?branch=${BRANCH_NAME}" > $RUNS_OUTPUT_JSON_FILE
}

update_runs_json_file

RUN_ID=$(jq -r ".workflow_runs[] | select( .head_sha == \"${HEAD_SHA}\" ) | select( .workflow_id == ${WORKFLOW_ID} ) | .id" $RUNS_OUTPUT_JSON_FILE)

echo "You can observe the logs at: https://github.com/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}"

while sleep 5; do

	update_runs_json_file

	STATUS=$(jq -r ".workflow_runs[] | select( .head_sha == \"${HEAD_SHA}\" ) | select( .workflow_id == ${WORKFLOW_ID} ) | .status" $RUNS_OUTPUT_JSON_FILE)

	echo "$(date): check suite state: ${STATUS}"

	if [ "$STATUS" = "completed" ]; then
	  break;
	fi

done

git push $REMOTE --delete $BRANCH_NAME
# git branch --delete $BRANCH_NAME


CONCLUSION=$(jq -r ".workflow_runs[] | select( .head_sha == \"${HEAD_SHA}\" ) | select( .workflow_id == ${WORKFLOW_ID} ) | .conclusion" $RUNS_OUTPUT_JSON_FILE)

echo "conclusion: ${CONCLUSION}"

if [ "$CONCLUSION" = "success" ]; then
	exit 0
fi

echo "Logs are available at: https://github.com/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}"

exit 1