#!/usr/bin/env bash
#
# Parse debian/changelog and set package version same as on PopOS! and Ubuntu
#
# ----------------------------------------------------------------------------
# 2024-02-14 Marcin Szydelski
#  get version from Cargo.toml
#  fix shellcheck issues
# 2021-01-09 Marcin Szydelski
#  init

# config
outdir="$(pwd)/.rpkg-build"
export outdir

# verification
[ -f Cargo.toml ] || {
  echo "No Cargo.toml configuration found."
  exit 1
}

# fetch upstream
git fetch upstream
# merge
git checkout master
git merge upstream/master -m "fetch upstream" --log

[ -d "${outdir}" ] && rm -rf "${outdir}"

version=$(python3 -c 'import toml;config = toml.load("Cargo.toml");print(config["package"]["version"])')

_tmp=$(git tag --list firmware-manager-"$version"-'*' | sort -n -t '-' -k 4 -r | head -1)
release=${_tmp##*-}

if [ "z$release" == "z" ]; then
  release=1
else
  if ! [[ "$release" =~ ^[0-9]+$ ]]; then
    echo "Release should be a number"
    exit 2
  fi
  # increment release number
  ((release++))
fi

# as a workaround set static version in spec file
sed -i "s#^Version:    .*#Version:    $version#" firmware-manager.spec.rpkg
sed -i "s#^Release:    .*#Release:    $release#" firmware-manager.spec.rpkg
git commit -m"bump Version to: $version-$release" firmware-manager.spec.rpkg

#test & build srpm
mkdir "$outdir"
rpkg local --outdir="$outdir" || {
  echo "rpkg local failed"
  exit 4
}

# rpkg tag
rpkg tag --version="$version" --release="$release"

srpm="$(ls .rpkg-build/firmware-manager-*.src.rpm)"

# publish / build oficially

copr-cli build system76 "$srpm" || {
  echo "Copr build failed"
  exit 5
}

# store in repo
git push || {
  echo "Git push failed"
  exit 6
}
git push --tags || {
  echo "Git push --tags failed"
  exit 6
}

# clear

if [ -d "$outdir" ]; then
  rm -rf "$outdir"
fi
