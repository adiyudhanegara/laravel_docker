zstyle :compinstall filename '/home/user/.zshrc'
autoload -Uz compinit
compinit
zstyle ':completion:*' completer _complete _ignored
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s

HISTFILE=~/.zsh_histfile
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
unsetopt beep
bindkey -e
autoload -U promptinit && promptinit
autoload -U colors && colors

setopt sharehistory
setopt hist_ignore_dups
setopt hist_reduce_blanks
setopt no_hist_beep
setopt hist_ignore_space

setopt multios
setopt correct

READNULLCMD=less

REPORTTIME=3
#PS1="%(3L.+.)%(?..%{${fg[yellow]}%}%?%{${fg[default]}%})%~%(!.%{${fg[red]}%}#.%{${fg[green]}%}%%)%{${fg[default]}%} "
PS1="%B%F{red}%(?..%? )%f%b%B%F{blue}%B%40<..<%~%<< %b%# "

#zstyle ':completion:*' menu select=4
bindkey '\e[3~' delete-char
bindkey '^[[H' vi-beginning-of-line
bindkey '^[[F' vi-end-of-line
bindkey -M viins '^r' history-incremental-search-backward
bindkey -M vicmd '^r' history-incremental-search-backward
bindkey -M viins '^O' push-line-or-edit
zstyle ':completion:*'            matcher-list 'm:{a-z}={A-Z}'
CORRECT_IGNORE='_*' # don't correct to completion functions
zstyle ':acceptline:default' nocompwarn 1 # disables useless message: "screen will not execute and completion _screen exists."
TIMEFMT='%J: %U+%S, %P CPU, %*E gesamt'

export EDITOR=vim
alias reload="kill -SIGUSR1 1"
