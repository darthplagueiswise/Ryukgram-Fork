[release] RyukGram v1.3.3

### 🆕 New features
- Updated for Instagram 437
- Story tray long-press "Profile picture" now also works in Instagram's new subscriber story preview menu
- New Instagram Plus menu in General — turns on Instagram's paid subscriber features inside the app, including story and message peek, story, chat and bio fonts, the app icon picker, custom story lists and more, with turn everything on/off and reset; features whose content comes from Instagram's servers may show empty since they still need a real subscription, and everything resets on its own if Instagram fails to launch a few times
- Keep deleted messages can now also keep the ones you unsend yourself — shown faded in chat and added to the deleted messages log on the right, like sent messages
- New "Save image (no music)" story download option — saves just the picture from a photo story that has Instagram music on it
- Auto-scroll reels is back — choose Instagram default or RyukGram mode (keeps advancing after you swipe back)
- New reels playback menu — hold the ⋯ or audio button on a reel for quick speed, seek (skip back/forward by a custom amount) and auto-scroll controls
- Hide suggested accounts and channels in Direct messages search
- Messages-only mode is now its own menu, can turn on automatically during a daily window (e.g. 10 PM – 6 AM), and adds a notifications shortcut in the inbox header that opens the activity feed the hidden tab would show
- Device ID masking now also hides the vendor ID and machine ID, can block Apple device attestation, and the reset can start fresh while keeping masking on
- Hold the account name at the top of Direct to show or hide your hidden chats, with an optional passcode/Face ID lock
- Follow requests tracker shows a badge for updates you haven't opened yet
- Story and disappearing-media overlay buttons can be repositioned by dragging them on a preview
- Notification pill can be placed anywhere on a phone preview, not just top or bottom
- Favorite GIFs long-press menu can now copy a GIF's link
- The DM "Draw" feature can now send an image as your doodle, from the in-app gallery, Photos, your Instagram or iOS keyboard stickers, or a pasted image, with a built-in editor to crop, freely resize, and remove the background
- Instants download now works on videos too, not just photos — expand, save, share and download-all all handle video instants
- Send a video from your gallery as an Instant — pick it, frame it square, trim any 7 seconds on a scrollable timeline with a live preview, then hold to record
- Confirm before capturing an Instant — optional alert on a photo tap or a held video before it sends, plus a confirm before tapping to switch Instants
- Custom chat backgrounds can now be videos or GIFs, not just images — pick from Photos, Files or the in-app gallery, frame with pan-zoom and trim video (GIFs become looping video), with the same opacity, blur and dim controls, and re-crop, re-trim or re-adjust any background later from the chat or settings
- Change Instagram's own interface language from the tweak — a picker under Interface with a full language list, including Arabic even if your device isn't set to it; restart to apply
- New "Block surveys" toggle under Focus/distractions — stops Instagram's in-app surveys and feedback prompts across the app

### 🛠 Fixes
- Custom chat background now fills behind the message input on Instagram 437 instead of leaving a black strip
- Follow requests tracker no longer counts tapping "Following" on an account you already follow as a new request
- Detailed color picker no longer crashes when you pick a color in the story drawing editor on Instagram 434
- OLED theme no longer turns the RyukGram settings screens fully black
- Downloading reels/videos with newer Instagram audio (xHE-AAC) no longer fails
- Feed scrolling is smoother, especially with the OLED theme enabled
- Favorite GIFs now send and appear reliably in Direct messages, and a newly pinned GIF loads without reopening the picker
- Deleted messages log now saves photos and videos at full quality instead of a low-res thumbnail
- Deleted messages log no longer crashes when you pull to refresh right after leaving a chat
- Reroute native Save now shows Instagram's Save button and long-press Save on DM photos & videos even where Instagram hid them, including in vanish mode
- Settings that need a restart now take effect after one restart instead of sometimes needing two
- Auto-clear cache now runs reliably on the chosen interval and finishes even if you close Instagram mid-clear
- Saving or sharing media now always uses a clean name (like username_stories_date) instead of the internal temporary filename
