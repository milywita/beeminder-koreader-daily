# beeminder-koreader-daily

A KOReader plugin that sends your pages-read-today to a Beeminder goal.

It's a fork of [beeminder.koplugin](https://github.com/cbrxyz/beeminder.koplugin) by [@cbrxyz](https://github.com/cbrxyz). The original tracks each book against its own goal and counts page turns. I wanted one goal for all my reading, and I wanted the numbers to stop jumping every time I flipped through a table of contents. So this version:

- sends a single daily total, no matter how many books you read that day
- takes its numbers from KOReader's statistics database (`statistics.sqlite3`), so they match what you see under Tools → Statistics

## Installing

1. Download the repo as a ZIP, or clone it.
2. Rename the folder to exactly `beeminder.koplugin`. KOReader ignores anything that doesn't end in `.koplugin`, so a folder called `beeminder.koplugin-main` (what GitHub's ZIP gives you) won't load, and you won't get an error about it.
3. Copy it into KOReader's plugins folder:
   - Android / Boox: `/sdcard/koreader/plugins/`
   - Kobo / Kindle / Linux: `koreader/plugins/` inside your KOReader install
4. Restart KOReader properly. Waking the device from sleep isn't enough.
5. You should now see Beeminder under Tools → More tools.

You'll also need Statistics turned on in KOReader, since that's where the page counts come from.

## Setting it up

You need a Beeminder goal to log to. A Do More goal fits well ("read 30 pages a day"). Its slug is the last part of the goal's URL, so `beeminder.com/alice/reading` has the slug `reading`.

In KOReader, go to Tools → More tools → Beeminder and fill in:

- your Beeminder username
- your [auth token](https://www.beeminder.com/api/v1/auth_token.json)
- the goal slug (defaults to `reading` if you leave it blank)

Then read a few pages, tap **Sync now**, and check that a datapoint shows up on your goal page.

## Using it

Mostly you don't have to do anything. The plugin syncs when you close a book, when the device goes to sleep, and when you exit KOReader. Each time, it counts the distinct pages you've read today (by your device's local date) across every book and either creates today's datapoint or updates the existing one. If you read in the morning and again at night, you still end up with one datapoint holding the full total.

The Beeminder menu shows today's page count, so you can check it before anything is sent. **Sync now** pushes it right away, which is handy after you've been offline.

## Things to know

- Syncing needs a network connection. If you're offline when it tries, nothing gets sent, but your reading is still recorded locally and goes out on the next successful sync.
- If you kill KOReader from the app switcher instead of exiting it, none of the sync triggers run.
- KOReader has renamed its stats table between versions (`page_stat` / `page_stat_data`). Both are handled, but a future schema change could break this.

## If something's off

**Menu says "Today's pages: unavailable":** the statistics database couldn't be read. Make sure Statistics is enabled and you've read at least one page since.

**Nothing shows up on Beeminder:** check the username, token and slug for typos, and make sure Wi-Fi was on when it synced.

**The number looks wrong:** compare it with Tools → Statistics. They read the same data, so they should agree. If they don't, please open an issue.

## Credits

Built on [beeminder.koplugin](https://github.com/cbrxyz/beeminder.koplugin) by [@cbrxyz](https://github.com/cbrxyz).
