# Ruby installs (2.7.4 master, 3.3.11 intermediate/global, 4.0.3 edge).
# RubyGems 4.x and Bundler 4.x both require Ruby >= 3.2.
# - For Ruby >= 3.2: update rubygems unbounded (latest 4.x), latest bundler.
# - For Ruby < 3.2: leave rubygems alone (each version's last compatible
#   rubygems is what already ships with that Ruby; chasing it with `gem
#   update --system` lands on releases that don't support 2.7) and pin
#   bundler to the last 2.7-compatible release.
for v in "${RUBY_VERSIONS[@]}"; do
  rbenv install -s "${v}"
  IFS=. read -r rb_major rb_minor _ <<<"${v}"
  if (( rb_major < 3 )) || (( rb_major == 3 && rb_minor < 2 )); then
    bundler_args=(-v 2.4.22)
  else
    RBENV_VERSION="${v}" rbenv exec gem update --system --no-document
    bundler_args=()
  fi
  RBENV_VERSION="${v}" rbenv exec gem install bundler "${bundler_args[@]}" --no-document
done
rbenv global "${RUBY_GLOBAL}"
rbenv rehash
