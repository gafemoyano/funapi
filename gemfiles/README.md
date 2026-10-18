# CI dependency coverage

CI tests the latest patch releases of Ruby 3.2, 3.3, 3.4, and 4.0. Ruby 3.2 is
retained as the gem's declared minimum series, although it is upstream EOL.

`latest.gemfile` resolves the newest compatible dependencies for each Ruby with
`bundle update`, independently of the root `Gemfile.lock`. This means the newest
versions allowed by the Gemfile and by each dependency's Ruby requirements, not
necessarily the same versions on every Ruby.

`minimum.gemfile` tests exact minimum **direct runtime dependencies** on Ruby 3.2.0.
Async is pinned to 2.10.2 rather than the gemspec's 2.8: async-websocket 0.30.0
requires async-http >= 0.76, whose minimum Async requirement is 2.10.2.
The optional database integration is tested with Sequel 5.63.0 and pg 1.3.0.
Transitive dependencies and other test tools resolve to compatible versions; this is
not a claim to test every transitive minimum or every Ruby/dependency combination.
Standard is kept on the existing 1.51 patch series to keep lint-policy upgrades
separate from runtime dependency compatibility.

Generated locks are ignored. To reproduce either lane locally:

```sh
BUNDLE_GEMFILE=gemfiles/minimum.gemfile bundle update
BUNDLE_GEMFILE=gemfiles/minimum.gemfile bundle exec rake
BUNDLE_GEMFILE=gemfiles/latest.gemfile bundle update
BUNDLE_GEMFILE=gemfiles/latest.gemfile bundle exec rake
```

The PostgreSQL job tests minimum dependencies on Ruby 3.2.0 and fresh latest
dependencies on Ruby 4.0, each with a PostgreSQL 16 service.
`REQUIRE_DATABASE=1` makes missing Sequel or an absent/empty
`DATABASE_URL` fail; connection errors also fail. It runs the database test file
explicitly, then the full test and Standard suite. No Docker fallback is used in
required mode. Repository branch protection must select both
`PostgreSQL minimum (required)` and `PostgreSQL latest (required)` if merges
should be blocked by these jobs; workflow configuration alone cannot
change branch protection.

For local database coverage, point `DATABASE_URL` at a **disposable** PostgreSQL
database (tests recreate tables) and run:

```sh
REQUIRE_DATABASE=1 DATABASE_URL=postgres://localhost/funapi_test bundle exec rake
```

Without required mode, local tests still use `DATABASE_URL` or Testcontainers
when available and skip database tests when neither is available.
