GITHUB_TOKEN=xxx
BRANCH=main
OWNER=ngr05
REPOSITORY=workflow-test
WORKFLOW=build
REPO=$(OWNER)/$(REPOSITORY)

run-tests:
	curl -X POST \
		-H "Accept: application/vnd.github.v3+json" \
		-H "Authorization: Bearer $(GITHUB_TOKEN)" \
		-d '{ "ref": "$(BRANCH)", "inputs": { "environment": "getdev" } }' \
		"https://api.github.com/repos/$(OWNER)/$(REPOSITORY)/actions/workflows/$(WORKFLOW).yml/dispatches"

get-runs:
	curl -H "Authorization: Bearer $(GITHUB_TOKEN)" \
  		https://api.github.com/repos/$(OWNER)/$(REPOSITORY)/actions/runs

get-run:
	curl -H "Authorization: Bearer $(GITHUB_TOKEN)" \
		https://api.github.com/repos/$(OWNER)/$(REPOSITORY)/actions/runs/$$RUN_ID

execute:
	@echo "Triggering GitHub Actions workflow..."
	@curl -X POST \
		-H "Accept: application/vnd.github.v3+json" \
		-H "Authorization: Bearer $(GITHUB_TOKEN)" \
		-d '{ "ref": "$(BRANCH)", "inputs": { "environment": "getdev" } }' \
		https://api.github.com/repos/$(REPO)/actions/workflows/$(WORKFLOW).yml/dispatches

	@sleep 10

	@echo "Fetching run ID..."
	@RUN_ID=""; \
	for i in $$(seq 1 10); do \
		RUN_ID=$$(curl -s -H "Authorization: Bearer $$GITHUB_TOKEN" \
  			https://api.github.com/repos/$(REPO)/actions/runs \
  			| jq -r '.workflow_runs[] | select(.name == "build" and .head_branch == "$(BRANCH)" and .event == "workflow_dispatch") | .id' \
  			| head -n1 | tr -d '\n'); \
		if [ "$$RUN_ID" != "null" ]; then \
			echo "Found run ID: $$RUN_ID"; \
			break; \
		fi; \
		sleep 5; \
	done; \
	if [ -z "$$RUN_ID" ]; then \
		echo "Failed to get workflow run ID"; \
		exit 1; \
	fi; \

	echo "Polling for workflow completion..."; \
	for i in $$(seq 1 60); do \
	STATUS=$$(curl -s -H "Authorization: Bearer $(GITHUB_TOKEN)" \
		https://api.github.com/repos/$(REPO)/actions/runs/$$RUN_ID \
		| jq -r '.status'); \
	echo "Run status: $$STATUS"; \
	if [ "$$STATUS" = "completed" ]; then \
		CONCLUSION=$$(curl -s -H "Authorization: Bearer $(GITHUB_TOKEN)" \
		https://api.github.com/repos/$(REPO)/actions/runs/$$RUN_ID \
		| jq -r '.conclusion'); \
		echo "Workflow finished with conclusion: $$CONCLUSION"; \
		if [ "$$CONCLUSION" != "success" ]; then exit 1; fi; \
		break; \
	fi; \
	sleep 10; \
	done; \

	echo "Checking for artifacts..."; \
	ARTIFACTS=$$(curl -s -H "Authorization: Bearer $(GITHUB_TOKEN)" \
		https://api.github.com/repos/$(REPO)/actions/runs/$$RUN_ID/artifacts); \
	COUNT=$$(echo "$$ARTIFACTS" | jq '.total_count'); \
	if [ "$$COUNT" -gt 0 ]; then \
		echo "Found $$COUNT artifact(s). Downloading..."; \
		echo "$$ARTIFACTS" | jq -c '.artifacts[]' | while read -r artifact; do \
			NAME=$$(echo $$artifact | jq -r '.name'); \
			URL=$$(echo $$artifact | jq -r '.archive_download_url'); \
			curl -L -H "Authorization: Bearer $(GITHUB_TOKEN)" -o "artifact_$${NAME}.zip" "$$URL"; \
			echo "Downloaded $$NAME"; \
		done; \
	else \
		echo "No artifacts to download."; \
	fi
