cd $(dirname $(readlink -f $0))/../src
find . -name '*.lua' | xargs grep --color=always "$1[ ]*=[^=]"
