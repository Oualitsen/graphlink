# GraphLink — Communication Roadmap

> **Philosophy:** One language at a time. Ship the tutorial before announcing the feature.
> Each phase builds audience for the next. Comparison articles are the highest-leverage
> content — they rank longest, get cited by LLMs the most, and drive the most qualified traffic.

---

## Overview

| Phase | Target | Timeline | Status |
|---|---|---|---|
| 1 | Dart / Flutter client | Now → Month 2 | ✅ Stable |
| 2 | TypeScript client | Month 1 → Month 2 | 🔧 ~1 week to ship |
| 3 | Java client | Month 2 → Month 4 | ✅ Stable |
| 4 | Spring Boot server | Month 4 → Month 6 | ✅ Stable |
| 5 | Go / Kotlin / C# / Python | Month 6+ | 📋 Demand-based |

> TypeScript is moved to Phase 2 because the architecture (parser → logical entities →
> serializers) means adding a new target is a matter of days, not months. Ship it early —
> it unlocks the largest developer community and makes every subsequent article reach further.

---

## Phase 1 — Dart / Flutter (Now → Month 2)

**Goal:** Own the "GraphQL + Flutter" search space. Flutter devs have very few mature
GraphQL codegen options — this is the least competitive, fastest-to-rank audience.

### Where to publish

| Platform | Role | Action |
|---|---|---|
| **Medium → Flutter Community** (`medium.com/flutter`) | Primary — 150k+ Flutter followers, submit each article for publication | Write here first, submit for inclusion |
| **dev.to** | Canonical source + fast Google indexing | Publish here, set canonical, then cross-post to Medium |
| **Flutter Weekly** (`flutterweekly.net`) | Newsletter distribution — pure reach, no writing | Submit article links after publishing |

### Articles

1. **"Stop writing GraphQL boilerplate in Flutter — let the schema do it"**
   Intro post. Before/after code. Link to docs. Targets: `flutter graphql`, `flutter graphql codegen`

2. **"How I generate 21.5% of a Flutter codebase from a GraphQL schema"**
   The production story with real numbers. Most shareable post of this phase.

3. **"GraphQL subscriptions in Flutter with zero boilerplate"**
   WebSocket is a pain point nobody solves well. High search volume, low competition.

4. **"GraphQL caching in Flutter without a state management library"**
   The `@glCache` angle. Very searchable — Flutter devs are always looking for caching solutions.

5. **"ferry vs GraphLink — why I stopped sending the whole schema"**
   Honest comparison. The Spring Boot validation problem is a concrete, provable differentiator.

### YouTube Videos

1. *Getting started in 5 minutes* — schema → `glink` → typed Flutter call (screen recording)
2. *Full Flutter + GraphQL setup from scratch* — complete workflow, 15–20 min
3. *Real-time subscriptions in Flutter with GraphQL* — focused WebSocket demo

### LinkedIn / Twitter

- Lead hook: *"21.5% of our Flutter codebase is generated. Here's how."*
- Share each article on publish day
- 30–60 sec clips from YouTube demos

---

## Phase 2 — TypeScript Client (Month 1 → Month 2)

**Goal:** Enter the largest developer community as early as possible. TypeScript devs are
the most active sharers — one good post here can reach further than all Flutter posts combined.

> **Why now?** The GraphLink architecture (language-agnostic parser → serializers) means
> TypeScript generation is days of work, not months. Shipping it in Phase 2 means every
> subsequent article about Dart, Java, and Spring Boot gets amplified by a TypeScript audience
> that already knows the tool.

### Where to publish

| Platform | Role | Action |
|---|---|---|
| **dev.to** | Primary — TypeScript community is most active here of any platform | Canonical source, publish here first |
| **Medium → Better Programming** | Secondary — large TS/JS readership, accepts submissions | Cross-post, submit for publication |
| **JavaScript Weekly** (`javascriptweekly.com`) | Newsletter — hundreds of thousands of JS devs | Submit link after each article |
| **TypeScript Weekly** (`typescript-weekly.com`) | Newsletter — targeted TS audience | Submit link after each article |
| **This Week in React** (`thisweekinreact.com`) | Newsletter — for the React-specific article only | Submit the React tutorial article |

### Articles

1. **"GraphLink now generates TypeScript — zero-config, zero boilerplate"** *(launch post)*
   Announcement. Show the schema → generated TypeScript client in one code block.
   Targets: `graphql typescript codegen`, `graphql code generator typescript`

2. **"GraphQL Code Generator vs GraphLink — a different philosophy"**
   Honest comparison with `graphql-code-generator` (the dominant tool). Focus on:
   config file complexity (GraphQL Code Generator needs a YAML config with plugins) vs.
   GraphLink's single `config.json`. Very high SEO value — tons of people search for alternatives.

3. **"Type-safe GraphQL in React without writing query strings"**
   Tutorial for the React audience. `autoGenerateQueries` is the hook.

4. **"One schema, three languages: Dart, Java, TypeScript — same glink command"**
   The multi-target story. Very shareable for teams that have mixed stacks.

### YouTube Videos

1. *TypeScript GraphQL client in 5 minutes* — schema → glink → typed React/Node call
2. *GraphLink vs graphql-code-generator — side-by-side setup* — the comparison video

### LinkedIn / Twitter

- TypeScript launch is a milestone worth a dedicated announcement post on both platforms
- The multi-language angle (*"One schema. Dart, Java, TypeScript. One command."*) works as
  a visual tweet/post — short, punchy, shareable

### Communities to target at launch

- `r/typescript`, `r/reactjs`, `r/node` on Reddit
- TypeScript Weekly newsletter (submit for inclusion)
- This Week in React newsletter (submit)
- A second Show HN specifically for the TypeScript launch

---

## Phase 3 — Java Client (Month 2 → Month 4)

**Goal:** Capture Java devs searching for alternatives to TypeReference boilerplate.
The Java community is large, moves slowly, and has acute pain here.

### Where to publish

| Platform | Role | Action |
|---|---|---|
| **DZone** (`dzone.com`) | Primary — the most-read Java platform after Stack Overflow, huge enterprise audience | Submit every article after publishing elsewhere. Non-optional for Java content. |
| **dev.to** | Canonical source + fast indexing | Publish here first, then submit to DZone |
| **Baeldung Java Weekly** (`baeldung.com/java-weekly-submit`) | Newsletter distribution | Submit article links — reaches Baeldung's entire Java audience, no writing required |
| **LinkedIn long-form articles** | Senior devs / tech leads live here, not Reddit | The no-generics comparison post works as a native LinkedIn article |

### Articles

1. **"Java GraphQL client without TypeReference — is it possible?"**
   SEO-targeted title. Answers the exact query Java devs type into Google and ChatGPT.

2. **"How I removed generics from every GraphQL call in our Java codebase"**
   The no-generics angle. Very shareable in Java communities on LinkedIn.

3. **"GraphQL + Java in 2025 — a practical guide without the boilerplate"**
   Broad tutorial. Targets the main high-volume search query for this audience.

4. **"GraphLink vs Netflix DGS vs spring-graphql HttpGraphQlClient"**
   Three-way comparison. Very high SEO value — Java devs search for this exact comparison.

5. **"How I generate 64% of a Java codebase from a GraphQL schema"**
   Production numbers story for the Java audience.

### YouTube Videos

1. *Java GraphQL client setup in 5 minutes* — schema → glink → typed Java call, no generics
2. *Before and after: Java GraphQL with and without GraphLink* — side-by-side screen recording
3. *Full Java + GraphQL project from scratch* — 20 min tutorial

### LinkedIn / Twitter

- Strongest hook: post a code snippet — TypeReference hell on the left, GraphLink on the right
- Target Java developer communities and Spring community pages on LinkedIn
- The "no generics" angle reads well as a short LinkedIn post with a before/after screenshot

---

## Phase 4 — Spring Boot Server (Month 4 → Month 6)

**Goal:** This is the most impressive story numerically (72% of files). Target backend
devs and tech leads who own the Spring architecture decision. These are senior people
who share less but decide more — LinkedIn is more important than Twitter for this phase.

### Where to publish

| Platform | Role | Action |
|---|---|---|
| **Baeldung (guest post)** | 🏆 Highest-value placement in the entire roadmap — #1 result for almost every Spring Boot query | Pitch a guest post: *"Schema-first Spring Boot with GraphLink"*. One published Baeldung article outperforms 10 articles anywhere else. |
| **DZone** | Primary distribution — Spring Boot is DZone's most popular category | Submit all articles |
| **InfoQ** (`infoq.com`) | Enterprise Java/architecture audience — submit a news piece, lower bar than a full article | Submit a summary/news item about GraphLink's Spring Boot generation |
| **LinkedIn** | Tech leads and architects are here, not Twitter | Post the 72% metric as a native LinkedIn article, not just a link |

### Articles

1. **"I generate 72% of my Spring Boot files from a GraphQL schema — here's the setup"**
   Lead with the number. The most clickable title of the entire roadmap.

2. **"Schema-first Spring Boot with GraphQL — the complete guide"**
   Long tutorial. Targets the main high-volume search query for this audience.

3. **"Auto-generating Spring Boot controllers from a GraphQL schema"**
   Specific tutorial for controller generation. Targets: `spring boot graphql controller generate`

4. **"GraphQL schema as the single source of truth for Flutter + Spring Boot"**
   Full-stack story — ties Phase 1 and Phase 4 together. Very shareable for teams using both.

5. **"How to eliminate Spring Boot boilerplate with code generation"**
   Broader audience. Not GraphQL-specific in the title — reaches devs who don't know they
   need GraphQL yet.

### YouTube Videos

1. *Spring Boot GraphQL server in 10 minutes — zero boilerplate* — the flagship demo
2. *Full-stack: Flutter + Spring Boot + GraphQL from one schema* — your most powerful demo,
   tells the complete story end-to-end
3. *GraphQL schema → Spring Boot controllers, services, and repositories* — focused on output

### LinkedIn / Twitter

- The 72% / 64% numbers are your strongest hook for a tech lead audience
- The full-stack video (Flutter + Spring Boot from one schema) is your most shareable asset —
  post it as a native video on LinkedIn, not just a YouTube link
- Target: Spring Boot, Java EE migration, microservices communities

---

## Phase 5 — Go / Kotlin / C# / Python (Month 6+, Demand-Based)

Each new language follows the same pattern and takes less effort as the audience grows:

1. **Ship the serializer** (days, same architecture)
2. **Write the announcement + getting-started article** (one post)
3. **Record a 5-minute YouTube demo** (one video)
4. **Write the comparison article** vs. the dominant tool in that ecosystem
5. **Post to the language's community** (subreddit, Discord, newsletter)

By Phase 5, the community will amplify launches. You won't need to do all the work yourself.

**Priority order** (based on developer population + GraphQL adoption):
1. **Kotlin** — natural fit given Spring Boot audience already established in Phase 4
2. **Go** — large backend community, strong GraphQL adoption (`gqlgen` users are a natural audience)
3. **C#** — large enterprise audience, strong .NET GraphQL pain
4. **Python** — large community but GraphQL adoption is lower; do it when there's clear demand

---

## Ongoing (Every Phase)

| Cadence | Action |
|---|---|
| Every release | Update `CHANGELOG.md`, post release notes on GitHub, share on LinkedIn/Twitter |
| Monthly | One Stack Overflow answer where GraphLink is genuinely the right answer |
| Quarterly | Review Google Search Console — double down on articles gaining traction |
| When someone posts about it | Engage, repost, build the community thread |
| Every new language added | Submit to that language's weekly newsletter and community forum |

---

## Realistic Monthly Schedule

| Month | Deliverable |
|---|---|
| 1 | 2 Flutter articles + getting-started YouTube + TypeScript shipped |
| 2 | TypeScript launch post + Show HN (TypeScript) + 1 Flutter comparison article |
| 3 | 2 Java articles + Java YouTube demo |
| 4 | 1 Java comparison article + full-stack YouTube (Flutter + Spring Boot) |
| 5 | 2 Spring Boot articles |
| 6 | Spring Boot flagship YouTube + 1 Spring comparison article + GSC review |
| 7 | Kotlin or Go launch (if ready) |
| 8+ | Expand based on what's working |

> **Sustainable pace for a solo developer: one article + one video per month.**
> That compounds to 12 indexed articles and 12 videos by end of year — enough for
> real organic traffic to feed each new piece you publish.

---

## Platform Reference

### By phase — where the audience actually is

| Phase | Primary | Secondary | Newsletter to submit to |
|---|---|---|---|
| Flutter | Medium → Flutter Community | dev.to | Flutter Weekly |
| TypeScript | dev.to | Medium → Better Programming | JS Weekly, TS Weekly, This Week in React |
| Java | DZone | dev.to + LinkedIn | Baeldung Java Weekly |
| Spring Boot | **Baeldung guest post** | DZone + LinkedIn | InfoQ news submission |

### Universal rule
> Always publish canonical on **dev.to** first (fast Google indexing, you own the canonical URL).
> Then cross-post or submit to the phase-specific platform.
> Never publish on Medium as canonical — you don't own the SEO there.

### Do not use for these audiences
- Medium for Java/Spring — wrong audience
- DZone for Flutter/TypeScript — wrong audience
- Reddit as primary — use it for launch posts only, not ongoing distribution
- LinkedIn for Flutter/TypeScript — wrong audience

---

## Content Priority Matrix

| Content type | Effort | SEO value | LLM citation | Audience reach |
|---|---|---|---|---|
| Comparison article | Medium | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Medium |
| Production story post | Low | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | High |
| Stack Overflow answer | Low | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | High |
| Dev.to tutorial | Medium | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Medium |
| Show HN | Low | ⭐⭐⭐ | ⭐⭐⭐ | High |
| YouTube 5-min demo | Medium | ⭐ | ⭐⭐ | High |
| YouTube full tutorial | High | ⭐⭐ | ⭐⭐⭐ | High |
| LinkedIn post + metrics | Low | None | ⭐ | High |

**If you can only do one thing per phase: write the comparison article.**

---

## The Core Message (Never Changes)

No matter the language, every piece of content leads with the same idea:

> *Define your GraphQL schema once.*
> *GraphLink writes the rest — typed, idiomatic, production-ready.*
> *Zero runtime dependency. Delete the tool any time. The code stays.*

The numbers back it up:
- **72%** of Spring Boot files generated in production
- **64%** of Spring Boot lines generated in production
- **21.5%** of Flutter codebase generated in production
- **135 files** hand-written across an entire Spring Boot backend
