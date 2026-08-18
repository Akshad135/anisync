# Anime Watcher for Omarchy 🎌

A native [Omarchy](https://omarchy.org/) status bar and popup plugin that synchronizes with **AniList** and **MyAnimeList (MAL)** to track anime episode releases, manga chapter countdowns, and watchlist progress with native desktop notifications.

![Anime Watcher Preview](preview.png)

## ✨ Features

- **⚡ Zero-Friction Dual-Account Sync**: Connect your public AniList, MyAnimeList, or both simultaneously—no passwords or OAuth tokens required.
- **🕒 Top Bar Release Ticker**: Live countdown pill on your status bar showing your next upcoming episode (e.g. `One Piece Ep 1175 · in 2h`) and new episode drop badges (`󱅫 2 New`).
- **🔔 Native Desktop Notifications**: Notifies you with episode titles, numbers, and cover art via `omarchy-notification-send` when new releases air.
- **🎭 Dual Profile Identity**: Overlapping avatar bubbles and unified username display when both AniList and MyAnimeList accounts are connected.
- **🎨 Dynamic Theming & Ambient Artwork**: Automatically harmonizes with your active Omarchy theme (`colors.toml`), with smart fallback to your currently watching show's cover art or custom banner image.
- **📱 Rich Multi-Tab Popup Panel**:
  - **Anime**: Live upcoming episode timeline with exact countdowns, recent 48h drops with "Mark as Seen", and active watchlist.
  - **Manga**: Reading list progress tracking with chapter counts and scores.
  - **Explore**: Instant search across AniList for any anime or manga with direct links and copyable URLs.
  - **Settings**: Dual provider management, section toggles, release alerts, background check frequencies, and custom banner backdrop.
- **🔌 IPC & CLI Integration**: Trigger sync, open, close, or toggle the popup via `omarchy-shell akshad135.anime-watcher <action>`.

---

## 🚀 Installation

Install and enable the plugin with a single command:

```bash
omarchy plugin add https://github.com/Akshad135/anime-watcher.git --enable
```

Alternatively, to install manually:

```bash
git clone https://github.com/Akshad135/anime-watcher.git ~/.config/omarchy/plugins/akshad135.anime-watcher
omarchy plugin enable akshad135.anime-watcher --section right
```

Restart the shell to load the widget:

```bash
omarchy restart shell
```

---

## 🎮 Usage & Controls

- **Left-Click Top Bar Button**: Toggle popup drawer.
- **Right-Click Top Bar Button**: Force immediate background re-sync.
- **Search Keybinding / CLI**: Toggle via `omarchy-shell akshad135.anime-watcher toggle`.
- **Keyboard Shortcuts in Drawer**:
  - `Escape`: Close popup drawer.
  - `Enter` (in Search): Execute AniList search.

---

## 🛡️ Security & Architecture

- **Zero Credentials**: Uses only public GraphQL and JSON endpoints with strict `--max-time` bounded network requests.
- **Safe Execution**: All background commands use structured argument arrays via Quickshell `Process` with zero shell string interpolation.
- **State Storage**: Settings and seen notification caches are stored safely in `~/.local/state/omarchy/plugins/akshad135.anime-watcher/`.

---

## 🧪 Testing

Run the automated test suite:

```bash
npm test
```

---

## 📄 License

[MIT](LICENSE) © [Akshad Agrawal](https://github.com/Akshad135)
