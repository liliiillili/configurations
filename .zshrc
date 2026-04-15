export PATH="/opt/homebrew/bin:$PATH"
#export PATH="/opt/homebrew/bin:$PATH"
#/opt/homebrew/Cellar
export ZSH="$HOME/.oh-my-zsh"
export PATH="/opt/homebrew/opt/python@3.14/bin:$PATH"
export PATH="/Users/a/Development/bin:$PATH"

ZSH_THEME="agnoster"

plugins=(
  git
  brew
  zsh-completions
  zsh-history-substring-search
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

prompt_context() {
  if [[ -n "$SSH_CONNECTION" ]]; then
    prompt_segment black default "%n@%m"
  else
    prompt_segment black default "%n"
  fi
}
export PATH="$HOME/.local/bin:$PATH"
