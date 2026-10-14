# Branding backups

Backups of the live Jellyfin branding are not kept in this repo, since it is public and the saved login disclaimer can hold private details. Every other file in this folder is ignored by git.

`rollback.sh` reads the backup from the folder named by `JELLYFIN_THEME_BACKUP_DIR`. That folder holds `branding.json` (LoginDisclaimer, CustomCss, SplashscreenEnabled as returned by `/Branding/Configuration`), `server-name.txt`, and a splash image when one was set.
