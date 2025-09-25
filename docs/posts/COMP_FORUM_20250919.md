GM :sun: and Happy Friday CompComm followers, 

I have received some questions like "Why would people pay 10 USDC to message this?" So I have prepared the following Research Note to explain in more detail how the experiment works. _It's all predicated on the portfolio being seeded with 100 USDC_, which is part of the launch plan.

---

This note explains the **economic dynamics** of sending paid messages to the CompComm agent, how MT is minted, and why there's a built‑in incentive to interact (especially early on). It also walks through a quick ETH example and solves for the number of messages needed (starting from a 100 USDC seed) for the **terminal value per MT** to reach 11 USDC/MT when the portfolio simply holds USDC.

## CompComm Model Setup

* **Initial portfolio AUM:** `A₀ = 100 USDC` (which the dev provides to kick start the fun)
* **Initial MT supply:** `S₀ = 0`
* **Per message:** pay `10 USDC` → deposit goes into the vault and **mints 1.2 MT** total: `1.0 MT` to the payer, `0.2 MT` to the developer treasury.
* **Terminal redemption:** pro‑rata redemption of the portfolio’s assets for WETH (or USDC in this simplified section) per MT.

When there have been `n` messages in total and *the portfolio passively holds USDC*, we have:

* **Assets:** `A(n) = 100 + 10·n`
* **Supply:** `S(n) = 1.2·n`
* **Terminal value per MT (post‑n messages):**
  `V(n) = A(n) / S(n) = (100 + 10n) / (1.2n)`

Equivalently: `V(n) = 100/(1.2n) + 10/1.2 = 83.33…/n + 8.333…`
This shows `V(n)` **decreases** with more messages and asymptotically approaches `8.333… USDC/MT` as `n → ∞` when the portfolio only accumulates USDC.

## Early Messages Create a Strong Incentive (Arbitrage‑like)

With **no MT outstanding** at the start, the **first message** puts `10 USDC` into the vault and mints `1.2 MT` total. The portfolio now has `110 USDC` and `1.2 MT` outstanding, so the terminal value per MT is:

`V(1) = 110 / 1.2 = 91.66… USDC/MT`

A user who paid `10 USDC` for **1 MT** now holds a claim worth **\~91.66 USDC** at terminal redemption (ignoring time/market risk). This *huge gap* exists because the initial seed (100 USDC) is shared among a very small MT supply. As more messages arrive, supply grows faster than assets on a per‑unit basis (10 USDC vs 1.2 MT → **8.333 USDC/MT**), so `V(n)` trends down.

For reference, after **two** total messages:

* Assets `A(2) = 120`, Supply `S(2) = 2.4` ⇒ `V(2) = 120 / 2.4 = 50 USDC/MT` (still >> 10).

## ETH Example: Interaction + Market Performance

Suppose ETH is initially \$4,000 and the **first message** says *"Buy ETH with all USDC."*
After the message, the vault has: `10 USDC + 0.0125 ETH` (since the original `100 USDC` bought `0.0125 ETH`). Supply is `1.2 MT`.

* At \$4,000/ETH, terminal value per MT is:
  `(10 + 0.0125·4000) / 1.2 = (10 + 50) / 1.2 = 60 / 1.2 = 50 USDC/MT`.
* If ETH later rises to \$5,000, the same basket is worth `10 + 0.0125·5000 = 72.5 USDC`, so:
  `72.5 / 1.2 = 60.416… USDC/MT`.

**Takeaway:** positive portfolio performance **raises** `V(n)` and **reinforces** the incentive to interact (send more messages) because deposits both (a) fund the vault and (b) mint MT that participates in improved terminal value.

## How Many Messages Until `V(n) = 11 USDC/MT`?

Assume we **hold only USDC** and each message adds `10 USDC` while minting `1.2 MT` (no price movement). Solve for `n` such that:

`(100 + 10n) / (1.2n) = 11`

`100 + 10n = 13.2n` ⇒ `100 = 3.2n` ⇒ `n = 31.25`

Because messages are discrete:

* After **31 messages**: `V(31) = 410 / 37.2 ≈ 11.02 USDC/MT` (just above 11).
* After **32 messages**: `V(32) = 420 / 38.4 = 10.9375 USDC/MT` (just below 11).

**Answer:** It takes **about 31-32 messages** from a 100 USDC seed for the terminal value per MT to fall to \~**11 USDC/MT** when simply stacking USDC. At **32 messages**, supply is `38.4 MT` (of which `32 MT` to message senders and `6.4 MT` to the dev treasury).

## Incentive Summary
So, to answer our original question: "Why would people pay 10 USDC to message this?", consider the following properties of the Compound Community Portfolio system:

1. **Early participation is highly rewarded.** With a 100 USDC seed and zero initial MT, early messages capture a large share of seeded value per MT.
2. **Activity feeds activity.** As users see elevated `V(n)` and as performance potentially increases portfolio value, there's a _rational incentive_ to submit more messages, which adds USDC and mints MT, compounding engagement.
3. **Natural glide‑path.** If no alpha is added (holding USDC only), `V(n)` drifts toward `~8.333 USDC/MT`. Performance (e.g., successful trades or yield) counteracts that drift and can maintain `V(n)` at higher levels, sustaining incentives.

## Discussion
As stated before, success for the project means having an active community involved. So, I'd love to get some of the amazing people from the community involved in this thread. To that end, I pose the following prompts here for anyone interested in joining the discussion. 

* Are my maths correct?
* Should message price or mint rate ever be dynamic (e.g., congestion responsive) to manage `V(n)` over time? How would that work?
* Would staged timelocks or rolling "epochs" improve fairness between early and late contributors? How might that work?
* What dashboards would you like to see to make `V(n)`, backlog, and performance legible in real time?

-- Mike
