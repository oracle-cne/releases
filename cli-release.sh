#! /bin/bash

BASE="$1"
HEAD="$2"
TOKEN_FILE="$3"

OWNER=oracle-cne
GH=https://api.github.com/repos/$OWNER
REPO=ocne
TOKEN=$(cat "$TOKEN_FILE")
IMAGE=localhost/ocne-release:latest

SPEC_PATH='buildrpm/ocne.spec'

gh() {
API="$1"
curl -s -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  $GH/$REPO/$API
}

pull_requests() {
	gh 'pulls?state=closed'
}

commits() {
	PR="$1"
	gh "pulls/$PR/commits"
}

commits_between() {
	B="$1"
	H="$2"
	gh "compare/${B}...${H}"
}

prs_for() {
	COMMIT="$1"
	gh "commits/$COMMIT/pulls"
}

issues() {
	QUERY=$(cat << EOF
{
  repository(owner: "$OWNER", name: "$REPO") {
    issues(states: CLOSED, last: 100) {
      nodes {
        number
        title
        linkedBranches(first: 10) {
          nodes {
            ref {
              associatedPullRequests {
                nodes {
                  number
                }
              }
            }
          }
        }
        closedByPullRequestsReferences(first: 10) {
          nodes {
            number
          }
        }
      }
    }
  }
}
EOF
)

	FORMATTED=$(echo "{}" | jq --arg query "$QUERY" '{"query": $query}')

	curl -s -X POST https://api.github.com/graphql \
		-H "Authorization: Bearer $TOKEN" \
		-d "$FORMATTED" | jq '.data.repository.issues.nodes'
}

get_file() {
	REF="$1"
	FILE_PATH="$2"

	gh "contents/${FILE_PATH}?ref=${REF}" | jq -r '.content' | base64 -d
}

latest_version() {
	REF="$1"
	FILE_PATH="$2"

	SPEC=$(get_file "$REF" "$FILE_PATH")

	CHANGELOG=$(echo "$SPEC" | grep -A 10 -e '^%changelog')
	ENTRY=$(echo "$CHANGELOG" | grep -e '\* .* - [0-9.-]*$' | head -1)
	VERSION=$(echo "$ENTRY" | grep -o -e '[0-9.-]*$')
	DASHES=$(echo "ocne-${VERSION}" | grep -o -e '-' | tr -d '\n' | wc -m)

	if [ "$DASHES" == 1 ]; then
		echo "$VERSION-1"
		return
	fi
	echo "$VERSION"
}

catalog() {
	VERSION="$1"

	APPS=$(podman run --rm -ti --entrypoint "/${VERSION}/usr/bin/ocne" "$IMAGE" catalog search --name embedded | tail -n +2 | tr '\t' ' ' | tr -s ' ' | cut -d' ' -f1,2 | sort)
	echo "$APPS"


}

# Get specfiles to get RPM versions
BASE_VERSION=$(latest_version "$BASE" "$SPEC_PATH")
HEAD_VERSION=$(latest_version "$HEAD" "$SPEC_PATH")

podman build --build-arg BASE_VERSION=$BASE_VERSION --build-arg HEAD_VERSION=$HEAD_VERSION -t "$IMAGE" ./cli-release

BASE_APPS=$(catalog "$BASE_VERSION")
HEAD_APPS=$(catalog "$HEAD_VERSION")

NEW_APPS=$(diff <(echo "$BASE_APPS") <(echo "$HEAD_APPS") | grep '^> ' | sed 's/^> //')

# Map issues to PRs

declare -A PR_TO_ISSUE
declare -A ISSUE_TO_TITLE
ISSUES_RESP=$(issues)

ISSUE_MAP=$(echo "$ISSUES_RESP" | jq -r '.[] | "\(.number)=\(.closedByPullRequestsReferences.nodes[].number)"')

for im in $ISSUE_MAP; do
	ISSUE=$(echo "$im" | cut -d= -f1)
	PR=$(echo "$im" | cut -d= -f2)
	PR_TO_ISSUE[$PR]=$ISSUE

	if [ -z "$PR" ]; then
		continue
	fi
	TITLE=$(echo "$ISSUES_RESP" | jq -r ".[] | select(.number==$ISSUE) | .title")
	ISSUE_TO_TITLE[$ISSUE]=$TITLE
done

COMMITS=$(commits_between "$BASE" "$HEAD" | jq -r '.commits[].sha')

declare -A PRS_TO_BRANCH
declare -A COMMITS_TO_PR
for commit in $COMMITS; do
	PRS_FOR_COMMIT=$(prs_for "$commit" | jq -r '.[] | "\(.number)=\(.head.ref)"')
	for pr in $PRS_FOR_COMMIT; do
		PR_NUM=$(echo "$PRS_FOR_COMMIT" | cut -d= -f1)
		BRANCH=$(echo "$PRS_FOR_COMMIT" | cut -d= -f2)
		PRS_TO_BRANCH[$PR_NUM]=$BRANCH
		COMMITS_TO_PR[$commit]=$PR_NUM
	done
done

# Start printing out new stuff

echo
echo
echo
echo "-----------Release Description---------"
echo
echo
echo

if [ -n "$NEW_APPS" ]; then
	echo "# New Applications"
	echo
	echo "$NEW_APPS"
	echo
fi

echo "# Issues"
echo
declare -A VISITED
declare -A UNLINKED
for commit in ${!COMMITS_TO_PR[@]}; do
	PR_NUM=${COMMITS_TO_PR[$commit]}
	ISSUE_NUM=${PR_TO_ISSUE[$PR_NUM]}

	if [ -z "$ISSUE_NUM" ]; then
		UNLINKED[$PR_NUM]=1
		continue
	fi

	if [[ -v VISITED[$ISSUE_NUM] ]]; then
		continue
	fi

	TITLE="${ISSUE_TO_TITLE[$ISSUE_NUM]}"
	VISITED[$ISSUE_NUM]=1
	echo "[#${ISSUE_NUM}] ${TITLE}"
done

echo
echo
echo
echo "-----Exceptions-----"

for unlinked in ${!UNLINKED[@]}; do
	echo "$unlinked has no linked issue"
done
