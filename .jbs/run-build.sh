#!/bin/sh
export MAVEN_HOME=/opt/maven/3.8.8
export GRADLE_HOME=/opt/gradle/4.10.3
export SBT_DIST=/opt/sbt/1.8.0
export TOOL_VERSION=4.10.3
export PROJECT_VERSION=1.4.9-1
export JAVA_HOME=/lib/jvm/java-1.8.0
export ENFORCE_VERSION=

set -- "$@" assemble publishToMavenLocal -DdisableTests 

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

if [ ! -z ${JBS_DISABLE_CACHE+x} ]; then
    cat >"/root/software/settings"/settings.xml <<EOF
    <settings>
EOF
else
    cat >"/root/software/settings"/settings.xml <<EOF
    <settings>
      <mirrors>
        <mirror>
          <id>mirror.default</id>
          <url>${CACHE_URL}</url>
          <mirrorOf>*</mirrorOf>
        </mirror>
      </mirrors>
EOF
fi

cat >>"/root/software/settings"/settings.xml <<EOF
  <!-- Off by default, but allows a secondary Maven build to use results of prior (e.g. Gradle) deployment -->
  <profiles>
    <profile>
      <id>gradle</id>
      <activation>
        <property>
          <name>useJBSDeployed</name>
        </property>
      </activation>
      <repositories>
        <repository>
          <id>artifacts</id>
          <url>file:///root/project/artifacts</url>
          <releases>
            <enabled>true</enabled>
            <checksumPolicy>ignore</checksumPolicy>
          </releases>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>artifacts</id>
          <url>file:///root/project/artifacts</url>
          <releases>
            <enabled>true</enabled>
            <checksumPolicy>ignore</checksumPolicy>
          </releases>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>
</settings>
EOF

#!/usr/bin/env bash
export GRADLE_USER_HOME="/root/software/settings/.gradle"
mkdir -p "${GRADLE_USER_HOME}"
mkdir -p "$HOME/.m2/"

#copy back the gradle folder for hermetic
cp -r /maven-artifacts/.gradle/* "$GRADLE_USER_HOME/" || true
cp -r /maven-artifacts/.m2/* "$HOME/.m2/" || true

cat > "${GRADLE_USER_HOME}"/gradle.properties << EOF
org.gradle.console=plain
# For Spring/Nebula Release Plugins
release.useLastTag=true
release.stage=final

# For https://github.com/Kotlin/kotlinx.team.infra
versionSuffix=

# Increase timeouts
systemProp.org.gradle.internal.http.connectionTimeout=600000
systemProp.org.gradle.internal.http.socketTimeout=600000
systemProp.http.socketTimeout=600000
systemProp.http.connectionTimeout=600000

# Settings for <https://github.com/vanniktech/gradle-maven-publish-plugin>
RELEASE_REPOSITORY_URL=file:/root/project/artifacts
RELEASE_SIGNING_ENABLED=false
mavenCentralUsername=
mavenCentralPassword=
EOF

if [ -d .hacbs-init ]; then
    rm -rf "${GRADLE_USER_HOME}"/init.d
    cp -r .hacbs-init "${GRADLE_USER_HOME}"/init.d
fi

#if we run out of memory we want the JVM to die with error code 134
export JAVA_OPTS="-XX:+CrashOnOutOfMemoryError"

export PATH="${JAVA_HOME}/bin:${PATH}"

#some gradle builds get the version from the tag
#the git init task does not fetch tags
#so just create one to fool the plugin
git config user.email "HACBS@redhat.com"
git config user.name "HACBS"
if [ -z "" ]; then
  echo "Enforce version not set, recreating original tag v1.4.9-1"
  git tag -m v1.4.9-1 -a v1.4.9-1 || true
else
  echo "Creating tag  to match enforced version"
  git tag -m  -a  || true
fi

if [ ! -d "${GRADLE_HOME}" ]; then
    echo "Gradle home directory not found at ${GRADLE_HOME}" >&2
    exit 1
fi

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

#our dependency tracing breaks verification-metadata.xml
#TODO: should we disable tracing for these builds? It means we can't track dependencies directly, so we can't detect contaminants
rm -f gradle/verification-metadata.xml

echo "Running Gradle command with arguments: $@"
if [ ! -d /root/project/source ]; then
  cp -r /root/project/workspace /root/project/source
fi
gradle -Dmaven.repo.local=/root/project/artifacts --info --stacktrace "$@"  | tee /root/project/logs/gradle.log

mkdir -p /root/project/build-info
cp -r "${GRADLE_USER_HOME}" /root/project/build-info/.gradle
cp -r "${HOME}/.m2" /root/project/build-info/.m2




