# Upstream

ChillZone is a fork of Olympus: https://github.com/dnl-gentile/olympus-addon (git remote `upstream`).

Base: `ed7a81e`, Olympus 1.5.1 (2026-11-05).

Commits are taken one by one with `bash scripts/port-upstream.sh <commit>|<from>..<to>`, which
rebrands each patch (`scripts/rebrand.py patch`) and applies it; it adds a row below for each.

Ported tests that hash or sign branded text (records, signed council fixtures) must be re-signed or regenerated after porting, as in commit 096e362.

| Upstream | ChillZone | Subject |
|---|---|---|
| 5c20a56 | 629a54b | The census goes as the reporter's own text while no relay answers; Elrond Oaklance a PvP pin (the pin in the test identity only) |
| 9ed56d3 | 7cfc96d | Prepare Olympus 1.5.2 |
| c4d15be | fe0472e | A family's store drops another family's counts-only rows; a plain Forever realm's row is its family's server |
| 9bd9893 | 001269e | Complete 1.5.2 census recovery, verification requests and client fixes |
| 07ad637 | f35521a | Keep ranking discovery retries distinct across relay deduplication |
| f92cfaf | ad34e33 | Expire relay forwarding duplicates with the delivery window (HandleIn/HandleAcross keep ChillZone's Fanned, which already expires with SEEN_FOR) |
| 5758599 | ed27881 | Preserve census origins and recover complete relay snapshots (QueueWord replaces ChillZone's KeyPart, the same chunk fix) |
| c88cb8b | e36b464 | Preserve verification decisions when merging same-scope stores |
| 8cdc338 | cc7936a | Keep recruit confirmations off native guild popup state |
| 42a6fff | 231c365 | Preserve verification recovery answers with missing evidence |
| bf3f682 | 2f6e52b | Show original census observation times in server breakdowns |
| 3422df5 | ee55323 | Add the map editor shortcut to Decrees for current editors |
| b84a9a5 | 8c2a6ae | Send carried census origins promptly within existing relay budgets |
| 39757bf | d1cda4f | Fit the Queen dragon opening to native portrait geometry |
| 07d134c | 1e34256 | Show the signed Queen dragon icon in native chat |
| e50c3a7 | d73d02a | Translate the Decrees map shortcut in every supported locale |
| b751180 | abc17af | Pause verification warnings for guild members while retaining GM follow-up (1.5.3) |
| f915fc8 | 63081e8 | Give release letters distinct titles and add the verification hotfix letter (1.5.3) |
