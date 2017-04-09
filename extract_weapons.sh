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

work_dir="$(pwd)/extract_weapons"
repo_dir="${work_dir}/repo"
list_dir="${work_dir}/list"

bin_dir="$(pwd)/bin"
PATH="${PATH}:${bin_dir}"

unvanquished_remote='git@github.com:UnvanquishedAssets/unvanquished_src.dpkdir.git'
dest_remote='git@github.com:illwieckz/unvanquished_src.dpkdir'
unvanquished_clone="${repo_dir}/unvanquished_src.dpkdir"
dest_clone="${repo_dir}/res-weapons_src.dpkdir"
final_subdir='weapons'
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
	models/weapons
	configs/weapon
	configs/missiles
EOF

listLoneFiles () 
{
	cat <<-EOF
	scripts/blaster.particle
	scripts/blaster.shader
	scripts/blaster.trail
	scripts/chaingun.shader
	scripts/ckit.shader
	scripts/firebomb.particle
	scripts/firebomb.shader
	scripts/firebomb_sub.particle
	scripts/fire.particle
	scripts/flamer.particle
	scripts/flamer.shader
	scripts/flamer.trail
	scripts/grenade.particle
	scripts/grenade.shader
	scripts/grenade.trail
	scripts/lasgun.particle
	scripts/lcannon_impact.particle
	scripts/lcannon.particle
	scripts/lcannon.shader
	scripts/lcannon.trail
	scripts/lgun.shader
	scripts/massdriver.particle
	scripts/massdriver.trail
	scripts/mdriver.shader
	scripts/mdriver.trail
	scripts/prifle.shader
	scripts/psaw.shader
	scripts/pulserifle.particle
	scripts/pulserifle.trail
	scripts/rifle.particle
	scripts/rifle.shader
	scripts/rifle.trail
	scripts/shotgun.particle
	scripts/shotgun.shader
	scripts/sockter.shader
	scripts/weapons.particle
	scripts/weapons.shader
	scripts/weapons.trail
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
