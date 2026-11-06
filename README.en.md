# Trueque

A board for your guild in **WoW Forever**: what you **want**, what you **have** and what you **can craft**. Everyone in the guild with the addon sees the same board, and one click whispers the author with a ready-made line ("Trueque: I have what you're looking for: [Bolt of Linen Cloth]"). When someone has what you want, it tells you. ("Trueque" is Spanish for barter.)

It pairs with [Taller](https://github.com/JoseArgento/taller): what you're missing for a recipe gets posted with one button.

[Leer en castellano](README.md)

**Contents**

- [How to use it](#how-to-use-it)
- [What it sends and receives](#what-it-sends-and-receives)
- [With Taller](#with-taller)
- [Install](#install)
- [How it was tested](#how-it-was-tested)
- [Development](#development)
- [Support](#support)

## How to use it

Open it with `/trueque`, with the **round minimap button** (right click: my posts; drag it around the minimap, `/trueque minimap off` hides it), with the key binding or from the addon compartment. The window is a **parchment book** (the [Pergamino](https://github.com/JoseArgento/pergamino) skin, the same as Bitácora and the other addons) with two bookmarks:

- **Board.** On the left, the guild's posts, newest first, with filters (All / Want / Have / Can craft) and a search box. On the right, the chosen post: the item, who posted it, the quantity, their note, when it expires, and a button: **"I have it"** when someone wants something, **"I'm interested"** when someone offers something or can craft it. The button whispers the author a ready-made line, nothing more. On your own post there are **"Edit"** and **"Done"**; closing asks first.
- **My posts.** Pick what it is (Want, Have, Can craft), **shift-click** an item or recipe into the field (or type a name), how many (empty = no limit), a short note (shift-click puts items inside the note too: "I trade it for [Wool Cloth]"), and **Publish**. On the right, your current posts: a click loads one into the form to change it (the button becomes **"Save changes"**), a right click closes it, after asking.

Hovering a post with an item or recipe shows the game's tooltip, as in chat; shift-click puts the link in the chat box.

Every post **expires after 7 days** (`/trueque days N`, 1 to 30) or when you close it. A player has up to 20 posts at a time.

**Matches.** If you post "Want X" and a guildmate has "Have X" or "Can craft X", the post gets a **"match"** tag and the chat tells you once: "Trueque: Match: Ana has it: [Bolt of Linen Cloth]". The other way round too: when you offer what someone is looking for.

`/trueque idioma es|en|auto` picks the language. `/trueque errores` shows the addon's own errors, to paste into an issue.

## What it sends and receives

Posts travel as **addon messages** on the guild channel (prefix `Trueque1`): on login and when the board opens, the addon asks "who has posts?" and everyone answers with theirs; publishing or closing sends just that change. Each message carries the kind, the item reference (`item:2996`) and its name, the quantity, the note, the date and the expiry: under 250 bytes.

- **Nothing received is ever run.** Fields are read as text. A reference becomes a link only when it is shaped like one (`item:`, `enchant:`, `trade:`); anything else stays plain text. A player can only post, change or close their own posts; up to 20 per player are kept.
- **It never writes in chat on its own.** The "I have it" and "I'm interested" whispers go out only when you click.
- Received posts are saved per guild (`TruequeDB`), so the board is full when you log in, and expired ones are dropped.
- On a **trial account**, Forever does not allow sending addon messages: you see the guild's board, but your posts stay with you. The addon tells you once.

## With Taller

With [Taller](https://github.com/JoseArgento/taller) installed, "My posts" shows a **"Post what I'm missing (Taller)"** button: it reads Taller's shopping list and posts a "Want" for each missing material, with the quantity. Already posted ones are skipped. Without Taller the button is not there.

## Install

Copy the `Trueque` folder into `Interface\AddOns\` inside the game's Forever folder (`World of Warcraft\_forever_\Interface\AddOns`). For the guild to see your posts, they need it too.

## How it was tested

**Tested:**
- ✅ Every function it uses exists in Forever 1.60.1: `tools/check_api.py` against the dumps of [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources) and the UI of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), `forever` branch.
- ✅ [forever-lint](https://github.com/JoseArgento/forever-lint) only shows the FL012 note (trial accounts, handled); Addon Sentry: "No risk signals" (all it can do is whisper, and only from a click).
- ✅ **41 tests** in Lua 5.1 (WoW's Lua) with several players of one guild passing messages around: publish, close and expire; ask and answer; nobody can close or overwrite someone else's post; broken and hostile messages dropped or reduced to text; `|` and `%` in text; the cap of 20 and the 250 bytes; matches, said once; the whisper only from a click; trial accounts; no guild; language; the book and the form; Taller present, absent and broken; the addon's own errors kept.

**Not seen in the client yet ⏳:**
- Everything visual: the book, the tags, the chips, the minimap button.
- That `C_ChatInfo.SendChatMessage` with `WHISPER` reaches "Name-Realm" as the sender arrives in `CHAT_MSG_ADDON`.
- That `ChatFrameUtil.InsertLink` is what Forever calls on shift-click with a focused field (it is what Bitácora uses).
- The link colour of an item the client has not loaded yet (white until it knows it).
- A whole guild running it at once.

**If something breaks:** `/trueque errores` shows the addon's last error (the last 10 are kept, no popups) to paste into a GitHub issue.

## Development

```bash
pip install pytest lupa
pytest
python tools/check_api.py --bir ../BlizzardInterfaceResources --ui ../wow-ui-source --scanner ../addon-sentry/src
python tools/make_icon.py   # redraws Trueque/Media/icon.tga
```

`Bindings.xml` is not listed in the TOC: the game loads it on its own. A `v*` tag packages the addon with the BigWigs packager. The skin is copied into `Trueque/Libs/Pergamino` (`tools/vendor.sh` in the pergamino repo updates it).

Not affiliated with Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc. MIT license.

## Support

All of this is free and open source, and it stays that way: no paid features, nothing early for supporters. If it helped you and you want to cover the time it takes to keep it working, you can do that on [Patreon](https://www.patreon.com/cw/DoblePupi). Thanks ♥
