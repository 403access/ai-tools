---
title: Usage & plan limits
sidebar_position: 4
---

import Figure from '@site/src/components/Figure';

# Usage & plan limits

The **Usage** tab combines your OpenCode Go allowances with aggregate activity
from OpenCode's stats API and session history.

<Figure src="/img/screenshots/usage.png" alt="Usage tab with Go plan limits, trend, streak, and activity totals" caption="Plan limits are hidden when no Go key is configured." />

## Plan limits

When a Go usage key is configured, the tab shows:

- **Rolling** (5h) consumption,
- **Weekly** consumption,
- **Monthly** consumption,

with percentage bars and reset countdowns. Values are read from
`https://opencode.ai/zen/go/v1/usage` and cached for both apps. See
[Go plan usage](../hub/go-usage.md) for key resolution.

:::note
The console's **Credits**, **Extra usage**, and **Auto-recharge** rows are not
part of the usage endpoint, so OpenCodeBar does not show them.
:::

## Summary tiles

- streak and active days,
- today's steps,
- prompts and sessions,
- total cost and tokens,
- tool calls and subagents.

## Trends

An interactive daily chart for **steps**, **cost**, or **tokens** across the
last 30 / 90 / 365 days or all time. Steps come from the stats API's daily
activity; cost and tokens are grouped from the session list by the day a
session was last updated.

## Projects by cost

The Usage tab ranks top projects by cost for the same selectable windows. Open a
project name to jump to its detail page.

## Activity heatmap

A GitHub-style heatmap of daily agent steps. It is a quick way to see momentum
and quiet stretches.

## Token mix

Input, output, reasoning, and cache read/write are broken out into a stacked
bar. Per-model steps and cost appear below.

## Tool reliability

The Usage tab includes a global tool-call success/failure summary, a bar chart
of call volume per tool, and filters for MCP, OS, library, and app tools. The
per-tool list adds failures and median duration. Project pages have the same
breakdown scoped to one project.

## Stale data

Usage numbers and plan limits are cached on disk. When the service or the API is
unreachable, the tab keeps showing the last known values and flags them as
stale rather than rendering an empty screen.
