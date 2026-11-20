# [Soeta's] Kjapp Utsendelse av Kolli

*K.U.K., "quick dispatch of parcels".* Mail tools for **World of Warcraft: Forever** (interface 16001), made to work alongside [Postal](https://www.curseforge.com/wow/addons/postal).

- **36 attachment slots** instead of 12 (set anywhere from 12 to 120). The extra slots continue the game's own grid in reading order, and every item stays in the slot you put it in. When you press Send, the items past the first 12 go out as follow-up letters of 12 to the same person, with "(2/3)" added to the subject.
- **Greyed out in your bags:** items in the extra slots look attached in Blizzard's bag windows, like the game does for real attachments.
- **Resizable Send Mail window:** drag the bottom-right corner down for more rows of slots; the mouse wheel scrolls the slots when they don't all fit. Right-click the corner to go back to the normal size.
- **Automatic subject:** an empty subject becomes the first item's name, like "Linen Cloth (20)". Right-click a few items, type a name, press Send. A subject you type yourself is never changed.
- **To field finds your alts first,** then friends (your friends list and Battle.net friends in this game), guild members, recently mailed and Postal contacts. The order is yours to change, and it always fills in the plain character name.
- **QuickAttach profiles per character:** choose which of Postal's QuickAttach buttons show. Jewelcrafting, Inscription and Optional Reagents are hidden by default, since Forever doesn't have them. A gear button under the buttons opens the settings.
- **One inbox row per batch:** letters from the same sender with the same subject and text show as one row, with all their attachments together. Shift-click the row to take everything.
- The "Postage:" label is gone; only the cost shows.

## Install

1. Click **Code → Download ZIP** on this page and unzip it.
2. Copy the **`KUK`** folder from inside `KjappUtsendelseAvKolli-main` to `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game (a new add-on folder isn't picked up by `/reload`).

**Postal** isn't included: its license doesn't allow sharing copies. Install it yourself. The slots, bag highlight, resizing, subject and inbox grouping work without it; the QuickAttach and To field features need Postal running.

## Settings

Type `/kuk`, click the minimap button, the gear under the QuickAttach buttons, or open Options → AddOns → [Soeta's] Kjapp Utsendelse av Kolli.

| Command | Does |
|---|---|
| `/kuk` | Settings window |
| `/kuk qa` | QuickAttach buttons and profiles |
| `/kuk max 36` | Number of attachment slots |
| `/kuk to alts friends guild` | To field order (sources left out are switched off) |
| `/kuk find gi` | What the To field would fill in for "gi", per source |
| `/kuk group` | Inbox grouping on/off |
| `/kuk icons` | All QuickAttach buttons on/off |
| `/kuk minimap` | Minimap button on/off |
