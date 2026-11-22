# Adaptive opponent research

Baseline: internal beta source `e4b11e1`, policy `adaptive-pacing-1`. This report proposes a playtest candidate. The released beta uses the baseline.

## What the beta does

[DuelEngine](../app/WordChainKit/Sources/WordChainKit/DuelEngine.swift) passes the elapsed time on the 20-second player clock and the turn's rejected submissions to [OpponentPolicy](../app/WordChainKit/Sources/WordChainKit/Opponent.swift). The policy runs locally. Pressure resets at the start of a new round and is preserved when resuming an interrupted round.

| At an accepted submission | Pressure update |
| --- | --- |
| 14 seconds or more, or at least two rejected submissions | Down one |
| No rejection and 7 seconds or less | Up one |
| No rejection and a positive multiple of three completed computer turns | Up one, unless the slow-reply rule takes precedence |
| Other cases | Hold |

Pressure stays within 0–8. The first two computer replies use pressure 0 and subsequent replies can ramp by one per exchange. After two consecutive computer moves that offered fewer than three familiar replies, the next choice uses pressure 0. That boost can last one reply, and the accumulated internal pressure can return on the reply after it.

The computer prefers familiar unused words that leave at least one legal human reply. It scores a shuffled sample of up to 24 candidates. If that sample has no continuing word, it checks the rest of that vocabulary tier before trying rare words. It plays a terminal word only when it has no continuing option. Its target ranges from eight to one familiar human replies. Reply counts are capped for scoring, weighted with total legal replies and the bot word's familiarity, and used in a randomized choice among up to five near-best candidates. The target is soft. It permits a prompt with zero familiar replies when a different legal computer word could offer some. The source familiarity rank is a proxy built from learner grades and a historical frequency list.

## Comparative evidence

| Reference | Evidence and application |
| --- | --- |
| Candy Crush Saga | King researchers demonstrated using player-like bots to estimate level difficulty before release. In 2019 King testified that it made level-wide adjustments, citing level 65, and described a common level design at that time. A 2015 King talk also records a decision against spending-based individualized level difficulty at the time. Current support documents limited-group feature tests. These sources establish playtest simulation, live balancing and feature cohorts. The evidence leaves personalized near-misses, spending-based ad removal or pricing, and attempts-based control of candy drops unresolved. [King paper](https://ieeexplore.ieee.org/document/8490442/) · [Parliament testimony](https://committees.parliament.uk/oralevidence/9464/pdf/) · [King chief scientist talk](https://businessofsoftware.org/talks/how-to-make-sense-of-big-data/) · [Feature test example](https://candycrush.zendesk.com/hc/en-us/articles/36873468198429-New-ways-to-tap-and-swipe-Special-Candies) |
| Left 4 Dead | Valve documents building pressure, allowing it to peak, easing it, and holding a distinct recovery interval. The useful analogue is to give the word-chain player a real breather after a demanding passage. [Valve AI Director presentation](https://cdn.cloudflare.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf) |
| Stockfish | The engine documents weakening its play via weighted selection among a shortlist of legal moves. Choosing a different legal reply is a concrete way to express difficulty while keeping the rules and clock stable. [Stockfish FAQ](https://official-stockfish.github.io/docs/stockfish-wiki/Stockfish-FAQ.html#how-do-skill-level-and-uci-elo-work) |
| WordChainer | The published Korean game has a five-step difficulty slider. The shipped JavaScript evaluates continuation counts, changes selection weights by level, and gives the bot a chance to fail below its highest setting. Our score attack can use continuation counts while keeping results tied to actual exhaustion and player actions. [Live game](https://cheesedongjin.github.io/WordChainer/) · [Published project](https://github.com/cheesedongjin/WordChainer) |

REA observed Candy Crush's public page and its download and Facebook links. This capture covered the storefront, so King gameplay and server decisions remain unobserved. Evidence `ev_b1fc8b24455713a943c8186e69b6c14772da3693401df645e27c3621eab147ba`. REA also parsed the WordChainer script served inline by its public site, then the relevant selection path was read directly. Script SHA-256 `c6f6c6941fe69848378b27ab9a1d6646bf5ac7d05545503782473ea7362873e5`. Static parent evidence `ev_b850a530782cf09145ccb3e4a66001c3e5c2eff7ebd8686ae8adc9078d13289e`.

In fresh WordChainer browser sessions, REA waited for the dictionary to load, selected the difficulty, and submitted `사과`. At level 1 the observed reply was `과수나무` (next prompt `무`). At level 5 it was `과부댁` (next prompt `댁`). These are single stochastic observations. The code review establishes the weighting policy. Runtime evidence `ev_addf4320fb652af1fe6fe477ee4f4c348dc1d0217069c72fe0214ebfb7123140` and `ev_f6abeee7c6b4b73d75b149c4912ebdf1702d71ca58cfa0264f5d17e54acf12e9`.

## Paired dictionary simulation

The simulation compiled the beta Swift engine with optimization and used the shipped dictionary, exclusions and 41 seeds. For each seed it sampled five familiar legal first replies using `SeededRandom(seed: 18)`. It compared the same position and per-position random seed at opening, at pressure 8 after the ramp, and at high internal pressure with the existing recovery trigger set. Two first replies ended the chain before the computer could respond. The remaining 203 positions are a sample of early board states tested under three different policy states. They do not model depletion in a full run, Korean typing, or player enjoyment.

| Policy state | Median familiar options left | Fewer than three | Zero familiar |
| --- | ---: | ---: | ---: |
| Opening | 49 | 1 | 1 |
| Maximum pressure | 1 | 132 | 53 |
| Recovery override | 49 | 1 | 1 |

In all 53 zero-familiar cases at maximum pressure, at least one legal alternative would have left a familiar reply. In 50, a familiar computer word could have left at least three. This follow-up searched the full legal candidate set and removed the candidate itself from counts where applicable. The simulation used rank ≥2 as familiar. Zero familiar therefore still allows rare words. At the sample's first position starting `가방 → 방문`, the opening and recovery bot picked `문어` (35 ranked-familiar replies) and the maximum-pressure bot picked `문턱` (one ranked-familiar reply). These are counterfactual computer selections for the same position.

## Recommended candidate

- Keep the same 20 seconds, word eligibility, scoring, random legal choices, and honest endings. Give the selected word's ending syllable the job of changing the challenge.
- Open comfortably for two exchanges. During the build-up, use two of the last three turns with clean, comparatively quick replies as evidence to raise pressure a step. Use elapsed time as a noisy signal and interpret it against the difficulty of the prompt. Distinguish submission problems such as unfinished composition or an accidental repeat from vocabulary struggle in the evaluation.
- Try a hard band of two to four plausible replies. Have a familiar candidate floor where possible. If the sample cannot meet that floor, use the next appropriate candidate from the full set before accepting a zero-familiar ending. Prefer words people recognize and represent different endings in the sample.
- After two hard exchanges or repeated signs of struggle, aim for two playable recovery turns before building again. Treat recovery as a state with its own duration. If the position provides no comfortable options, choose the best legal continuation available. Count only a recovery prompt the policy actually delivered.
- Keep the experiment on-device during early beta. Record consented playtest summaries with policy version, seed, prompt option count, active turn time, rejection category, ending cause and replay choice. Avoid collecting raw drafts. Use player reports to distinguish a satisfying hard prompt from a typing problem or an obscure-word trap.

First compare the current policy, a fixed medium policy and the candidate on paired dictionary positions. Add long-run simulations with differing word knowledge, slower input, occasional revisions, repeat depletion and strict capacity checks. Use simulated play to find outliers. Then use alternating policy order with Korean-speaking testers of different typing speeds. Compare first-three-turn timeouts, zero-familiar prompts, back-to-back hard prompts, voluntary rematches, perceived fairness and where people say a run became tedious. Check the percentage of positions where the difficulty band is feasible before tuning its thresholds. If a materially revised policy ships, keep earlier rounds visible under their original policy and score context.
