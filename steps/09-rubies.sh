# Ruby installs (2.7.4 master, 3.3.11 intermediate/global, 4.0.3 edge).
for v in "${RUBY_VERSIONS[@]}"; do
  rbenv install -s "${v}"
  # Latest bundler requires Ruby >= 3.2; pin older rubies to the last
  # compatible release.
  IFS=. read -r rb_major rb_minor _ <<<"${v}"
  if (( rb_major < 3 )) || (( rb_major == 3 && rb_minor < 2 )); then
    bundler_args=(-v 2.4.22)
  else
    bundler_args=()
  fi
  RBENV_VERSION="${v}" rbenv exec gem install bundler "${bundler_args[@]}" --no-document
done
rbenv global "${RUBY_GLOBAL}"
rbenv rehash
