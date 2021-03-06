#!/bin/sh

if test "$#" -ne 4; then
  echo "Usage: $0 DESTINATION URL GITBRANCH HASH"
  exit 1
fi
DEST=$1
URL=$2
GITBRANCH=$3
REVISION=$4

GIT_VERSION=`git --version | grep -o "[0-9.]*"`
GIT_MAJOR=`echo $GIT_VERSION | cut -d. -f1`
GIT_MINOR=`echo $GIT_VERSION | cut -d. -f2`

if test "$GIT_MAJOR" -gt 1 || (test "$GIT_MAJOR" = 1 && test "$GIT_MINOR" -gt 7); then
  SINGLE_BRANCH="--single-branch"
else
  SINGLE_BRANCH=""
fi

if test -d "$DEST"; then
  # Clean out any old mess
  (cd "$DEST" && git reset --hard)
  (cd "$DEST" && git clean -f)
  (cd "$DEST" && git checkout -q "$REVISION" || git fetch --tags -fq "$URL" "$GITBRANCH" || (sleep 10 && git fetch --tags -fq "$URL" "$GITBRANCH") || (sleep 20 && git fetch --tags -fq "$URL" "$GITBRANCH")) || rm -rf "$DEST"
fi
if ! test -d "$DEST"; then
  echo "[$DEST] does not exist: cloning [$URL]"
  (git clone --branch "$GITBRANCH" $SINGLE_BRANCH "$URL" "$DEST" || (sleep 10 && git clone --branch "$GITBRANCH" $SINGLE_BRANCH "$URL" "$DEST") || (sleep 30 && git clone --branch "$GITBRANCH" $SINGLE_BRANCH "$URL" "$DEST")) || exit 1
  # In case of CRLF properties, etc
  (cd "$DEST" && git reset --hard)
  (cd "$DEST" && git clean -fdx)
fi

if ! (cd "$DEST" && git checkout -f "$REVISION" ); then
  echo "Failed: $0 $*"
  exit 1
fi

(cd "$DEST" && git reset --hard)
(cd "$DEST" && git clean -fdx)

echo "$REVISION" > "$DEST.rev"
