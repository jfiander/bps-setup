# Ruby installs (2.7.4 master, 3.3.11 intermediate/global, 4.0.3 edge).
# RubyGems and Bundler 4.x both require Ruby >= 3.2; older rubies need
# the last release on the previous major line.
for v in "${RUBY_VERSIONS[@]}"; do
  rbenv install -s "${v}"
  IFS=. read -r rb_major rb_minor _ <<<"${v}"
  if (( rb_major < 3 )) || (( rb_major == 3 && rb_minor < 2 )); then
    rubygems_args=(3.5.22)
    bundler_args=(-v 2.4.22)
  else
    rubygems_args=()
    bundler_args=()
  fi
  RBENV_VERSION="${v}" rbenv exec gem update --system "${rubygems_args[@]}" --no-document
  RBENV_VERSION="${v}" rbenv exec gem install bundler "${bundler_args[@]}" --no-document
done
rbenv global "${RUBY_GLOBAL}"
rbenv rehash
