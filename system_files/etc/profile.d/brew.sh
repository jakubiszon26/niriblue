# Load Homebrew into the shell environment if installed
if [ -d /var/home/linuxbrew/.linuxbrew ]; then
    eval "$(/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
