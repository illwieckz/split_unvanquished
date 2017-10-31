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
#  git clone https://github.com/illwieckz/unanquished_split.git
#  cd unanquished_split
#  ./extract_mapvega.sh

# Note that this script is not enough to do the task, some stuff were done by hand after that

if [ -z "${TMPDIR}" ]
then
	temp_dir="$(mktemp -d "/tmp/extract.XXXXXXXX}")"
else
	temp_dir="$(mktemp -d "${TMPDIR}/extract.XXXXXXXX")"
fi

work_dir="$(pwd)/extract_mapvega"
repo_dir="${work_dir}/repo"
list_dir="${work_dir}/list"

bin_dir="$(pwd)/bin"
PATH="${PATH}:${bin_dir}"

vega_remote='git@github.com:IngarKCT/map-vega.git'
mappak_remote='git@github.com:UnvanquishedAssets/map-vega_src.dpkdir'
mappak_mirror="${repo_dir}/map-vega_src.dpkdir.git"
vega_mirror="${repo_dir}/map-vega.git"
mappak_local="${repo_dir}/map-vega_src.dpkdir"
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
	meta/vega
	minimaps
	models
	sound
	textures/vega_custom_src
	${final_subdir}
EOF

listLoneFiles () 
{
	cat <<-EOF
	about/map-vega.txt
	compile.sh
	maps/vega.map
	pk3-map.sh
	README
	scripts/shaderlist.txt
	scripts/vega_custom.particle
	scripts/vega_custom.shader
	scripts/vega_models.shader
	EOF
}

# unwrap tools
./write_scripts.sh

cd "${work_dir}"

printf '== mirror original tree ==\n'

if ! [ -d "${vega_mirror}" ]
then
	git clone --mirror "${vega_remote}" "${vega_mirror}"
fi

(
	cd "${vega_mirror}"
	switchBranch "${main_branch}"
	git fetch --all

)

printf '== mirror new tree ==\n'

git clone --mirror "${vega_mirror}" "${mappak_mirror}"

(
	cd "${mappak_mirror}"
	switchBranch "${main_branch}"

	printf '== list all files from repository ==\n'

	listAllFiles > "${all_list}"

	printf '== list all files from engine subdirectories ==\n'

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

# 	printf '== push new repository ==\n'

#	git push -f --mirror "${mappak_remote}"
)

exit
printf '== clone local repository ==\n'

git clone "${mappak_mirror}" "${mappak_local}"

(
	cd "${mappak_local}"
	git checkout "${main_branch}"

	printf '== set new origin ==\n'

	git remote remove origin
	git remote add origin "${mappak_remote}"
)

#EOF
