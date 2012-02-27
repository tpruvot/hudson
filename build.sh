#!/usr/bin/env bash

function check_result {
  if [ "0" -ne "$?" ]
  then
    echo $1 step failed !
    cat $WORKSPACE/archive/reposync.log
    exit 1
  fi
}

if [ -z "$WORKSPACE" ]; then
  echo WORKSPACE not specified
  exit 1
fi

if [ -z "$CLEAN_TYPE" ]; then
  echo CLEAN_TYPE not specified
  exit 1
fi

if [ -z "$REPO_BRANCH" ]; then
  echo REPO_BRANCH not specified
  exit 1
fi

if [ -z "$LUNCH" ]; then
  echo LUNCH not specified
  exit 1
fi

if [ -z "$RELEASE_TYPE" ]; then
  echo RELEASE_TYPE not specified
  exit 1
fi

rm -rf $WORKSPACE/archive
mkdir -p $WORKSPACE/archive
export BUILD_NO=$BUILD_NUMBER
unset BUILD_NUMBER

export PATH=~/bin:$PATH

REPO=$(which repo)
if [ -z "$REPO" ]; then
  mkdir -p ~/bin
  curl -s -S https://dl-ssl.google.com/dl/googlesource/git-repo/repo > ~/bin/repo
  chmod a+x ~/bin/repo
fi

# git config --global user.name $(whoami)@$NODE_NAME
# git config --global user.email jenkins@cyanogenmod.com

# Repo manifest
if [ -z "$REPO_MANIFEST" ]; then
  REPO_MANIFEST=CyanogenMod
fi

cd $WORKSPACE
if [ ! -d "$REPO_BRANCH" ]
then
  mkdir $REPO_BRANCH
  if [ ! -z "$BOOTSTRAP" -a -d "$BOOTSTRAP" ]; then
    echo Bootstrapping repo with: $BOOTSTRAP
    cp -R $BOOTSTRAP/.repo $REPO_BRANCH
  fi
  cd $REPO_BRANCH
  repo init -u git://github.com/$REPO_MANIFEST/android.git -b $REPO_BRANCH
else
  cd $REPO_BRANCH
  repo init -u git://github.com/$REPO_MANIFEST/android.git -b $REPO_BRANCH
fi

# make sure ccache is in PATH
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilt/$(uname|awk '{print tolower($0)}')-x86/ccache"

if [ -f ~/.jenkins_profile ]
then
  . ~/.jenkins_profile
fi

HUDSON_DIR=$WORKSPACE/hudson
cp $HUDSON_DIR/$REPO_BRANCH.xml $WORKSPACE/$REPO_BRANCH/.repo/local_manifest.xml

echo Syncing...
repo sync -j 1 -f 2>$WORKSPACE/archive/reposync.log
check_result repo sync failed.
echo Sync complete.

cd $WORKSPACE/$REPO_BRANCH
if [ -f $HUDSON_DIR/$REPO_BRANCH-setup.sh ]
then
  $HUDSON_DIR/$REPO_BRANCH-setup.sh
fi

# colorization fix in Jenkins (override yellow color)
export BUILD_WITH_COLORS=0
export CL_PFX="\"\033[34m\""
export CL_INS="\"\033[32m\""
export CL_RST="\"\033[0m\""
export USE_CCACHE=1

cd $WORKSPACE/$REPO_BRANCH
echo "We are ready to build in $WORKSPACE/$REPO_BRANCH"

. build/envsetup.sh
lunch $LUNCH
check_result lunch failed.

export USE_CCACHE=1

rm -f $OUT/update*.zip*

UNAME=$(uname)
if [ "$RELEASE_TYPE" = "CM_NIGHTLY" ]
then
  export CYANOGEN_NIGHTLY=true
  export CM_NIGHTLY=true
elif [ "$RELEASE_TYPE" = "CM_SNAPSHOT" ]
then
  export CM_SNAPSHOT=true
elif [ "$RELEASE_TYPE" = "CM_RELEASE" ]
then
  export CYANOGEN_RELEASE=true
  export CM_RELEASE=true
fi

if [ ! "$(ccache -s|grep -E 'max cache size'|awk '{print $4}')" = "5.0" ]
then
  ccache -M 5G
fi

make $CLEAN_TYPE
mka bacon recoveryzip recoveryimage checkapi
check_result Build failed.

# Files to keep
mkdir -p $WORKSPACE/archive
cp $OUT/update*.zip* $WORKSPACE/archive/
if [ -f $OUT/utilities/update.zip ]
then
  cp $OUT/utilities/update.zip $WORKSPACE/archive/recovery.zip
fi
if [ -f $OUT/recovery.img ]
then
  cp $OUT/recovery.img $WORKSPACE/archive/
fi

# archive the build.prop as well
ZIP=$(ls $WORKSPACE/archive/update*.zip)
unzip -c $ZIP system/build.prop > $WORKSPACE/archive/build.prop
