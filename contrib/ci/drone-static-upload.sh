#!/usr/bin/env bash

# Script used with Drone CI to upload build artifacts (because specifying all this in
# .drone.jsonnet is too painful).



set -o errexit

if [ -z "$SSH_KEY" ]; then
    echo -e "\n\n\n\e[31;1mUnable to upload artifact: SSH_KEY not set\e[0m"
    # Just warn but don't fail, so that this doesn't trigger a build failure for untrusted builds
    exit 0
fi

echo "$SSH_KEY" >ssh_key

set -o xtrace  # Don't start tracing until *after* we write the ssh key

chmod 600 ssh_key

os="${UPLOAD_OS:-$DRONE_STAGE_OS-$DRONE_STAGE_ARCH}"
if [ -n "$WINDOWS_BUILD_NAME" ]; then
    os="windows-$WINDOWS_BUILD_NAME"
fi

if [ -n "$DRONE_TAG" ]; then
    # For a tag build use something like `lokinet-linux-amd64-v1.2.3`
    base="lokinet-$os-$DRONE_TAG"
else
    # Otherwise build a length name from the datetime and commit hash, such as:
    # lokinet-linux-amd64-20200522T212342Z-04d7dcc54
    base="lokinet-$os-$(date --date=@$DRONE_BUILD_CREATED +%Y%m%dT%H%M%SZ)-${DRONE_COMMIT:0:9}"
fi

mkdir -v "$base"
mkdir -v gui
if [ -e release/*.exe ]; then
    cp -av release/*.exe gui/lokinet-gui.exe
    # zipit up yo
    archive="$base.zip"
    zip -r "$archive" gui
elif [ -e release/*.deb ]; then
    cp -av release/*.deb "$base"
    # tar dat shiz up yo
    archive="$base-deb.tar.xz"
    tar cJvf "$archive" "$base"
elif [ -e release/*.AppImage ]; then
    cp -av release/*.AppImage "$base"
    # tar dat shiz up yo
    archive="$base-appimage.tar.xz"
    tar cJvf "$archive" "$base"
elif [ -e release/*-mac.zip ]; then
    archive="$base-unsigned.zip"
    cp release/*-mac.zip $archive
fi

upload_to="oxen.rocks/${DRONE_REPO// /_}/${DRONE_BRANCH// /_}"

# sftp doesn't have any equivalent to mkdir -p, so we have to split the above up into a chain of
# -mkdir a/, -mkdir a/b/, -mkdir a/b/c/, ... commands.  The leading `-` allows the command to fail
# without error.
upload_dirs=(${upload_to//\// })
mkdirs=
dir_tmp=""
for p in "${upload_dirs[@]}"; do
    dir_tmp="$dir_tmp$p/"
    mkdirs="$mkdirs
-mkdir $dir_tmp"
done

sftp -i ssh_key -b - -o StrictHostKeyChecking=off drone@oxen.rocks <<SFTP
$mkdirs
put $archive $upload_to
SFTP

set +o xtrace

echo -e "\n\n\n\n\e[32;1mUploaded to https://${upload_to}/${archive}\e[0m\n\n\n"

