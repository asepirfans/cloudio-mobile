# Karaoke search and automatic lyrics — 2026-10-18

Search now exposes persistent Musik/Karaoke categories. Karaoke searches add a
karaoke query to both catalogs, require explicit karaoke/backing-track/no-vocal
labels and reject vocal-guide/with-vocals labels. This is metadata filtering,
not signal analysis or vocal removal. General YouTube music filtering still
rejects spoken/non-music content.

Karaoke tracks persist their mode and original search hint in playlists/player
sessions. Playback automatically starts a cached original-song lyrics request.
The lyrics resolver uses cleaned song metadata and query hints rather than
assuming a karaoke uploader is the original artist. A lyric match needs both
song and artist evidence; unrelated artists and instrumental-only records are
not accepted. Original lyric timestamps are deliberately rendered as manual
text because karaoke intros, keys and arrangements can have different timing.
The lyrics control uses the prefetched result without requiring a typed lookup.
Karaoke playback does not automatically transition to ordinary vocal radio.

Validation:
- Four karaoke service/model tests passed, including vocal-guide rejection,
  saved metadata, correct original-song lyrics, and ambiguous-artist rejection.
- Existing lyric/filter/session/player regression cases passed (40 service and
  controller cases in the combined run). The widget selector was corrected to
  distinguish the result title from identical input text, then its suite passed.
- The widget test switches from a TikTok sound to Karaoke and checks the result,
  category selection and source badge. Screenshot inspected:
  `tool/ui_previews/karaoke-search.png`.
- Two search layout checks passed: 390 logical pixels, and 320 with 1.4x text.
- Targeted Flutter analysis: no issues.
- Live opt-in test passed for `Adele Someone Like You`: search returned a
  labelled karaoke recording (video ID DTGY_eEJ_to), and automatic LRCLIB lookup
  returned original-song lyrics with 52 lines. No lyrics text is copied here.
  Log: `/private/tmp/cloudio_karaoke_live_test.log`.

The live service check verifies search/lyric retrieval, not listening to the
recording or synchronized lyrics. Lyrics remain dependent on catalog coverage
and network availability. Users can open Lirik in the player; it is not forced
open over playback.

The final `lib/main.dart` iOS release build succeeded (48.8 seconds in Xcode),
was installed on the connected iPhone 12, and CoreDevice confirmed launch.
