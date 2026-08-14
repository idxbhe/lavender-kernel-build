#!/system/bin/sh
MODDIR=${0%/*};
if [ $(uname -r | grep Nexus) ]; then
    $MODDIR/nexus
else 
    rm -rf $MODDIR;
fi;