#TODO How can I get this programatically (given that this file is sourced not executed)
script_dir="$HOME/Yew/cschuyle-bin"

alias ddf="$script_dir/ddf"

export CS_DF_DATA_DIRS="$DRAGNON_DF_DATA_DIRS"

export PATH="$PATH:$script_dir"

[[ -d "$script_dir/privates" ]] && export PATH="$PATH:$script_dir/privates"