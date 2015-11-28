# Charlie
# by Alex Ciobica
# https://github.com/c10b10
# Based on Pure by Sindre Sorhus
# MIT License

# You can configure theme by defining the following constants:
# * CHARLIE_GIT_NEEDS_PULL_SYM (Default: ⇣): The symbol displayed in the
#   preprompt when the git repo needs to pull
# * CHARLIE_GIT_NEEDS_PUSH_SYM (default: ↑): The symbol displayed
#   in the preprompt when the git repo needs to push
# * CHARLIE_GIT_UNTRACKED_DIRTY (Default: 0): If set to a value different
#   than 0, it will include untracked files in the check that determines
#   wether a git repo is dirty.
# * CHARLIE_GIT_DIRTY_SYM (Default: ∗): The symbol displayed when
#   the git repo is dirty.
# * CHARLIE_GIT_AUTO_FETCH (Default: 1): Set `CHARLIE_GIT_AUTO_FETCH=0` to
#   prevent Charlie from checking whether the current Git remote has
#   been updated.

# For sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

# Colors generated with http://geoff.greer.fm/lscolors/
alias ls="ls -FG"
# Define colors for BSD ls.
export LSCOLORS='Gxfxcxdxbxeggdabagacad'
# Define colors for the completion system.
export LS_COLORS='di=1;36;40:ln=35;40:so=32;40:pi=33;40:ex=31;40:bd=34;46:cd=36;43:su=0;41:sg=0;46:tw=0;42:ow=0;43:'

# Generic helpers
# ---------------

# Save string length to var
charlie_string_length_to_var() {
	local str=$1 var=$2 length
	# perform expansion on str and check length
	length=$(( ${#${(S%%)str//(\%([KF1]|)\{*\}|\%[Bbkf])}} ))

	# store string length in variable as specified by caller
	typeset -g "${var}"="${length}"
}

# Utility that changes the terminal window title
charlie_set_window_title() {
	# Start setting the title
	print -n '\e]0;'

	# Show hostname if connected through ssh
	[[ -n $SSH_CONNECTION ]] && print -Pn '(%m) '
    print -Pn $1

	# End setting the title
	print -n '\a'
}

# Environment helpers
# -------------------

# Outputs information about rvm
charlie_get_rvm_info() {
  # ruby_version=$(~/.rvm/bin/rvm-prompt)
  if [ -f ~/.rvm/bin/rvm-prompt ]; then
      local ruby_version=$(~/.rvm/bin/rvm-prompt v g)
      if [ -n "$ruby_version" ]; then
        echo "%F{227}◊ $ruby_version%f "
      else
        echo "%F{227}system%f "
      fi
  fi
}

# Outputs information about the python virtualenv
function virtualenv_info {
    [ $VIRTUAL_ENV ] && echo '('`basename $VIRTUAL_ENV`') '
}

# Output a different symbol depending on the active versioning system
charlie_vcs_symbol() {
    git branch >/dev/null 2>/dev/null && echo "%F{202}±%f" && return
    hg root >/dev/null 2>/dev/null && echo "%F{250}☿%f" && return
	svn info >/dev/null 2>/dev/null && echo "%F{111}⑆%f"
}

# Displays down and up in a git repo that needs to pull or push
charlie_get_git_push_pull_arrows() {

	# Continue only if there's an upstream
	command git rev-parse --abbrev-ref @'{u}' &>/dev/null || return

	local arrow_status
    # Check left (push) and right (pull) status
	arrow_status="$(command git rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)"
	# Exit if command failed
	(( !$? )) || return

	# left and right are tab-separated, split on tab and store as array
	arrow_status=(${(ps:\t:)arrow_status})
	local arrows left=${arrow_status[1]} right=${arrow_status[2]}

	(( ${right:-0} > 0 )) && arrows+="${CHARLIE_GIT_NEEDS_PULL_SYM:-⇣}"
	(( ${left:-0} > 0 )) && arrows+="${CHARLIE_GIT_NEEDS_PUSH_SYM:-↑}"

	[[ -n $arrows ]] && echo "${arrows} "
}

# Checks if git is dirty
# If the paramenter is not 0, it considers untracked files dirty
charlie_get_git_dirty() {
    # Exit if this isn't a git repo
    [ -d .git ] || return

    # If untracked files aren't considered dirty...
    if [[ $1 == "0" ]]; then
		command git diff --no-ext-diff --quiet --exit-code
    # ... else check if there are modified or untracked files.
	else
		test -z "$(command git status --porcelain --ignore-submodules -unormal)"
	fi

	(( $? )) && echo "%F{red}${CHARLIE_GIT_DIRTY_SYM:-∗}%f"
}

# Async tasks
# -----------

charlie_async_git_fetch() {
	# Use cd -q to avoid side effects of changing directory,
    # e.g. chpwd hooks
	cd -q "$*"

	# Set GIT_TERMINAL_PROMPT=0 to disable auth prompting
    # for git fetch (git 2.3+)
	GIT_TERMINAL_PROMPT=0 command git -c gc.auto=0 fetch
}

charlie_async_tasks() {
	# Initialize the async worker only once
	((!${charlie_async_init:-0})) && {
		async_start_worker "charlie_worker" -u -n
		charlie_async_init=1
	}

	# Store the path to the working tree
	local working_tree="${vcs_info_msg_1_#x}"

	# Check if the git project dir changed
    # ($current_working_tree is prefixed by "x")
	if [[ ${current_working_tree#x} != $working_tree ]]; then
		# Stop any running async jobs
		async_flush_jobs "charlie_worker"

		# Set the new working tree and prefix with "x" to prevent the
        # creation of a named path by AUTO_NAME_DIRS
		current_working_tree="x${working_tree}"
	fi

	# Only perform tasks inside git projects
	[[ -n $working_tree ]] || return
    [[ -d $working_tree/.git ]] || return

	# Do not preform git fetch if it is disabled or working_tree == $HOME
	if (( ${CHARLIE_GIT_AUTO_FETCH:-1} )) && [[ $working_tree != $HOME ]]; then
		# tell worker to do a git fetch
		async_job "charlie_worker" charlie_async_git_fetch "${working_tree}"
	fi
}

# Hooks
# -----

# Before executing it, change the window title to include the command
charlie_preexec() {
    local cmd=$2
    charlie_set_window_title "%~: $cmd"
}

# The pre command hook
charlie_precmd() {

	# Show the current path in the window title
	charlie_set_window_title "%~"

	# Get the VCS info
	vcs_info

    # Perform the async git fetch
	charlie_async_tasks

	# Render the first line of the prompt
	charlie_render_preprompt
}

# Renders the first line of the prompt
# ------------------------------------
charlie_render_preprompt() {

    local color_push_pull="%F{220}" color_path="%F{118}" color_vcs="%F{214}"
    local git_dirty=$(charlie_get_git_dirty ${CHARLIE_GIT_UNTRACKED_DIRTY:-0})
    local symbol=$(charlie_vcs_symbol)
    local user_host preprompt=''

	# Show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && user_host=' %F{154}%n%f@%F{220}%m%f'

	# Show username@host if root, with username in white
	[[ $UID -eq 0 ]] && user_host=' %F{243}%n%F{250}@%F{220}%m%f'

    # Start the versioning symbol
    preprompt+="$symbol"
    # spacing
    [[ -n $symbol ]] && preprompt+=" "
	# +git pull/push arrows
    preprompt+="$color_push_pull$(charlie_get_git_push_pull_arrows)%f"
	# +the path
    preprompt+="$color_path%~%f "
    # spacing
    #if [[ -n $symbol ]] then;
    #    preprompt+=" ≫ "
    #fi
	# +versioning info
	preprompt+="$color_vcs${vcs_info_msg_0_}${git_dirty}%f"
	# +username and machine if applicable
	preprompt+=$user_host

    print -P "\n${preprompt}"
}

# Setups the theme and ads the second line of the prompt
# ------------------------------------------------------
charlie_setup() {
	# Prevent percentage showing up if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	zmodload zsh/datetime
	zmodload zsh/zle
	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

    # See 9.3.1: http://zsh.sourceforge.net/Doc/Release/Functions.html
	add-zsh-hook precmd charlie_precmd
	add-zsh-hook preexec charlie_preexec

    # vcs_info configuration at 26.4.2 in
    # http://zsh.sourceforge.net/Doc/Release/User-Contributions.html
    # --------------------------------------------------------------

	zstyle ':vcs_info:*' enable git svn
	zstyle ':vcs_info:*' use-simple true
	# Only export two msg variables from vcs_info
	zstyle ':vcs_info:*' max-exports 2
    # Only works for git hg and bzr
    zstyle ':vcs_info:*' check-for-staged-changes true
    zstyle ':vcs_info:*' stagedstr '%F{118}+'

	# vcs_info_msg_0_ = ' %b' (for branch)
    # vcs_info_msg_1_ = 'x%R' git top level (%R), x-prefix prevents creation of a named path (AUTO_NAME_DIRS) (Currently not used, but kept for example)
    zstyle ':vcs_info:git*' formats '%b%c' 'x%R'
    zstyle ':vcs_info:git*' actionformats '%b|%a' 'x%R'

    # SVN format and action formats
    zstyle ':vcs_info:svn*' formats '%b' 'x%R'
    zstyle ':vcs_info:svn*' actionformats '%b|%a' 'x%R'
    zstyle ':vcs_info:svn:*' branchformat '%r'

	# Prompt turns red if the previous command didn't exit with 0
    PROMPT="%(?.%F{081}.%F{white}[%?] %F{red})${CHARLIE_PROMPT_SYM:-❯}%f "
}

charlie_setup "$@"
