#! /bin/sh

# Author:  Thomas DEBESSE <dev@illwieckz.net>
# License: CC0 1.0 [https://creativecommons.org/publicdomain/zero/1.0/]

# It's recommended to run filters in tmpfs mounted point to speed up I/Os
# and to save your precious SSD
#
# Example:
#
#  mkdir -p /mnt/tmpfs
#  mount -t tmpfs -o size=2G tmpfs /mnt/tmpfs
#  export TMPDIR='/mnt/tmpfs'
#
# It's even better and faster to do everything on that tmpfs mounted point
#
#  cd /mnt/tmpfs
#  git clone https://github.com/illwieckz/unvanquished_split.git
#  cd unvanquished_split
#  ./extract_main.sh

if [ -z "${TMPDIR}" ]
then
	temp_dir="$(mktemp -d "/tmp/extract.XXXXXXXX}")"
else
	temp_dir="$(mktemp -d "${TMPDIR}/extract.XXXXXXXX")"
fi

work_dir="$(pwd)/extract_main"
repo_dir="${work_dir}/repo"
list_dir="${work_dir}/list"

bin_dir="$(pwd)/bin"
PATH="${PATH}:${bin_dir}"

unvanquished_remote='git@github.com:Unvanquished/Unvanquished.git'
mainpak_remote='git@github.com:illwieckz/unvanquished_src.pk3dir'
mainpak_mirror="${repo_dir}/unvanquished_src.pk3dir.git"
unvanquished_mirror="${repo_dir}/Unvanquished.git"
mainpak_local="${repo_dir}/unvanquished_src.pk3dir"
final_subdir='main'
main_branch='master'
subdir_list="${list_dir}/subdir_list.txt"
all_list="${list_dir}/all_list.txt"
moved_list="${list_dir}/moved_list.txt"
previous_list="${list_dir}/previous_list.txt"
movable_list="${list_dir}/movable_list.txt"

mkdir -p "${work_dir}"
mkdir -p "${repo_dir}"
mkdir -p "${list_dir}"

cat > "${subdir_list}" <<-EOF
	${final_subdir}
EOF

# unwrap tools
./write_scripts.sh

cd "${work_dir}"

printf '== mirror original tree ==\n'

if ! [ -d "${unvanquished_mirror}" ]
then
	git clone --mirror "${unvanquished_remote}" "${unvanquished_mirror}"
fi

(
	cd "${unvanquished_mirror}"
	switchBranch "${main_branch}"
	git fetch --all

)

printf '== mirror new tree ==\n'

git clone --mirror "${unvanquished_mirror}" "${mainpak_mirror}"

(
	cd "${mainpak_mirror}"
	switchBranch "${main_branch}"

	printf '== drop pull requests ==\n'

	# we will not be able to push pull requests, so, we can drop them
	git for-each-ref --format='%(refname)' 'refs/pull/' \
	| xargs -P1 -n1 git update-ref -d

	# remove some 'reviewable' stuff that mess repository
	# see https://github.com/Unvanquished/Unvanquished/pull/828
	# and https://reviewable.io/reviews/unvanquished/unvanquished/828
	git for-each-ref --format='%(refname)' 'refs/reviewable/' \
	| xargs -P1 -n1 git update-ref -d

	printf '== list all files from repository ==\n'

	listAllFiles > "${all_list}"

	printf '== list all files from engine subdirectories ==\n'

	grepAllFilesInAllSubdirs "${all_list}" "${subdir_list}" > "${movable_list}"

	printf '== list all previous files to subdirectories ==\n'

	listPreviousFilesInAllBranches "${movable_list}" > "${previous_list}"
	
	printf '== list all moved files from subdirectories ==\n'

	cat "${movable_list}" "${previous_list}" \
	| grep -v "^${final_subdir}/" \
	| sort -u > "${moved_list}"

	printf '== move files in final subdirectory ==\n'

	# filter_dir is automatically deleted by git filter-branch
	filter_dir="$(mktemp -d "${temp_dir}/filter.XXXXXXXX")"
	git filter-branch -d "${filter_dir}" -f \
		--tree-filter "moveFilter '${final_subdir}' '${moved_list}'" \
		--tag-name-filter cat -- --all


	git for-each-ref --format='%(refname)' 'refs/original/' \
	| xargs -P1 -n1 git update-ref -d

	printf '== extract subdirectory ==\n'

	# filter_dir is automatically deleted by git filter-branch
	filter_dir="$(mktemp -d "${temp_dir}/filter.XXXXXXXX")"
	git filter-branch -d "${filter_dir}" -f \
		--subdirectory-filter "${final_subdir}" \
		--tag-name-filter cat -- --all

	git for-each-ref --format='%(refname)' 'refs/original/' \
	| xargs -P1 -n1 git update-ref -d

	printf '== garbage collect ==\n'

	git reflog expire --expire=now --all
	git gc --prune=now --aggressive

	printf '== push new repository ==\n'

	git push -f --mirror "${mainpak_remote}"
)

printf '== clone local repository ==\n'

git clone "${mainpak_mirror}" "${mainpak_local}"

(
	cd "${mainpak_local}"
	git checkout "${main_branch}"

	printf '== set new origin ==\n'

	git remote remove origin
	git remote add origin "${mainpak_remote}"
)

#EOF
