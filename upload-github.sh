#!/usr/bin/env bash
#
# Author: Stefan Buck
# License: MIT
# https://gist.github.com/stefanbuck/ce788fee19ab6eb0b4447a85fc99f447
#
#
# This script accepts the following parameters:
#
# * owner
# * repo
# * tag
# * filename
# * github_api_token
#
# Script to upload a release asset using the GitHub API v3.
#
# Example:
#
# upload-github-release-asset.sh github_api_token=TOKEN owner=stefanbuck repo=playground tag=v0.1.0 filename=./build.zip
#

# {"url":"https://api.github.com/repos/DroidFreak32/OTA/releases/assets/149198505","id":149198505,"node_id":"RA_kwDOBUc0xc4I5Jap","name":"lineage-20.0-20240201-UNOFFICIAL-kebab.zip","label":"","uploader":{"login":"DroidFreak32","id":23462457,"node_id":"MDQ6VXNlcjIzNDYyNDU3","avatar_url":"https://avatars.githubusercontent.com/u/23462457?v=4","gravatar_id":"","url":"https://api.github.com/users/DroidFreak32","html_url":"https://github.com/DroidFreak32","followers_url":"https://api.github.com/users/DroidFreak32/followers","following_url":"https://api.github.com/users/DroidFreak32/following{/other_user}","gists_url":"https://api.github.com/users/DroidFreak32/gists{/gist_id}","starred_url":"https://api.github.com/users/DroidFreak32/starred{/owner}{/repo}","subscriptions_url":"https://api.github.com/users/DroidFreak32/subscriptions","organizations_url":"https://api.github.com/users/DroidFreak32/orgs","repos_url":"https://api.github.com/users/DroidFreak32/repos","events_url":"https://api.github.com/users/DroidFreak32/events{/privacy}","received_events_url":"https://api.github.com/users/DroidFreak32/received_events","type":"User","site_admin":false},"content_type":"application/octet-stream","state":"uploaded","size":1073598149,"download_count":0,"created_at":"2024-02-01T16:00:12Z","updated_at":"2024-02-01T16:01:45Z","browser_download_url":"https://github.com/DroidFreak32/OTA/releases/download/lineage-kebab/lineage-20.0-20240201-UNOFFICIAL-kebab.zip"}

# Fallback for env variables
[[ -z "$GITHUB_UPLOAD_API_TOKEN" ]] && export GITHUB_UPLOAD_API_TOKEN=$(pass env/GITHUB_UPLOAD_API_TOKEN)
[[ -z "$owner" ]] && export owner=DroidFreak32
[[ -z "$repo" ]] && export repo=OTA
[[ -z $tag ]] && export tag="lineage-kebab"

export filename="$@"
echo "Initializing upload for $filename"

# echo $GITHUB_UPLOAD_API_TOKEN $owner $repo $tag $filename

# exit


# Check dependencies.
set -e
xargs=$(which gxargs || which xargs)

# Validate settings.
[ "$TRACE" ] && set -x

# CONFIG=$@

# for line in $CONFIG; do
#   eval "$line"
# done

# Define variables.
GH_API="https://api.github.com"
GH_REPO="$GH_API/repos/$owner/$repo"
GH_TAGS="$GH_REPO/releases/tags/$tag"
AUTH="Authorization: token $GITHUB_UPLOAD_API_TOKEN"
WGET_ARGS="--content-disposition --auth-no-challenge --no-cookie"
CURL_ARGS="-LJO#"

if [[ "$tag" == 'LATEST' ]]; then
  GH_TAGS="$GH_REPO/releases/latest"
fi

# Validate token.
curl -o /dev/null -sH "$AUTH" $GH_REPO || { echo "Error: Invalid repo, token or network issue!";  exit 1; }

# Read asset tags.

echo "Running curl -sH \"$AUTH\" $GH_TAGS"
response=$(curl -sH "$AUTH" $GH_TAGS)

# Get ID of the release.
eval $(echo "$response" | grep -m 1 "id.:" | grep -w id | tr : = | tr -cd '[[:alnum:]]=')
[ "$id" ] || { echo "Error: Failed to get release id for tag: $tag"; echo "$response" | awk 'length($0)<100' >&2; exit 1; }
release_id="$id"

# ------New Code starts Here------
# Get ID of the asset based on given filename.
id=""
for row in $(echo $response | jq '.assets | map({name: .name, id: .id})' | jq -c '.[]'); do
  name=$(echo ${row} | jq -r '.name')
  if [ $name == $(basename $filename) ]; then
    asset_id=$(echo ${row} | jq -r '.id')
    echo "Deleting asset($asset_id)... "
    DELETE_URL="https://api.github.com/repos/${owner}/${repo}/releases/assets/${asset_id}"
    curl  -X "DELETE" -H "Authorization: token $GITHUB_UPLOAD_API_TOKEN" "${DELETE_URL}"
  fi
done

# Upload asset
echo "Uploading asset... "

# Construct url
GH_ASSET="https://uploads.github.com/repos/$owner/$repo/releases/$release_id/assets?name=$(basename $filename)"
echo $GH_ASSET
echo "----"

#echo curl "$GITHUB_OAUTH_BASIC" --data-binary @"$filename" -H "Authorization: token $GITHUB_UPLOAD_API_TOKEN" -H "Content-Type: application/octet-stream" $GH_ASSET
curl --progress-bar "$GITHUB_OAUTH_BASIC" --data-binary @"$filename" -H "Authorization: token $GITHUB_UPLOAD_API_TOKEN" -H "Content-Type: application/octet-stream" $GH_ASSET > /tmp/upload.json

export DEVICE_JSON="$LINEAGE_BUILD.json"

cat > ~/OTA/"$DEVICE_JSON" << EOF
{
  "response": [
    {
      "datetime": $(date -r $filename +%s),
      "filename": "$(basename $filename)",
      "id": "$(cat $filename.sha256sum | cut -d' ' -f1)",
      "romtype": "unofficial",
      "size": $(jq ".size" /tmp/upload.json),
      "url": $(jq ".browser_download_url" /tmp/upload.json),
      "version": "20.0"
    }
  ]
}
EOF
cat ~/OTA/"$DEVICE_JSON"
