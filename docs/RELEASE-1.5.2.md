# ChillZone 1.5.2 — release candidate

## Changes

- Keep the last accepted census visible during rebuilding, with its original observation time.
- Show this server's soldiers prominently and a smaller accepted total across servers. Details
  retain ruleset, faction, freshness and the separate estimate of individual people.
- Relay bounded counts and guild summaries across realm groups without transferring role authority.
- Isolate legacy counts whose PvE/PvP origin was lost, preserving the original cache outside the
  accepted totals. Scoped snapshots restore empty clients immediately. Forwarded observations
  retain their original observer and date; repeat holders never become extra witnesses.
- Let a pending guild's GM resend a verification request without resetting the original deadline.
  A five-minute cooldown is separate from that deadline and survives reloads.
- Relay verification decisions to their intended recipients.
- Recover Church records from successive available keepers promptly and retry silent sources.
- Request missing game/crafting inventories when their ranking is opened, with bounded retries.
- Let unchanged inventories circulate between relays again after the duplicate window expires,
  while preserving suppression of recent copies and the existing sender and traffic checks.
- Prefer a fully valued bank observation once two independent holders confirm it. Preserve its
  original time, even when the corrected value is lower.
- Fix the innkeeper's first Bones lesson and multiplayer simultaneous opening rolls.
- Add the Queen's dragon frame and repair late-created party frames.
- Let the King and signed High Council preview and publish custom map labels.
- Add compact player-tooltip details and size controls, plus a collapsible ChillZone portrait menu.

## Test limitations and client acceptance

Offline tests exercise the actual Lua handlers against simulated client APIs. They do not prove
live whisper delivery, native frame layering, server-side moderation or a second player's receipt.
Before publication, run these checks in the installed candidate:

1. Open the census immediately after login. The retained observation must be dated; rebuilding
   must not silently replace a known total with zero. Click the header and inspect the server
   breakdown, stale/unavailable states and separate people estimates.
2. Log into characters in two realm groups. Historical counts should appear under their own
   group and faction, not become guild members or council authority in the current realm.
   Check both PvE → PvP and PvP → PvE with a recipient that never visited the source ruleset.
   Unknown original evidence must remain labelled as reported, not accepted merely because
   several ordinary clients forwarded it. Compare the current ruleset label with the guild list.
3. As a pending guild's GM, open `/cz verify`, resend, and reload. Original time remaining must
   not restart. An immediate repeat must respect the cooldown; a refused send must not consume it.
4. With a verifier and GM on different participating guilds, approve and confirm the decision
   reaches the GM. Do not use a real revocation merely to create test data.
5. Use `/cz borders test queen-dragon`, inspect self, target and party frames, then
   `/cz borders test off`. Create or reload party frames after login and check they still show.
6. Open the world map as King/High Council. Edit a label, preview, cancel, then deliberately
   confirm a harmless test label. Check a second client's map and restore the original. An
   ordinary member must not have editing authority. Native artwork remains artwork; ChillZone
   draws its own editable label. Delivery depends on the live relay and connected peers.
7. Hover an ChillZone player, adjust tooltip size, and change to/from gamepad mode. No stale
   tooltip modifications or duplicate portrait entries should remain.
8. Take the innkeeper's first lesson without reopening gossip. Then use two clients for a free
   Bones game, including simultaneous opening rolls. Both clients must progress and agree.
9. Open a games/crafting ranking on a late client while two holders of a verified result are
   online. Check eventual recovery, no duplicate result after reload, and no acceptance from a
   single untrusted identity claim. Older clients still use periodic discovery.
10. Give different Apostles disjoint legitimate Church records, then bring their clients online.
    Confirm catch-up combines the records and skips a temporarily silent peer. Authority and
    audience restrictions must remain unchanged.
11. For an authorized bank viewer, receive a partial valuation, then the complete valuation of
    the same observation from two holders. One holder alone must not replace it. Reload and
    confirm the original observation date and corrected total remain.

The Companion is a separate artifact and backend rollout. Public packaging must exclude private
network source, local signed council overlays, account data and credentials. A successful offline
suite or package build is not a publication or an in-game acceptance result.
