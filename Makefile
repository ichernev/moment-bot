# Deployable artefact: dist/moment-bot.tar.gz = app + standalone gem bundle compiled for the server's
# distro ruby (ubuntu:26.04). The server only needs the `ruby` package.
#   make fetch     download the tarball built by GitHub Actions for the current commit (needs `gh`)
#   make dist      or build it locally in an $(IMAGE) container (needs docker; runs test/smoke.rb)
#   make deploy    unpack dist/moment-bot.tar.gz into $(HOST):/opt/moment-bot and restart the service
#   make lock      refresh Gemfile.lock (in the same container)
HOST  ?= mainlining.dev
IMAGE ?= ubuntu:26.04
REPO  ?= ichernev/moment-bot
DOCKER = docker run --rm -v "$(CURDIR)":/src -w /src -e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) $(IMAGE)

.PHONY: dist fetch lock deploy clean

dist:
	$(DOCKER) sh script/build.sh

fetch:
	rm -rf dist
	run=$$(gh run list -R $(REPO) -w build -c $$(git rev-parse HEAD) -s success -L 1 --json databaseId -q '.[0].databaseId'); \
	  [ -n "$$run" ] || { echo "no successful CI build for $$(git rev-parse --short HEAD) (pushed? still running?)"; exit 1; }; \
	  gh run download $$run -R $(REPO) -n moment-bot -D dist
	ls -la dist

lock:
	$(DOCKER) sh -c 'apt-get update -qq && apt-get install -y -qq ruby >/dev/null && gem install -N bundler >/dev/null && bundle lock --update && chown $$HOST_UID:$$HOST_GID Gemfile.lock'

deploy: dist/moment-bot.tar.gz
	scp dist/moment-bot.tar.gz $(HOST):/tmp/moment-bot.tar.gz
	ssh $(HOST) 'set -e; sudo rm -rf /opt/moment-bot.new; sudo mkdir /opt/moment-bot.new; \
	  sudo tar -xzf /tmp/moment-bot.tar.gz -C /opt/moment-bot.new; rm /tmp/moment-bot.tar.gz; \
	  sudo rm -rf /opt/moment-bot.old; [ ! -d /opt/moment-bot ] || sudo mv /opt/moment-bot /opt/moment-bot.old; \
	  sudo mv /opt/moment-bot.new /opt/moment-bot; sudo systemctl restart moment-bot; sleep 2; \
	  systemctl is-active moment-bot && curl -fsS http://127.0.0.1:9292/ && echo'

dist/moment-bot.tar.gz:
	@echo "no dist/moment-bot.tar.gz: run 'make fetch' (CI build) or 'make dist' (local docker)"; exit 1

clean:
	rm -rf dist
