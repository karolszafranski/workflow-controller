#!/usr/bin/env bash

if [ -n "$DEBUG" ]; then
	set -x
	printenv
fi

########################################################################
# Job configuration and variables/constants definitions                #
########################################################################

# Github Token needs to be stored in macOS keychain on the node which
# executes this script
GITHUB_TOKEN="$(security find-generic-password -a $USER -s ES_REVIEW_SQUIRREL_GITHUB_TOKEN -w)"


# git config --global user.email "rjs@eclipsesource.com"
# git config --global user.name "Robert Schmidt"

# repository where actions should be executed
# https://github.com/tabris/tabris-ios-review
REPO_OWNER="tabris"
REPO_NAME="tabris-ios-review"


REMOTE="tb"
REMOTE_URL="ssh://git@github.com/${REPO_OWNER}/${REPO_NAME}.git"

EXECUTION_ID=$(date +%y%m%d%H%M)

# instead of a timestamp with a prefix...
# BRANCH_NAME="prefix_${EXECUTION_ID}"

# create a branch name basing on a reference given by Gerrit
# first component of the name ("refs/") needs to be removed from the
# name to make it work:
# "refs/changes/68/20768/2" =>> "changes/68/20768/2"
BRANCH_NAME="${GERRIT_REFSPEC#refs/}"

# identifier of a workflow which executes tests
# this was retrieved by manually executing rest github api calls and
# going through returned data
# WORKFLOW_ID="535074" # test.yaml identifier in eclipsesource/tabris-ios
WORKFLOW_ID="3000569"  # test.yaml identifier in tabris/tabris-ios-review

HEAD_SHA="$(git rev-list HEAD | head -n 1)"

SLEEP_INTERVAL=30

# file where workflow run status will be stored
RUNS_OUTPUT_JSON_FILE="output.json"

# function which updates the file with current workflow state
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

########################################################################
# Execute tests                                                        #
########################################################################

echo "Add remote \"${REMOTE_URL}\" aliased as \"${REMOTE}\""
git remote add "${REMOTE}" "${REMOTE_URL}"

echo "Create branch \"${BRANCH_NAME}\""
git checkout -b $BRANCH_NAME

echo "Push branch \"${BRANCH_NAME}\" to \"${REMOTE}\" remote"
git push --set-upstream "${REMOTE}" "${BRANCH_NAME}"

SCHEDULING_DELAY=15
echo "Waiting ${SCHEDULING_DELAY} seconds, for the workflow to be scheduled..."
sleep ${SCHEDULING_DELAY}

update_runs_json_file

RUN_ID=$(jq -r ".workflow_runs | map(select( .workflow_id == ${WORKFLOW_ID} )) | map(select( .head_sha == \"${HEAD_SHA}\" )) | sort_by( .run_number ) | .[-1] | .id" $RUNS_OUTPUT_JSON_FILE)

echo "Github workflow run identifier: ${RUN_ID}"
echo "You can observe the logs at: https://github.com/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}"

while sleep $SLEEP_INTERVAL; do

	update_runs_json_file

	STATUS=$(jq -r ".workflow_runs | map(select( .workflow_id == ${WORKFLOW_ID} )) | map(select( .head_sha == \"${HEAD_SHA}\" )) | sort_by( .run_number ) | .[-1] | .status" $RUNS_OUTPUT_JSON_FILE)

	echo "check suite state: ${STATUS} ($(date))"

	if [ "$STATUS" = "completed" ]; then
	  break;
	fi

done


echo "Removing \"${BRANCH_NAME}\" branch from \"${REMOTE}\" remote..."
git push $REMOTE --delete $BRANCH_NAME
# git branch --delete $BRANCH_NAME


########################################################################
# Get artifcats                                                        #
########################################################################

echo "Downloading artifacts..."
## get artifacts
ARTIFACTS_OUTPUT_JSON_FILE="artifacts-output.json"
curl \
	--silent \
	--location \
	--request GET \
	--header 'Accept: application/vnd.github.everest-preview+json' \
	--header 'Content-Type: application/json' \
	--header "Authorization: token $GITHUB_TOKEN" \
	--header 'cache-control: no-cache' \
	"https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}/artifacts" > $ARTIFACTS_OUTPUT_JSON_FILE

ARCHIVE_DOWNLOAD_URL=$(jq -r ".artifacts | map(select( .name == \"artifacts\" )) | .[] | .archive_download_url" $ARTIFACTS_OUTPUT_JSON_FILE)
curl -v -L -H "Authorization: token ${GITHUB_TOKEN}" -o archive.zip "$ARCHIVE_DOWNLOAD_URL"

# arrange artifacts in the same way as they used to be when unit tests are
# executed locally
mkdir artifacts
cd artifacts
mv ../archive.zip ./
unzip -q archive.zip # -q stands for quiet
cd ..
cp -R artifacts/test-reports .
# JUnitResultArchiver refuses to publish "old" results so we update modification
# time with `touch`
touch test-reports/Tabris_Test.xml
## get artifacts - end


########################################################################
# Exit                                                                 #
########################################################################

# depending on the status of the job on the remote this script will either exit
# with successful or non-successful error code

CONCLUSION=$(jq -r ".workflow_runs | map(select( .workflow_id == ${WORKFLOW_ID} )) | map(select( .head_sha == \"${HEAD_SHA}\" )) | sort_by( .run_number ) | .[-1] |  .conclusion" $RUNS_OUTPUT_JSON_FILE)

echo "Conclusion: ${CONCLUSION}"

if [ "$CONCLUSION" = "success" ]; then
	exit 0
fi

echo "Logs are available at: https://github.com/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}"

exit 1