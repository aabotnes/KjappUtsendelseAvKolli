# [Soeta's] Kjapp Utsendelse av Kolli

*K.U.K., "quick dispatch of parcels".* Everything for the mailbox in one add-on, for **World of Warcraft: Forever** (interface 16001). No other mail add-on needed.

**Sending**

- **36 attachment slots** instead of 12 (set anywhere from 12 to 120). The extra slots continue the game's own grid in reading order, and every item stays in the slot you put it in. When you press Send, the items past the first 12 go out as follow-up letters of 12 to the same person, with "(2/3)" added to the subject.
- **Greyed out in your bags:** items in the extra slots look attached in Blizzard's bag windows, like real attachments do.
- **Resizable Send Mail window:** drag the bottom-right corner down for more rows of slots; the mouse wheel scrolls the slots when they don't all fit. Right-click the corner to go back to the normal size.
- **Automatic subject:** an empty subject becomes the first item's name, like "Linen Cloth (20)". Right-click a few items, type a name, press Send. A subject you type yourself is never changed.
- **QuickAttach buttons** down the right side: Cloth, Leather, Metal & Stone, Herb, Cooking, Elemental, Enchanting and more. Left-click attaches every matching item from your bags; right-click gives the button a default recipient. Each character picks a profile of which buttons show; Jewelcrafting, Inscription and Optional Reagents are hidden by default, since Forever doesn't have them.
- **Address book:** the arrow beside the To field lists your alts (with level and class), recently mailed, contacts, friends and guild members. With Baganator installed, all the characters it knows are added as alts automatically; others can be added by hand.
- **To field finds your alts first** while you type, then friends, guild, recently mailed and contacts. The order is yours to change, and it fills in the full character name ("First Surname"), never a realm.

**Receiving**

- **Open letters** show their gold first, then the items, in rows of 7; only as many rows as needed, with a scroll bar for big batches.
- **One inbox row per batch:** letters from the same sender with the same subject and text show as one row. Opening it shows the gold and every item of all its letters in the letter's grid; *Take all* or shift-click the row takes everything.
- **Tick boxes** on every row. With letters ticked, *Take ticked* and *Return ticked* take the place of Open All.
- **Return and delete icons** on every row (delete only for letters with nothing left in them). **Ctrl-click** a row to send it back.
- The **mouse wheel** turns the inbox pages.
- When you close the mailbox, chat says **how much gold you collected**.
- An open letter gets **Forward** and **Copy text** buttons.
- The "Postage:" label is gone; only the cost shows.

## Install

1. Click **Code → Download ZIP** on this page and unzip it.
2. Copy the **`KUK`** folder from inside `KjappUtsendelseAvKolli-main` to `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game (a new add-on folder isn't picked up by `/reload`).

If you used Postal before, leave it enabled for your first login with K.U.K.: your alts, recently mailed and contacts are copied over once. After that you can remove Postal.

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
