savedcmd_diamorphine.mod := printf '%s\n'   diamorphine.o | awk '!x[$$0]++ { print("./"$$0) }' > diamorphine.mod
