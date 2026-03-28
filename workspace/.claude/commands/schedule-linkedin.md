# Schedule LinkedIn Posts for the Month

Select the best unscheduled LinkedIn drafts and schedule **2 posts per remaining day** this month via Post Bridge on Ryan Eggleston's personal LinkedIn (https://www.linkedin.com/in/ryan-eggleston).

**Goal**: Post signal, not noise. AI is a loud industry — every post that earns a slot should make Ryan's two audiences stop scrolling.

---

## Phase 1: Environment & Scope

1. Load `POST_BRIDGE_API_KEY` from `~/.bashrc` (note: bashrc has a non-interactive guard, so use eval):
   ```bash
   eval $(grep "export POST_BRIDGE_API_KEY" ~/.bashrc)
   echo "Key set: ${POST_BRIDGE_API_KEY:+yes}"
   ```
   If not set, abort: "POST_BRIDGE_API_KEY not found. Add `export POST_BRIDGE_API_KEY=<key>` to ~/.bashrc."
   **Important**: Run this eval before every `curl` command block in subsequent steps.

2. Calculate remaining days this month (dynamic — do NOT hardcode):
   ```bash
   # Tomorrow through last day of current month
   TOMORROW=$(date -d "tomorrow" +%Y-%m-%d)
   LAST_DAY=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%Y-%m-%d)
   ```
   If tomorrow > last day of month → "Nothing to schedule — month is complete." Stop.

3. List remaining days (one per line, YYYY-MM-DD format).

---

## Phase 2: Check What's Already Covered

4. Get Ryan's LinkedIn account from Post Bridge:
   ```bash
   eval $(grep "export POST_BRIDGE_API_KEY" ~/.bashrc)
   curl -s -H "Authorization: Bearer $POST_BRIDGE_API_KEY" \
     "https://api.post-bridge.com/v1/social-accounts?platform=linkedin" | jq .
   ```
   Find Ryan's personal account — look for username containing "Ryan Eggleston" (NOT "Ruska AI", that's the company page).
   The personal account ID is **41731**. Verify it exists in the response. If not found → abort: "Ryan Eggleston personal LinkedIn account not found in Post Bridge."

5. Fetch existing posts:
   ```bash
   # Scheduled posts
   curl -s -H "Authorization: Bearer $POST_BRIDGE_API_KEY" \
     "https://api.post-bridge.com/v1/posts?status=scheduled&limit=100" | jq .
   # Posted posts
   curl -s -H "Authorization: Bearer $POST_BRIDGE_API_KEY" \
     "https://api.post-bridge.com/v1/posts?status=posted&limit=100" | jq .
   ```
   Extract which dates already have posts for account **41731** (compare date portion of `scheduled_at` in America/Denver timezone). Count how many posts each date has.

6. Build list of **open slots**. Each day gets 2 slots (AM and PM). A day with 0 posts = 2 open slots, 1 post = 1 open slot, 2+ posts = 0 open slots.
   If zero open slots → "All remaining days have 2 posts scheduled. Nothing to do." Stop.
   Otherwise, report: "Found N open slots across M days: [list dates with slot counts]"

---

## Phase 3: Build Audience Context

The two audiences and what resonates with each:

**Audience A — Developers/builders** (→ Open Harness stars)
- Signal: Real terminal output, copy-pasteable commands, honest failures, architectural decisions
- Noise: "AI will change everything", vague predictions, hype without proof

**Audience B — SMB owners in Southern Utah** (→ ruska.ai/services leads)
- Signal: Platform names (Zoho, Guesty, QuickBooks), concrete time/money saved, local references
- Noise: Dev jargon, abstract automation, tool comparisons

7. **Browse live signals with agent-browser** to understand current context:

   **a. Ryan's LinkedIn profile — recent engagement:**
   ```bash
   agent-browser close --all 2>/dev/null || true
   agent-browser open "https://www.linkedin.com/in/ryan-eggleston/recent-activity/all/"
   sleep 5
   agent-browser snapshot --compact > /tmp/linkedin-activity.txt 2>/dev/null || true
   agent-browser screenshot /tmp/linkedin-activity.png 2>/dev/null || true
   agent-browser close --all 2>/dev/null || true
   ```
   Read the snapshot to identify: which recent posts got the most reactions/comments, what topics are driving engagement, any audience patterns (developer vs SMB response).

   **b. Open Harness GitHub repo — current metrics:**
   ```bash
   agent-browser open "https://github.com/ryaneggz/open-harness"
   sleep 3
   agent-browser snapshot --compact > /tmp/open-harness-github.txt 2>/dev/null || true
   agent-browser close --all 2>/dev/null || true
   ```
   Note current stars, forks, recent activity. Drafts referencing features that appear in recent commits feel more authentic.

   **c. AI industry pulse — what's resonating on LinkedIn right now:**
   ```bash
   agent-browser open "https://www.linkedin.com/feed/hashtag/aiagents/"
   sleep 5
   agent-browser snapshot --compact > /tmp/linkedin-ai-pulse.txt 2>/dev/null || true
   agent-browser close --all 2>/dev/null || true
   ```
   Scan for trending themes. If a topic is saturated (e.g., everyone posting about the same new model release), **deprioritize** drafts on that topic — signal means standing out from the noise, not adding to it. If an underserved angle is emerging, **boost** drafts that address it.

   Use these live signals to adjust ranking weights in Phase 4.

8. **Pull GitHub activity** from both accounts for recent context:
   ```bash
   # Ryan's personal account — recent pushes, PRs, issues
   gh api users/ryaneggz/events --jq '.[0:20] | .[] | {type, repo: .repo.name, created_at, payload_action: .payload.action // empty}' 2>/dev/null || echo "ryaneggz: no events or auth required"

   # AI agent account — what the agent has been shipping
   gh api users/im-an-ai-agent/events --jq '.[0:20] | .[] | {type, repo: .repo.name, created_at, payload_action: .payload.action // empty}' 2>/dev/null || echo "im-an-ai-agent: no events or auth required"

   # Open Harness repo activity specifically
   gh api repos/ryaneggz/open-harness/commits --jq '.[0:10] | .[] | {sha: .sha[0:7], date: .commit.author.date, message: .commit.message}' 2>/dev/null || echo "open-harness: no recent commits"
   ```
   Use this to:
   - Identify which features/fixes were shipped in the last 7-14 days
   - **Boost drafts that align with recent work** — a post about HEARTBEAT.md is more authentic if heartbeat code was just committed
   - **Deprioritize drafts about features that haven't been touched** — stale topics feel less genuine
   - Note the agent account's activity patterns for potential Build Log content alignment

9. **Pull Post Bridge analytics** (if past posts exist):
   ```bash
   # Sync fresh data
   curl -s -X POST -H "Authorization: Bearer $POST_BRIDGE_API_KEY" \
     "https://api.post-bridge.com/v1/analytics/sync" | jq .
   # Get 90-day analytics
   curl -s -H "Authorization: Bearer $POST_BRIDGE_API_KEY" \
     "https://api.post-bridge.com/v1/analytics?platform=linkedin&timeframe=90d" | jq .
   # Get post results to map content → performance
   curl -s -H "Authorization: Bearer $POST_BRIDGE_API_KEY" \
     "https://api.post-bridge.com/v1/post-results?platform=linkedin" | jq .
   ```
   Build a performance profile: which topics/pillars/formats drove the most engagement.
   If no analytics data → note "First run, no analytics. Using style guide baselines."

10. **Read iteration memory** at `memory/linkedin-ghostwriter-iterations.md`:
   - Scan for recurring "what went well" patterns about engagement
   - Identify high-performing formats (✅/❌ contrast, story-based, ultra-short, copy-paste commands)
   - Note flagged anti-patterns
   - Synthesize a **learned preferences summary** (2-3 sentences)

11. **Read style guide** at `.claude/skills/linkedin-ghostwriter/references/style-guide.md`:
    - Baseline engagement tiers: Steal My Workflow > Structured follow-up > Lessons learned > Announcements
    - These are starting weights — analytics override when available

12. **Check recent posting history** from step 5:
    - What pillars were posted in the last 7-14 days?
    - What audience (A or B) were recent posts targeting?
    - Note diversity gaps to inform selection

---

## Phase 4: Rank Drafts

13. **Load all drafts** from `.claude/skills/linkedin-ghostwriter/assets/drafts/`:
    - Read each `.md` file (exclude `queue.md`, `queue.md.bak*`)
    - Parse YAML frontmatter (topic, pillar, date) where present
    - For drafts without frontmatter, look up pillar from `queue.md` "## Done" section (match by filename)
    - Do NOT read from `assets/scheduled/` — that folder holds already-scheduled drafts

14. **Mandatory quality gate** (fail any = disqualified):
    - [ ] Contains `github.com/ryaneggz/open-harness` OR a quickstart command (`make NAME=`)
    - [ ] At least one proof point (concrete number, terminal command, or specific platform/file name)
    - [ ] Engagement hook (question mark `?` in last 5 lines, OR "steal"/"try it" keyword)
    - [ ] Open Harness feature reference (SOUL.md, MEMORY.md, HEARTBEAT.md, AGENTS.md, CLAUDE.md, sandbox, quickstart, workspace)

15. **Score for resonance** (0-100):

    **A. Specificity & Signal (0-35 pts)** — This is the most important criterion. Signal > noise.
    - 35: Concrete numbers + real command + named platform/tool (e.g., "83 tickets, 91% accuracy, Zoho Desk")
    - 25: Concrete numbers + command OR named platform
    - 15: One proof point type only
    - 5: Vague claims without specifics

    **B. Engagement Pattern Match (0-25 pts)** — Weight by analytics when available:
    - If analytics show a pillar outperforms, boost those drafts by up to +10
    - Default (no analytics): P3 Steal My Workflow = 25, P2 Build Log = 20, P4 Honest Reflection = 20, P1 Pain→Solution = 15, P5 SMB/Platform = 15
    - P5 may get analytics boost if SMB posts actually perform well

    **C. Hook Quality (0-15 pts)**
    - 15: Specific question targeting audience pain + "steal this" framing
    - 12: Specific question alone
    - 10: "Try it" CTA with command
    - 5: Generic CTA

    **D. Format & Length (0-10 pts)**
    - 10: 50-150 words + emoji-prefixed structure + Unicode bold hook
    - 7: 151-200 words, good structure
    - 3: Outside range or weak structure

    **E. Timeliness & Relevance (0-15 pts)** — from agent-browser and GitHub context:
    - 15: Draft topic directly aligns with a feature shipped in the last 7 days (from GitHub activity) AND addresses an underserved angle on LinkedIn (from AI pulse scan)
    - 10: Draft aligns with recent GitHub activity OR addresses an underserved angle
    - 5: Draft topic is evergreen but not tied to recent activity
    - 0: Draft topic overlaps with saturated LinkedIn trend (everyone already posting about it)

    **F. Anti-pattern Penalties (subtract)**
    - -10 each: Banned phrases ("excited to announce", "thrilled to share", "leveraging")
    - -20: Reused closer "That's not a roadmap. That's a Tuesday."
    - -5: No emoji in first line
    - -10: Hashtag dump at end (3+ hashtags in last 3 lines)

16. Sort all passing drafts by score descending.

---

## Phase 5: Select with Diversity Constraints

17. **Greedy selection with guardrails** — pick **2 drafts per day** to fill open slots:

    **Same-day pairing rule**: The two posts on the same day MUST target different audiences:
    - Slot 1 (AM): Developer-focused (P1, P2, P3) or Both (P4)
    - Slot 2 (PM): SMB-focused (P5) or Both (P4)
    - If not enough SMB drafts, both slots can be developer-focused but must use different pillars
    - Never schedule the same pillar twice on the same day

    **Cross-day rules** (apply across consecutive days):
    - **Pillar diversity**: Avoid scheduling the same pillar in the same slot on consecutive days
    - **Recent posting history**: Deprioritize pillars that were heavy in the last 7 days (from step 12)
    - If diversity filters eliminate all remaining candidates, relax constraints and take next-highest score

    **Selection order**:
    - For each day, pick highest-scored draft for AM slot
    - Then pick highest-scored draft that satisfies the same-day pairing rule for PM slot
    - Move to next day

18. **Present selection to user BEFORE scheduling** — show a table:

    ```
    | Day        | Slot | Score | Pillar              | Audience  | Topic (first line)       | Draft File              |
    |------------|------|-------|---------------------|-----------|--------------------------|-------------------------|
    | 2026-03-29 | AM   | 87    | P3: Steal Workflow  | Developer | 🔧 Inject a Task...     | 2026-03-28-15-05.md     |
    | 2026-03-29 | PM   | 82    | P5: SMB/Platform    | SMB       | 🎯 Zero Rules Engine... | 2026-03-28-20-22.md     |
    | 2026-03-30 | AM   | 84    | P2: Build Log       | Developer | 🏨 My Agent Found 4...  | 2026-03-29-15-00.md     |
    | 2026-03-30 | PM   | 79    | P4: Honest Reflect  | Both      | 🫣 My Agent Quoted...   | 2026-03-29-16-00.md     |
    ```

    Show reasoning for each pick (e.g., "PM slot gets P5 to pair with AM's developer post").
    Show the learned preferences summary from step 10.

    **Ask user to confirm before proceeding.** If they want to swap any posts, adjust.

---

## Phase 6: Schedule via Post Bridge

19. For each confirmed (draft, target_date) pair:
    - Strip YAML frontmatter (only the first `---...---` block) to get clean caption text. Use `awk` to preserve any `---` horizontal rules in the body:
      ```bash
      CAPTION=$(awk 'BEGIN{fm=0} /^---$/{fm++; if(fm<=2) next} fm>=2{print}' draft_file.md)
      ```
      If the draft has no frontmatter (first line is not `---`), use the full file as caption.
    - Use `jq` for safe JSON construction (handles Unicode, newlines, quotes):
      ```bash
      JSON=$(jq -n --arg caption "$CAPTION" --argjson accounts "[ACCOUNT_ID]" --arg scheduled "$TARGET_DATE"'T15:00:00Z' \
        '{social_accounts: $accounts, caption: $caption, scheduled_at: $scheduled}')
      curl -s -X POST \
        -H "Authorization: Bearer $POST_BRIDGE_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$JSON" \
        "https://api.post-bridge.com/v1/posts" | jq .
      ```
    - **AM slot**: 15:00 UTC = 9:00 AM MDT (morning peak — professionals scrolling at start of workday)
    - **PM slot**: 21:00 UTC = 3:00 PM MDT (afternoon peak — post-lunch scroll, second wave of engagement)
    - If a day already has 1 post scheduled, only fill the missing slot (check existing post time to determine which slot is taken)
    - Verify response has a post ID. On error: log it, skip this slot, continue with next.

20. **Move each scheduled draft** to `assets/scheduled/`:
    ```bash
    mv .claude/skills/linkedin-ghostwriter/assets/drafts/DRAFT_FILE.md \
       .claude/skills/linkedin-ghostwriter/assets/scheduled/
    ```
    This prevents scheduled drafts from being re-selected in future runs. The `scheduled/` folder lives alongside `drafts/`, not inside it.

---

## Phase 7: Log & Report

21. Append to `memory/YYYY-MM-DD.md`:
    ```
    ## LinkedIn Post Scheduler — [timestamp]
    - Posts scheduled: N
    - Uncovered days found: N
    - [For each post]: Date, slot (AM/PM), draft file, pillar, topic, Post Bridge post ID
    - Audience balance: N developer-focused, N SMB-focused, N bridge
    - Slots filled: N AM, N PM
    - Analytics insights used: [summary or "first run, no analytics"]
    - Errors: [list or "none"]
    ```

22. Display summary to user:
    - How many posts scheduled
    - Which days are now covered
    - Any days that couldn't be filled (and why)
    - Next steps: "Run `/schedule-linkedin` again next month. Analytics from this month's posts will inform next month's ranking."

---

## Reference Files

Read these as needed during execution:
- Post Bridge API: `.claude/skills/post-bridge/SKILL.md` and `.claude/skills/post-bridge/references/api-endpoints.md`
- Style guide: `.claude/skills/linkedin-ghostwriter/references/style-guide.md`
- Open Harness context: `.claude/skills/linkedin-ghostwriter/references/open-harness.md`
- Drafts (unscheduled): `.claude/skills/linkedin-ghostwriter/assets/drafts/*.md`
- Drafts (scheduled): `.claude/skills/linkedin-ghostwriter/assets/scheduled/*.md`
- Queue (pillar mapping): `.claude/skills/linkedin-ghostwriter/assets/drafts/queue.md`
- Iteration memory: `memory/linkedin-ghostwriter-iterations.md`
