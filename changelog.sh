#!/usr/bin/env bash

# Prints a changelog following the KeepAChangelog format to stdout
# Assumes versions are tracked with lightweight tags in master branch
# Generates changelog messages by parsing commits in branches merged to master

set -eu

map_branch_commit_messages_to_assoc_array() {
	local branch_commit_messages=$1
	# echo $branch_commit_messages
	if [ -z "${_commit_messages_by_tag_delta[$previous_tag:$current_tag]:-}" ] 
	then
		_commit_messages_by_tag_delta[$previous_tag:$current_tag]="$branch_commit_messages"
	else
		_commit_messages_by_tag_delta[$previous_tag:$current_tag]="${_commit_messages_by_tag_delta[$previous_tag:$current_tag]:-},$branch_commit_messages"
	fi
}

get_branch_commit_messages_from_merge_commit_sha() {
	local merge_commit_sha=$1
	local branch_commits=$(git log $merge_commit_sha --not $(git rev-list master ^$merge_commit_sha --merges | tail -1)^ --pretty=tformat:"%s")
	echo "$branch_commits"
}

map_merge_commit_shas_branch_commit_messages_to_assoc_array() {
	local merge_commit_shas=$1
	while read -r merge_commit_sha
	do
		branch_commit_messages=$(get_branch_commit_messages_from_merge_commit_sha $merge_commit_sha)
		map_branch_commit_messages_to_assoc_array "$branch_commit_messages"
	done <<< $merge_commit_shas
}

get_merge_commit_shas_between_tags() {
	local from_tag=$1
	local to_tag=$2
	local merge_commit_shas=$(git log $from_tag...$to_tag --merges --pretty="%s" | sed -n "s#Merge commit\s*'\(.*\)'#\1#p")
	echo "$merge_commit_shas"
}

get_tag_list() {
	local tag_list=$(git tag "v[0-9]*" --list --sort=-v:refname)
	echo "$tag_list";
}

map_merged_branches_commit_messages_to_assoc_array() {
	local tag_list=$(get_tag_list)
	local current_tag="HEAD"
	while read -r previous_tag
	do
		tag_at_HEAD=$(git tag --points-at HEAD)
		if [ $previous_tag = "$tag_at_HEAD" ]
		then
			current_tag=$tag_at_HEAD
			continue
		fi
		merge_commit_shas=$(get_merge_commit_shas_between_tags $previous_tag $current_tag)
		if [ -n "$merge_commit_shas" ]
		then
			map_merge_commit_shas_branch_commit_messages_to_assoc_array "$merge_commit_shas"
		fi
		current_tag=$previous_tag
	done <<< $tag_list
}

declare -A _commit_messages_by_tag_delta
map_merged_branches_commit_messages_to_assoc_array

map_commit_message_to_changelog_messages() {
	local _git_log_entry=$1
	case ${_git_log_entry} in
		[Ss]ecurity*)
			_git_security_entries="$(
				cat <<-EOT
					${_git_security_entries:-### Security}
					- ${_git_log_entry#*:}
				EOT
			)"
			;;
		[Ff]ix* | [Ff]ixe[sd]* | [Bb]ugfix*)
			_git_bugfix_entries="$(
				cat <<-EOT
					${_git_bugfix_entries:-### Fixes}
					- ${_git_log_entry#*:}
				EOT
			)"
			;;
		[Rr]emove[sd]*)
			_git_removed_entries="$(
				cat <<-EOT
					${_git_removed_entries:-### Removed}
					- ${_git_log_entry#*:}
				EOT
			)"
			;;
		[Dd]eprecate[sd]*)
			_git_deprecated_entries="$(
				cat <<-EOT
					${_git_deprecated_entries:-### Deprecated}
					- ${_git_log_entry#*:}
				EOT
			)"
			;;
		[Cc]hange*[sd]* | [Uu]pdate*[sd]*)
			_git_changed_entries="$(
				cat <<-EOT
					${_git_changed_entries:-### Changed}
					- ${_git_log_entry#*:}
				EOT
			)"
			;;
		[Aa]dd* | [Ff]eature*)
			_git_added_entries="$(
				cat <<-EOT
					${_git_added_entries:-### Added}
					- ${_git_log_entry#*:}
				EOT
			)"
			;;
	esac
}

map_tag_delta_commit_messages_to_changelog_messages() {
	local tag_delta_commit_messages=$1
	while read -r commit_message
	do
		map_commit_message_to_changelog_messages "$commit_message"
	done <<< $tag_delta_commit_messages
}

get_changelog_from_tag() {
	tag=$1
	tag_header="## $tag"
	tag_changelog="$(cat <<-EOT
${tag_header}
${_git_security_entries:+${_git_security_entries}

}\
${_git_bugfix_entries:+${_git_bugfix_entries}

}\
${_git_removed_entries:+${_git_removed_entries}

}\
${_git_deprecated_entries:+${_git_deprecated_entries}

}\
${_git_changed_entries:+${_git_changed_entries}

}\
${_git_added_entries:-}
		EOT
	)"
	echo "$tag_changelog"
}

reset_changelog_messages() {
	_git_security_entries=""
	_git_bugfix_entries=""
	_git_removed_entries=""
	_git_deprecated_entries=""
	_git_changed_entries=""
	_git_changed_entries=""
	_git_added_entries=""	
}

generate_changelog() {
	tag_deltas_descending="$(printf '%s\n' "${!_commit_messages_by_tag_delta[@]}" | sort -r )"
	while read -r tag_delta
	do
		current_tag=$(echo $tag_delta | cut -d ":" -f2)
		tag_delta_commit_messages=$(echo "${_commit_messages_by_tag_delta[$tag_delta]:-}" | sed "s/,/\n/")
		map_tag_delta_commit_messages_to_changelog_messages "$tag_delta_commit_messages"
		if [ $current_tag = "HEAD" ]
		then
			current_tag="Unreleased"
		fi
		get_changelog_from_tag $current_tag
		reset_changelog_messages
	done <<< $tag_deltas_descending	
}

generate_changelog