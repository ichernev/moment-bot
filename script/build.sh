#!/bin/sh
# Runs inside ubuntu:26.04 (see Makefile): installs the gems as a standalone bundle built against the
# distro ruby the server uses, runs the smoke test, and packs the deployable tarball into dist/.
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ruby ruby-dev build-essential ca-certificates >/dev/null
gem install -N bundler -v "~> 4.0" >/dev/null

rm -rf /build && mkdir /build
cp -r Gemfile config.ru server.rb bin test /build/
[ ! -f Gemfile.lock ] || cp Gemfile.lock /build/
cd /build
[ ! -f Gemfile.lock ] || bundle config set --local frozen true
bundle config set --local path vendor/bundle
bundle install --standalone --quiet
ruby test/smoke.rb

rm -rf vendor/bundle/ruby/*/cache test
mkdir -p /src/dist
cp Gemfile.lock /src/dist/
tar -czf /src/dist/moment-bot.tar.gz --owner=0 --group=0 .
chown -R "$HOST_UID:$HOST_GID" /src/dist
ls -la /src/dist
