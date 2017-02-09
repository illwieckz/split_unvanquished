#! /bin/sh

# Author:  Thomas DEBESSE <dev@illwieckz.net>
# License: CC0 1.0 [https://creativecommons.org/publicdomain/zero/1.0/]

# You can set TMPDIR to a tmpfs mounted point to speed up I/Os and to save your precious SSD
# Example:
#
#  mkdir -p /mnt/tmpfs
#  mount -t tmpfs -o size=2G tmpfs /mnt/tmpfs
#  export TMPDIR='/mnt/tmpfs'

if [ -z "${TMPDIR}" ]
then
	temp_dir="$(mktemp -d "/tmp/extract.XXXXXXXX}")"
else
	temp_dir="$(mktemp -d "${TMPDIR}/extract.XXXXXXXX")"
fi

tab="$(printf '\t')"
current_dir="$(pwd)"
sub_dir='daemon'
unvanquished_remote='git@github.com:Unvanquished/Unvanquished.git'
daemon_remote='git@github.com:illwieckz/Daemon.git'
temp_daemon_mirror="$(mktemp -d "${temp_dir}/daemon.XXXXXXXX.git")"
unvanquished_mirror="${current_dir}/Unvanquished.git"
daemon_local="${current_dir}/Daemon"

if ! [ -d "${unvanquished_mirror}" ]
then
	git clone --mirror "${unvanquished_remote}" "${unvanquished_mirror}"
fi

(
	cd "${unvanquished_mirror}"
	git fetch --all
)

git clone --mirror "${unvanquished_mirror}" "${temp_daemon_mirror}"

(
	cd "${temp_daemon_mirror}"

	filter_dir="$(mktemp -d "${temp_dir}/filter.XXXXXXXX")"
	git filter-branch -d "${filter_dir}" -f --subdirectory-filter "${sub_dir}" --tag-name-filter cat -- --all
	# filter_dir is automatically deleted by git filter-branch

	git for-each-ref --format="%(refname)" refs/original/ | xargs -n 1 git update-ref -d
	git for-each-ref --format="%(refname)" refs/pull/ | xargs -n 1 git update-ref -d

	git reflog expire --expire=now --all
	git gc --prune=now --aggressive

	git push -f --mirror "${daemon_remote}"
)

git clone "${temp_daemon_mirror}" "${daemon_local}"

(
	cd "${daemon_local}"

	git remote remove origin
	git remote add origin "${daemon_remote}"

	git checkout -b submodules master

	cat > '.gitmodules' <<-EOF
	[submodule "libs/breakpad"]
	${tab}path = libs/breakpad
	${tab}url = https://github.com/Unvanquished/breakpad.git
	[submodule "libs/recastnavigation"]
	${tab}path = libs/recastnavigation
	${tab}url = https://github.com/Unvanquished/recastnavigation.git
	EOF

	git add '.gitmodules'
	git commit -m 'readd submodules'

	git checkout master
	git merge submodules

	git push origin submodules
	git push origin master
)

rm -Rf "${temp_daemon_mirror}"
rmdir "${temp_dir}"

#EOF
