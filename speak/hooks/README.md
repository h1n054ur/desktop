# speak hooks: install lines

For `speak/install.sh` (merge these in, then this file can go):

```sh
ln -sfn "$here/bin/speak-focused" "$HOME/.local/bin/speak-focused"
mkdir -p "$HOME/.config/opencode/plugins"
ln -sfn "$here/opencode/speak.ts" "$HOME/.config/opencode/plugins/speak.ts"
```

`$here` is the `speak/` folder. The Claude Code hook runs from the repo path, so it needs no link.
