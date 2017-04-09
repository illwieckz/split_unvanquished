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

work_dir="$(pwd)/extract_buildables"
repo_dir="${work_dir}/repo"
list_dir="${work_dir}/list"

bin_dir="$(pwd)/bin"
PATH="${PATH}:${bin_dir}"

unvanquished_remote='git@github.com:UnvanquishedAssets/unvanquished_src.dpkdir.git'
dest_remote='git@github.com:illwieckz/unvanquished_src.dpkdir'
unvanquished_clone="${repo_dir}/unvanquished_src.dpkdir"
dest_clone="${repo_dir}/res-buildables_src.dpkdir"
final_subdir='buildables'
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
	configs/buildables
	models/buildables
	sound/buildables
EOF

listLoneFiles () 
{
	cat <<-EOF
	scripts/acid_tube.shader
	scripts/alien_buildable_burn.particle
	scripts/arm.shader
	scripts/barricade.shader
	scripts/booster.particle
	scripts/booster.shader
	scripts/buildables.particle
	scripts/buildables.shader
	scripts/drill.shader
	scripts/eggpod.shader
	scripts/hive.shader
	scripts/human_buildable_nova.particle
	scripts/leech.shader
	scripts/medistat.shader
	scripts/metal_gibs.shader
	scripts/mgturret.shader
	scripts/overmind.shader
	scripts/reactor.shader
	scripts/repeater.shader
	scripts/rocket.particle
	scripts/rocketpod.shader
	scripts/rocket.trail
	scripts/spiker.shader
	scripts/telenode-md3.shader
	scripts/telenode.shader
	scripts/turret.particle
	EOF
}

# unwrap tools
./write_scripts.sh

cd "${work_dir}"

printf '== clone original tree ==\n'

if ! [ -d "${unvanquished_clone}" ]
then
	git clone "${unvanquished_remote}" "${unvanquished_clone}"
fi

(
	cd "${unvanquished_clone}"
	switchBranch "${main_branch}"
	git fetch --all

)

printf '== clone new tree ==\n'

git clone "${unvanquished_clone}" "${dest_clone}"

(
	cd "${dest_clone}"
	switchBranch "${main_branch}"

	printf '== list all files from repository ==\n'

	listAllFiles > "${all_list}"

	printf '== list all files from needed subdirectories ==\n'

	grepAllFilesInAllSubdirs "${all_list}" "${subdir_list}" > "${movable_list}"
	listLoneFiles >> "${movable_list}"

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
		--tag-name-filter cat --


	git for-each-ref --format='%(refname)' 'refs/original/' \
	| xargs -P1 -n1 git update-ref -d

	printf '== extract subdirectory ==\n'

	# filter_dir is automatically deleted by git filter-branch
	filter_dir="$(mktemp -d "${temp_dir}/filter.XXXXXXXX")"
	git filter-branch -d "${filter_dir}" -f \
		--subdirectory-filter "${final_subdir}" \
		--tag-name-filter cat --

	git for-each-ref --format='%(refname)' 'refs/original/' \
	| xargs -P1 -n1 git update-ref -d

	printf '== garbage collect ==\n'

	git reflog expire --expire=now --all
	git gc --prune=now --aggressive
)

#EOF
