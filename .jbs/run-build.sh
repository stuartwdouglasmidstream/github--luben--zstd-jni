#!/bin/sh
export MAVEN_HOME=/opt/maven/3.8.8
export GRADLE_HOME=/opt/gradle/4.10.3
export SBT_DIST=/opt/sbt/1.8.0
export TOOL_VERSION=1.8.0
export PROJECT_VERSION=1.4.9-1
export JAVA_HOME=/lib/jvm/java-1.8.0
export ENFORCE_VERSION=

set -- "$@" --no-colors +publish 

#!/usr/bin/env bash
set -o verbose
set -eu
set -o pipefail
FILE="$JAVA_HOME/lib/security/cacerts"
if [ ! -f "$FILE" ]; then
    FILE="$JAVA_HOME/jre/lib/security/cacerts"
fi

if [ -f /root/project/tls/service-ca.crt/service-ca.crt ]; then
    keytool -import -alias jbs-cache-certificate -keystore "$FILE" -file /root/project/tls/service-ca.crt/service-ca.crt -storepass changeit -noprompt
fi



#!/usr/bin/env bash
set -o verbose
set -eu
set -o pipefail

cp -r -a  /original-content/* /root/project
cd /root/project/workspace

if [ -n "" ]
then
    cd 
fi

if [ ! -z ${JAVA_HOME+x} ]; then
    echo "JAVA_HOME:$JAVA_HOME"
    PATH="${JAVA_HOME}/bin:$PATH"
fi

if [ ! -z ${MAVEN_HOME+x} ]; then
    echo "MAVEN_HOME:$MAVEN_HOME"
    PATH="${MAVEN_HOME}/bin:$PATH"
fi

if [ ! -z ${GRADLE_HOME+x} ]; then
    echo "GRADLE_HOME:$GRADLE_HOME"
    PATH="${GRADLE_HOME}/bin:$PATH"
fi

if [ ! -z ${ANT_HOME+x} ]; then
    echo "ANT_HOME:$ANT_HOME"
    PATH="${ANT_HOME}/bin:$PATH"
fi

if [ ! -z ${SBT_DIST+x} ]; then
    echo "SBT_DIST:$SBT_DIST"
    PATH="${SBT_DIST}/bin:$PATH"
fi
echo "PATH:$PATH"

#fix this when we no longer need to run as root
export HOME=/root

mkdir -p /root/project/logs /root/project/packages /root/project/build-info



#This is replaced when the task is created by the golang code
sed -i -e '/\/\/ Sonatype/,/\}/d' -e '/\/\/ Android \.aar/,/\/\/ classified Jars$/d' build.sbt
sed -i -e 's/com\.github\.joprice/io.github.joprice/;' -e 's/0\.2\.1/0.2.2/;' project/plugins.sbt


#!/usr/bin/env bash

mkdir -p "${HOME}/.sbt"
cp -r /maven-artifacts/* "$HOME/.sbt/*" || true

if [ ! -d "${SBT_DIST}" ]; then
    echo "SBT home directory not found at ${SBT_DIST}" >&2
    exit 1
fi


mkdir -p "$HOME/.sbt/1.0/"
cat > "$HOME/.sbt/repositories" <<EOF
[repositories]
  local
  my-maven-proxy-releases: http://localhost:8080/v2/cache/rebuild-google/1615049670000/
EOF

# TODO: we may need .allowInsecureProtocols here for minikube based tests that don't have access to SSL
cat >"$HOME/.sbt/1.0/global.sbt" <<EOF
publishTo := Some(("MavenRepo" at s"file:/root/project/artifacts")),
EOF

# Only add the Ivy Typesafe repo for SBT versions less than 1.0 which aren't found in Central. This
# is only for SBT build infrastructure.
if [ -f project/build.properties ]; then
    function ver { printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' '); }
    if [ -n "$(cat project/build.properties | grep sbt.version)" ] && [ $(ver `cat project/build.properties | grep sbt.version | sed -e 's/.*=//'`) -lt $(ver 1.0) ]; then
        cat >> "$HOME/.sbt/repositories" <<EOF
  ivy:  https://repo.typesafe.com/typesafe/ivy-releases/, [organization]/[module]/(scala_[scalaVersion]/)(sbt_[sbtVersion]/)[revision]/[type]s/[artifact](-[classifier]).[ext]
EOF
        mkdir "$HOME/.sbt/0.13/"
        cat >"$HOME/.sbt/0.13/global.sbt" <<EOF
publishTo := Some(Resolver.file("file", new File("/root/project/artifacts")))
EOF
    fi
fi



if [ ! -d /root/project/source ]; then
    cp -r /root/project/workspace /root/project/source
fi
echo "Running SBT command with arguments: $@"

eval "sbt $@" | tee /root/project/logs/sbt.log

cp -r "${HOME}"/.sbt/* /root/project/build-info




