index="fi_summary_github"
    ( source="Report_Github_VSM_Implementation_PullRequest"
      OR (source="Report_Github_VSM_Implementation_PushRequest" id=*) )
| eval RepoName=lower(trim(RepoName))
| where len(RepoName)>0
| lookup GHRepo-Mappings.csv RepoName OUTPUT BU ApplicationName
| where isnotnull(BU)
| mvexpand BU
| search BU="*" ApplicationName="*" RepoName="*"
| timechart span=1d limit=0 dc(RepoName) as ActiveRepoCount by BU


#####Information###

This query gives a daily count of active repos per BU. A repo is active on a day if it had a pull request, or a push with a commit ID, on that day. It only counts repos that exist in your mapping file.

Step by step

Base search
   index="fi_summary_github"
       ( source=PullRequest OR (source=PushRequest id=*) )

Reads events from the summary index. PR events are all kept. Push events are kept only if the id field exists, so pushes without a commit ID are dropped.

Clean the repo name
   | eval RepoName=lower(trim(RepoName))

Converts RepoName to lowercase and strips extra spaces, so the same repo always looks identical.

Remove blank repo names
   | where len(RepoName)>0

Drops events where the repo name is empty after cleaning.

Look up BU and ApplicationName
   | lookup GHRepo-Mappings.csv RepoName OUTPUT BU ApplicationName

Matches each event’s RepoName against the CSV and adds the BU and ApplicationName fields to the event. The match is case-sensitive, so the CSV’s repo names must be lowercase for this to work.

Keep only mapped repos
   | where isnotnull(BU)

If the repo wasn’t found in the CSV, BU is empty and the event is dropped. This does the same job as the inner join did before.

Split multi-BU repos
   | mvexpand BU

If a repo is mapped to more than one BU, the lookup returns several values in one field. mvexpand turns that into one event per BU, so each BU gets its own count. If no repo has multiple BUs, this line does nothing.

Dashboard filters
   | search BU="*" ApplicationName="*" RepoName="*"

Wildcards that match everything for now. In the dashboard, replace each * with its token (for example BU="$bu_tok$").

Daily count per BU
   | timechart span=1d limit=0 dc(RepoName) as ActiveRepoCount by BU

Groups events into 1-day buckets and counts the distinct repos in each bucket, with one series per BU. limit=0 shows every BU instead of grouping smaller ones into “OTHER”.

Example

Day	BU	Events	ActiveRepoCount
Mon	Finance	repo-a (push), repo-a (PR), repo-b (PR)	2
Mon	HR	repo-c (push)	1
Tue	Finance	repo-a (push)	1

Repo-a counts once on Monday even though it had two events, because dc counts distinct values.

Key points

It’s an either check: a repo needs a push or a PR on that day, not both.
If every BU shows zero, the usual cause is case mismatch between the lowercased RepoName and the CSV values.
Because the application name isn’t part of the final count, a repo mapped to several applications is still counted once per BU per day.