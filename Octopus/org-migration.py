import csv
import json
import os
import requests

# --- CONFIGURATION ---
OCTOPUS_URL = "https://your-octopus-url.com"  # e.g., https://example.com
API_KEY = "API-YOURKEYGOESHERE"  # Your Octopus API key
SPACE_ID = "Spaces-1"  # Target space ID (Default is usually Spaces-1)
CSV_FILE_PATH = "projects.csv"  # Name of your CSV input file

OLD_ORG = "old-github-org"
NEW_ORG = "new-github-org"

# --- DRY RUN CONTROL ---
# Set to True to safely test. Set to False to actually update Octopus.
DRY_RUN = True
# ---------------------

headers = {
    "X-Octopus-ApiKey": API_KEY,
    "Content-Type": "application/json",
    "Accept": "application/json",
}


def update_git_org_for_project(project_identifier):
    """Fetches a project and calculates or applies the new GitHub org URL."""
    # 1. Fetch project data using the name or slug
    project_url = f"{OCTOPUS_URL}/api/{SPACE_ID}/projects/{project_identifier}"
    response = requests.get(project_url, headers=headers)

    # If direct fetch fails, search for it by display name
    if response.status_code == 404:
        search_url = (
            f"{OCTOPUS_URL}/api/{SPACE_ID}/projects?skip=0&take=1&name="
            + requests.utils.quote(project_identifier)
        )
        search_response = requests.get(search_url, headers=headers)

        if not search_response.ok:
            print(f"❌ Error searching for project '{project_identifier}'")
            return

        search_results = search_response.json().get("Items", [])
        if not search_results:
            print(f"⚠️ Project '{project_identifier}' not found in Octopus.")
            return

        project_data = search_results[0]
        project_url = f"{OCTOPUS_URL}/api/{SPACE_ID}/projects/{project_data.get('Id')}"
    elif not response.ok:
        print(
            f"❌ Failed to fetch project '{project_identifier}': {response.status_code}"
        )
        return
    else:
        project_data = response.json()

    project_name = project_data.get("Name")

    # 2. Check if the project is Git version controlled
    persistence = project_data.get("PersistenceSettings")
    if not persistence or persistence.get("Type") != "Git":
        print(
            f"Skip: '{project_name}' is not configured for Git Version Control (Config-As-Code)."
        )
        return

    # Extract Git details
    git_details = persistence.get("Details", {})
    current_url = git_details.get("RepositoryUrl", "")

    # 3. Calculate the new repository URL
    if OLD_ORG in current_url:
        new_url = current_url.replace(
            f"://github.com{OLD_ORG}/", f"://github.com{NEW_ORG}/"
        )
        new_url = new_url.replace(
            f"github.com:{OLD_ORG}/", f"github.com:{NEW_ORG}/"
        )
    else:
        print(
            f"Info: '{project_name}' - Old org '{OLD_ORG}' not found in current URL ({current_url})."
        )
        return

    # 4. Handle execution based on DRY_RUN status
    if DRY_RUN:
        print(f"🔍 [DRY RUN] Project '{project_name}' would be updated:")
        print(f"    Current: {current_url}")
        print(f"    Proposed: {new_url}")
        return

    # Actual update execution if DRY_RUN is False
    project_data["PersistenceSettings"]["Details"]["RepositoryUrl"] = new_url
    print(f"🔄 '{project_name}': Updating URL to -> {new_url}")

    update_response = requests.put(
        project_url, headers=headers, data=json.dumps(project_data)
    )

    if update_response.ok:
        print(f"✅ Successfully updated '{project_name}' to the new org.")
    else:
        print(
            f"❌ Failed to update '{project_name}': {update_response.status_code} - {update_response.text}"
        )


def main():
    if not os.path.exists(CSV_FILE_PATH):
        print(f"❌ Error: CSV file not found at '{CSV_FILE_PATH}'")
        return

    if DRY_RUN:
        print(
            "🚀 RUNNING IN DRY-RUN MODE. NO CHANGES WILL BE MADE TO OCTOPUS.\n"
        )
    else:
        print("⚠️ WARNING: DRY-RUN IS OFF. LIVE UPDATES WILL BE APPLIED.\n")

    print(f"Reading projects from {CSV_FILE_PATH}...")

    with open(CSV_FILE_PATH, mode="r", encoding="utf-8-sig") as file:
        reader = csv.DictReader(file)

        if "ProjectName" not in reader.fieldnames:
            print(
                "❌ Error: CSV must have a column header named exactly 'ProjectName'"
            )
            return

        for row in reader:
            project_name = row["ProjectName"].strip()
            if project_name:
                update_git_org_for_project(project_name)


if __name__ == "__main__":
    main()
