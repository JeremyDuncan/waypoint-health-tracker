FROM ruby:3.4.8-slim AS build
WORKDIR /app
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential libyaml-dev pkg-config && rm -rf /var/lib/apt/lists/*
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development:test
COPY Gemfile Gemfile.lock ./
RUN bundle install && bundle exec bootsnap precompile --gemfile
COPY . .
RUN RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

FROM ruby:3.4.8-slim
WORKDIR /app
RUN apt-get update -qq && apt-get install --no-install-recommends -y curl libyaml-0-2 sqlite3 && rm -rf /var/lib/apt/lists/* && groupadd --gid 1000 app && useradd --uid 1000 --gid 1000 --create-home app && mkdir /data && chown app:app /data
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development:test DATABASE_PATH=/data/hearth.sqlite3
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=app:app /app /app
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 CMD curl -fsS http://127.0.0.1:3000/up || exit 1
ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
