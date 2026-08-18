# Anime Watcher for Omarchy 🎌

A native [Omarchy](https://omarchy.org/) status bar plugin that syncs with **AniList** and **MyAnimeList (MAL)** to track anime episode and manga release countdowns, with desktop notifications when new releases drop.

![Preview](preview.png)

## ✨ Features

- **⚡ Zero-Friction Account Sync**: Enter your public AniList or MyAnimeList username—no passwords or OAuth tokens needed.
- **🕒 Top Bar Release Ticker**: Live countdown pill on your status bar showing your next upcoming episode (e.g. `OP Ep 1175 in 3d` or `Solo Leveling Ep 8 in 2h`) and new episode drop badges (`2 New`).
- **🔔 Native Desktop Notifications**: Notifies you with episode titles, numbers, and cover art via `omarchy-notification-send` when new releases air.
- **📱 Rich Multi-Tab Popup Panel**:
  - **Schedule**: Chronological timeline of upcoming episodes with countdowns, air dates, and cover art.
  - **Drops**: Catch up on releases from the past 48 hours with "Open in Browser" and "Mark as Seen".
  - **Watchlist**: View your active watching and reading progress with scores and episode counts.
  - **Search**: Search any anime or manga on AniList instantly.
  - **Settings**: Configure sync accounts, notification preferences, and check intervals.

## 🚀 Installation & Setup

1. Clone or symlink into your Omarchy plugins directory:
   ```bash
   ln -s ~/Projects/anime-watcher ~/.config/omarchy/plugins/akshad135.anime-watcher
   ```
2. Rescan plugins in Omarchy Shell:
   ```bash
   omarchy-shell shell rescanPlugins
   ```
3. Enable and add to your status bar:
   ```bash
   omarchy bar move akshad135.anime-watcher --section right
   ```

## 🛠️ Configuration

Open the plugin on your bar, switch to the **Settings** tab, and enter your AniList and/or MyAnimeList username.

## 📄 License

MIT License
