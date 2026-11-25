import csv
import requests

# --- CONFIGURATION ---
OCTOPUS_URL = "https://your-octopus-url.com"
API_KEY = "API-YOURKEYGOESHERE"
SPACE_ID = "Spaces-1"
CSV_FILE_PATH = "projects.csv"

OLD_ORG = "old-github-org"

# True  -> export only Git (Config-as-Code) projects whose URL contains OLD_ORG
# False -> export every project in the space
ONLY_MATCHING_GIT_PROJECTS = True
# ---------------------

headers = {
    "X-Octopus-ApiKey": API_KEY,
    "Accept": "application/json",
}


def fetch_all_projects():
    """Pages through the projects API and returns every project."""
    projects = []
    skip = 0
    take = 100

    while True:
        url = f"{OCTOPUS_URL}/api/{SPACE_ID}/projects?skip={skip}&take={take}"
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        data = response.json()

        items = data.get("Items", [])
        projects.extend(items)

        skip += len(items)
        if not items or skip >= data.get("TotalResults", 0):
            break

    return projects


def main():
    print("Fetching projects from Octopus...")
    projects = fetch_all_projects()
    print(f"Found {len(projects)} projects in total.")

    rows = []
    for p in projects:
        persistence = p.get("PersistenceSettings") or {}
        is_git = persistence.get("Type") == "Git"
        repo_url = persistence.get("Url") or (persistence.get("Details") or {}).get(
            "RepositoryUrl", ""
        )

        if ONLY_MATCHING_GIT_PROJECTS and not (is_git and OLD_ORG in repo_url):
            continue

        rows.append(
            {
                "ProjectName": p.get("Name", ""),
                "Slug": p.get("Slug", ""),
                "Id": p.get("Id", ""),
                "IsGit": is_git,
                "RepositoryUrl": repo_url,
            }
        )

    with open(CSV_FILE_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f, fieldnames=["ProjectName", "Slug", "Id", "IsGit", "RepositoryUrl"]
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} projects to {CSV_FILE_PATH}")


if __name__ == "__main__":
    main()