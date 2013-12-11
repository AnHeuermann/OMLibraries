#!/bin/sh
BUILD=build/

ENCODING=UTF-8
STD=3.3
LICENSE=modelica2
SVNOPTS="--non-interactive --username anonymous"
OMC=omc
GITBRANCH=release
while echo $1 | grep -q "^--"; do
OPT="$1"
shift
case $OPT in
--omc)
  OMC="$1"
  shift
  ;;
--build-dir)
  BUILD="$1"
  shift
  ;;
--encoding)
  ENCODING="$1"
  shift
  ;;
--std)
  STD="$1"
  shift
  ;;
--license)
  LICENSE="$1"
  shift
  ;;
--breaks)
  BREAKS="$1"
  shift
  ;;
--patchlevel)
  PATCHLEVEL="$1"
  shift
  ;;
--gitbranch)
  GITBRANCH="$1"
  shift
  ;;
--no-package)
  # $1 will be a comment
  NOPACKAGE="$1"
  shift
  ;;
--remove-files)
  # Files that should be stripped from the package. Usually redundant binaries.
  REMOVE_FILES="$1"
  shift
  ;;
--automatic-updates)
  # Skip this; used in the python script
  shift
  ;;
*)
  echo "Unknown option $OPT"
  exit 1
  ;;
esac

done

if test $# -lt 5 || !(test "$1" = SVN || test "$1" = GIT); then
  echo "Usage: $0 [flags] [SVN|GIT] URL REVISION DEST [LIBRARIES]"
  echo "   --encoding=[UTF-8]"
  echo "   --std=[3.3]"
  exit 1
fi
TYPE="$1"
URL="$2"
REVISION="$3"
DEST="$4"
shift;shift;shift;shift

if test "$TYPE" = SVN; then

if ! test -d "$DEST"; then
  svn co $SVNOPTS "-r$REVISION" "$URL" "$DEST" || exit 1
  echo "$REVISION" > "$DEST.rev"
elif test -d "$DEST" && ! test "$URL" = "`svn info "$DEST" | grep ^URL: | sed "s/URL: //"`"; then
  echo "Not same URL... $URL and `svn info "$DEST" | grep ^URL: | sed "s/URL: //"`"
  rm -rf "$DEST"
  svn co $SVNOPTS "-r$REVISION" "$URL" "$DEST" || exit 1
  echo "$REVISION" > "$DEST.rev"
else
  if test `svn info $SVNOPTS --xml "$DEST" | xpath -q -e '/info/entry/commit/@revision' | grep -o "[0-9]*"` = "$REVISION"; then
    echo "$DEST is up to date"
  elif ! svn up $SVNOPTS "-r$REVISION" "$DEST"; then
    echo "Failed to update $DEST"
    rm -rf "$DEST"
    exit 1
  else
    # svn-clean is a nice extra; not needed
    svn-clean "$DEST" 2> /dev/null
  fi
  echo "$REVISION" > "$DEST.rev"
fi

elif test "$TYPE" = GIT; then

if test -d "$DEST"; then
  (cd "$DEST" && git checkout -q "$REVISION" || git fetch -q "$URL" origin "$GITBRANCH" || (sleep 10 && git fetch -q "$URL" origin "$GITBRANCH") || (sleep 20 && git fetch -q "$URL" origin "$GITBRANCH")) || rm -rf "$DEST"
fi
if ! test -d "$DEST"; then
  echo "[$DEST] does not exist: cloning [$URL]"
  (git clone "$URL" "$DEST" || (sleep 10 && git clone "$URL" "$DEST") || (sleep 30 && git clone "$URL" "$DEST")) || exit 1
fi
if ! (cd "$DEST" && git checkout "$REVISION" ); then
  exit 1
fi
echo "$REVISION" > "$DEST.rev"

else
  echo "Unknown repository type: $TYPE" >&2
  exit 1
fi

mkdir -p "$BUILD"
if test "$*" = "all"; then
 shift
 CURWD=`pwd`
 cd "$DEST"
 for f in *.mo */package.mo; do
   if test "$f" != "package.mo"; then
     LIBS="$LIBS `echo $f | grep -v "[*]" | sed "s/ /%20/g" | sed "s,/package.mo,," | sed "s,.mo$,,"`"
   fi
 done
 cd "$CURWD"
elif test "$*" = "none"; then
 shift
fi
echo $LIBS
for f in $LIBS "$@"; do
  if test "$f" = "self"; then
    LIB=`./get-name.sh "$OMC" "$DEST/package.mo" "$ENCODING" "$STD"`
    VER=""
    if test -z "$LIB"; then
      echo "*** Error: Failed to read package name from $DEST/package.mo"
      exit 1
    fi
  else
    LIB=`echo $f | sed "s/%20/ /g" | cut -d" " -f1`
    VER=`echo $f | sed "s/%20/ /g" | grep " " | cut -d" " -f2`
    echo Copy library [$LIB] version [$VER] from `pwd`
  fi
  if test "$f" = "self"; then
    SOURCE="$DEST"
    MOFILE="$DEST/package.mo"
    EXT=""
  elif [ ! -z "$VER" ] && [ -d "$DEST/$LIB $VER" ]; then
    SOURCE="$DEST/$LIB $VER"
    EXT=""
  elif [ ! -z "$VER" ] && [ -f "$DEST/$LIB $VER.mo" ]; then
    SOURCE="$DEST/$LIB $VER.mo"
    EXT=".mo"
  elif test -d "$DEST/$LIB"; then
    SOURCE="$DEST/$LIB"
    MOFILE="$DEST/$LIB/package.mo"
    EXT=""
  elif test -f "$DEST/$LIB.mo"; then
    SOURCE="$DEST/$LIB.mo"
    MOFILE="$SOURCE"
    EXT=".mo"
  else
    echo "Did not find library $DEST/$LIB :("
    exit 1
  fi
  if test -z "$VER"; then
    VER=`./get-version.sh "$OMC" "$BUILD" "$MOFILE" "$LIB" "$ENCODING" "$STD"`
    echo "Got version $VER for $LIB"
    if test -z "$VER"; then
      NAME="$LIB"
    else
      NAME="$LIB $VER"
    fi
  elif test "$VER" = "none"; then
    NAME="$LIB"
  else
    NAME="$LIB $VER"
  fi
  rm -rf "$BUILD/$NAME" "$BUILD/$NAME.mo"
  # Link recursive... Fast, efficient
  echo Copy: cp -a "$SOURCE" "$BUILD/$NAME$EXT"
  cp -a "$SOURCE" "$BUILD/$NAME$EXT"
  for FILES in $REMOVE_FILES; do
    echo Removing files: [$BUILD/$NAME$EXT/$FILES]
    rm -rf "$BUILD/$NAME$EXT/$FILES"
  done
  if test -f "$NAME.patch"; then
    if ! patch -d "$BUILD/" -f -p1 < "$NAME.patch"; then
      echo "Failed to apply $NAME.patch"
      exit 1
    fi
    echo "Applied $NAME.patch"
    PATCHREV=`git rev-list HEAD --count "$NAME.patch" 2>/dev/null`
    if test -z "$PATCHREV"; then
      echo "Not a git repository. We need it to give patch revisions."
      exit 1
    fi
    PATCHREV=`echo -om$PATCHREV`
    # Do this a second time after patching for updated uses-annotations... Yes, a bit weird
    if test -d "$BUILD/$NAME$EXT"; then
      ./get-version.sh "$OMC" "$BUILD" "$BUILD/$NAME$EXT/package.mo" "$LIB" "$ENCODING" "$STD"
    else
      ./get-version.sh "$OMC" "$BUILD" "$BUILD/$NAME$EXT" "$LIB" "$ENCODING" "$STD"
    fi
  else
    PATCHREV=""
  fi
  # Add custom patch levels
  if echo "$PATCHLEVEL" | grep -q ":"; then
    PATCHLEVELTHIS=`echo "$PATCHLEVEL" | grep -o "$LIB:[A-Za-z0-9_-]*" | cut -d: -f2`
  else
    PATCHLEVELTHIS="$PATCHLEVEL"
  fi
  if test ! -z "$PATCHLEVELTHIS"; then
    PATCHREV="$PATCHLEVELTHIS"
  fi
  echo $LICENSE > "$BUILD/$NAME.license"
  if test "$TYPE" = SVN; then
    echo `svn info $SVNOPTS --xml "$SOURCE" | xpath -q -e '/info/entry/commit/@revision' | grep -o "[0-9]*"`$PATCHREV > "$BUILD/$NAME.last_change"
    # Skipping changelog. Was only used for debian packages, but it is not that useful and quite slow
    # svn log --xml --verbose "$SOURCE" | sed "s,<date>.*</date>,<date>1970-01-01</date>," | sed "s,<author>\(.*\)</author>,<author>none</author><author-svn>\1</author-svn>," | xsltproc svn2cl.xsl - > "$BUILD/$NAME.changes"
  else
    CHANGED=`cd "$DEST" && git show -s --format="%ad" --date="iso" "$REVISION" | tr -d -- - | cut "-d " -f1-2 | tr -d : | tr " " -`
    echo "$CHANGED~git~$GITBRANCH$PATCHREV" > "$BUILD/$NAME.last_change"
    cat "$BUILD/$NAME.last_change"
  fi
  if ! test -z "$BREAKS"; then
    echo "$BREAKS" > "$BUILD/$NAME.breaks"
  fi
  if ! test -z "$NOPACKAGE"; then
    echo "$NOPACKAGE" > "$BUILD/$NAME.nopackage"
  fi
  rm -rf "$BUILD/$NAME$EXT/.svn" "$BUILD/$NAME$EXT/.git"*

  if ! test "$STD" = "3.3"; then
    echo "$STD" > "$BUILD/$NAME.std"
  fi
  if ! test "$ENCODING" = "UTF-8"; then
    echo "$ENCODING" > "$BUILD/$NAME/package.encoding"
  fi
  if test -d "$BUILD/$NAME$EXT"; then
    LIBTOTEST="$BUILD/$NAME$EXT/package.mo"
  else
    LIBTOTEST="$BUILD/$NAME$EXT"
  fi
  ./test-valid.sh "$OMC" "$BUILD" "$LIBTOTEST" || exit 1
done
