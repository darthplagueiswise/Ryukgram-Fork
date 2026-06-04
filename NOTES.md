[release] RyukGram v1.3.0

### ✨ Highlights
- **On-device gallery** — every download can mirror into an in-app library, filterable by type / source / uploader, with audio and GIF entries that play inline.
- **Download manager** — parallel downloads with a configurable limit, a combined progress pill and a live queue (cancel / retry / redownload / bulk select).
- **Universal notifications** — one configurable pill replaces every toast, error HUD and download banner, with per-action routing and four styles.
- **Deleted messages log** — a dedicated UI for every unsent message type, with per-sender groups, search, filter and bulk Save / Share / Delete.
- **Security & Privacy** — passcode + biometric lock for settings, gallery, DMs, individual chats and Instagram itself.
- **Profile Analyzer overhaul** — snapshots, a visited-profiles tracker, and inline Follow / Unfollow on every list.
- **Custom chat backgrounds** — per-chat images injected into IG's native theme picker, with upload, cropper and per-image opacity / blur / dim.

### 🆕 New features

#### Downloads & media saving
- Download manager — parallel downloads with a configurable limit, one combined progress pill, and a live queue with cancel / retry / redownload, long-press share / save and bulk select; opens from the pill, a home-bar shortcut or Settings
- Advanced encoding panel — full control over HD downloads: codec (hardware / libx264), preset, tune, H.264 profile + level, CRF / bitrate, pixel format, max resolution, frame rate, audio codec / bitrate / channels / sample rate, faststart and metadata stripping
- Enhanced media resolution — pulls higher-quality images straight from IG's CDN
- Live download + encode progress — HD downloads show a real percentage in the pill
- Auto-retry dropped downloads — offline downloads are parked and resume the moment the connection returns
- Keeps working in the background — downloads, encoding, profile scans, batch follow/unfollow and audio sending no longer pause when you leave the app
- Save to a dedicated album — every download can route into a named Photos album when enabled (defaults to RyukGram)

#### Gallery
- On-device gallery — filterable by type / source / uploader, with audio and GIF entries that play inline in the carousel; folders show a thumbnail collage + last-activity date and can group by uploader (sections or virtual folders)
- Hold the DM tab to open the gallery
- Save to Gallery from the expanded media viewer — the share button surfaces a Save / Share menu when the gallery is on, carrying username / source attribution through
- Send from gallery — pick from the in-app gallery or the Photos library when the gallery is enabled

#### Notifications
- Universal notification pill (Minimal / Colorful / Glow / Island) replaces every toast, error HUD and download banner, with per-action routing (custom pill / IG-native / off), top or bottom placement, swipe-to-dismiss, multi-pill stacking and a master kill switch

#### Profile & Profile Analyzer
- Show full follower / post counts on profile headers
- Profile card details — view count, like count and upload date overlaid on each post / reel card in profile grids, with optional short-number format and on-demand fetch for posts that ship without counts
- "Copy all info" — copies username / name / bio / link / ID as labeled lines
- Copy Info is now a full section — toggle each variant, reorder, and set the default tap straight to "Copy username", etc.
- Filter & sort follower / following lists — a half-sheet to reorder or filter by mutuals, who-follows-you, verified or A–Z, reverse order, jump to top / bottom, and load more on demand
- Profile Analyzer — snapshots: optionally archive a dated copy of each scan and choose which one new scans compare against, with multi-select delete, a size limit and usage warnings
- Profile Analyzer — optional Visited profiles tracker: logs every profile you open with last-viewed date, visit count, and date / verified / private filters
- Profile Analyzer — inline Follow / Unfollow on every row, lazy-loaded on scroll
- Profile Analyzer — Mutual followers list supports inline and batch Unfollow

#### Messages & DMs
- Deleted messages log — a dedicated UI for every unsent message type, with per-sender groups, search, filter and bulk Save / Share / Delete
- Custom chat backgrounds — per-chat images injected into IG's native theme picker, with library upload + built-in cropper, per-image opacity / blur / dim, an optional global default, and a per-account list of chats with backgrounds
- DM voice messages — long-press → Download → Photos / Gallery / Share
- Disappearing DM media — "Download to Gallery" now truly saves to the gallery; share / Photos saves attribute to the sender
- DM Upload Audio — pick existing audio or video from the gallery
- Pin recipients in the share sheet — long-press to float chats to the top
- Hide the "Send to group chat" row in the share sheet, with an optional confirm before sending
- Silence incoming calls — audio / video calls ring silently with no notification or screen, without declining them; works even when the app is closed

#### Stories & Notes
- Mentions overlay button on stories — opens the list of mentioned accounts (handles, shared-post owners, in-post tags, reel collab co-authors)
- Bypass Reveal sticker — view stories blurred behind a Reveal sticker without DMing the author
- Allow video in the photo sticker — the story photo-sticker picker accepts videos too
- Custom solid or gradient color for music and lyric stickers
- Custom note themes — Background / Text / Emoji buttons above the color palette in the bubble editor: pick any bubble and text color, or set a custom emoji
- Notes long-press — copy text and download GIF / audio (Photos or Gallery)

#### Reels, Instants & media
- Send Instants from your photo album — a gallery button on the Instants camera with a built-in square cropper, posting through IG's native capture flow
- Instants action button — Expand / Save (Photos / Gallery) / Share / Save all, fully configurable through the standard action-menu config (reorder, hide, default tap)
- Allow screenshots on Instants — bypasses the screenshot / screen-record block
- Reels action button — bulk download / copy for photo-carousel reels, auto-hidden on single-item reels
- Reels audio detail page — copy link, download and share, or save to gallery
- Reels audio-only quality picker now saves into the gallery when chosen
- Swipe a reel left to open the author's profile
- Skip sensitive-content covers — auto-reveals reels and posts hidden behind warnings
- Start media muted — expanded videos open with sound off

#### Comments
- Custom GIF in comments — long-press the composer's GIF button to paste a Giphy link
- Comment media long-press — Download / Copy link / Expand on GIF and image comments, routed through Photos / Gallery

#### Interface, navigation & theming
- Settings → Interface — renamed from Navigation; gathers Tab-bar shortcuts (Home shortcut + Action-button icon), Notifications, tab-bar config, tab hiding, Messages-only and Experimental flags in one place
- What's-new indicator — a blue dot marks settings added this release and clears once you view them, with an Advanced toggle to keep it pinned
- Home shortcut button — a configurable extra button on the home top bar with a multi-action menu: Gallery, Downloads, Settings, Profile Analyzer, Changelog, Security & Privacy, Hidden chats, Locked chats, Fake location and Clear cache
- Theme picker (Off / Light / Dark / OLED) with a Force-theme toggle, replacing the separate Force-dark and Full-OLED switches
- Global action-button icon picker — change the icon used across feed, stories, reels and DMs
- Per-button action icons — override the action-button icon for a specific surface (feed, reels, stories, DMs, profile) or leave it following the shared default
- App icon picker — swap the home-screen Instagram icon for older designs, reverting on failure
- Liquid Glass tab bar — Fixed (never shrink) or Hide-on-scroll mode
- Optional date header at the top of feed / reel / story action menus

#### Security & Privacy
- App-wide lock — passcode + biometric lock for tweak settings, the gallery, the deleted-messages log, Profile Analyzer, the DM inbox, individual chats, and Instagram itself, with per-target idle / re-lock options
- Hidden chats — long-press a DM to hide it, managed under Security & Privacy
- App-switcher snapshot shroud — covers IG content when a locked surface is visible
- Per-account lists — excluded chats, hidden chats, locked chats and share-sheet pins are now scoped per IG account

#### Confirmations
- Confirm Instants emoji reaction — optional confirm before a quick reaction sends
- Confirm Instants capture & Confirm switching Instant — optional confirms before the shutter fires and before a tap advances to the next Instant
- Confirm note like & Confirm note emoji reaction — optional confirms on the opened-note screen

#### Hiding ads & clutter
- Hide ads — per-surface toggles (Feed, Stories, Reels, Explore & Search, Shopping) under a master switch
- Hide stories midcards (Trending / Music)
- Hide friends avatars on the Reels Friends tab
- Hide the social-context overlay on reels
- Hide "Made with Edits" / "Open in Edits" promo pills on reels
- Hide the TestFlight beta-update popup

#### Localization & about
- New translations — Portuguese (Brazil), Turkish, Chinese (Simplified) and French
- In-app translator tool can now export any shipped language's strings, not just English
- About → Credits — a new sub-screen with grouped Inspirations / Code / Translators rows

### 🛠 Fixes
- Fake profile stats restored on IG 428+ (the profile-stats cell moved to Swift)
- Repost restored on IG 428+ — no longer fails to save before opening the creator
- Confirm voice messages restored on IG 428+
- Send file in DMs works again on IG 430
- "Warn before clearing on refresh" dialog works again on IG 430
- Story seen receipts work on accounts in IG's encrypted-DMs rollout
- Keep deleted messages works on accounts in IG's encrypted-DMs rollout
- Keep deleted messages — pull-to-refresh on one account no longer clears preserved messages from your other logged-in accounts
- Cancelling a fastest-mode download now actually aborts (audio extract, DASH and bulk paths)
- Download pill no longer gets stuck after audio and comment-GIF taps
- Story video download from the long-press gesture
- Media viewer Save-to-Photos failing for profile pictures
- Single carousel save now carries the post's username
- Repost reels now download / repost / expand as video instead of the thumbnail
- Upload Audio — trim UI play button silent after pausing; some Reels audio files failed to convert
- DM Upload Audio — video from the library no longer silently fails to send
- Disappearing media "Download to Gallery" was routing to Photos
- DM voice and disappearing-media saves now attribute to the actual sender
- Follow indicator survives re-layout and shows on profiles opened from mentions / deep links, and no longer shows the previous profile's status when you reopen a different one
- Fake profile stats / hide call buttons no longer require a restart to toggle
- Profile Analyzer — tapping a row in any list now dismisses the settings sheet before opening the profile
- Action-button icon picker — SF Symbols render verbatim across feed / stories / DMs / profile
- Story action button missing on first launch
- DM visual action button not loading until toggled off and on
- Story resumes after dismissing our action-button menu
- Carousel multi-photo posts no longer crash on action-button open
- Action-sheet popup rows now tappable across the full row width
- Messages-only floating gear unclickable under the nav blur
- OLED keyboard reverting to translucent on focus
- Tapping a DM push while Settings / gallery / etc. is open no longer leaves the tweak nav bar stuck above the chat
- Custom note themes — color picker no longer crashes the bubble editor
- Language picker collapsing zh-Hant and zh-Hans to the same display name
- Hide trending searches — no more empty gap under the search bar
- Hide friends map — works again after IG moved the tile
- Doom-scrolling reel limit restored on the latest IG, and now windows around the tapped reel
- Strip-tracking / embed-link rewrite now also applies to the profile Copy URL action and the in-app DM share preview
- DM full last-active time — no longer drifts with the wall clock and renders in non-English IG locales
- Popup dismissals persist across launches on sideload — "Introducing the Instagram map" and other NUX banners no longer reappear every cold launch, without breaking rich notifications

### ⚡ Improvements
- Output filenames consistent across every save surface — `@username_context_timestamp` for feed / reels / stories / DMs / notes / comments / disappearing media
- Custom date format — relative threshold, compact "1h" style, and a Combine-with-date option for "Jan 5, 2026 (2h)" or "2h – Jan 5, 2026"
- Backup & Restore reworked — pick what to include from Settings: per-account chat & story filters, hidden & locked chats, Profile Analyzer, gallery, chat backgrounds and deleted messages. Settings stay a clean, shareable JSON with no IDs or device data, while picking media exports a compressed bundle. Backups now cover every account at once, so restoring on a new device fills each account in as you sign in
- Download pill redesigned — compact, light blur, dark / light aware
- Clear cache — new "Preserve messages database" toggle skips DMs, drafts and Notes when clearing
- Settings → Confirm actions grouped into sections (Likes, Reactions, Stories & highlights, Instants, Follows, Calls, Messaging, Comments & posts)
- Confirm-action dialogs now show which action you're confirming
- Confirm sticker interaction is now a picker — Disabled / All / Reaction stickers only
- Follow indicator is now a picker — Off / On / Colored
- Deleted-messages filter grouped into Media / Audio / Shared / Other, with an active-count badge
- Deleted messages — edit history (original + each edit with timestamps) captured before unsend; "Open profile" button on the user view
- Unsent-message pill now shows the sender's username, fires on backgrounded accounts too, and labels which of your accounts received the unsend
- Scroll-to-top button on the deleted-messages and gallery views
- Tap a notification pill to jump to its target — Saved to Gallery opens the gallery, the unsent-message pill opens the deleted-messages log
- Tap a row in the excluded-chats / users, locked-chats or hidden-chats list to open the profile (dismisses the popup, like Profile Analyzer)
- No more double notifications when IG is open — toggle in Advanced → Notifications, on by default; rich previews still come through as normal
- Story mentions overlay button gains an optional count badge for unique mentioned accounts
- View story mentions now also lists accounts surfaced by shared post / reel stickers (post owner, in-post tags, reel collab co-authors)
- Force legacy stickers in tray now also restores the Reveal sticker, in addition to Quiz
- No suggested users extended to the activity (heart) tab
- Hide Meta AI now also suppresses the "Try free AI creation tools" feed unit
- View highlight cover opens the uncropped square image
- Send audio as file — long-press the DM camera button to upload while replying
- Upload Audio trim UI — dedicated Stop button, smoother playback
- Disable vanish-mode swipe now also blocks the pull-up animation

### 🙏 Credits
- [@Mikasa-san](https://github.com/Mikasa-san) — code contributions
- Bruno (@brunorainha) — Portuguese (Brazil) translation
- [@yesnt10](https://github.com/yesnt10) — Turkish translation
- [@jaydenjcpy](https://github.com/jaydenjcpy) — Chinese (Simplified) translation and Chinese (Traditional) wording fixes
- [@yannouuuu](https://github.com/yannouuuu) (Yann Renard) — French translation
- [@n3d1117](https://github.com/n3d1117) (Edoardo) — Following feed mode (PR #19)
- [@efibalogh](https://github.com/efibalogh) — code inspiration
- [@asdfzxcvbn](https://github.com/asdfzxcvbn) — [zxPluginsInject](https://github.com/asdfzxcvbn/zxPluginsInject) sideload-compatibility shim

### ⚠️ Known issues
- Preserved unsent messages can't be removed via "Delete for you"; pull-to-refresh clears them (a warning is available in Settings)
- With Liquid Glass buttons + Hide-UI-on-capture both on, the DM eye leaves an empty glass bubble in captures
