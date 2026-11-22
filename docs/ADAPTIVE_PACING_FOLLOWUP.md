# Adaptive pacing follow-up for TestFlight 0.2.0

[The first audit](ADAPTIVE_PACING_RESEARCH.md) found that maximum pressure could leave zero familiar answers even when the computer had a more playable legal choice. This pass used fresh research and matched dictionary positions to refine how the bot raises pressure, gives players a breather, and falls back when a chain gets tight.

## What research adds

- **Control matters.** Ang and Mitchell's CHI PLAY study compared fixed, system-ramped, and player-oriented adaptation. The published abstract reports lower perceived control for system ramping than player-oriented adaptation. Here the visible rules remain stable, the help sheet explains the computer's changing word choice, and changes based on timing require more than one observation. [Ang and Mitchell](https://doi.org/10.1145/3116595.3116623)
- **Measure enjoyment directly.** Cutting et al.'s preregistered study with 311 participants established different difficulty outcomes, with no significant differences in enjoyment or voluntary replay. Lomas et al. reported different patterns for self-chosen and assigned difficulty in an educational game. Ask about fairness and preference separately from observing voluntary replay. [Cutting et al.](https://pmc.ncbi.nlm.nih.gov/articles/PMC9890114/) · [Lomas et al.](https://doi.org/10.1145/3025453.3025638)
- **Use several observations and account for the prompt.** Zook and Riedl found a relationship between measured performance and rated difficulty in their RPG task, and modeled performance over time. Here the bot tracks a short window of clean and struggling turns and gives a slightly wider timing band on narrower prompts. Korean typing speed and vocabulary remain different influences on elapsed time. [Zook and Riedl](https://faculty.cc.gatech.edu/~riedl/pubs/aiide12.pdf)

These studies support the design and measurement questions. The timing bands, familiarity floors and two-prompt recovery are engineering choices for this beta.

## Rules in the second build

The bot starts with two comfortable choices where the dictionary allows. It adapts in steps using two qualifying turns out of the last three, then clears the evidence window. On a prompt with at least five familiar answers, clean replies within nine seconds count as quick and replies taking at least 14 seconds count as struggle. On tighter prompts those thresholds are 10 and 16 seconds. Basic formatting, incomplete composition and repeated-word rejections do not count as vocabulary struggles. Sustained struggle or two consecutive prompts with fewer than five familiar options starts recovery. The recovery budget counts two delivered prompts with at least five familiar options. A turn with no comfortably playable option uses the best available choice and does not consume that budget.

Choices use the available legal continuations after removing previously used words, the candidate itself, and excluded words. The computer checks the whole candidate pool for a move that leaves two familiar answers, or one when two are unavailable. It uses a rare-only prompt only when every legal continuation is that scarce. During the climb it prefers a familiar computer word whenever that word can leave at least two familiar replies, even if this means easing off the hardest target. It selects with some variety across distinct next syllables. A genuine dead end can still end the round and an accepted player finishing word still scores.

All of this runs in the current round on-device. The fixed turn clock and score rules carry forward. A saved build 1 round continues with its original opponent, including the stored pending word. A new round uses the new policy and starts a comparable personal-best series. Earlier scores remain in history.

## Shipped-dictionary checks

The matched audit used the same 203 non-terminal positions and random seed per position as the first report. It forced the specified pacing state and verified actual unused reply counts against independent enumeration. At each policy's maximum pressure:

| Measure | Build 1 | Build 2 |
| --- | ---: | ---: |
| Median familiar human replies | 1 | 3 |
| Prompts with zero familiar human replies | 53 | 0 |
| Prompts with two to four familiar human replies | 51 | 150 |
| Computer words below the familiarity threshold | 12 | 13 |

An earlier draft hit the two-to-four range in 192 positions but used 55 below-threshold computer words. The familiar-first rule brought that down to 13. At maximum pressure after `개구리 → 이해력`, the earlier draft selected `역미셀` with three familiar options. The final version selected `역할` with 11, leaving a more recognizable prompt. Both counts are dictionary estimates.

In 246 capped simulations across both builds, three artificial vocabulary and typing profiles played from all 41 starting seeds. Under the revised policy the slow profile saw nine hard prompts in 1,007 turns, the middle profile 219 in 944, and the fast profile 318 in 993. Hard meant four or fewer estimated familiar answers. These simulations cut off at 28 accepted player words and use synthetic timing and word knowledge. They illustrate that the policy behaves differently with different inputs. They cannot estimate actual round length, player vocabulary, or how enjoyable the pacing is.

## On-device playtest

Use counterbalanced rounds with similar starting words. Record first-three-turn timeouts, what made a player get stuck, actual rematch choices and perceived fairness separately. Include slower Korean typists and stronger players. Ask whether a hard prompt felt satisfying, unfamiliar, or merely hard to type, and whether the easier stretch felt earned. Compare with a fixed medium policy as well as build 1 if the pacing has a mixed reaction. A long synthetic chain has no direct bearing on enjoyment.
