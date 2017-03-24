#! /bin/sh

# Author:  Thomas DEBESSE <dev@illwieckz.net>
# License: CC0 1.0 [https://creativecommons.org/publicdomain/zero/1.0/]

# xargs need executable files in path and can't work with functions
# that's why we create files instead of functions

# wr is an helper to write scripts
wr () {
	mkdir -p "${bin_dir}"
	bin_file="${bin_dir}/${1}"
	printf '#!/bin/sh\n' > "${bin_file}"
	cat >> "${bin_file}"
	chmod +x "${bin_file}"

}

# git ls-files does not work in bare repositories
wr listFiles <<\EOF
	git ls-tree --full-tree -r HEAD \
	| cut -f2 \
	| sort
EOF

wr listBranches <<\EOF
	git branch --list \
	| sed -e 's/.* //' \
	| sort
EOF

wr listNameStatusPerFile <<\EOF
	git log --format='' --follow --name-status -M -- "${1}" \
	| sort -u
EOF

wr listPreviousFilesPerFile <<\EOF
	listNameStatusPerFile "${1}" \
	| grep '^R[0-9][0-9][0-9]' \
	| cut -f2 \
	| sort
EOF

wr getCurrentBranch <<\EOF
	git rev-parse --abbrev-ref HEAD
EOF

wr switchBranch <<\EOF
	git symbolic-ref HEAD "refs/heads/${1}"
EOF

# it's better to not parallelize otherwise
# race condition can happen
wr listPreviousFilesInBranch <<\EOF
	current_branch="$(getCurrentBranch)"
	switchBranch "${2}"
	cat "${1}" \
	| xargs -P1 -n1 listPreviousFilesPerFile
	switchBranch "${current_branch}"
EOF

# this can't be parallelized at all since
# the called script switch branches
# because the previous name lookup relies
# on current branch history
wr listPreviousFilesInAllBranches <<\EOF
	listBranches \
	| xargs -P1 -n1 listPreviousFilesInBranch "${1}" \
	| sort -u
EOF

# we have to raise some limits to track previous renames
wr listAllFiles <<\EOF
	git config diff.renameLimit 10000
	git log --all --pretty=format: --name-only \
	| sort -u	
EOF

wr grepAllFilesPerSubdir <<\EOF
	cat "${1}" \
	| grep "^${2}/" \
	| sort -u
EOF

# it's better to not parallelize otherwise
# race condition can happen
wr grepAllFilesInAllSubdirs <<\EOF
	cat "${2}" \
	| xargs -P1 -n1 grepAllFilesPerSubdir "${1}"
EOF

# git mv keeps file even if they are ignored
# but git mv is slow, we will readd the ignored one latter
wr moveExistingFileToSubdir <<\EOF
	[ -f "${2}" ] || exit 0
	mkdir -p "${1}/$(dirname "${2}")"
	mv "${2}" "${1}/${2}"
EOF

# after moving files in parallel, adding them in bunch
# git add is slow and can't be parallelized at all
wr moveFilter <<\EOF
	cat "${2}" \
	| xargs "-P$(nproc)" -n1 moveExistingFileToSubdir "${1}"
	cat "${2}" \
	| sed -e "s|^|${1}/|" \
	| xargs -P1 -n500 git add --force --ignore-errors 2>/dev/null
	true
EOF

#EOF
