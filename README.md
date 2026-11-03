# moment-bot
ruby CI server for Moment.js on Github

Heavily based off the great Github tutorial on [building CI servers](https://developer.github.com/v3/guides/building-a-ci-server/), and [its code](https://github.com/github/platform-samples/tree/master/api/ruby/building-a-ci-server).
Forked from [marwahaha/moment-bot](https://github.com/marwahaha/moment-bot).

It listens for `pull_request` webhooks on `/event_handler` and sets three commit statuses on the PR:
**Title** (must start with `[bugfix]`, `[feature]`, `[locale]`, …), **Base branch** (must not be `master`)
and **Generated files** (no edits to `moment.js`, `min/`, `locale/`, `build/`).

## Build & deploy

Everything is built locally in an `ubuntu:26.04` container (the server's distro), so the server only needs
the distro `ruby` package — no bundler, compilers or network access to rubygems.

```
make lock      # (re)generate Gemfile.lock
make dist      # dist/moment-bot.tar.gz: app + standalone gem bundle; runs test/smoke.rb
make deploy    # dist, then unpack into mainlining.dev:/opt/moment-bot and restart the service
```

`HOST=` overrides the SSH target (needs passwordless sudo there).

### One-time server setup

```
sudo apt install ruby nginx certbot
sudo install -m 600 /dev/null /etc/moment-bot.env   # MY_PERSONAL_GITHUB_TOKEN=<token with repo:status>
sudo cp deploy/moment-bot.service /etc/systemd/system/ && sudo systemctl enable moment-bot
sudo cp deploy/nginx-moment-bot.conf /etc/nginx/sites-available/moment-bot   # + symlink into sites-enabled
```

## Running locally

```
bundle config set --local path vendor/bundle
bundle install --standalone
MY_PERSONAL_GITHUB_TOKEN=<token> RACK_ENV=development bin/server
ruby test/smoke.rb    # no network, fake GitHub API
```

In your Github repo, [add a webhook](https://developer.github.com/webhooks/creating/#setting-up-a-webhook)
(content type `application/x-www-form-urlencoded`) to `https://<host>/event_handler` for Pull Request events.
