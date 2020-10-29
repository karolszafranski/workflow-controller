#!/usr/bin/env bash

# set -x
# printenv

GITHUB_TOKEN="$(security find-generic-password -a $USER -s ES_REVIEW_SQUIRREL_GITHUB_TOKEN -w)"

# git config --global user.email "rjs@eclipsesource.com"
# git config --global user.name "Robert Schmidt"

REPO_OWNER="tabris"
REPO_NAME="tabris-ios-review"

REMOTE="tb"
REMOTE_URL="ssh://git@github.com/${REPO_OWNER}/${REPO_NAME}.git"

EXECUTION_ID=$(date +%y%m%d%H%M)
# BRANCH_NAME="prefix_${EXECUTION_ID}"

# "refs/changes/68/20768/2" =>> "changes/68/20768/2"
BRANCH_NAME="${GERRIT_REFSPEC#refs/}"

WORKFLOW_ID="535074" # es/tabris-ios
WORKFLOW_ID="3000569" # tb/tabris-ios

HEAD_SHA="$(git rev-list HEAD | head -n 1)"

echo "Add remote \"${REMOTE}\":\"${REMOTE_URL}\""
git remote add "${REMOTE}" "${REMOTE_URL}"

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

RUN_ID=$(jq -r ".workflow_runs | map(select( .workflow_id == ${WORKFLOW_ID} )) | map(select( .head_sha == \"${HEAD_SHA}\" )) | sort_by( .run_number ) | .[-1] | .id" $RUNS_OUTPUT_JSON_FILE)
CHECK_SUITE_ID=$(jq -r ".workflow_runs | map(select( .workflow_id == ${WORKFLOW_ID} )) | map(select( .head_sha == \"${HEAD_SHA}\" )) | sort_by( .run_number ) | .[-1] | .check_suite_id" $RUNS_OUTPUT_JSON_FILE)

echo "You can observe the logs at: https://github.com/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}"

while sleep 5; do

	update_runs_json_file

	STATUS=$(jq -r ".workflow_runs | map(select( .workflow_id == ${WORKFLOW_ID} )) | map(select( .head_sha == \"${HEAD_SHA}\" )) | sort_by( .run_number ) | .[-1] | .status" $RUNS_OUTPUT_JSON_FILE)

	echo "$(date): check suite state: ${STATUS}"

	if [ "$STATUS" = "completed" ]; then
	  break;
	fi

done

git push $REMOTE --delete $BRANCH_NAME
# git branch --delete $BRANCH_NAME


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
curl -v -L -o archive.zip "$ARCHIVE_DOWNLOAD_URL?access_token=$GITHUB_TOKEN"

# arrange artifacts in the same way as they used to be when job was executed locally
mkdir artifacts
cd artifacts
mv ../archive.zip ./
unzip archive.zip
cd ..
cp -R artifacts/test-reports .
touch test-reports/Tabris_Test.xml # JUnitResultArchiver refuses to publish "old" results
## get artifacts - end

# finish with apropriate conclusion

CONCLUSION=$(jq -r ".workflow_runs | map(select( .workflow_id == ${WORKFLOW_ID} )) | map(select( .head_sha == \"${HEAD_SHA}\" )) | sort_by( .run_number ) | .[-1] |  .conclusion" $RUNS_OUTPUT_JSON_FILE)

echo "conclusion: ${CONCLUSION}"

if [ "$CONCLUSION" = "success" ]; then
	exit 0
fi

echo "Logs are available at: https://github.com/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}"

exit 1