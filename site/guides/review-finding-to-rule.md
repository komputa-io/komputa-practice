---
title: Turn a review finding into a rule
description: After a review, fix each mistake where it starts, in the project, the house rules or the template, so it does not come back.
sidebar:
  order: 5
---

Use this guide after you review a pull request or finish a slice of work, when a finding looks like a gap in the rules and not only in the code. The `standards-feedback` skill sorts each finding and proposes where its fix goes.

## Before you start

- The practice's skills are linked, so `standards-feedback` is installed. See the [Quickstart](/start/quickstart).
- You have the findings: review comments, fix rounds, and the gate and CI failures of the change.

## Steps

1. **Ask for the feedback pass.** For example:

   ```text
   Run standards-feedback on the review findings of pull request 42.
   ```

2. **Read how it sorts each finding.** Each finding goes in exactly one kind:

   | Kind | Sign | Where the fix goes |
   |---|---|---|
   | Project | Only this repo is wrong | A fix or an issue in the repo |
   | Missing | No rule covers it | A new rule in a house skill |
   | Unclear | Two rules disagree, or one reads two ways | One rule, reworded |
   | Too deep | The rule is only in a reference file | The rule moves into `SKILL.md` |
   | Not enforced | The agent read the rule and broke it anyway | A check in the project template |
   | Missing input | The rule needs a fact the repo never declared | A question in `copier.yml` |

   A check beats more words. More text is the fix only when no tool can check the rule.

3. **Approve the table.** The skill shows one table of findings, kinds, changes and repos, and says which findings are for the project only. Nothing changes the standards until you agree.

4. **Review and merge the pull requests.** It opens one pull request for each repo. A check in the template comes with a test that fails on the mistake and passes on the fix.

5. **Close the loop.** After the merge, pull the practice clone, sync the skills, and update the repo that showed the gap, so the new check holds there too:

   ```sh
   git -C ~/Code/komputa-practice pull
   skillshare sync -g                                   # when you link skills with skillshare
   uvx --exclude-newer "7 days" copier update --data-file <environment.yml>
   ```

## Next steps

- [How it fits](/explanation/how-it-fits): who owns each part, and how a rule changes.
- [The quality funnel](/explanation/quality-funnel): why a check beats a rule.
